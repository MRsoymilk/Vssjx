"""Session-cap recovery against an isolated PostgreSQL/Rust instance."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import os
from pathlib import Path
import subprocess
import threading
from uuid import uuid4

from pg_fixture import PostgresFixture
from run_account_auth import stop
from run_online_pve import Player, api
from run_server_connection import wait_for_server

ROOT = Path(__file__).resolve().parents[1]


def main():
    suffix = '.exe' if os.name == 'nt' else ''
    binary = os.environ.get('SSJX_TEST_SERVER_BIN', str(ROOT / 'server/target/debug' / ('vssjx-server' + suffix)))
    checks = 0

    def check(condition, message):
        nonlocal checks
        checks += 1
        assert condition, message

    with PostgresFixture() as db:
        env = {key: value for key, value in os.environ.items() if not key.startswith('SSJX_')}
        env.update(SSJX_ENV_FILE='', SSJX_DATABASE_URL=db.url, SSJX_BIND_ADDR='127.0.0.1:0',
                   SSJX_MONITOR_BIND_ADDR='', SSJX_LOG_DIR='', RUST_LOG='info',
                   SSJX_AUTH_MAX_SESSIONS='3', SSJX_AUTH_RATE_ACCOUNT='1000',
                   SSJX_AUTH_RATE_IP='1000', SSJX_AUTH_RATE_GLOBAL='10000')
        processes, sockets, logs = [], [], []

        def start():
            process = subprocess.Popen([binary], env=env, stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, text=True, encoding='utf-8')
            processes.append(process)
            base = wait_for_server(process)
            threading.Thread(target=lambda: logs.extend(process.stdout), daemon=True).start()
            return process, base

        process, base = start()
        password = 'owned-session-cap-password'

        def auth(action, payload=None, token=None):
            return api(base, '/api/v1/auth/' + action, payload, token)

        def login(name='session_owner', secret=password):
            return auth('login', dict(username=name, password=secret))

        def count():
            return int(db.query("SELECT count(*) FROM sessions s JOIN accounts a ON a.id=s.account_id WHERE a.username='session_owner'"))

        try:
            for username in ('session_owner', 'session_other'):
                check(auth('register', dict(username=username, password=password))[0] == 201, 'Create owned account')
            code, other = login('session_other')
            check(code == 200, 'Other account logged in')
            issued = []
            for _ in range(3):
                code, session = login()
                check(code == 200, 'Fill original session cap')
                issued.append(session)
            check(count() == 3, 'Cap is reached before regression case')
            code, created = api(base, '/api/v1/characters', dict(operation_id=str(uuid4()),
                                display_name='会话回归', job=0, gender=0, school=0, rules_version='creation-v1'),
                                issued[0]['access_token'])
            check(code == 201, 'Create character owned by oldest session')
            character_id = created['character']['id']
            old_world = Player(base, issued[0], character_id)
            sockets.append(old_world)
            code, _ = api(base, '/api/v1/world/ticket', dict(character_id=character_id, protocol_version=1,
                          config_hash=hashlib.sha256((ROOT / 'shared/data/qingyun-v1.json').read_bytes()).hexdigest()),
                          issued[0]['access_token'])
            check(code == 200, 'Old session also has an outstanding world ticket')
            check(login(secret='incorrect-session-password')[0] == 401, 'Wrong password rejected at cap')
            check(count() == 3 and auth('me', token=issued[0]['access_token'])[0] == 200, 'Wrong password cannot evict existing sessions')
            code, newest = login()
            check(code == 200 and count() == 3, 'Fourth valid login succeeds without increasing cap')
            check(auth('me', token=issued[0]['access_token'])[0] == 401, 'Evicted access token cannot read account')
            check(auth('refresh', dict(refresh_token=issued[0]['refresh_token']))[0] == 401, 'Evicted refresh token cannot restore session')
            check(db.query(f"SELECT count(*) FROM world_tickets WHERE session_id='{issued[0]['session_id']}'") == '0', 'Eviction invalidates outstanding world tickets')
            for session in issued[1:]:
                check(auth('me', token=session['access_token'])[0] == 200, 'Recent sessions survive oldest eviction')
            check(auth('me', token=other['access_token'])[0] == 200, 'Other account unaffected')
            replacement_world = Player(base, newest, character_id)
            sockets.append(replacement_world)
            check(replacement_world.id == character_id and replacement_world.state['character']['display_name'] == '会话回归', 'New session can enter same persistent character after old session eviction')
            for player in sockets: player.close()
            sockets.clear()
            with ThreadPoolExecutor(max_workers=2) as executor:
                parallel = list(executor.map(lambda _: login(), range(2)))
            check(all(code == 200 for code, _ in parallel) and count() == 3, 'Concurrent successful logins keep exact cap')
            for _, session in parallel:
                check(auth('me', token=session['access_token'])[0] == 200, 'Concurrent newest credentials remain valid')
            current = parallel[-1][1]
            before_ids = db.query("SELECT string_agg(id::text,',' ORDER BY id) FROM sessions WHERE account_id=(SELECT id FROM accounts WHERE username='session_owner')")
            db.query("CREATE FUNCTION reject_session_probe() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'owned session rollback probe'; END$$; CREATE TRIGGER reject_session_insert BEFORE INSERT ON sessions FOR EACH ROW EXECUTE FUNCTION reject_session_probe();")
            check(login()[0] == 503, 'Insert failure is reported')
            after_ids = db.query("SELECT string_agg(id::text,',' ORDER BY id) FROM sessions WHERE account_id=(SELECT id FROM accounts WHERE username='session_owner')")
            check(before_ids == after_ids and auth('me', token=current['access_token'])[0] == 200, 'Failed replacement rolls eviction back atomically')
            db.query('DROP TRIGGER reject_session_insert ON sessions; DROP FUNCTION reject_session_probe();')
            stop(process)
            env['SSJX_AUTH_MAX_SESSIONS'] = '1'
            process, base = start()
            code, last = login()
            check(code == 200 and count() == 1, 'Lowered cap recovers preexisting excess sessions in one login')
            check(auth('me', token=current['access_token'])[0] == 401 and auth('me', token=last['access_token'])[0] == 200, 'Cap one revokes prior credentials and retains new credentials')
            check(auth('me', token=other['access_token'])[0] == 200, 'Other account remains valid across restart and cap change')
            check(password not in ''.join(logs) and db.password not in ''.join(logs), 'No test credentials logged')
            print(f'SESSION CAP RECOVERY: {checks} checks, 0 failures')
        finally:
            for player in sockets: player.close()
            for owned in processes:
                if owned.poll() is None: stop(owned)


if __name__ == '__main__':
    main()
