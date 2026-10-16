"""Serve the exported game with an explicitly rejecting login fixture for UI checks."""
import argparse
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import subprocess
import threading

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--public', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    requests = []

    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, *parts, **kwargs):
            super().__init__(*parts, directory=str(args.public.resolve()), **kwargs)

        def log_message(self, *_args):
            pass

        def do_GET(self):
            requests.append(self.path)
            if self.path == '/favicon.ico':
                self.send_response(204)
                self.end_headers()
                return
            super().do_GET()

        def end_headers(self):
            self.send_header('Cache-Control', 'no-store')
            super().end_headers()

        def do_POST(self):
            requests.append(self.path)
            length = int(self.headers.get('Content-Length', '0'))
            if length < 0 or length > 65536:
                self.send_error(413)
                return
            self.rfile.read(length)  # Test credentials are discarded, never logged.
            body = b'{"code":"ACCOUNT_UNAVAILABLE"}'
            self.send_response(503 if self.path == '/api/v1/auth/login' else 404)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        base = f'http://127.0.0.1:{server.server_port}'
        result = subprocess.run(['node', str(ROOT / 'tests/web_game_browser.cjs'), base, str(output)],
                                env=os.environ.copy(), capture_output=True, text=True, timeout=300)
        text = result.stdout + result.stderr
        (output / 'browser.log').write_text(text)
        (output / 'requests.json').write_text(json.dumps(requests, indent=2))
        print(text, end='', flush=True)
        assert result.returncode == 0 and 'WEB GAME BROWSER:' in text, 'See browser.log/screenshots'
        api = [request for request in requests if '/api/v1/' in request]
        assert api == ['/api/v1/auth/login'], 'Only the explicit direct-login fixture request is allowed'
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


if __name__ == '__main__':
    main()
