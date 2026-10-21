"""Deletion contract against an owned disposable PostgreSQL; never player data."""
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import threading
import sys
import hashlib
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from uuid import uuid4

from pg_fixture import PostgresFixture
from run_account_auth import stop
from run_server_connection import wait_for_server
from ws_fixture import WebSocket

ROOT = Path(__file__).resolve().parents[1]


def main():
    binary = os.environ.get('SSJX_TEST_SERVER_BIN')
    if not binary:
        raise RuntimeError('Set SSJX_TEST_SERVER_BIN to the server built from this source')
    checks = 0

    def check(value, description):
        nonlocal checks
        checks += 1
        assert value, description

    with PostgresFixture() as db:
        env = {k: v for k, v in os.environ.items() if not k.startswith('SSJX_')}
        env.update(SSJX_ENV_FILE='', SSJX_DATABASE_URL=db.url, SSJX_BIND_ADDR='127.0.0.1:0',
                   SSJX_MONITOR_BIND_ADDR='', SSJX_LOG_DIR='', SSJX_AUTH_RATE_IP='1000',
                   SSJX_AUTH_RATE_GLOBAL='10000', SSJX_AUTH_RATE_ACCOUNT='100', RUST_LOG='info')
        process = subprocess.Popen([binary], env=env, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True, encoding='utf-8')
        try:
            base = wait_for_server(process)

            def api(path, body=None, token=None):
                headers = {'Content-Type': 'application/json'}
                if token:
                    headers['Authorization'] = 'Bearer ' + token
                request = Request(base + path, json.dumps(body).encode() if body is not None else None,
                                  headers, method='POST' if body is not None else 'GET')
                try:
                    response = urlopen(request, timeout=12)
                except HTTPError as error:
                    response = error
                with response:
                    return response.code, json.load(response)

            def account(name):
                data = dict(username=name, password='deletion-test-password-1234')
                check(api('/api/v1/auth/register', data)[0] == 201, 'register isolated account')
                status, session = api('/api/v1/auth/login', data)
                check(status == 200, 'login isolated account')
                return session['access_token']

            token, other = account('delete_first'), account('delete_other')

            def create(name, auth=token):
                payload = dict(operation_id=str(uuid4()), display_name=name, job=1, gender=0,
                               school=3, rules_version='creation-v1')
                status, result = api('/api/v1/characters', payload, auth)
                check(status == 201, 'create isolated role')
                return result['character'], payload

            def deletion(character, **overrides):
                return dict(operation_id=str(uuid4()), character_id=character['id'],
                            character_name=character['display_name'], **overrides)

            route = '/api/v1/characters/delete'
            first, creation = create('删除测试')
            second, _ = create('保留测试')
            payload = deletion(first)
            check(api(route, payload)[0] == 401, 'authentication required')
            check(api(route, payload, other)[0] == 404, 'cannot delete other account role')
            check(api(route, dict(payload, character_name='别的名字'), token)[1]['code'] == 'CHARACTER_CHANGED', 'stale confirmation refused')
            check(api(route, dict(payload, gold=10), token)[0] == 400, 'strict deletion request')
            config_hash = hashlib.sha256((ROOT / 'shared/data/qingyun-v1.json').read_bytes()).hexdigest()
            ticket_body = dict(character_id=first['id'], protocol_version=1, config_hash=config_hash)
            status, ticket = api('/api/v1/world/ticket', ticket_body, token)
            check(status == 200, 'issue world ticket before deletion')
            socket = WebSocket(base.replace('http://', 'ws://') + '/api/v1/world/ws')
            try:
                socket.send(dict(type='auth.exchange', ticket=ticket['ticket'], protocol_version=1,
                                 config_hash=config_hash, world_sync_version=2))
                ready, _ = socket.recv()
                check(ready['type'] == 'auth.ready', 'join real shared world')
                check(api(route, payload, token)[1]['code'] == 'CHARACTER_BUSY', 'connected character cannot be deleted')
                socket.send(dict(type='world.leave'))
                deadline = time.monotonic() + 5
                while not db.query(f"SELECT 1 FROM security_audit WHERE character_id='{first['id']}' AND action='world.leave';") and time.monotonic() < deadline:
                    time.sleep(0.05)
            finally:
                socket.close()
            battle = str(uuid4())
            db.query(f"INSERT INTO pve_battles(id,character_id,rules_version,state) VALUES('{battle}','{first['id']}','qingyun-pve-v1','{{}}'); UPDATE characters SET active_battle_id='{battle}' WHERE id='{first['id']}';")
            check(api(route, payload, token)[1]['code'] == 'CHARACTER_BUSY', 'offline battle state blocks deletion')
            db.query(f"UPDATE characters SET active_battle_id=NULL WHERE id='{first['id']}'; UPDATE pve_battles SET active=false WHERE id='{battle}';")
            guild = str(uuid4())
            db.query(f"INSERT INTO guilds(id,name,name_key) VALUES('{guild}','测试公会','测试公会'); INSERT INTO guild_members(character_id,guild_id,role) VALUES('{first['id']}','{guild}','leader');")
            check(api(route, payload, token)[1]['code'] == 'CHARACTER_IN_GUILD', 'guild leader cannot orphan guild')
            db.query(f"DELETE FROM guilds WHERE id='{guild}';")
            team = str(uuid4())
            db.query(f"INSERT INTO teams(id) VALUES('{team}'); INSERT INTO team_members(character_id,team_id,leader) VALUES('{first['id']}','{team}',true);")
            check(api(route, payload, token)[1]['code'] == 'CHARACTER_IN_TEAM', 'team member must leave first')
            db.query(f"DELETE FROM teams WHERE id='{team}';")
            with ThreadPoolExecutor(max_workers=2) as executor:
                results = list(executor.map(lambda _: api(route, payload, token), range(2)))
            check(all(status == 200 for status, _ in results) and sorted(r['replayed'] for _, r in results) == [False, True], 'concurrent retry deletes once')
            check([c['id'] for c in api('/api/v1/characters', token=token)[1]['characters']] == [second['id']], 'list excludes deleted and preserves survivor')
            check(db.query(f"SELECT count(*) FROM security_audit WHERE character_id='{first['id']}' AND action='character.delete' AND outcome='accepted';") == '1', 'single durable audit')
            check(api('/api/v1/world/ticket', ticket_body, token)[0] == 403, 'deleted identity cannot enter world')
            check(db.query(f"SELECT count(*) FROM pve_battles WHERE id='{battle}';") == '1', 'historical battle references retained')
            check(api('/api/v1/characters', creation, token)[1]['code'] == 'CHARACTER_DELETED', 'old creation receipt cannot resurrect deleted role')
            check(api(route, dict(payload, character_id=second['id'], character_name=second['display_name']), token)[1]['code'] == 'IDEMPOTENCY_CONFLICT', 'same operation cannot delete different role')
            for endpoint in ['/api/v1/social', '/api/v1/teams']:
                check(api(endpoint, dict(character_id=first['id'], action='snapshot'), token)[0] == 403, 'deleted role has no gameplay/social authority')
            replacement, _ = create('删除测试')
            check(replacement['id'] != first['id'], 'released name gets fresh identity')
            check(api(route, payload, token)[0] == 200 and len(api('/api/v1/characters', token=token)[1]['characters']) == 2, 'old deletion retry cannot affect replacement')
            for i in range(3):
                create(f'新增测试{i}')
            check(len(api('/api/v1/characters', token=token)[1]['characters']) == 5, 'deleted slot released within five-role limit')
            for role in api('/api/v1/characters', token=token)[1]['characters']:
                check(api(route, deletion(role), token)[0] == 200, 'delete remaining role')
            check(api('/api/v1/characters', token=token)[1]['characters'] == [], 'last deletion yields empty roster')
            stop(process)
            process = subprocess.Popen([binary], env=env, stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, text=True, encoding='utf-8')
            base = wait_for_server(process)
            check(api('/api/v1/characters', token=token)[1]['characters'] == [], 'restart preserves empty roster')
            create('重建测试')
            godot = os.environ.get('GODOT_BIN')
            if godot:
                posts = []

                class Proxy(BaseHTTPRequestHandler):
                    def log_message(self, *_args):
                        pass

                    def do_GET(self):
                        self.forward()

                    def do_POST(self):
                        self.forward()

                    def forward(self):
                        body = self.rfile.read(int(self.headers.get('Content-Length', '0')))
                        request = Request(base + self.path, body if self.command == 'POST' else None,
                                          {key: value for key, value in self.headers.items()
                                           if key.lower() in ('authorization', 'content-type')}, method=self.command)
                        try:
                            response = urlopen(request, timeout=12)
                        except HTTPError as error:
                            response = error
                        with response:
                            data = response.read()
                            if self.path == route:
                                posts.append(json.loads(body))
                                if response.code == 200 and len(posts) == 1:
                                    self.close_connection = True
                                    return  # Server committed, client never received its receipt.
                            self.send_response(response.code)
                            self.send_header('Content-Type', 'application/json')
                            self.send_header('Content-Length', str(len(data)))
                            self.end_headers()
                            self.wfile.write(data)

                proxy = ThreadingHTTPServer(('127.0.0.1', 0), Proxy)
                thread = threading.Thread(target=proxy.serve_forever, daemon=True)
                thread.start()
                try:
                    ui_env = dict(env, SSJX_TEST_SERVER_URL=f'http://127.0.0.1:{proxy.server_port}')
                    ui = subprocess.run([godot, '--headless', '--path', str(ROOT / 'client'),
                                         'res://tests/online_character_deletion_test.tscn'],
                                        env=ui_env, capture_output=True, text=True, encoding='utf-8', timeout=60)
                    print(ui.stdout, end='')
                    print(ui.stderr, end='', file=sys.stderr)
                    check(ui.returncode == 0 and '0 failures' in ui.stdout, 'real online selection UI deletion')
                    check(len(posts) == 3 and posts[0] == posts[1] and posts[1]['character_id'] != posts[2]['character_id'], 'lost receipt retry keeps original operation and role')
                finally:
                    proxy.shutdown()
                    proxy.server_close()
                    thread.join(timeout=5)
            print(f'CHARACTER DELETION SERVER: {checks} checks, 0 failures')
        finally:
            stop(process)


if __name__ == '__main__':
    main()
