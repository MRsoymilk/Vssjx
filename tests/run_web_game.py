"""Serve an already exported real game on an owned loopback port for Chromium UI tests."""
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
        assert not any('/api/v1/' in request for request in requests), 'Offline gameplay must not contact account/world APIs'
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


if __name__ == '__main__':
    main()
