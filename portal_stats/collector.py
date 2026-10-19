"""Read Nginx container stdout. This privileged CLI is separate from the UI."""
from datetime import timedelta
import os
import re
import selectors
import subprocess
import time

from .store import MAX_LINE, iso, utc_now


class Lines:
    def __init__(self):
        self.buffer = b''
        self.discarding = False

    def feed(self, chunk):
        result = []
        for part in chunk.splitlines(keepends=True):
            if self.discarding:
                if part.endswith(b'\n'):
                    self.discarding = False
                continue
            self.buffer += part
            if len(self.buffer) > MAX_LINE:
                self.buffer = b''
                self.discarding = not part.endswith(b'\n')
                result.append(b'X' * (MAX_LINE + 1))
            elif part.endswith(b'\n'):
                result.append(self.buffer)
                self.buffer = b''
        return result


def docker_stream(store, container, stopped, command='docker'):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,127}', container):
        raise ValueError('INVALID_CONTAINER_NAME')
    delay = 1
    while not stopped.is_set():
        process = None
        try:
            # Replay retained logs, including after rotation/reconnect. Request IDs
            # deduplicate transactionally. Older retired dates cannot count twice.
            since = iso(utc_now() - timedelta(days=30))
            process = subprocess.Popen([command, 'logs', '--follow', '--timestamps', '--since', since, container],
                                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            os.set_blocking(process.stdout.fileno(), False)
            store.status('streaming')
            lines = Lines()
            batch = []
            last_flush = last_heartbeat = time.monotonic()
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ)
                eof = False
                while not stopped.is_set() and not eof:
                    for _key, _mask in selector.select(timeout=1):
                        chunk = os.read(process.stdout.fileno(), 65536)
                        if chunk:
                            batch.extend(lines.feed(chunk))
                        else:
                            eof = True
                    now = time.monotonic()
                    if batch and (len(batch) >= 100 or now-last_flush >= 1 or eof):
                        store.ingest(batch)
                        batch.clear()
                        last_flush = now
                        delay = 1
                    if now-last_heartbeat >= 5:
                        store.prune()
                        store.status('streaming')
                        last_heartbeat = now
                if batch:
                    store.ingest(batch)
            if not stopped.is_set():
                store.status('retrying', 'DOCKER_EXIT')
        except OSError:
            store.status('retrying', 'DOCKER_UNAVAILABLE')
        finally:
            if process:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=5)
                process.stdout.close()
        stopped.wait(delay)
        delay = min(delay * 2, 30)
    store.status('stopped')
