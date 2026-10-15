"""Real private monitor, rotating JSON logs, WebSockets and DB outage/recovery.

Uses disposable PostgreSQL, no private .env, no user accounts or client saves.
--browser optionally runs real headless Chromium with playwright-core.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
from urllib.error import HTTPError
from urllib.request import Request, ProxyHandler, build_opener
from uuid import uuid4
from pg_fixture import PostgresFixture
from ws_fixture import WebSocket
from run_capacity import fingerprint

ROOT = Path(__file__).resolve().parents[1]
MAP_HASH = hashlib.sha256((ROOT / 'shared/data/qingyun-v1.json').read_bytes()).hexdigest()


def eventually(test, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = test()
        if result:
            return result
        time.sleep(.1)
    raise AssertionError('Condition did not converge before deadline')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('/tmp/opencode/vssjx-observability'))
    parser.add_argument('--browser', action='store_true')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    args.output = args.output.resolve()
    subprocess.run(['cargo', 'build', '--locked', '--manifest-path', str(ROOT / 'server/Cargo.toml')], check=True)
    checks = 0
    opener = build_opener(ProxyHandler({}))  # Never send local tests through user proxies.

    def check(value, message):
        nonlocal checks
        checks += 1
        assert value, message

    def request(base, path, data=None, token=None, headers=None, method=None):
        sent = {'content-type':'application/json', **(headers or {})}
        if token:
            sent['authorization'] = 'Bearer ' + token
        body = json.dumps(data).encode() if data is not None else None
        try:
            response = opener.open(Request(base + path, data=body, headers=sent, method=method), timeout=8)
        except HTTPError as error:
            response = error
        with response:
            return response.status, response.headers, response.read()

    def api(base, path, data=None, token=None):
        code, headers, body = request(base, path, data, token)
        return code, headers, json.loads(body) if body else {}

    def stop(process):
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
            raise AssertionError('Server did not shut down gracefully')
        check(process.returncode == 0, 'Clean SIGTERM shutdown')

    with PostgresFixture() as db:
        env = {k:v for k,v in os.environ.items() if not k.startswith('SSJX_') and k != 'RUST_LOG'}
        env.update(SSJX_ENV_FILE='', SSJX_DATABASE_URL=db.url, SSJX_BIND_ADDR='127.0.0.1:0',
                   SSJX_MONITOR_BIND_ADDR='127.0.0.1:0', SSJX_LOG_DIR=str(args.output / 'logs'),
                   SSJX_LOG_FILE_MIB='1', SSJX_LOG_FILES='3', RUST_LOG='trace', SSJX_AUTH_RATE_IP='1000',
                   SSJX_AUTH_RATE_GLOBAL='10000', SSJX_AUTH_RATE_ACCOUNT='100', SSJX_WORLD_SAVE_SECONDS='1')
        process = None
        sockets = []
        consoles = []
        sensitive = [db.password, db.url, 'private-password-marker-12345', 'private-chat-marker-12345',
                     'private-query-marker', 'private-header-marker', 'private-caller-id', 'monitor_private_user', '监控测试甲', '监控测试乙']

        def start(index):
            path = args.output / f'console-{index}.log'
            console = path.open('w')
            consoles.append(console)
            child = subprocess.Popen([str(ROOT / 'server/target/debug/vssjx-server')], env=env, cwd=args.output, stdout=console, stderr=subprocess.STDOUT)
            def listening():
                if child.poll() is not None:
                    raise AssertionError('Server exited before listening; inspect console log')
                text = path.read_text()
                game = re.search(r'\baddress=(127\.0\.0\.1:\d+)', text)
                monitor = re.search(r'\bmonitor_endpoint=(127\.0\.0\.1:\d+)', text)
                return ('http://' + game[1], 'http://' + monitor[1]) if game and monitor else None
            try:
                base, monitor = eventually(listening, 30)
            except BaseException:
                child.terminate()
                child.wait(timeout=10)
                raise
            return child, base, monitor

        try:
            process, base, monitor = start(1)
            def status():
                code, _, value = api(monitor, '/api/status')
                check(code == 200, 'Monitor status is available')
                return value
            initial = eventually(lambda: (value if (value := status())['database']['status'] == 'ok' else None))
            boot = initial['boot_id']
            check(initial['world']['connected_players'] == 0, 'World starts empty')
            for path in ['/', '/dashboard.js', '/dashboard.css', '/api/status']:
                code, headers, body = request(monitor, path)
                check(code == 200 and bool(body), 'Dashboard resources served')
                check(headers['cache-control'] == 'no-store' and 'frame-ancestors' in headers['content-security-policy'], 'No-cache and CSP')
            check(request(base, '/api/status')[0] == 404, 'Private status absent from game listener')
            for headers in [{'host':'evil.example'}, {'origin':'http://evil.example'}, {'sec-fetch-site':'cross-site'}]:
                code = request(monitor, '/api/status', headers=headers)[0]
                check(code == 403, f'Rebinding/cross-site access blocked: {headers}: {code}')
            check(request(monitor, '/api/status', method='POST')[0] == 405, 'Monitor has no write API')
            code, headers, _ = api(base, '/api/v1/auth/login', {'username':'monitor_private_user','password':'private-password-marker-12345'})
            check(code == 401, 'Real failed login')
            rejected_id = headers['x-request-id']
            events = status()['recent_events']
            check(any(event['correlation_id'] == rejected_id and event['code'] == 'UNAUTHORIZED' for event in events), 'Failed login correlates to request ID')
            raw_code, raw_headers, _ = request(base, '/private-query-marker?token=private-query-marker', headers={
                'authorization':'Bearer private-header-marker', 'x-request-id':'private-caller-id'})
            check(raw_code == 404 and raw_headers['x-request-id'] != 'private-caller-id', 'Request IDs are generated by server')
            for index, nickname in enumerate(['监控测试甲','监控测试乙']):
                username = 'monitor_private_user' if index == 0 else 'monitor_second_user'
                sensitive.append(username)
                check(api(base, '/api/v1/auth/register', {'username':username,'password':sensitive[2]})[0] == 201, 'Register isolated account')
                code, _, session = api(base, '/api/v1/auth/login', {'username':username,'password':sensitive[2]})
                check(code == 200, 'Log in isolated account')
                sensitive.extend([session['access_token'], session['refresh_token']])
                code, _, created = api(base, '/api/v1/characters', {'operation_id':str(uuid4()),'display_name':nickname,'job':2,'gender':index,'school':0,'rules_version':'creation-v1'}, session['access_token'])
                check(code == 201, 'Create isolated online character')
                code, _, ticket = api(base, '/api/v1/world/ticket', {'character_id':created['character']['id'],'protocol_version':1,'config_hash':MAP_HASH}, session['access_token'])
                check(code == 200, 'Issue single-use ticket')
                sensitive.append(ticket['ticket'])
                ws = WebSocket(base.replace('http://','ws://') + '/api/v1/world/ws')
                sockets.append(ws)
                ws.send({'type':'auth.exchange','ticket':ticket['ticket'],'protocol_version':1,'config_hash':MAP_HASH,'world_sync_version':2})
                ready = ws.recv()[0]
                check(ready['type'] == 'auth.ready', 'World exchange succeeds')
                ws.snapshot()
                if index == 0:
                    command = {key:ready[key] for key in ['game_session_id','connection_epoch','world_epoch']}
                    ws.send(dict(command, type='world.move_to', input_seq='1', target=[13,16]))
                    ws.snapshot(lambda entities: entities[created['character']['id']]['cell'] == [13,16])
                    ws.send({'type':'chat.send','client_message_id':str(uuid4()),'channel':'public','text':sensitive[3]})
            snapshot = eventually(lambda: (value if (value:=status())['world']['connected_players'] == 2 else None))
            check(snapshot['websocket']['active'] == 2 and snapshot['tick']['count'] > 0 and snapshot['websocket']['sent_application_bytes'] > 0, 'Live world/socket/tick/byte counters')
            # Fixed protocol errors do not leak the rejected frame's raw content.
            bad = WebSocket(base.replace('http://','ws://') + '/api/v1/world/ws')
            sockets.append(bad)
            bad.send({'type':'private-header-marker'})
            check(bad.recv()[0]['code'] == 'INVALID_HANDSHAKE', 'Invalid WebSocket handshake rejected')
            bad.close()
            sockets.pop()
            eventually(lambda: status()['errors'].get('INVALID_HANDSHAKE',0) == 1)
            if args.browser:
                subprocess.run(['node', str(ROOT / 'tests/monitor_browser.cjs'), monitor, str(args.output)], env=env, check=True, timeout=90)
            for ws in sockets:
                ws.close()
            sockets.clear()
            eventually(lambda: status()['websocket']['active'] == 0)
            # Exercise enough error logs to rotate a real 1 MiB file.
            def miss(_):
                return request(base, '/private-query-marker?token=private-query-marker')[0]
            with ThreadPoolExecutor(max_workers=16) as executor:
                check(all(code == 404 for code in executor.map(miss, range(4000))), 'Bounded error flood completes')
            eventually(lambda: (args.output / 'logs/server.jsonl.1').exists())
            after = status()
            check(len(after['recent_events']) == 100, 'Recent events have a fixed memory bound')
            check(len(after['http']['routes']) < 20, 'Raw unknown URLs do not multiply labels')
            check(after['logging']['file_io_errors'] == 0, 'No file IO errors')
            subprocess.run(['docker','pause',db.name], check=True, capture_output=True)
            unavailable = eventually(lambda: (value if (value:=status())['database']['status']=='unavailable' else None), 15)
            started = time.monotonic()
            check(request(monitor, '/api/status')[0] == 200 and time.monotonic()-started < 1, 'Monitor remains responsive while DB paused')
            check(api(base,'/readyz')[0] == 503, 'Readiness reports database outage')
            subprocess.run(['docker','unpause',db.name], check=True, capture_output=True)
            recovered = eventually(lambda: (value if (value:=status())['database']['status']=='ok' else None), 15)
            check(api(base,'/readyz')[0] == 200, 'Database readiness recovers')
            (args.output / 'status.json').write_text(json.dumps(recovered,ensure_ascii=False,indent=2))
            stop(process)
            process = None
            process, base, monitor = start(2)
            restarted = status()
            check(restarted['boot_id'] != boot and not restarted['recent_events'] and restarted['world']['connected_players'] == 0, 'Restart creates new boot and clears process counters')
            stop(process)
            process = None
            console_text = ''.join((args.output/f'console-{index}.log').read_text() for index in [1,2])
            paths = list((args.output/'logs').glob('server.jsonl*'))
            check(1 <= len(paths) <= 3 and all(p.stat().st_size <= 1048576 for p in paths), 'Real disk retention is bounded by 3 x 1 MiB')
            lines = [json.loads(line) for path in paths for line in path.read_text().splitlines()]
            check(all(line.get('timestamp') and line.get('level') for line in lines), 'Persisted log records are structured JSON')
            check(any(line['fields'].get('message') == 'server stopped' for line in lines), 'Graceful exit flushes final log record')
            check(any('request_id' in line.get('span',{}) for line in lines), 'JSON events contain request correlation span')
            check('database health unavailable' in console_text and 'database health recovered' in console_text, 'Outage and recovery logged')
            check(rejected_id in console_text, 'Original failed-login request ID is searchable in logs')
            retained = console_text + json.dumps(lines,ensure_ascii=False) + json.dumps(recovered,ensure_ascii=False)
            check(all(marker not in retained for marker in sensitive), 'No passwords/tokens/tickets/names/chat/query/header values in logs or monitor')
            check(all(str(line.get('target','')).startswith('vssjx_server') for line in lines), 'RUST_LOG=trace cannot expose dependency diagnostics')
            report = {'checks':checks,'failures':0,'scope':'real local HTTP/WS, disposable PostgreSQL, trace logging, 4000-error rotation flood, DB pause/recovery, restart',
                      'retained_log_files':len(paths),'retained_log_bytes':sum(p.stat().st_size for p in paths),'retained_json_records':len(lines),
                      'db_outage_probe_ms':unavailable['database']['probe_ms'],'dropped_records':after['logging']['dropped_records'],
                      'browser':args.browser, 'git_head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
                      'source_sha256':fingerprint(), 'server_binary_sha256':hashlib.sha256((ROOT/'server/target/debug/vssjx-server').read_bytes()).hexdigest(),
                      'dirty':bool(subprocess.check_output(['git','status','--porcelain'],cwd=ROOT,text=True))}
            (args.output/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
            print(f'OBSERVABILITY: {checks} checks, 0 failures; {len(paths)} bounded JSON log files')
        finally:
            for ws in sockets:
                ws.close()
            if process is not None and process.poll() is None:
                stop(process)
            for console in consoles:
                console.close()


if __name__ == '__main__':
    main()
