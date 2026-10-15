"""Real PostgreSQL character transactions + original Godot creation UI; no private .env."""
import argparse
import hashlib
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import threading
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from uuid import uuid4
from pg_fixture import PostgresFixture
from run_account_auth import stop
from run_server_connection import wait_for_server

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--render', action='store_true')
    args = parser.parse_args()
    subprocess.run(['cargo', 'build', '--locked', '--manifest-path', str(ROOT / 'server/Cargo.toml')], check=True)
    with PostgresFixture() as db:
        env = {k: v for k, v in os.environ.items() if not k.startswith('SSJX_')}
        env.update(SSJX_ENV_FILE='', SSJX_DATABASE_URL=db.url, SSJX_BIND_ADDR='127.0.0.1:0', RUST_LOG='info', SSJX_MONITOR_BIND_ADDR='', SSJX_LOG_DIR='',
                   SSJX_AUTH_RATE_IP='1000', SSJX_AUTH_RATE_GLOBAL='10000', SSJX_AUTH_RATE_ACCOUNT='100')
        logs = []

        def start():
            process = subprocess.Popen([str(ROOT / 'server/target/debug/vssjx-server')], env=env,
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            try:
                return process, wait_for_server(process)
            except BaseException:
                stop(process)
                raise

        process, base = start()
        password = 'character-test-password-1234'

        def api(path, payload=None, token=None, raw=None):
            headers = {'Content-Type': 'application/json'}
            if token:
                headers['Authorization'] = 'Bearer ' + token
            body = json.dumps(payload).encode() if payload is not None else raw
            try:
                response = urlopen(Request(base + path, data=body, headers=headers,
                                           method='POST' if body is not None else 'GET'), timeout=12)
            except HTTPError as error:
                response = error
            with response:
                return response.code, json.load(response)

        def account(username):
            assert api('/api/v1/auth/register', {'username': username, 'password': password})[0] == 201
            status, session = api('/api/v1/auth/login', {'username': username, 'password': password})
            assert status == 200
            return session

        def request(name, **overrides):
            return dict(operation_id=str(uuid4()), display_name=name, job=1, gender=0, school=2,
                        rules_version='creation-v1', **overrides)

        def create(session, data):
            return api('/api/v1/characters', data, session['access_token'])

        try:
            first, second, third, rollback = [account(name) for name in ('char_first', 'char_second', 'char_third', 'char_rollback')]
            assert api('/api/v1/characters')[0] == 401
            assert api('/api/v1/characters', request('未认证'))[0] == 401
            assert api('/api/v1/characters', token=first['access_token'])[1]['characters'] == []
            original = request('  青衫Ab_1  ')
            with ThreadPoolExecutor(max_workers=2) as executor:
                results = list(executor.map(lambda _: create(first, original), range(2)))
            assert [status for status, _ in results] == [201, 201]
            assert sorted(data['replayed'] for _, data in results) == [False, True]
            character = results[0][1]['character']
            assert character['display_name'] == '青衫Ab_1' and character['state_revision'] == '1'
            assert character['gold'] == 30 and character['hp'] == 95 and character['mp'] == 45
            assert character['level'] == 1 and (character['cell_x'], character['cell_y']) == (10, 16)
            normalized = json.dumps(['character.create:v1', '青衫Ab_1', 1, 0, 2, 'creation-v1'], ensure_ascii=False, separators=(',', ':')).encode()
            assert db.query(f"SELECT encode(request_digest,'hex') FROM account_operation_receipts WHERE account_id='{first['account']['id']}' AND operation_id='{original['operation_id']}';") == hashlib.sha256(normalized).hexdigest()
            assert db.query(f"SELECT string_agg(definition_id || ':' || quantity, ',' ORDER BY definition_id) FROM inventory_items WHERE character_id='{character['id']}';") == 'potion:6,sword:1'
            equivalent = dict(original, display_name='青衫Ab_1')
            assert create(first, equivalent)[1]['character']['id'] == character['id']
            reordered = json.dumps(dict(reversed(list(original.items()))), ensure_ascii=False, indent=2).encode()
            assert api('/api/v1/characters', token=first['access_token'], raw=reordered)[1]['character']['id'] == character['id']
            for changes in ({'display_name': '新昵称'}, {'job': 2}, {'gender': 1}, {'school': 0}, {'rules_version': 'creation-future'}, {'display_name': '青衫ab_1'}):
                assert create(first, dict(original, **changes)) == (409, {'code': 'IDEMPOTENCY_CONFLICT'})
            assert create(first, request('新昵称'))[1]['code'] == 'CHARACTER_LIMIT_REACHED'
            receipt_path = '/api/v1/character-operations/' + original['operation_id']
            assert api(receipt_path, token=first['access_token'])[1]['character'] == character
            assert api(receipt_path, token=second['access_token'])[0] == 404

            occupied = request('青衫ab_1')
            assert create(second, occupied)[1]['code'] == 'NAME_TAKEN'
            assert db.query(f"SELECT count(*) FROM characters WHERE account_id='{second['account']['id']}';") == '0'
            # A refusal is durable, even after later successful creation on the account.
            assert create(second, dict(occupied, display_name='新昵称'))[1]['code'] == 'IDEMPOTENCY_CONFLICT'
            assert create(second, dict(request('第二位修士'), operation_id=original['operation_id']))[0] == 201
            assert api(receipt_path, token=second['access_token'])[1]['character']['display_name'] == '第二位修士'
            assert create(second, occupied)[1]['code'] == 'NAME_TAKEN'

            invalid = request('青\n衫')
            assert create(third, invalid)[1]['code'] == 'INVALID_NAME'
            assert create(third, dict(invalid, display_name='有效昵称'))[1]['code'] == 'IDEMPOTENCY_CONFLICT'
            for field in ('account_id', 'gold', 'hp', 'name_key'):
                assert create(third, dict(request('有效昵称'), **{field: 999}))[0] == 400
            duplicate = json.dumps(request('有效昵称'))[:-1] + ',"job":2}'
            assert api('/api/v1/characters', token=third['access_token'], raw=duplicate.encode())[0] == 400
            for invalid_id in ('0' * 32, str(uuid4()).replace('-', ''), '00000000-0000-0000-0000-000000000000'):
                assert create(third, dict(request('有效昵称'), operation_id=invalid_id))[0] == 400
            assert create(third, dict(request('有效昵称'), job=3))[1]['code'] == 'INVALID_APPEARANCE'
            stale = dict(request('有效昵称'), rules_version='creation-future')
            assert create(third, stale)[1]['code'] == 'RULES_UNSUPPORTED'
            with ThreadPoolExecutor(max_workers=2) as executor:
                competing = list(executor.map(lambda name: create(third, request(name)), ['同账号甲', '同账号乙']))
            assert sorted(status for status, _ in competing) == [201, 409]
            assert create(third, stale)[1]['code'] == 'RULES_UNSUPPORTED'

            # Force failure AFTER inserting the character to prove initial assets/receipt atomicity.
            db.query("CREATE FUNCTION reject_fixture_item() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'fixture failure'; END $$; CREATE TRIGGER fixture_item_failure BEFORE INSERT ON inventory_items FOR EACH ROW EXECUTE FUNCTION reject_fixture_item();")
            retry = request('回滚修士')
            assert create(rollback, retry)[0] == 503
            assert db.query(f"SELECT count(*) FROM characters WHERE account_id='{rollback['account']['id']}';") == '0'
            assert db.query(f"SELECT count(*) FROM account_operation_receipts WHERE account_id='{rollback['account']['id']}';") == '0'
            db.query('DROP TRIGGER fixture_item_failure ON inventory_items; DROP FUNCTION reject_fixture_item();')
            assert create(rollback, retry)[0] == 201

            race_a, race_b = account('name_race_a'), account('name_race_b')
            with ThreadPoolExecutor(max_workers=2) as executor:
                futures = [executor.submit(create, race_a, request('并发Name')), executor.submit(create, race_b, request('并发name'))]
                raced = [future.result() for future in futures]
            assert sorted(status for status, _ in raced) == [201, 409]
            assert next(data for status, data in raced if status == 409)['code'] == 'NAME_TAKEN'
            assert db.query("SELECT count(*) FROM characters WHERE name_key='并发name';") == '1'
            assert db.query('SELECT count(*) FROM inventory_items;') == str(2 * int(db.query('SELECT count(*) FROM characters;')))

            disabled = account('char_disabled')
            db.query("UPDATE accounts SET disabled=TRUE WHERE username='char_disabled';")
            assert create(disabled, request('禁用账号'))[0] == 401
            expired = account('char_expired')
            db.query(f"UPDATE sessions SET access_expires_at=NOW()-INTERVAL '1 second' WHERE id='{expired['session_id']}';")
            assert create(expired, request('过期账号'))[0] == 401

            # Revoke AFTER initial authentication, while creation is waiting on its account lock.
            waiting = account('char_waiting_auth')
            holder = subprocess.Popen(['docker', 'exec', '-i', db.name, 'psql', '-U', 'vssjx', '-d', 'vssjx_auth_test', '-qAt', '-v', 'ON_ERROR_STOP=1'],
                                      stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            holder.stdin.write(f"BEGIN; SELECT id FROM accounts WHERE id='{waiting['account']['id']}' FOR UPDATE; SELECT 'fixture-locked';\n")
            holder.stdin.flush()
            try:
                while holder.stdout.readline().strip() != 'fixture-locked':
                    assert holder.poll() is None, 'Fixture account lock failed'
                with ThreadPoolExecutor(max_workers=1) as executor:
                    future = executor.submit(create, waiting, request('等待后撤销'))
                    deadline = time.monotonic() + 2
                    while db.query("SELECT count(*) FROM pg_stat_activity WHERE wait_event_type='Lock' AND query LIKE 'SELECT id FROM accounts WHERE id=%FOR UPDATE';") == '0':
                        assert time.monotonic() < deadline, 'Creation never reached account lock'
                        time.sleep(0.02)
                    db.query(f"UPDATE sessions SET revoked_at=NOW() WHERE id='{waiting['session_id']}';")
                    holder.communicate(input='COMMIT;\n\\q\n', timeout=5)
                    assert future.result()[0] == 401
                assert db.query(f"SELECT count(*) FROM characters WHERE account_id='{waiting['account']['id']}';") == '0'
                assert db.query(f"SELECT count(*) FROM account_operation_receipts WHERE account_id='{waiting['account']['id']}';") == '0'
            finally:
                if holder.poll() is None:
                    holder.communicate(input='ROLLBACK;\n\\q\n', timeout=5)

            # Restart with original DB: success and refusal receipts survive and still precede current limits.
            logs.append(stop(process))
            process, base = start()
            assert create(first, original)[1]['character'] == character
            assert create(second, occupied)[1]['code'] == 'NAME_TAKEN'
            assert api('/api/v1/characters', token=first['access_token'])[1]['characters'] == [character]
            db.query(f"UPDATE characters SET gold=35,state_revision=2 WHERE id='{character['id']}';")
            current = api('/api/v1/characters', token=first['access_token'])[1]['characters'][0]
            assert current['gold'] == 35 and current['state_revision'] == '2'
            assert create(first, original)[1]['character'] == character  # Historical receipt is immutable.

            # UI proxy deliberately loses the FIRST committed creation response.
            posts = []

            class Proxy(BaseHTTPRequestHandler):
                def log_message(self, *_args):
                    pass

                def do_GET(self):
                    self.forward()

                def do_POST(self):
                    self.forward()

                def forward(self):
                    body = self.rfile.read(int(self.headers.get('Content-Length', 0))) if self.command == 'POST' else None
                    headers = {key: value for key, value in self.headers.items() if key.lower() in ('authorization', 'content-type')}
                    create_request = json.loads(body) if self.path == '/api/v1/characters' and self.command == 'POST' else None
                    first_of_name = False
                    if create_request:
                        posts.append(create_request)
                        first_of_name = sum(post['display_name'] == create_request['display_name'] for post in posts) == 1
                    if create_request and create_request['display_name'] == '未决修士' and first_of_name:
                        status, data = 503, b'{"code":"SERVER_BUSY"}'  # No commit: client still cannot assume this.
                    else:
                        try:
                            response = urlopen(Request(base + self.path, data=body, headers=headers, method=self.command), timeout=10)
                        except HTTPError as error:
                            response = error
                        with response:
                            data, status = response.read(), response.code
                        if create_request and create_request['display_name'] == '界面青衫' and first_of_name and status == 201:
                            status, data = 503, b'{"code":"SERVER_BUSY"}'
                    self.send_response(status)
                    self.send_header('Content-Type', 'application/json')
                    self.send_header('Content-Length', str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)

            proxy = ThreadingHTTPServer(('127.0.0.1', 0), Proxy)
            thread = threading.Thread(target=proxy.serve_forever, daemon=True)
            thread.start()
            try:
                ui_env = dict(env, SSJX_TEST_SERVER_URL=f'http://127.0.0.1:{proxy.server_port}',
                              SSJX_NICKNAME_VECTORS=str(ROOT / 'shared/protocol/nickname-v1.json'))
                capture = os.environ.get('SSJX_CHARACTER_CAPTURE_PATH', '')
                if capture:
                    Path(capture).mkdir(parents=True, exist_ok=True)
                    ui_env['SSJX_CHARACTER_CAPTURE_PATH'] = capture
                command = [sys.executable, str(ROOT / 'tests/run_offscreen.py'), '--rendering-driver', 'opengl3_es'] if args.render else [os.environ.get('GODOT_BIN', 'godot'), '--headless']
                command += ['--path', str(ROOT / 'client'), 'res://tests/online_characters_test.tscn']
                ui = subprocess.run(command, env=ui_env, capture_output=True, text=True, timeout=90)
                print(ui.stdout, end='')
                print(ui.stderr, end='', file=sys.stderr)
                assert ui.returncode == 0 and '0 failures' in ui.stdout and not re.search(r'(^ERROR:|SCRIPT ERROR)', ui.stderr, re.M)
                retries = [post for post in posts if post['display_name'] == '界面青衫']
                assert len(retries) == 2 and retries[0] == retries[1]
                pending_retries = [post for post in posts if post['display_name'] == '未决修士']
                assert len(pending_retries) == 2 and pending_retries[0] == pending_retries[1]
                assert db.query("SELECT count(*) FROM characters WHERE display_name='界面青衫';") == '1'
            finally:
                proxy.shutdown()
                proxy.server_close()
                thread.join(timeout=5)

            subprocess.run(['docker', 'pause', db.name], check=True, capture_output=True)
            try:
                assert create(first, original)[0] == 503
                assert api('/readyz')[0] == 503
                assert api('/healthz')[0] == 200
            finally:
                subprocess.run(['docker', 'unpause', db.name], check=True, capture_output=True)
            assert create(first, original)[1]['character']['id'] == character['id']
            print('PASS: character uniqueness, same-account/name races, durable receipts, rollback, restart, auth, outage, UI and unknown-response replay')
        finally:
            logs.append(stop(process))
            assert password not in ''.join(logs) and db.password not in ''.join(logs)


if __name__ == '__main__':
    main()
