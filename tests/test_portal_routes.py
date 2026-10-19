"""Real isolated Nginx/TLS checks using inert game bytes, never a player service."""
import base64
import gzip
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import http.client
import importlib.util
import json
import os
from pathlib import Path
import shutil
import socket
import ssl
import struct
import subprocess
import tempfile
import threading
import time
import unittest
from uuid import uuid4

from ws_fixture import WebSocket

ROOT = Path(__file__).resolve().parents[1]


def load_tool(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'tools' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def free_port():
    with socket.socket() as listener:
        listener.bind(('127.0.0.1', 0))
        return listener.getsockname()[1]


class Backend(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *_args):
        pass

    def do_GET(self):
        if self.headers.get('Upgrade', '').lower() == 'websocket':
            if self.headers.get('Origin') != 'https://allowed.fixture.invalid':
                self.send_error(403)
                return
            key = self.headers['Sec-WebSocket-Key']
            accept = base64.b64encode(hashlib.sha1((key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()).decode()
            self.send_response(101)
            self.send_header('Upgrade', 'websocket')
            self.send_header('Connection', 'Upgrade')
            self.send_header('Sec-WebSocket-Accept', accept)
            self.end_headers()
            self.wfile.flush()
            while True:
                header = self.rfile.read(2)
                if not header or header[0] & 15 == 8:
                    return
                length = header[1] & 127
                if length == 126:
                    length = struct.unpack('!H', self.rfile.read(2))[0]
                if length > 4096 or not header[1] & 128:
                    return
                mask = self.rfile.read(4)
                body = self.rfile.read(length)
                if len(body) != length:
                    return
                decoded = bytes(byte ^ mask[i % 4] for i, byte in enumerate(body))
                self.wfile.write(bytes([0x81, len(decoded)]) + decoded)
                self.wfile.flush()
        else:
            body = json.dumps({'service': 'fixture-only', 'path': self.path,
                               'origin': self.headers.get('Origin'),
                               'authorization': self.headers.get('Authorization')}).encode()
            self.send_response(401 if self.path == '/api/v1/auth/me' else 200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)


@unittest.skipUnless(shutil.which('docker') and shutil.which('openssl'), 'Docker and OpenSSL required')
class PortalRouteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.image = os.environ.get('SSJX_TEST_NGINX_IMAGE', 'nginx:1.29-alpine')
        available = subprocess.run(['docker', 'image', 'inspect', cls.image], capture_output=True)
        if available.returncode:
            raise unittest.SkipTest('Set SSJX_TEST_NGINX_IMAGE to a locally cached Nginx image; no image is pulled')
        temporary = tempfile.TemporaryDirectory(prefix='vssjx-portal-routes-', dir='/tmp/opencode' if Path('/tmp/opencode').is_dir() else None)
        cls.addClassCleanup(temporary.cleanup)
        cls.base = Path(temporary.name)
        cls.public = cls.base / 'public'
        cls.public.mkdir()
        cls.managed_public = cls.base / 'managed-apks'
        cls.managed_public.mkdir()
        for name in ('index.js', 'index.wasm', 'index.pck'):
            (cls.public / name).write_bytes((name.encode() + b' fixture, not a real executable\n') * 1024)
        config = {'executable': 'index', 'fileSizes': {'index.wasm': 1000, 'index.pck': 1000}}
        (cls.public / 'index.html').write_text('<!doctype html><title>Game fixture</title>\n<script src="index.js"></script>\nconst config = ' + json.dumps(config) + ';\n')
        cls.assets = load_tool('export_web').prepare_static_assets(cls.public)
        (cls.public / 'downloads').mkdir()
        (cls.public / 'downloads/vssjx-arm64.apk').write_bytes(b'inert APK download fixture')
        (cls.public / '.env').write_text('fixture-hidden-must-not-be-served')
        cls.original = {p.relative_to(cls.public): p.read_bytes() for p in cls.public.rglob('*') if p.is_file()}
        cls.portal = load_tool('prepare_portal').prepare(cls.base / 'portal')
        shutil.copytree(cls.portal, cls.public / 'navigation')
        certs = cls.base / 'certs/live/vssjx-ip'
        certs.mkdir(parents=True)
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
                        '-subj', '/CN=127.0.0.1', '-addext', 'subjectAltName=IP:127.0.0.1',
                        '-keyout', str(certs / 'privkey.pem'), '-out', str(certs / 'fullchain.pem')],
                       capture_output=True, check=True)
        cls.context = ssl.create_default_context(cafile=str(certs / 'fullchain.pem'))
        cls.backend = ThreadingHTTPServer(('127.0.0.1', 0), Backend)
        cls.backend.daemon_threads = True
        thread = threading.Thread(target=cls.backend.serve_forever, daemon=True)
        thread.start()
        cls.addClassCleanup(cls.backend.server_close)
        cls.addClassCleanup(cls.backend.shutdown)
        cls.http_port, cls.https_port = free_port(), free_port()
        text = (ROOT / 'deploy/public.web.https.nginx.conf').read_text()
        text = text.replace('listen 80 default_server;', f'listen 127.0.0.1:{cls.http_port} default_server;')
        text = text.replace('listen 443 ssl default_server;', f'listen 127.0.0.1:{cls.https_port} ssl default_server;')
        text = text.replace('http://127.0.0.1:8080', f'http://127.0.0.1:{cls.backend.server_port}')
        (cls.base / 'default.conf').write_text(text)
        cls.container = 'vssjx-portal-check-' + uuid4().hex
        cls.addClassCleanup(lambda: subprocess.run(['docker', 'rm', '-f', cls.container], capture_output=True))
        subprocess.run(['docker', 'run', '--detach', '--rm', '--pull=never', '--network', 'host', '--name', cls.container,
                        '--mount', f'type=bind,source={cls.base / "default.conf"},target=/etc/nginx/conf.d/default.conf,readonly',
                        '--mount', f'type=bind,source={cls.public},target=/usr/share/nginx/html,readonly',
                        '--mount', f'type=bind,source={cls.managed_public},target=/srv/vssjx-apks,readonly',
                        '--mount', f'type=bind,source={cls.base / "certs"},target=/etc/letsencrypt,readonly',
                        cls.image], capture_output=True, check=True)
        deadline = time.monotonic() + 15
        while True:
            try:
                cls.request('/')
                break
            except (OSError, http.client.HTTPException):
                if time.monotonic() > deadline:
                    raise RuntimeError(subprocess.run(['docker', 'logs', cls.container], capture_output=True, text=True).stderr)
                time.sleep(0.05)

    @classmethod
    def request(cls, path, headers=None, plain=False, method='GET'):
        connection = (http.client.HTTPConnection('127.0.0.1', cls.http_port, timeout=5) if plain else
                      http.client.HTTPSConnection('127.0.0.1', cls.https_port, context=cls.context, timeout=5))
        try:
            connection.request(method, path, headers=headers or {})
            response = connection.getresponse()
            return response.status, response.headers, response.read()
        finally:
            connection.close()

    def test_homepage_opt_in_preview_and_rollback(self):
        for path in ('/', '/navigation.html', '/navigation/index.html'):
            status, headers, body = self.request(path)
            self.assertEqual(status, 200)
            self.assertEqual(body, (self.portal / 'index.html').read_bytes())
            self.assertIn('text/html', headers['Content-Type'])
            self.assertIn('no-cache', headers['Cache-Control'])
        navigation = self.public / 'navigation'
        navigation.rename(self.base / 'navigation-paused')
        try:
            self.assertEqual(self.request('/')[2], self.original[Path('index.html')])
            self.assertEqual(self.request('/navigation.html')[0], 404)
            self.assertEqual(self.request('/webgame/')[2], self.original[Path('index.html')])
        finally:
            (self.base / 'navigation-paused').rename(navigation)

    def test_new_and_legacy_game_urls_are_byte_identical(self):
        self.assertEqual(self.request('/webgame')[0], 302)
        self.assertTrue(self.request('/webgame?from=portal')[1]['Location'].endswith('/webgame/?from=portal'))
        for name in ('index.html', 'index.js', 'index.wasm', 'index.pck'):
            with self.subTest(name=name):
                old = self.request('/' + name)
                new = self.request('/webgame/' + name)
                self.assertEqual(old[0], 200)
                self.assertEqual(new[0], 200)
                self.assertEqual(new[2], old[2])
                self.assertEqual(new[2], self.original[Path(name)])
                self.assertNotIn('immutable', new[1].get('Cache-Control', ''))
                if name.endswith('.wasm'):
                    self.assertEqual(new[1].get_content_type(), 'application/wasm')
        self.assertEqual(self.request('/webgame/')[2], self.original[Path('index.html')])

    def test_both_versioned_paths_keep_gzip_and_cache_policy(self):
        for prefix in ('/', '/webgame/'):
            for name in ('index.js', 'index.wasm', 'index.pck'):
                path = self.assets['prefix'] + name
                with self.subTest(path=prefix + path):
                    status, headers, body = self.request(prefix + path, {'Accept-Encoding': 'gzip'})
                    self.assertEqual(status, 200)
                    self.assertEqual(headers['Content-Encoding'], 'gzip')
                    self.assertIn('Accept-Encoding', headers['Vary'])
                    self.assertIn('immutable', headers['Cache-Control'])
                    self.assertEqual(gzip.decompress(body), self.original[Path(path)])
                    self.assertEqual(self.request(prefix + path)[2], self.original[Path(path)])
            status, headers, _ = self.request(prefix + self.assets['prefix'] + 'missing.wasm')
            self.assertEqual(status, 404)
            self.assertNotIn('immutable', headers.get('Cache-Control', ''))

    def test_resources_download_and_private_routes(self):
        for name in ('portal.css', 'app-icon.webp'):
            status, headers, body = self.request('/navigation/' + name)
            self.assertEqual(status, 200)
            self.assertEqual(body, (self.portal / name).read_bytes())
            self.assertIn("default-src 'none'", headers['Content-Security-Policy'])
        self.assertEqual(self.request('/downloads/vssjx-arm64.apk')[2], b'inert APK download fixture')
        for path in ('/.env', '/webgame/.env', '/navigation/.env', '/flarum', '/flarum/',
                     '/flarum/api', '/api/status', '/api/announcements', '/missing.wasm',
                     '/webgame/missing.wasm', '/webgame/api/v1/server-info', '/scripts/admin/data_browser.gd'):
            with self.subTest(path=path):
                self.assertEqual(self.request(path)[0], 404)

    def test_api_path_credentials_and_origin_are_not_rewritten(self):
        status, headers, body = self.request('/api/v1/auth/me', {'Origin': 'https://allowed.fixture.invalid', 'Authorization': 'Bearer synthetic-fixture-only'})
        self.assertEqual(status, 401)
        self.assertEqual(headers['Cache-Control'], 'no-store')
        result = json.loads(body)
        self.assertEqual(result['path'], '/api/v1/auth/me')
        self.assertEqual(result['origin'], 'https://allowed.fixture.invalid')
        self.assertEqual(result['authorization'], 'Bearer synthetic-fixture-only')
        self.assertEqual(self.request('/api/v1/server-info')[0], 200)

    def websocket(self, origin):
        client = WebSocket.__new__(WebSocket)
        client.socket = self.context.wrap_socket(socket.create_connection(('127.0.0.1', self.https_port), timeout=5), server_hostname='127.0.0.1')
        self.addCleanup(client.close)
        client.buffer = b''
        key = base64.b64encode(os.urandom(16)).decode()
        client.socket.sendall((f'GET /api/v1/world/ws HTTP/1.1\r\nHost: 127.0.0.1:{self.https_port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: {key}\r\nOrigin: {origin}\r\n\r\n').encode())
        while b'\r\n\r\n' not in client.buffer:
            data = client.socket.recv(4096)
            if not data:
                raise EOFError('Fixture handshake closed')
            client.buffer += data
        header, client.buffer = client.buffer.split(b'\r\n\r\n', 1)
        return client, header

    def test_wss_survives_graceful_reload_and_untrusted_origin_is_rejected(self):
        client, header = self.websocket('https://allowed.fixture.invalid')
        self.assertIn(b'101 Switching Protocols', header)
        client.send({'type': 'fixture.echo', 'phase': 'before'})
        self.assertEqual(client.recv()[0]['phase'], 'before')
        configuration = self.base / 'default.conf'
        configuration.write_text(configuration.read_text().replace(
            '    add_header Cache-Control no-cache always;',
            '    add_header Cache-Control no-cache always;\n    add_header X-Fixture-Reload after always;', 1))
        subprocess.run(['docker', 'exec', self.container, 'nginx', '-t'], capture_output=True, check=True)
        subprocess.run(['docker', 'exec', self.container, 'nginx', '-s', 'reload'], capture_output=True, check=True)
        deadline = time.monotonic() + 10
        while self.request('/')[1].get('X-Fixture-Reload') != 'after':
            self.assertLess(time.monotonic(), deadline, 'New worker did not load the fixture configuration')
            time.sleep(0.05)
        # The existing TLS/WS socket stays bound to its original worker.
        client.send({'type': 'fixture.echo', 'phase': 'after'})
        self.assertEqual(client.recv()[0]['phase'], 'after')
        self.assertEqual(self.request('/')[0], 200)
        _, rejected = self.websocket('https://untrusted.fixture.invalid')
        self.assertIn(b'403 Forbidden', rejected)

    def test_original_game_files_and_http_redirect_are_preserved(self):
        for name, content in self.original.items():
            self.assertEqual((self.public / name).read_bytes(), content)
        status, headers, _ = self.request('/webgame/?from=old', plain=True)
        self.assertEqual(status, 301)
        self.assertTrue(headers['Location'].endswith('/webgame/?from=old'))
        self.assertTrue(headers['Location'].startswith('https://'))

    def test_fixed_entry_redirects_and_private_event_log(self):
        from portal_stats.store import parse_event
        secret = 'synthetic-do-not-log-credential'
        for path, target in (('/go/webgame', '/webgame/'), ('/go/android', '/downloads/vssjx-arm64.apk')):
            status, headers, _ = self.request(path + '?next=https://untrusted.invalid&token=' + secret,
                                             {'Authorization': 'Bearer ' + secret, 'User-Agent': secret})
            self.assertEqual(status, 302)
            self.assertTrue(headers['Location'].endswith(target))
            self.assertNotIn('untrusted', headers['Location'])
        self.request('/')
        self.request('/webgame/')
        self.request('/downloads/vssjx-arm64.apk', {'Range': 'bytes=0-3'})
        logs = subprocess.check_output(['docker', 'logs', self.container], stderr=subprocess.DEVNULL)
        events = [parse_event(line) for line in logs.splitlines() if line.startswith(b'VSSJX_PORTAL_V1 ')]
        routes = {entry['route'] for entry in events}
        self.assertTrue({'portal', 'game', 'web_click', 'android_click', 'apk'} <= routes)
        self.assertTrue(any(entry['route'] == 'apk' and entry['status'] == 206 and entry['bytes'] == 4 for entry in events))
        raw_events = b'\n'.join(line for line in logs.splitlines() if line.startswith(b'VSSJX_PORTAL_V1 '))
        for forbidden in (secret.encode(), b'127.0.0.1', b'/api/', b'Authorization', b'User-Agent', b'next='):
            self.assertNotIn(forbidden, raw_events)
        before = {entry['id'] for entry in events}
        self.request('/go/android', method='HEAD')
        self.request('/api/v1/server-info', {'Authorization': secret})
        self.request('/navigation/portal.css')
        later = subprocess.check_output(['docker', 'logs', self.container], stderr=subprocess.DEVNULL)
        after = {parse_event(line)['id'] for line in later.splitlines() if line.startswith(b'VSSJX_PORTAL_V1 ')}
        self.assertEqual(before, after, 'HEAD, API and portal assets do not produce analytics events')

    def test_managed_apk_can_switch_without_changing_legacy_files(self):
        from io import BytesIO
        from portal_stats.apks import ApkManager
        from test_portal_apks import apk
        manager = ApkManager(self.base / 'private-apks', self.managed_public)
        data = apk(b'managed download fixture')
        record = manager.upload(BytesIO(data), len(data), 'test.apk')['file']
        try:
            manager.publish(record['id'])
            status, headers, body = self.request('/downloads/vssjx-arm64.apk')
            self.assertEqual((status, body), (200, data))
            self.assertEqual(headers.get('Cache-Control'), 'no-store')
            self.assertNotIn('ETag', headers)
            self.assertEqual(self.request('/downloads/vssjx-arm64.apk', {'If-Modified-Since': 'Thu, 31 Dec 2099 23:59:59 GMT'})[0], 200)
            self.assertIn(record['sha256'].encode(), self.request('/downloads/SHA256SUMS.txt')[2])
            self.assertEqual(self.request('/downloads/vssjx-arm64.apk', {'Range': 'bytes=0-3'})[2], data[:4])
            self.assertEqual((self.public / 'downloads/vssjx-arm64.apk').read_bytes(), b'inert APK download fixture')
        finally:
            (self.managed_public / 'current').unlink(missing_ok=True)  # Owned test fixture only.
        self.assertEqual(self.request('/downloads/vssjx-arm64.apk')[2], b'inert APK download fixture')


if __name__ == '__main__':
    unittest.main()
