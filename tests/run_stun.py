"""Stun persistence/replay/rollback against an owned PostgreSQL and Rust server."""
import copy
import json
import os
import subprocess
import threading
import time
from uuid import uuid4
from pg_fixture import PostgresFixture
from run_account_auth import stop
from run_online_pve import ROOT, Player, api
from run_server_connection import wait_for_server


def main():
    binary = os.environ.get('SSJX_TEST_SERVER_BIN', str(ROOT/'server/target/debug/vssjx-server'))
    with PostgresFixture() as db:
        env = {k: v for k, v in os.environ.items() if not k.startswith('SSJX_')}
        env.update(SSJX_ENV_FILE='', SSJX_DATABASE_URL=db.url, SSJX_BIND_ADDR='127.0.0.1:0',
                   SSJX_MONITOR_BIND_ADDR='', SSJX_LOG_DIR='', RUST_LOG='info',
                   SSJX_AUTH_RATE_IP='1000', SSJX_AUTH_RATE_GLOBAL='10000', SSJX_AUTH_RATE_ACCOUNT='100')

        def start():
            process = subprocess.Popen([binary], env=env, stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, text=True)
            try:
                base = wait_for_server(process)
            except BaseException:
                stop(process)
                raise
            threading.Thread(target=lambda: list(process.stdout), daemon=True).start()
            return process, base

        process, base = start()
        clients = []
        try:
            password = 'owned-stun-test-password'
            assert api(base, '/api/v1/auth/register', dict(username='stun_test', password=password))[0] == 201
            code, session = api(base, '/api/v1/auth/login', dict(username='stun_test', password=password))
            assert code == 200
            code, created = api(base, '/api/v1/characters', dict(operation_id=str(uuid4()), display_name='雷霆眩晕', job=0, gender=0, school=3, rules_version='creation-v1'), session['access_token'])
            assert code == 201, created
            char = created['character']['id']
            db.query(f"UPDATE characters SET level=60,hp=500,mp=200,quest_stage=1 WHERE id='{char}'")
            a = Player(base, session, char); clients.append(a)
            a.approach('wolf_a')
            a.command('', request=dict(operation_id=str(uuid4()), action='challenge', target='wolf_a', encounter_version=2))
            battle_id = a.state['battle']['id']
            template = json.loads(db.query(f"SELECT state::text FROM pve_battles WHERE id='{battle_id}'"))
            assert template['formation']['fighters'][0]['effects']['balance']['stun_revision'] == 1
            # Keep the owned test target alive without changing production definitions.
            template['formation']['enemies'] = template['formation']['enemies'][:1]
            enemy = template['formation']['enemies'][0]
            enemy['hp'] = enemy['definition']['hp'] = template['enemy_hp'] = template['enemy']['hp'] = 100000
            enemy['definition']['attack'] = template['enemy']['attack'] = 1
            a.close()
            db.query(f"UPDATE pve_battles SET state=$owned${json.dumps(template)}$owned$::jsonb WHERE id='{battle_id}'")
            a = Player(base, session, char); clients.append(a)

            def skill_request():
                return dict(operation_id=str(uuid4()), action='skill', target='sheet_010',
                            enemy_slot='m0', battle_id=battle_id, expected_revision=a.state['battle']['revision'])

            proc = None
            for _ in range(30):
                while a.state['battle']['formation']['fighters'][0]['effects']['balance']['cooldowns'].get('sheet_010', 0):
                    a.command('guard')
                    time.sleep(.06)
                result, request = a.command('', request=skill_request())
                events = result['state']['battle']['formation']['events']
                if any(event['action'] == 'stun' for event in events):
                    proc = result, request
                    break
                time.sleep(.06)
            assert proc is not None, 'No landed 35% stun within 30 casts'
            result, request = proc
            battle = copy.deepcopy(result['state']['battle'])
            events = battle['formation']['events']
            assert sum(event['action'] == 'stun' for event in events) == 1
            assert not any(event['actor'] == 'm0' and event['action'] in ('attack', 'skill') for event in events)
            assert not battle['formation']['enemies'][0]['effects'].get('enemy_stun', 0)
            assert battle['formation']['fighters'][0]['effects']['balance']['cooldowns']['sheet_010'] == 3
            replay, _ = a.command('', request=request)
            assert replay['replayed'] and replay['state']['battle'] == battle
            rejected, _ = a.command('', request=skill_request(), ok=False)
            assert rejected['code'] == 'SKILL_COOLDOWN' and rejected['state']['battle'] == battle

            a.close(); stop(process); process, base = start()
            a = Player(base, session, char); clients.append(a)
            assert a.state['battle'] == battle, 'Restart must keep the exact frozen revision, cooldown and result'
            replay, _ = a.command('', request=request)
            assert replay['replayed'] and replay['state']['battle'] == battle
            for _ in range(3):
                a.command('guard'); time.sleep(.06)
            before = copy.deepcopy(a.state['battle'])
            pending = skill_request()
            db.query("CREATE FUNCTION reject_stun_receipt() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'owned stun rollback'; END$$; CREATE TRIGGER reject_stun_receipt BEFORE INSERT ON pve_operation_receipts FOR EACH ROW EXECUTE FUNCTION reject_stun_receipt();")
            a.ws.send(dict(type='pve.command', command=pending))
            assert a.until('error')['code'] == 'DATABASE_UNAVAILABLE'
            db.query('DROP TRIGGER reject_stun_receipt ON pve_operation_receipts; DROP FUNCTION reject_stun_receipt();')
            a.close(); a = Player(base, session, char); clients.append(a)
            assert a.state['battle'] == before, 'Receipt failure cannot spend mana, apply stun or start cooldown'
            result, _ = a.command('', request=pending)
            replay, _ = a.command('', request=pending)
            assert replay['replayed'] and replay['state']['battle'] == result['state']['battle']

            # Simulate a pre-feature saved formation: missing marker never opts in.
            a.close()
            old = json.loads(db.query(f"SELECT state::text FROM pve_battles WHERE id='{battle_id}'"))
            for effects in [old['skills'], old['formation']['fighters'][0]['effects']]:
                effects.pop('enemy_stun', None)
                effects['balance'].pop('stun_revision', None)
                effects['balance']['cooldowns'] = {}
            db.query(f"UPDATE pve_battles SET state=$owned${json.dumps(old)}$owned$::jsonb WHERE id='{battle_id}'")
            a = Player(base, session, char); clients.append(a)
            result, _ = a.command('', request=skill_request())
            assert not any(event['action'] == 'stun' for event in result['state']['battle']['formation']['events'])
            assert not result['state']['battle']['formation']['fighters'][0]['effects']['balance']['cooldowns'].get('sheet_010', 0)
            print('STUN LIVE: PASS (new formation, actual proc/skip, cooldown, replay, reconnect/restart, atomic rollback, original-ID retry, pre-feature save)')
        finally:
            for client in clients:
                try:
                    client.close()
                except OSError:
                    pass
            stop(process)


if __name__ == '__main__':
    main()
