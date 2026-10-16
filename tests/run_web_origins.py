"""P2a exact Origin policy against real PostgreSQL/Rust and optional Chromium.

Only owned loopback listeners, disposable DB and dummy users; never private .env.
This is not a Godot Web export, public TLS test or phone-browser acceptance.
"""
import argparse
import base64
import hashlib
from http.client import HTTPConnection
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import subprocess
import threading
import time
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import Request, ProxyHandler, build_opener
from uuid import uuid4

from pg_fixture import PostgresFixture
from ws_fixture import WebSocket

ROOT = Path(__file__).resolve().parents[1]
MAP_HASH = hashlib.sha256((ROOT / 'shared/data/qingyun-v1.json').read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('/tmp/opencode/vssjx-web-origins'))
    parser.add_argument('--browser', action='store_true')
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    subprocess.run(['cargo', 'build', '--locked', '--manifest-path', str(ROOT / 'server/Cargo.toml')], check=True)
    binary = ROOT / 'server/target/debug' / ('vssjx-server.exe' if os.name == 'nt' else 'vssjx-server')
    checks, sockets, servers = 0, [], []
    opener = build_opener(ProxyHandler({}))
    sensitive = ['origin-test-password-1234', 'private-origin-marker']

    def check(value, label):
        nonlocal checks
        checks += 1
        assert value, label

    class Page(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def do_GET(self):
            body = b'<!doctype html><title>P2 Origin fixture, not the game</title><p>WebSocket Origin test only.</p>'
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    for _ in range(2):
        frontend = ThreadingHTTPServer(('127.0.0.1', 0), Page)
        threading.Thread(target=frontend.serve_forever, daemon=True).start()
        servers.append(frontend)
    allowed_page, denied_page = [f'http://127.0.0.1:{server.server_port}' for server in servers]
    env = {key: value for key, value in os.environ.items() if not key.startswith('SSJX_') and key not in ['RUST_LOG', 'DEBUG', 'PWDEBUG']}
    env.update(SSJX_ENV_FILE='', SSJX_BIND_ADDR='127.0.0.1:0', SSJX_MONITOR_BIND_ADDR='',
               SSJX_LOG_DIR='', RUST_LOG='trace', SSJX_AUTH_RATE_IP='1000', SSJX_AUTH_RATE_GLOBAL='10000',
               SSJX_AUTH_RATE_ACCOUNT='100', SSJX_WORLD_RECONNECT_SECONDS='2')
    process, console = None, None

    def start(label, origins, development='', database=None, rate='1000'):
        nonlocal process, console
        current = dict(env, SSJX_WEB_ALLOWED_ORIGINS=origins, SSJX_WEB_DEV_ORIGINS=development, SSJX_AUTH_RATE_IP=rate)
        if database:
            current['SSJX_DATABASE_URL'] = database
        console = (output / f'{label}.log').open('w', encoding='utf8')
        process = subprocess.Popen([str(binary)], env=current, cwd=output, stdout=console, stderr=subprocess.STDOUT, text=True)
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            text = (output / f'{label}.log').read_text('utf8')
            match = re.search(r'address=(127\.0\.0\.1:\d+)', text)
            if match:
                return 'http://' + match[1]
            if process.poll() is not None:
                raise AssertionError('Test server stopped before listening; inspect redacted startup log')
            time.sleep(.05)
        raise AssertionError('Test server startup timed out')

    def stop():
        nonlocal process, console
        for socket in sockets:
            socket.close()
        sockets.clear()
        if process is not None:
            process.terminate()
            try:
                process.wait(timeout=12)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
                raise AssertionError('Test server failed to stop gracefully')
            finally:
                if console is not None:
                    console.close()
            check(process.returncode == 0, 'Server shuts down cleanly')
            process = console = None

    def upgrade(base, origins=(), forwarded=()):
        parsed = urlsplit(base)
        connection = HTTPConnection(parsed.hostname, parsed.port, timeout=5)
        try:
            connection.putrequest('GET', '/api/v1/world/ws')
            for name, value in [('Upgrade', 'websocket'), ('Connection', 'Upgrade'), ('Sec-WebSocket-Version', '13'),
                                ('Sec-WebSocket-Key', base64.b64encode(os.urandom(16)).decode()), *forwarded]:
                connection.putheader(name, value)
            for origin in origins:
                connection.putheader('Origin', origin)
            connection.endheaders()
            response = connection.getresponse()
            body = response.read()
            return response.status, json.loads(body) if body else {}
        finally:
            connection.close()

    def api(base, path, data=None, token=None):
        headers = {'Content-Type': 'application/json'}
        if token: headers['Authorization'] = 'Bearer ' + token
        body = json.dumps(data).encode() if data is not None else None
        try:
            response = opener.open(Request(base + path, data=body, headers=headers), timeout=10)
        except HTTPError as error:
            response = error
        with response:
            raw = response.read()
            return response.status, json.loads(raw) if raw else {}

    def user(base, username, display):
        check(api(base, '/api/v1/auth/register', {'username': username, 'password': sensitive[0]})[0] == 201, 'Create disposable account')
        code, session = api(base, '/api/v1/auth/login', {'username': username, 'password': sensitive[0]})
        check(code == 200, 'Authenticate disposable account')
        sensitive.extend([session['access_token'], session['refresh_token']])
        code, created = api(base, '/api/v1/characters', {'operation_id': str(uuid4()), 'display_name': display,
            'job': 1, 'gender': 0, 'school': 0, 'rules_version': 'creation-v1'}, session['access_token'])
        check(code == 201, 'Create authoritative character')
        return session, created['character']['id']

    def ticket(base, session, character):
        code, result = api(base, '/api/v1/world/ticket', {'character_id': character, 'protocol_version': 1, 'config_hash': MAP_HASH}, session['access_token'])
        check(code == 200, 'Request one-use world ticket')
        sensitive.append(result['ticket'])
        return result['ticket']

    def connect(base, raw, origin=None, version=1, world_version=2, config_hash=MAP_HASH):
        socket = WebSocket(base.replace('http://', 'ws://') + '/api/v1/world/ws', origin=origin)
        sockets.append(socket)
        socket.send({'type': 'auth.exchange', 'ticket': raw, 'protocol_version': version, 'config_hash': config_hash, 'world_sync_version': world_version})
        return socket, socket.recv()[0]

    try:
        base = start('default-policy', '')
        for origin in ['https://game.example.test', allowed_page, 'null', '']:
            check(upgrade(base, [origin]) == (403, {'code': 'ORIGIN_NOT_ALLOWED'}), 'Default denies present Origin')
        check(upgrade(base)[0] == 503, 'Missing Origin still reaches native auth-service gate')
        stop()
        for key, value in [('SSJX_WEB_ALLOWED_ORIGINS', 'https://user:private-origin-marker@host'),
                           ('SSJX_WEB_DEV_ORIGINS', 'http://192.168.1.2:8060')]:
            result = subprocess.run([str(binary)], env=dict(env, **{key:value}), cwd=output, capture_output=True, text=True, timeout=10)
            text = result.stdout + result.stderr
            check(result.returncode != 0 and key in text and 'private-origin-marker' not in text, 'Malformed Origin config fails closed without echoing values')

        with PostgresFixture() as database:
            sensitive.extend([database.password, database.url])
            base = start('allowlist-policy', 'HTTPS://GAME.EXAMPLE.TEST:443', allowed_page, database.url)
            for origins in [['https://evil.example'], ['null'], [''], ['http://game.example.test'],
                            ['https://game.example.test:444'], ['https://sub.game.example.test'],
                            ['https://game.example.test/'], ['https://game.example.test.evil'],
                            ['https://user:private-origin-marker@game.example.test'], [denied_page],
                            ['https://game.example.test', 'https://game.example.test'],
                            ['https://game.example.test,https://evil.example'], ['https://game.example.test https://evil.example'],
                            [b'https://\xff.example']]:
                check(upgrade(base, origins) == (403, {'code': 'ORIGIN_NOT_ALLOWED'}), 'Reject untrusted, malformed or repeated Origin')
            check(upgrade(base, ['https://evil.example'], [('X-Forwarded-Origin','https://game.example.test'),
                ('X-Forwarded-Host','game.example.test')])[0] == 403, 'Forwarded headers cannot create trust')
            alice, alice_id = user(base, 'origin_alice', '来源甲')
            bob, bob_id = user(base, 'origin_bob', '来源乙')
            check(api(base, '/api/v1/world/ticket', {'character_id': bob_id, 'protocol_version': 1, 'config_hash': MAP_HASH}, alice['access_token'])[0] == 403, 'Origin cannot bypass character ownership at ticket issuance')
            for origin in [None, 'https://game.example.test', allowed_page]:
                bad, reply = connect(base, '0' * 64, origin)
                check(reply == {'type':'error','code':'INVALID_TICKET'}, 'Native and allowed browser paths still reject invalid tickets')
                bad.close()
            version_ticket = ticket(base, alice, alice_id)
            wrong, reply = connect(base, version_ticket, 'https://game.example.test', version=99)
            check(reply['code'] == 'CONFIG_MISMATCH', 'Allowed Origin cannot bypass application protocol checks')
            wrong.close()
            wrong, reply = connect(base, version_ticket, allowed_page, config_hash='0' * 64)
            check(reply['code'] == 'CONFIG_MISMATCH', 'Allowed Origin cannot bypass world configuration hash checks')
            wrong.close()
            wrong, reply = connect(base, version_ticket, 'https://game.example.test', world_version=99)
            check(reply['code'] == 'WORLD_PROTOCOL_MISMATCH', 'Allowed Origin cannot bypass world version checks')
            wrong.close()
            a, ready_a = connect(base, version_ticket, 'https://GAME.example.test:443')
            check(ready_a['type'] == 'auth.ready' and alice_id in a.snapshot(), 'Trusted normalized Origin authenticates and receives validated snapshot')
            replay, reply = connect(base, version_ticket)
            check(reply['code'] == 'INVALID_TICKET', 'Ticket replay remains rejected on the native path')
            replay.close()
            b, ready_b = connect(base, ticket(base, bob, bob_id))
            check(ready_b['type'] == 'auth.ready' and set(b.snapshot()) == {alice_id, bob_id}, 'No-Origin native client still joins the same world')
            check(set(a.snapshot(lambda rows: len(rows) == 2)) == {alice_id, bob_id}, 'Browser and native clients share all visible entities')
            code, another = api(base, '/api/v1/auth/login', {'username':'origin_alice','password':sensitive[0]})
            check(code == 200, 'Second login session is distinct')
            sensitive.extend([another['access_token'], another['refresh_token']])
            denied, reply = connect(base, ticket(base, another, alice_id), allowed_page)
            check(reply['code'] == 'CHARACTER_BUSY', 'Trusted Origin cannot override a different login owner')
            denied.close()
            resumed, ready_new = connect(base, ticket(base, alice, alice_id), allowed_page)
            check(ready_new['type'] == 'auth.ready' and ready_new['game_session_id'] == ready_a['game_session_id']
                  and int(ready_new['connection_epoch']) > int(ready_a['connection_epoch']), 'Same-session browser reconnect preserves fenced takeover')
            check(alice_id in resumed.snapshot(), 'Reconnected browser gets a complete validated snapshot')
            expired = ticket(base, alice, alice_id)
            database.query('UPDATE world_tickets SET expires_at=NOW()-INTERVAL \'1 second\';')
            denied, reply = connect(base, expired, allowed_page)
            check(reply['code'] == 'INVALID_TICKET', 'Allowed Origin cannot revive expired tickets')
            denied.close()
            oversized = WebSocket(base.replace('http://','ws://') + '/api/v1/world/ws', origin=allowed_page)
            sockets.append(oversized)
            oversized.send_frame(1, b'x' * 4096)
            try:
                oversized.recv()
            except TimeoutError:
                check(False, 'Oversized frame must close the socket, not merely time out')
            except (EOFError, ConnectionError):
                check(True, 'Allowed Origin retains the frame-size limit')
            else:
                check(False, 'Oversized pre-auth frame must not receive world data')
            oversized.close()
            if args.browser:
                carol, carol_id = user(base, 'origin_carol', '浏览修士')
                browser_ticket = ticket(base, carol, carol_id)
                result = subprocess.run(['node', str(ROOT / 'tests/web_origin_browser.cjs'), allowed_page, denied_page,
                    base.replace('http://','ws://') + '/api/v1/world/ws', str(output)],
                    env=env, input=json.dumps({'ticket':browser_ticket, 'character':carol_id, 'hash':MAP_HASH}),
                    capture_output=True, text=True, timeout=45)
                (output/'browser.log').write_text(result.stdout + result.stderr, encoding='utf8')
                check(result.returncode == 0 and 'WEB ORIGIN BROWSER:' in result.stdout, 'Actual Chromium Origin and memory-only ticket exchange')
            stop()
            base = start('rate-limit-policy', 'https://game.example.test', database=database.url, rate='1')
            bad, reply = connect(base, '0' * 64, 'https://game.example.test')
            check(reply['code'] == 'INVALID_TICKET', 'First allowed upgrade still requires ticket')
            bad.close()
            check(upgrade(base, ['https://game.example.test'])[0] == 429, 'Allowed Origin cannot bypass IP admission limit')
            check(upgrade(base)[0] == 429, 'Native and browser upgrades share existing IP limit')
            stop()
        for logfile in output.glob('*.log'):
            text = logfile.read_text('utf8')
            check(not any(value and value in text for value in sensitive), 'No passwords, tokens, tickets or invalid Origin credentials in logs')
        records = {'checks':checks, 'failures':0, 'browser':args.browser,
                   'git_head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
                   'scope':'Owned loopback PostgreSQL/Rust and browser WS fixture only, not Godot Web, TLS or mobile acceptance'}
        (output/'report.json').write_text(json.dumps(records, indent=2), encoding='utf8')
        print(f'WEB ORIGINS: {checks} checks, 0 failures', flush=True)
    finally:
        try:
            stop()
        finally:
            for server in servers:
                server.shutdown()
                server.server_close()


if __name__ == '__main__':
    main()
