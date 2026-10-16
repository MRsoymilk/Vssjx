"""Real PostgreSQL + Rust + Godot account authentication, never a production DB."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from pg_fixture import PostgresFixture
from run_server_connection import wait_for_server

ROOT = Path(__file__).resolve().parents[1]


def stop(process):
    process.terminate()
    try:
        output = process.communicate(timeout=10)[0]
    except subprocess.TimeoutExpired:
        process.kill()
        output = process.communicate()[0]
    return output or ''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--render', action='store_true')
    args = parser.parse_args()
    binary = os.environ.get('SSJX_TEST_SERVER_BIN')
    if not binary:
        subprocess.run(['cargo', 'build', '--locked', '--manifest-path', str(ROOT / 'server/Cargo.toml')], check=True)
        binary = ROOT / 'server/target/debug/vssjx-server'
    with PostgresFixture() as database:
        env = dict(os.environ, SSJX_DATABASE_URL=database.url, SSJX_BIND_ADDR='127.0.0.1:0', RUST_LOG='info', SSJX_ENV_FILE='',
                   SSJX_AUTH_ACCESS_SECONDS='120', SSJX_AUTH_REFRESH_SECONDS='600', SSJX_MONITOR_BIND_ADDR='', SSJX_LOG_DIR='')
        logs = []

        def start():
            process = subprocess.Popen([str(binary)], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            try:
                return process, wait_for_server(process)
            except BaseException:
                stop(process)
                raise

        process, base = start()

        def api(path, payload=None, token=None, raw=None):
            headers = {'Content-Type': 'application/json'}
            if token:
                headers['Authorization'] = 'Bearer ' + token
            body = json.dumps(payload).encode() if payload is not None else raw
            request = Request(base + path, data=body, headers=headers, method='POST' if body is not None or path.endswith('/logout') else 'GET')
            try:
                response = urlopen(request, timeout=10)
            except HTTPError as error:
                response = error
            with response:
                data = response.read()
                return response.code, json.loads(data) if data else {}

        def auth(operation, payload=None, token=None, raw=None):
            return api('/api/v1/auth/' + operation, payload, token, raw)

        password = 'test-password-1234'
        try:
            assert api('/readyz')[0] == 200
            info = api('/api/v1/server-info')[1]
            assert info['stage'] == 'account_auth' and info['capabilities'] == ['account_auth', 'character_creation', 'shared_world', 'public_chat']
            assert auth('register', {'username': 'abc', 'password': 'short'})[0] == 422
            assert auth('register', {'username': 'a!', 'password': password})[0] == 422
            assert auth('register', raw=b'{broken')[0] == 400
            assert auth('register', {'username': 'ignored', 'password': password, 'admin': True})[0] == 400
            assert auth('register', raw=b'x' * 5000)[0] == 400
            status, created = auth('register', {'username': ' Player_One ', 'password': password})
            assert status == 201 and created['account']['username'] == 'player_one'
            assert auth('register', {'username': 'PLAYER_ONE', 'password': password})[0] == 409
            with ThreadPoolExecutor(max_workers=2) as executor:
                statuses = list(executor.map(lambda _: auth('register', {'username': 'race_user', 'password': password})[0], range(2)))
            assert sorted(statuses) == [201, 409]
            assert database.query("SELECT count(*) FROM accounts WHERE username='race_user';") == '1'
            stored = database.query("SELECT password_hash FROM accounts WHERE username='player_one';")
            assert stored.startswith('$argon2id$') and password not in stored
            assert auth('login', {'username': 'player_one', 'password': 'incorrect-password'})[0] == 401
            assert auth('login', {'username': 'missing_user', 'password': password})[0] == 401
            status, session = auth('login', {'username': 'PLAYER_ONE', 'password': password})
            assert status == 200 and len(session['access_token']) == 64 and len(session['refresh_token']) == 64
            assert session['expires_in'] == 120 and session['refresh_expires_in'] == 600
            assert 'password_hash' not in json.dumps(session)
            digest = database.query(f"SELECT encode(access_digest,'hex') FROM sessions WHERE id='{session['session_id']}';")
            assert digest == hashlib.sha256(session['access_token'].encode()).hexdigest()
            assert auth('me', token=session['access_token'])[1]['account'] == created['account']
            assert auth('me')[0] == 401
            assert auth('refresh', {'refresh_token': 'not-a-token'})[0] == 401
            with ThreadPoolExecutor(max_workers=2) as executor:
                refreshed = list(executor.map(lambda _: auth('refresh', {'refresh_token': session['refresh_token']}), range(2)))
            assert sorted(status for status, _ in refreshed) == [200, 401]
            rotated = next(data for status, data in refreshed if status == 200)
            assert auth('me', token=session['access_token'])[0] == 401
            assert auth('me', token=rotated['access_token'])[0] == 200
            assert rotated['refresh_expires_in'] <= session['refresh_expires_in']
            logs.append(stop(process))
            process, base = start()
            assert auth('me', token=rotated['access_token'])[0] == 200
            assert auth('logout', token=rotated['access_token'])[0] == 204
            assert auth('logout', token=rotated['access_token'])[0] == 204
            assert auth('me', token=rotated['access_token'])[0] == 401
            assert auth('refresh', {'refresh_token': rotated['refresh_token']})[0] == 401
            _, session = auth('login', {'username': 'player_one', 'password': password})
            database.query(f"UPDATE sessions SET access_expires_at=NOW()-INTERVAL '1 second' WHERE id='{session['session_id']}';")
            assert auth('me', token=session['access_token'])[0] == 401
            status, session = auth('refresh', {'refresh_token': session['refresh_token']})
            assert status == 200
            database.query("UPDATE accounts SET disabled=TRUE WHERE username='player_one';")
            assert auth('me', token=session['access_token'])[0] == 401
            assert auth('refresh', {'refresh_token': session['refresh_token']})[0] == 401
            assert auth('login', {'username': 'player_one', 'password': password})[0] == 401
            assert auth('register', {'username': 'logout_race', 'password': password})[0] == 201
            _, race_session = auth('login', {'username': 'logout_race', 'password': password})
            with ThreadPoolExecutor(max_workers=2) as executor:
                refresh_future = executor.submit(auth, 'refresh', {'refresh_token': race_session['refresh_token']})
                logout_future = executor.submit(auth, 'logout', None, race_session['access_token'])
                refresh_status, race_result = refresh_future.result()
                assert logout_future.result()[0] == 204
            assert refresh_status in [200, 401]
            if refresh_status == 200:
                assert auth('me', token=race_result['access_token'])[0] == 401
            assert database.query("SELECT count(*) FROM sessions s JOIN accounts a ON a.id=s.account_id WHERE a.username='logout_race' AND s.revoked_at IS NULL;") == '0'
            ui_env = dict(env, SSJX_TEST_SERVER_URL=base)
            if args.render:
                command = [sys.executable, str(ROOT / 'tests/run_offscreen.py'), '--rendering-driver', 'opengl3_es']
            else:
                command = [os.environ.get('GODOT_BIN', 'godot'), '--headless']
            command += ['--path', str(ROOT / 'client'), 'res://tests/account_auth_test.tscn']
            result = subprocess.run(command, env=ui_env, text=True, capture_output=True, timeout=60)
            print(result.stdout, end='')
            print(result.stderr, end='', file=sys.stderr)
            assert result.returncode == 0 and '0 failures' in result.stdout and not re.search(r'(^ERROR:|SCRIPT ERROR)', result.stderr, re.M)
            subprocess.run(['docker', 'pause', database.name], check=True, capture_output=True)
            try:
                assert api('/healthz')[0] == 200
                assert api('/readyz')[0] == 503
            finally:
                subprocess.run(['docker', 'unpause', database.name], check=True, capture_output=True)
            rate_limited = False
            for _ in range(70):
                if auth('me', token='0' * 64)[0] == 429:
                    rate_limited = True
                    break
            assert rate_limited
            print('PASS: PostgreSQL persistence, Argon2id, account races, rotation, expiry, revocation, restart, readiness and UI')
        finally:
            logs.append(stop(process))
            assert password not in ''.join(logs) and database.password not in ''.join(logs), 'Credentials must not be logged'


if __name__ == '__main__':
    main()
