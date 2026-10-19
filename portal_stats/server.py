"""Loopback-only management UI. No Docker access, CORS or public ingest API."""
import csv
from datetime import date, datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from io import StringIO
import ipaddress
import json
from pathlib import Path
import secrets
import socket
from socketserver import ThreadingMixIn
import sqlite3
import threading
from urllib.parse import parse_qs, urlsplit

from .apks import ApkError, ApkManager
from .store import LOCAL_TIME, METRICS, read_summary

ASSETS = Path(__file__).parent / 'assets'


class StatsServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True

    def __init__(self, bind, port, database, apks=None):
        address = ipaddress.ip_address(bind)
        if not address.is_loopback:
            raise ValueError('STATS_MUST_BIND_LOOPBACK')
        if address.version == 6:
            self.address_family = socket.AF_INET6
        self.database = Path(database).resolve()
        if not self.database.is_file():
            raise ValueError('INITIALIZE_STATS_DATABASE_FIRST')
        self.apks = apks
        self.token = secrets.token_urlsafe(32)
        self.slots = threading.BoundedSemaphore(16)
        super().__init__((bind, port), Handler)

    def process_request(self, request, client_address):
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except BaseException:
            self.slots.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.slots.release()

    def handle_error(self, *_args):
        # Never print request URLs, tokens, filenames or tracebacks to access logs.
        pass


class Handler(BaseHTTPRequestHandler):
    server_version = 'PortalStats'
    sys_version = ''

    def setup(self):
        super().setup()
        self.connection.settimeout(30)

    def log_message(self, *_args):
        pass

    def reply(self, status, value, content_type='application/json; charset=utf-8', extra=None):
        if isinstance(value, (dict, list)):
            value = json.dumps(value, ensure_ascii=False).encode()
        elif isinstance(value, str):
            value = value.encode()
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(value)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('X-Frame-Options', 'DENY')
        self.send_header('Content-Security-Policy', "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'")
        for key, entry in (extra or {}).items():
            self.send_header(key, entry)
        self.end_headers()
        if self.command != 'HEAD':
            self.wfile.write(value)

    def permitted(self, write=False):
        port = self.server.server_port
        host = self.headers.get('Host', '')
        bind = self.server.server_address[0]
        bind_host = '[' + bind + ']' if ':' in bind else bind
        allowed = {f'{bind_host}:{port}', f'localhost:{port}'}
        origin = self.headers.get('Origin')
        if (not ipaddress.ip_address(self.client_address[0]).is_loopback
                or len(self.headers.get_all('Host', [])) != 1 or host not in allowed
                or len(self.headers.get_all('Origin', [])) > 1
                or self.headers.get('Sec-Fetch-Site', '') not in ('', 'none', 'same-origin')
                or (origin is not None and origin != 'http://' + host)):
            self.reply(403, {'code': 'LOCAL_ORIGIN_REQUIRED'})
            return False
        candidate_token = self.headers.get('X-Portal-Token', '')
        if write and (origin != 'http://' + host
                      or len(self.headers.get_all('X-Portal-Token', [])) != 1
                      or not candidate_token.isascii() or len(candidate_token) > 128
                      or not secrets.compare_digest(candidate_token, self.server.token)):
            self.reply(403, {'code': 'MANAGEMENT_TOKEN_REQUIRED'})
            return False
        return True

    def parsed(self):
        if len(self.path) > 2048:
            raise ValueError('URL_TOO_LONG')
        parts = urlsplit(self.path)
        if parts.scheme or parts.netloc or parts.fragment:
            raise ValueError('INVALID_URL')
        query = parse_qs(parts.query, keep_blank_values=True, max_num_fields=4)
        if any(len(values) != 1 for values in query.values()):
            raise ValueError('DUPLICATE_QUERY')
        return parts.path, {key: values[0] for key, values in query.items()}

    def summary(self, query):
        if set(query) - {'start', 'end'}:
            raise ValueError('UNKNOWN_QUERY')
        today = datetime.now(LOCAL_TIME).date()
        start = date.fromisoformat(query.get('start', today.isoformat()))
        end = date.fromisoformat(query.get('end', today.isoformat()))
        if end > today:
            raise ValueError('FUTURE_DATE')
        result = read_summary(self.server.database, start, end)
        heartbeat = result['collector'].get('heartbeat')
        age = None
        if heartbeat:
            age = max(0, int((datetime.now(timezone.utc) - datetime.fromisoformat(heartbeat)).total_seconds()))
        result['collector']['heartbeat_age_seconds'] = age
        result['collector']['live'] = result['collector'].get('collector_state') == 'streaming' and age is not None and age < 20
        return result

    def do_GET(self):
        if not self.permitted():
            return
        try:
            path, query = self.parsed()
            if path == '/favicon.ico' and not query:
                return self.reply(204, b'')
            static = {'/': ('index.html', 'text/html; charset=utf-8'),
                      '/app.js': ('app.js', 'application/javascript; charset=utf-8'),
                      '/style.css': ('style.css', 'text/css; charset=utf-8')}
            if path in static and not query:
                filename, content_type = static[path]
                return self.reply(200, (ASSETS / filename).read_bytes(), content_type)
            if path == '/api/bootstrap' and not query:
                return self.reply(200, {'token': self.server.token, 'apk_enabled': self.server.apks is not None})
            if path in ('/api/summary', '/api/export.csv'):
                result = self.summary(query)
                if path == '/api/summary':
                    return self.reply(200, result)
                output = StringIO(newline='')
                writer = csv.writer(output)
                writer.writerow(('day_UTC+08:00', *METRICS))
                for row in result['days']:
                    writer.writerow((row['day'], *(row[name] for name in METRICS)))
                return self.reply(200, '\ufeff' + output.getvalue(), 'text/csv; charset=utf-8',
                                  {'Content-Disposition': 'attachment; filename="portal-statistics.csv"'})
            if path == '/api/apks' and not query:
                if not self.server.apks:
                    return self.reply(200, {'enabled': False, 'files': []})
                return self.reply(200, {'enabled': True, **self.server.apks.listing()})
            self.reply(404, {'code': 'NOT_FOUND'})
        except (ValueError, OverflowError):
            self.reply(400, {'code': 'INVALID_QUERY'})
        except (sqlite3.Error, OSError):
            self.reply(503, {'code': 'LOCAL_DATA_UNAVAILABLE'})

    def length(self, maximum):
        values = self.headers.get_all('Content-Length', [])
        if self.headers.get('Transfer-Encoding') or len(values) != 1 or not values[0].isdigit():
            raise ApkError('CONTENT_LENGTH_REQUIRED', 411)
        length = int(values[0])
        if not 0 < length <= maximum:
            raise ApkError('BODY_TOO_LARGE', 413)
        return length

    def write_request(self):
        self.close_connection = True
        if not self.permitted(write=True):
            return
        try:
            if not self.server.apks:
                raise ApkError('APK_MANAGEMENT_DISABLED', 409)
            path, query = self.parsed()
            if self.command == 'POST' and path == '/api/apks/upload' and set(query) == {'name'}:
                if self.headers.get('Content-Type') != 'application/octet-stream':
                    raise ApkError('OCTET_STREAM_REQUIRED', 415)
                length = self.length(self.server.apks.max_upload)
                result = self.server.apks.upload(self.rfile, length, query['name'])
                return self.reply(200 if result['duplicate'] else 201, result)
            components = path.strip('/').split('/')
            if len(components) >= 3 and components[:2] == ['api', 'apks'] and not query:
                action = components[3] if len(components) == 4 else ''
                if (self.command == 'DELETE' and len(components) == 3) or (self.command == 'POST' and action == 'publish'):
                    if self.headers.get('Content-Type') != 'application/json':
                        raise ApkError('JSON_REQUIRED', 415)
                    body = json.loads(self.rfile.read(self.length(512)))
                    if body != {'confirm': components[2]}:
                        raise ApkError('EXPLICIT_CONFIRMATION_REQUIRED')
                    result = (self.server.apks.delete(components[2]) if self.command == 'DELETE'
                              else self.server.apks.publish(components[2]))
                    return self.reply(200, result)
            self.reply(404, {'code': 'NOT_FOUND'})
        except ApkError as error:
            self.reply(error.status, {'code': error.code})
        except (ValueError, OverflowError):
            self.reply(400, {'code': 'INVALID_REQUEST'})
        except (sqlite3.Error, OSError):
            self.reply(503, {'code': 'LOCAL_FILE_OPERATION_FAILED'})

    do_POST = write_request
    do_DELETE = write_request

    def do_OPTIONS(self):
        self.reply(405, {'code': 'METHOD_NOT_ALLOWED'})
