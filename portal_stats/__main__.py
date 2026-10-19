import argparse
import json
import os
from pathlib import Path
import signal
import sys
import threading

from .collector import Lines, docker_stream
from .store import Store


def main():
    parser = argparse.ArgumentParser(description='Private portal statistics; never connects to the game database')
    commands = parser.add_subparsers(dest='command', required=True)
    for name in ('init', 'collect'):
        command = commands.add_parser(name)
        command.add_argument('--database', type=Path, required=True)
        if name == 'collect':
            command.add_argument('--stdin', action='store_true', help='Import a bounded NDJSON stream instead of following Docker')
            command.add_argument('--container', default='vssjx-nginx-1')
    args = parser.parse_args()
    os.umask(0o077)
    store = Store(args.database)
    try:
        if args.command == 'init':
            store.status('idle')
        elif args.stdin:
            lines = Lines()
            counts = {}
            while chunk := sys.stdin.buffer.read(65536):
                for key, value in store.ingest(lines.feed(chunk)).items():
                    counts[key] = counts.get(key, 0) + value
            if lines.buffer:
                for key, value in store.ingest([lines.buffer]).items():
                    counts[key] = counts.get(key, 0) + value
            store.status('idle')
            print(json.dumps(counts))
        else:
            stopped = threading.Event()
            signal.signal(signal.SIGINT, lambda *_args: stopped.set())
            signal.signal(signal.SIGTERM, lambda *_args: stopped.set())
            docker_stream(store, args.container, stopped)
    finally:
        store.close()


if __name__ == '__main__':
    main()
