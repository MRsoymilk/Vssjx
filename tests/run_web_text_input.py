"""Real mobile-sized WASM login/chat against an owned disposable Rust/Postgres service."""
import argparse
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import select
import socket
import subprocess
import threading
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from uuid import uuid4
from pg_fixture import PostgresFixture
from run_account_auth import stop
from run_online_pve import api
from run_server_connection import wait_for_server

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--public', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    upstream = None

    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, *parts, **kwargs):
            super().__init__(*parts, directory=str(args.public.resolve()), **kwargs)

        def log_message(self, *_args):
            pass

        def proxy(self):
            if self.headers.get('Upgrade', '').lower() == 'websocket':
                host, port = upstream.removeprefix('http://').split(':')
                with socket.create_connection((host, int(port)), timeout=10) as target:
                    headers = ''.join(f'{key}: {value}\r\n' for key, value in self.headers.items())
                    target.sendall(f'GET {self.path} HTTP/1.1\r\n{headers}\r\n'.encode())
                    while True:
                        ready, _, _ = select.select([target, self.connection], [], [], 20)
                        if not ready:
                            return
                        for source in ready:
                            data = source.recv(65536)
                            if not data:
                                return
                            (self.connection if source is target else target).sendall(data)
                return
            length = int(self.headers.get('Content-Length', '0'))
            assert 0 <= length <= 65536
            data = self.rfile.read(length) if length else None
            headers = {key: value for key, value in self.headers.items()
                       if key.lower() in ('content-type', 'authorization', 'origin')}
            try:
                reply = urlopen(Request(upstream + self.path, data=data, headers=headers, method=self.command), timeout=15)
            except HTTPError as error:
                reply = error
            with reply:
                body = reply.read()
                self.send_response(reply.status)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        def do_GET(self):
            if self.path.startswith('/api/v1/'):
                self.proxy()
            else:
                super().do_GET()

        def do_POST(self):
            self.proxy()

    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    base = f'http://127.0.0.1:{server.server_port}'
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with PostgresFixture() as db:
            env = {k: v for k, v in os.environ.items() if not k.startswith('SSJX_')}
            env.update(SSJX_ENV_FILE='', SSJX_DATABASE_URL=db.url, SSJX_BIND_ADDR='127.0.0.1:0',
                       SSJX_MONITOR_BIND_ADDR='', SSJX_LOG_DIR='', SSJX_WEB_DEV_ORIGINS=base, RUST_LOG='info')
            process = subprocess.Popen([os.environ['SSJX_TEST_SERVER_BIN']], env=env,
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf-8')
            try:
                upstream = wait_for_server(process)
                def drain():
                    for _line in process.stdout:
                        pass
                threading.Thread(target=drain, daemon=True).start()
                # Disposable credentials only; never written to reports, screenshots or storage.
                credentials = dict(username='web_ime_probe', password='Owned-Web-中文-42!')
                assert api(upstream, '/api/v1/auth/register', credentials)[0] == 201
                code, session = api(upstream, '/api/v1/auth/login', credentials)
                assert code == 200
                code, _ = api(upstream, '/api/v1/characters', dict(operation_id=str(uuid4()),
                    display_name='输入测试', job=0, gender=0, school=0, rules_version='creation-v1'), session['access_token'])
                assert code == 201
                result = subprocess.run(['node', str(ROOT / 'tests/web_text_input_browser.cjs'), base, str(output)],
                    input=json.dumps(credentials), capture_output=True, text=True, encoding='utf-8', timeout=180)
                (output / 'browser.log').write_text(result.stdout + result.stderr, encoding='utf-8')
                print(result.stdout + result.stderr, end='')
                assert result.returncode == 0, 'See browser.log'
            finally:
                stop(process)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


if __name__ == '__main__':
    main()
