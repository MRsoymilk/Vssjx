"""Actual Rust/Godot integration and cross-process address persistence.

Run from any directory: python tests/run_server_connection.py [--render]
--render uses tests/run_offscreen.py; optional SSJX_LOGIN_CAPTURE_PATH saves UI.
"""
import argparse
import json
import os
from pathlib import Path
import re
import selectors
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]


def wait_for_server(process):
    with selectors.DefaultSelector() as selector:
        selector.register(process.stdout, selectors.EVENT_READ)
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if selector.select(timeout=0.2):
                line = process.stdout.readline()
                match = re.search(r'address=(127\.0\.0\.1:\d+)', line)
                if match:
                    return 'http://' + match[1]
            if process.poll() is not None:
                raise RuntimeError('Rust server exited before listening')
    raise RuntimeError('Rust server did not announce a listening address')


def run_godot(env, render=False):
    if render:
        command = [sys.executable, str(ROOT / 'tests/run_offscreen.py')]
    else:
        command = [env.get('GODOT_BIN', 'godot'), '--headless']
    command += ['--path', str(ROOT / 'client')]
    if render:
        command += ['--rendering-driver', 'opengl3_es']
    command += ['res://tests/server_connection_test.tscn']
    result = subprocess.run(command, env=env, text=True, capture_output=True, timeout=60)
    print(result.stdout, end='')
    if result.stderr:
        print(result.stderr, end='', file=sys.stderr)
    if result.returncode or '0 failures' not in result.stdout or re.search(r'(SCRIPT ERROR|^ERROR:)', result.stderr, re.M):
        raise RuntimeError('Godot server connection checks failed')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--render', action='store_true')
    args = parser.parse_args()
    subprocess.run(['cargo', 'build', '--locked', '--manifest-path', str(ROOT / 'server/Cargo.toml')], check=True)
    binary = ROOT / 'server/target/debug' / ('vssjx-server.exe' if os.name == 'nt' else 'vssjx-server')
    env = dict(os.environ, SSJX_BIND_ADDR='127.0.0.1:0', RUST_LOG='info')
    env.pop('SSJX_TEST_PERSISTENCE_PHASE', None)
    service = subprocess.Popen([str(binary)], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    fixture = None
    try:
        backend = wait_for_server(service)
        with urlopen(backend + '/healthz', timeout=3) as response:
            assert json.load(response)['stage'] == 'connection_only'
        seen = []

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def do_GET(self):
                seen.append(self.path)
                prefix = self.path.split('/')[1]
                if prefix == 'slow':
                    time.sleep(1.0)
                with urlopen(backend + '/api/v1/server-info', timeout=3) as response:
                    info = json.load(response)
                code = 200
                if prefix == 'wrong':
                    info['service'] = 'another-game'
                elif prefix == 'protocol':
                    info['protocol_version'] = 2
                elif prefix == 'unavailable':
                    code = 503
                elif prefix == 'redirect':
                    code = 302
                body = json.dumps(info).encode()
                if prefix == 'bad':
                    body = b'not-json'
                elif prefix == 'oversized':
                    body = b'x' * 40000
                try:
                    self.send_response(code)
                    self.send_header('Content-Type', 'application/json')
                    self.send_header('Content-Length', str(len(body)))
                    if code == 302:
                        self.send_header('Location', backend + '/api/v1/server-info')
                    self.end_headers()
                    self.wfile.write(body)
                except (BrokenPipeError, ConnectionResetError):
                    pass  # Timeout and cancellation intentionally close sockets.

        fixture = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        threading.Thread(target=fixture.serve_forever, daemon=True).start()
        scratch = '/tmp/opencode' if Path('/tmp/opencode').is_dir() else None
        with tempfile.TemporaryDirectory(prefix='vssjx-connection-', dir=scratch) as directory:
            env['SSJX_CONNECTION_PATH'] = str(Path(directory) / 'connection.cfg')
            env['SSJX_TEST_SERVER_URL'] = backend
            env['SSJX_TEST_FIXTURE_URL'] = f'http://127.0.0.1:{fixture.server_port}'
            run_godot(env, args.render)
            assert '/prefix/api/v1/server-info' in seen
            # These two separate Godot processes use the same settings file.
            env['SSJX_TEST_PERSISTENCE_PHASE'] = 'write'
            run_godot(env)
            env['SSJX_TEST_PERSISTENCE_PHASE'] = 'read'
            run_godot(env)
        print('PASS: Rust discovery, Godot login UI, failure handling, prefix and restart persistence')
    finally:
        if fixture:
            fixture.shutdown()
            fixture.server_close()
        service.terminate()
        try:
            service.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            service.kill()
            service.communicate()


if __name__ == '__main__':
    main()
