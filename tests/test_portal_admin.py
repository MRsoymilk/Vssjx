from datetime import datetime, timezone
import http.client
import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import threading
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from portal_stats.apks import ApkManager
from portal_stats.server import StatsServer
from portal_stats.store import Store
from test_portal_apks import apk
from test_portal_stats import event


class AdminTests(unittest.TestCase):
    def setUp(self):
        temporary = TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.database = self.root / 'stats.sqlite3'
        store = Store(self.database)
        store.ingest([event(moment=datetime.now(timezone.utc))])
        store.status('idle')
        store.close()
        self.manager = ApkManager(self.root / 'packages', self.root / 'published', max_upload=4096, quota=16384)
        self.server = StatsServer('127.0.0.1', 0, self.database, self.manager)
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.origin = f'http://127.0.0.1:{self.server.server_port}'

    def request(self, path, method='GET', body=None, headers=None, manage=False):
        extra = dict(headers or {})
        if manage:
            extra.update({'Origin': self.origin, 'X-Portal-Token': self.server.token})
        if isinstance(body, dict):
            body = json.dumps(body).encode()
            extra.setdefault('Content-Type', 'application/json')
        connection = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=5)
        try:
            connection.request(method, path, body=body, headers=extra)
            response = connection.getresponse()
            return response.status, response.headers, response.read()
        finally:
            connection.close()

    def upload(self, data=None):
        return self.request('/api/apks/upload?name=test.apk', 'POST', apk() if data is None else data,
                            headers={'Content-Type': 'application/octet-stream'}, manage=True)

    def test_loopback_host_origin_and_csrf_boundaries(self):
        for bind in ('0.0.0.0', '192.168.1.2', '::'):
            with self.assertRaises(ValueError):
                StatsServer(bind, 0, self.database)
        for headers in ({'Host': 'attacker.invalid'}, {'Origin': 'https://attacker.invalid'},
                        {'Sec-Fetch-Site': 'cross-site'}, {'Sec-Fetch-Site': 'same-site'}):
            self.assertEqual(self.request('/api/bootstrap', headers=headers)[0], 403)
        self.assertEqual(self.request('/api/apks/upload?name=test.apk', 'POST', apk(), headers={'Content-Type': 'application/octet-stream'})[0], 403)
        self.assertEqual(self.request('/api/apks/upload?name=test.apk', 'POST', apk(),
                                      headers={'Content-Type': 'application/octet-stream', 'Origin': self.origin, 'X-Portal-Token': '\xe9'})[0], 403)
        status, headers, data = self.request('/api/bootstrap')
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(data)['token'], self.server.token)
        self.assertNotIn('Access-Control-Allow-Origin', headers)
        self.assertIn('no-store', headers['Cache-Control'])

    def test_statistics_csv_and_static_assets(self):
        status, headers, body = self.request('/api/summary')
        self.assertEqual(status, 200)
        result = json.loads(body)
        self.assertEqual(result['totals']['portal_views'], 1)
        self.assertFalse(result['collector']['live'])
        status, headers, body = self.request('/api/export.csv')
        self.assertEqual(status, 200)
        self.assertIn('text/csv', headers['Content-Type'])
        self.assertTrue(body.startswith(b'\xef\xbb\xbfday_UTC+08:00'))
        self.assertIn('attachment', headers['Content-Disposition'])
        for path in ('/', '/app.js', '/style.css'):
            status, headers, _ = self.request(path)
            self.assertEqual(status, 200)
            self.assertIn("frame-ancestors 'none'", headers['Content-Security-Policy'])
        for path in ('/../stats.sqlite3', '/.env', '/api/ingest', '/api/apks/../../private'):
            self.assertEqual(self.request(path)[0], 404)

    def test_invalid_date_ranges_duplicate_queries_and_unknown_fields(self):
        for query in ('start=2020-01-01&end=2026-01-01', 'start=2026-01-01&start=2026-02-02',
                      'start=not-a-date', 'unknown=1', 'end=9999-01-01', 'start=2026-12-31&end=2026-01-01'):
            self.assertEqual(self.request('/api/summary?' + query)[0], 400)

    def test_upload_publish_and_delete_are_explicit_and_current_is_protected(self):
        status, _, body = self.upload()
        self.assertEqual(status, 201)
        old = json.loads(body)['file']['id']
        self.assertEqual(self.upload()[0], 200)
        self.assertEqual(self.request('/api/apks/' + old + '/publish', 'POST', {}, manage=True)[0], 400)
        self.assertEqual(self.request('/api/apks/' + old + '/publish', 'POST', {'confirm': old}, manage=True)[0], 200)
        self.assertEqual(self.request('/api/apks/' + old, 'DELETE', {'confirm': old}, manage=True)[0], 409)
        status, _, body = self.upload(apk(b'new package'))
        self.assertEqual(status, 201)
        new = json.loads(body)['file']['id']
        self.assertEqual(self.request('/api/apks/' + new + '/publish', 'POST', {'confirm': new}, manage=True)[0], 200)
        self.assertEqual(self.request('/api/apks/' + old, 'DELETE', {'confirm': old}, manage=True)[0], 200)
        records = json.loads(self.request('/api/apks')[2])
        self.assertEqual(records['current'], new)
        self.assertEqual(len(records['files']), 1)

    def test_upload_size_content_type_and_bad_archive_do_not_change_files(self):
        self.assertEqual(self.request('/api/apks/upload?name=test.apk', 'POST', b'x' * 4097,
                                      headers={'Content-Type': 'application/octet-stream'}, manage=True)[0], 413)
        self.assertEqual(self.request('/api/apks/upload?name=test.apk', 'POST', b'bad', manage=True)[0], 415)
        self.assertEqual(self.upload(b'not an apk')[0], 400)
        self.assertEqual(self.manager.listing()['files'], [])
        self.assertEqual(list(self.manager.packages.iterdir()), [])


if __name__ == '__main__':
    unittest.main()
