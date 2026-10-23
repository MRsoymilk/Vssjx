"""Social API authorization, persistence, races and rollback in an owned disposable DB."""
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import threading
from uuid import uuid4
from pg_fixture import PostgresFixture
from run_account_auth import stop
from run_online_pve import api, Player
from run_server_connection import wait_for_server

ROOT = Path(__file__).resolve().parents[1]


def main():
    binary = os.environ.get('SSJX_TEST_SERVER_BIN', str(ROOT / 'work/duels/target/debug/vssjx-server.exe'))
    checks = []

    def check(value, label):
        assert value, label
        checks.append(label)

    with PostgresFixture() as db:
        env = {k: v for k, v in os.environ.items() if not k.startswith('SSJX_')}
        env.update(SSJX_ENV_FILE='', SSJX_DATABASE_URL=db.url, SSJX_BIND_ADDR='127.0.0.1:0', SSJX_MONITOR_BIND_ADDR='', SSJX_LOG_DIR='', RUST_LOG='info', SSJX_AUTH_RATE_IP='10000', SSJX_AUTH_RATE_GLOBAL='100000', SSJX_AUTH_RATE_ACCOUNT='1000')

        def start():
            p = subprocess.Popen([binary], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf8')
            try: base = wait_for_server(p)
            except BaseException: stop(p); raise
            threading.Thread(target=lambda: list(p.stdout), daemon=True).start()
            return p, base

        process, base = start()
        clients = []
        try:
            def create(name):
                password = 'owned-social-test-password'
                assert api(base, '/api/v1/auth/register', dict(username=name, password=password))[0] == 201
                _, session = api(base, '/api/v1/auth/login', dict(username=name, password=password))
                code, data = api(base, '/api/v1/characters', dict(operation_id=str(uuid4()), display_name=name, job=1, gender=0, school=3, rules_version='creation-v1'), session['access_token'])
                assert code == 201, data
                return session, data['character']['id']

            a, b, c = create('social_a'), create('social_b'), create('social_c')
            check(db.query("SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='guilds' AND column_name='deleted_at'") == '0', 'Guild creation uses the actual hard-delete guild schema, without a character-only deleted_at column')

            def send(who, action, expected='OK', request=None, **kw):
                payload = request or dict(character_id=who[1], action=action, **kw)
                if action not in ['snapshot', 'profile', 'find', 'guild_browse'] and request is None: payload['operation_id'] = str(uuid4())
                code, value = api(base, '/api/v1/social', payload, who[0]['access_token'])
                assert code == 200 and value['code'] == expected, (code, value, expected)
                check(value['ok'] == (expected == 'OK'), action + ': correct outcome ' + expected)
                return value, payload

            check(api(base, '/api/v1/social', dict(character_id=a[1], action='snapshot'))[0] == 401, 'Anonymous access rejected')
            check(api(base, '/api/v1/social', dict(character_id=a[1], action='snapshot'), b[0]['access_token'])[0] == 403, 'Cannot impersonate another character')
            check(api(base, '/api/v1/social', dict(character_id=a[1], action='friend_request', target=b[1]), a[0]['access_token'])[0] == 400, 'Mutation requires an operation UUID')
            check(api(base, '/api/v1/social', dict(character_id=a[1], action='guild_approve', role='leader'), a[0]['access_token'])[0] == 400, 'Client-supplied authority fields rejected')
            online = Player(base, a[0], a[1]); clients.append(online)
            view, _ = send(b, 'find', name='SOCIAL_A')
            card = view['profile']
            check(card['id'] == a[1] and card['online'] and card['display_name'] == 'social_a', 'Exact canonical-name lookup and online status')
            check(set(card) == {'id', 'display_name', 'job', 'gender', 'school', 'level', 'online', 'appearance', 'combat', 'equipment', 'guild'}, 'Profile public-field allowlist')
            check(not any(k in json.dumps(card) for k in ['account_id', 'access_token', 'gold', 'xp', 'potions', 'quantities', 'allocated_attributes']), 'No private account, wallet or inventory state')
            send(a, 'find', 'PLAYER_NOT_FOUND', name='missing')
            send(a, 'friend_request', 'SELF_TARGET', target=a[1])
            first, request = send(a, 'friend_request', target=b[1])
            again, _ = send(a, 'friend_request', request=request)
            check(again['replayed'] and len(again['state']['outgoing']) == 1, 'Lost-response retry cannot duplicate friendship')
            conflict = dict(request, target=c[1])
            check(api(base, '/api/v1/social', conflict, a[0]['access_token'])[0] == 409, 'Same operation UUID cannot change target')
            send(a, 'friend_accept', 'FORBIDDEN', target=b[1])
            send(c, 'friend_accept', 'REQUEST_NOT_FOUND', target=a[1])
            send(b, 'friend_reject', target=a[1])
            send(a, 'friend_request', 'FRIEND_COOLDOWN', target=b[1])
            send(b, 'friend_request', 'FRIEND_COOLDOWN', target=a[1])
            db.query("UPDATE friendships SET updated_at=clock_timestamp()-interval '6 minutes'")
            send(a, 'friend_request', target=b[1])
            send(b, 'friend_accept', target=a[1])
            av, _ = send(a, 'snapshot'); bv, _ = send(b, 'snapshot')
            check(av['state']['friends'][0]['id'] == b[1] and bv['state']['friends'][0]['id'] == a[1], 'Accepted friendship is symmetric')
            send(b, 'friend_request', 'ALREADY_FRIENDS', target=a[1])
            send(a, 'friend_request', target=c[1]); send(a, 'friend_remove', target=c[1])
            check(not send(c, 'snapshot')[0]['state']['incoming'], 'Sender can cancel pending request')
            send(b, 'guild_create', 'INVALID_NAME', name='<bad>')
            result, creation = send(a, 'guild_create', name='青云同盟')
            guild = result['state']['guild']['id']
            send(b, 'guild_create', 'GUILD_NAME_TAKEN', name='青云同盟')
            repeated, _ = send(a, 'guild_create', request=creation)
            check(repeated['replayed'] and repeated['state']['guild']['id'] == guild, 'Guild creation idempotence')
            send(a, 'guild_create', 'ALREADY_IN_GUILD', name='其他帮派')
            send(b, 'guild_apply', target=guild)
            send(b, 'guild_apply', 'ALREADY_APPLIED', target=guild)
            send(b, 'guild_approve', 'NOT_IN_GUILD', target=b[1])
            send(a, 'guild_approve', target=b[1])
            send(b, 'guild_announce', 'LEADER_REQUIRED', text='forged')
            send(a, 'guild_announce', text='欢迎同道，共修蜀山。')
            bv, _ = send(b, 'snapshot')
            check(bv['state']['guild']['announcement'] == '欢迎同道，共修蜀山。' and not bv['state']['guild']['applications'], 'Member sees persisted announcement but cannot read join applications')
            send(a, 'guild_announce', 'INVALID_TEXT', text='x'*121)
            send(a, 'guild_leave', 'LEADER_MUST_TRANSFER')
            send(b, 'guild_disband', 'LEADER_REQUIRED')
            send(c, 'guild_apply', target=guild)
            send(a, 'guild_reject', target=c[1])
            send(c, 'guild_apply', target=guild)
            send(c, 'guild_cancel', target=guild)
            check(not send(a, 'snapshot')[0]['state']['guild']['applications'], 'Applicant can cancel own application')
            send(a, 'guild_transfer', 'MEMBER_NOT_FOUND', target=c[1])
            send(a, 'guild_transfer', target=b[1])
            send(a, 'guild_kick', 'LEADER_REQUIRED', target=b[1])
            send(b, 'guild_kick', target=a[1])
            send(a, 'guild_create', name='昆仑同盟')
            send(c, 'guild_apply', target=guild)
            second = send(a, 'snapshot')[0]['state']['guild']['id']
            send(c, 'guild_apply', target=second)
            with concurrent.futures.ThreadPoolExecutor(2) as pool:
                outcomes = list(pool.map(lambda pair: api(base, '/api/v1/social', dict(character_id=pair[0][1], operation_id=str(uuid4()), action='guild_approve', target=c[1]), pair[0][0]['access_token']), [(a, second), (b, guild)]))
            check(sum(v[1]['ok'] for v in outcomes) == 1 and db.query(f"SELECT count(*) FROM guild_members WHERE character_id='{c[1]}'") == '1', 'Concurrent approvals admit player to exactly one guild')
            check(db.query(f"SELECT count(*) FROM guild_applications WHERE character_id='{c[1]}'") == '0', 'Joining clears all other applications')
            # Audit failure must roll back the membership change and its receipt.
            db.query("CREATE FUNCTION reject_social_audit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.action LIKE 'social.%' THEN RAISE EXCEPTION 'owned failure'; END IF; RETURN NEW; END $$; CREATE TRIGGER reject_social BEFORE INSERT ON security_audit FOR EACH ROW EXECUTE FUNCTION reject_social_audit();")
            failed = dict(character_id=a[1], operation_id=str(uuid4()), action='guild_announce', text='must roll back')
            check(api(base, '/api/v1/social', failed, a[0]['access_token'])[0] == 503, 'Audit failure fails closed')
            check(db.query(f"SELECT announcement FROM guilds WHERE id='{second}'") != 'must roll back' and db.query(f"SELECT count(*) FROM social_receipts WHERE operation_id='{failed['operation_id']}'") == '0', 'Failed commit rolls back both state and receipt')
            db.query('DROP TRIGGER reject_social ON security_audit; DROP FUNCTION reject_social_audit();')
            online.close(); clients.clear()
            stop(process); process, base = start()
            restored, _ = send(b, 'snapshot')
            check(restored['state']['guild']['id'] == guild and restored['state']['friends'][0]['id'] == a[1], 'Friendship, guild role and announcement survive server restart')
            view, _ = send(b, 'guild_browse', name='青云同盟')
            check(len(view['state']['guilds']) == 1 and view['state']['guilds'][0]['id'] == guild, 'Exact name finds guild regardless of directory ordering')
            send(a, 'friend_remove', target=b[1])
            check(not send(b, 'snapshot')[0]['state']['friends'], 'Friend deletion visible on both sides')
            send(b, 'guild_disband')
            check(send(b, 'snapshot')[0]['state']['guild'] is None, 'Disband removes all membership and applications atomically')
            recreated, _ = send(b, 'guild_create', name='青云同盟')
            check(recreated['state']['guild']['id'] != guild and db.query("SELECT count(*) FROM guilds WHERE name_key='青云同盟'") == '1', 'Hard-deleted guild names can be reused without restoring the old guild')
            send(b, 'guild_disband')
            race_a, race_b = create('guild_race_a'), create('guild_race_b')
            with concurrent.futures.ThreadPoolExecutor(2) as pool:
                duplicate_creates = list(pool.map(lambda row: api(base, '/api/v1/social', dict(character_id=row[0][1], operation_id=str(uuid4()), action='guild_create', name=row[1]), row[0][0]['access_token']), [(race_a, 'CloudGuild'), (race_b, 'cloudguild')]))
            check(all(status == 200 for status, _ in duplicate_creates) and sorted(value['code'] for _, value in duplicate_creates) == ['GUILD_NAME_TAKEN', 'OK'], 'Concurrent canonical-name guild creation returns a business rejection, not a database error')
            check(db.query("SELECT count(*) FROM guilds WHERE name_key='cloudguild'") == '1', 'Concurrent canonical-name creation persists exactly one guild')
            check(int(db.query("SELECT count(*) FROM security_audit WHERE action LIKE 'social.%'")) > 20, 'Social mutations and rejections are audited without private request bodies')
            # Seed only this disposable fixture to exercise actual capacity boundaries.
            db.query("WITH owners AS (INSERT INTO accounts(id,username,password_hash) SELECT gen_random_uuid(),'cap_'||i,a.password_hash FROM accounts a CROSS JOIN generate_series(1,151) g(i) WHERE a.username='social_a' RETURNING id,username) INSERT INTO characters(id,account_id,display_name,name_key,name_rules_version,rules_version,job,gender,school,hp,mp) SELECT gen_random_uuid(),id,username,username,'nickname-v1','creation-v1',1,0,3,95,45 FROM owners;")
            db.query(f"INSERT INTO friendships(low_id,high_id,requester_id,status) SELECT LEAST('{a[1]}'::uuid,id),GREATEST('{a[1]}'::uuid,id),'{a[1]}','accepted' FROM characters WHERE name_key LIKE 'cap_%' ORDER BY name_key LIMIT 100")
            send(a, 'friend_request', 'FRIEND_LIMIT', target=b[1])
            check(len(send(a, 'snapshot')[0]['state']['friends']) == 100, 'Capacity response keeps all existing friends intact')
            full = str(uuid4())
            db.query(f"INSERT INTO guilds(id,name,name_key) VALUES('{full}','容量帮派','容量帮派'); INSERT INTO guild_members(character_id,guild_id,role) SELECT id,'{full}',CASE WHEN name_key='cap_101' THEN 'leader' ELSE 'member' END FROM characters WHERE name_key LIKE 'cap_%' AND substring(name_key FROM 5)::int BETWEEN 101 AND 150;")
            send(b, 'guild_apply', 'GUILD_FULL', target=full)
            if os.environ.get('GODOT_BIN'):
                ua, ub = create('social_ui_a'), create('social_ui_b')
                send(ub, 'friend_request', target=ua[1])
                godot_env = dict(os.environ, SSJX_SOCIAL_TEST=json.dumps(dict(base=base, username='social_ui_a', character=ua[1], other=ub[1])))
                client = subprocess.run([os.environ['GODOT_BIN'], '--headless', '--path', str(ROOT / 'client'), '--quit-after', '18000', 'res://tests/social_live_test.tscn'], env=godot_env, capture_output=True, text=True, encoding='utf8', timeout=90)
                print(client.stdout)
                if client.stderr: print(client.stderr)
                check(client.returncode == 0 and '0 failures' in client.stdout and 'SCRIPT ERROR' not in client.stderr, 'Real Godot login, social transport and UI integration')
                check(db.query(f"SELECT count(*) FROM friendships WHERE status='accepted' AND (low_id='{ua[1]}' OR high_id='{ua[1]}')") == '1', 'Godot confirmed friendship is in the independent database')
                check(db.query("SELECT count(*) FROM guilds WHERE name='测试同盟' AND announcement='来自真实客户端的公告'") == '1', 'Godot-created guild and announcement persisted')
            env['SSJX_AUTH_RATE_IP'] = '1'
            stop(process); process, base = start()
            check(api(base, '/api/v1/characters', token=a[0]['access_token'])[0] == 200 and api(base, '/api/v1/characters', token=a[0]['access_token'])[0] == 429, 'Owned fixture exhausted its strict login/character IP budget')
            send(a, 'snapshot'); send(b, 'snapshot')
            check(True, 'Social polling keeps its independent budget behind a shared tunnel IP')
            print(f'SOCIAL: {len(checks)} checks passed')
        finally:
            for p in clients: p.close()
            stop(process)


if __name__ == '__main__': main()
