"""Real nine-second login response using an owned loopback HTTP fixture; no database."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    requests = []

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def do_POST(self):
            assert self.path == '/api/v1/auth/login'
            self.rfile.read(int(self.headers['Content-Length']))
            requests.append(self.path)
            time.sleep(9.2)
            body = b'{"code":"UNAUTHORIZED"}'
            self.send_response(401)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        env = dict(os.environ, SSJX_DELAYED_AUTH_FIXTURE=f'http://127.0.0.1:{server.server_port}')
        result = subprocess.run([env.get('GODOT_BIN', 'godot'), '--headless', '--path', str(ROOT / 'client'),
                                 'res://tests/account_network_timeout_test.tscn'], env=env,
                                capture_output=True, text=True, encoding='utf8', timeout=40)
        print(result.stdout + result.stderr, end='')
        assert result.returncode == 0 and 'ACCOUNT NETWORK TIMEOUT: 3 checks, 0 failures' in result.stdout
        assert len(requests) == 1, 'Never automatically replay a credential request'
        print('DELAYED AUTH FIXTURE: exactly one request; no automatic retry: PASS')
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=3)


if __name__ == '__main__':
    main()
