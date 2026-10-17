"""Equipment commands against an owned PostgreSQL/Rust server, never the live service."""
import os
from pathlib import Path
import subprocess
import threading
import time
from uuid import uuid4
from pg_fixture import PostgresFixture
from run_account_auth import stop
from run_online_maps import MapPlayer
from run_online_pve import api
from run_server_connection import wait_for_server

ROOT = Path(__file__).resolve().parents[1]


def main():
    binary = os.environ.get('SSJX_TEST_SERVER_BIN', str(ROOT / 'server/target/debug/vssjx-server'))
    sockets = []
    with PostgresFixture() as db:
        env = {k:v for k,v in os.environ.items() if not k.startswith('SSJX_')}
        env.update(SSJX_ENV_FILE='', SSJX_DATABASE_URL=db.url, SSJX_BIND_ADDR='127.0.0.1:0',
            SSJX_MONITOR_BIND_ADDR='', SSJX_LOG_DIR='', RUST_LOG='info', SSJX_AUTH_RATE_IP='1000',
            SSJX_AUTH_RATE_ACCOUNT='100', SSJX_WORLD_RECONNECT_SECONDS='1')

        def start():
            p = subprocess.Popen([binary], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 text=True, encoding='utf-8')
            try: address = wait_for_server(p)
            except BaseException: stop(p); raise
            threading.Thread(target=lambda:list(p.stdout), daemon=True).start()
            return p, address

        def create(name):
            password = 'owned-equipment-test-password'
            assert api(base, '/api/v1/auth/register', dict(username=name, password=password))[0] == 201
            code, session = api(base, '/api/v1/auth/login', dict(username=name, password=password))
            assert code == 200
            code, data = api(base, '/api/v1/characters', dict(operation_id=str(uuid4()), display_name=name,
                job=0, gender=0, school=0, rules_version='creation-v1'), session['access_token'])
            assert code == 201, data
            return session, data['character']['id']

        def join(session, cid):
            a = MapPlayer(base, session, cid)
            sockets.append(a)
            return a

        def gear(a, action, target='sword', revision=None, ok=True):
            return a.command('', request=dict(operation_id=str(uuid4()), action=action, target=target,
                expected_revision=revision or a.state['character']['state_revision']), ok=ok)

        process, base = start()
        try:
            session, cid = create('gear_first')
            other, other_id = create('gear_second')
            a = join(session, cid)
            assert a.state['equipment'] == dict(version='equipment-v1', weapon_owned=True, weapon=None)
            assert a.state['stats']['attack'] == 18
            v,_ = gear(a, 'equip', target='unknown', ok=False)
            assert v['code'] == 'INVALID_EQUIPMENT'
            v,_ = gear(a, 'equip', revision='0', ok=False)
            assert v['code'] == 'STALE_EQUIPMENT'
            equipped, request = gear(a, 'equip')
            assert equipped['state']['equipment']['weapon'] == 'sword'
            assert equipped['state']['stats']['attack'] == 23
            assert equipped['state']['attributes']['combat']['physical_attack'] == 23
            replay,_ = a.command('', request=request)
            assert replay['replayed'] and replay['state'] == equipped['state']
            v,_ = gear(a, 'equip', ok=False)
            assert v['code'] == 'EQUIPMENT_UNCHANGED'
            a.close(); stop(process)
            process, base = start()
            a = join(session, cid)
            assert a.state['equipment']['weapon'] == 'sword' and a.state['stats']['attack'] == 23
            gear(a, 'unequip')
            assert a.state['stats']['attack'] == 18 and a.state['equipment']['weapon'] is None
            # An old receipt cannot re-equip a weapon in durable state.
            a.command('', request=request)
            a.close(); a = join(session, cid)
            assert a.state['equipment']['weapon'] is None

            before = a.state['character']['state_revision']
            db.query("CREATE FUNCTION reject_gear_receipt() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'owned rollback probe'; END$$; CREATE TRIGGER reject_gear BEFORE INSERT ON pve_operation_receipts FOR EACH ROW EXECUTE FUNCTION reject_gear_receipt();")
            a.ws.send(dict(type='pve.command', command=dict(operation_id=str(uuid4()), action='equip', target='sword', expected_revision=before)))
            assert a.until('error')['code'] == 'DATABASE_UNAVAILABLE'
            assert db.query(f"SELECT equipped FROM inventory_items WHERE character_id='{cid}' AND definition_id='sword'") == 'f'
            assert db.query(f"SELECT state_revision FROM characters WHERE id='{cid}'") == before
            db.query('DROP TRIGGER reject_gear ON pve_operation_receipts; DROP FUNCTION reject_gear_receipt();')
            a.close(); a = join(session, cid)
            a.move([20,16])
            for _ in range(30):
                a.until('world.delta')
                if a.ws.entities[cid]['next_cell'] is not None: break
            v,_ = gear(a, 'equip', ok=False)
            assert v['code'] == 'PLAYER_MOVING'
            a.walk([20,16])
            gear(a, 'equip')
            a.approach('qingwei'); a.command('accept', 'qingwei')
            a.approach('wolf_a'); a.command('challenge', 'wolf_a')
            v,_ = gear(a, 'unequip', ok=False)
            assert v['code'] == 'BATTLE_ACTIVE' and a.state['stats']['attack'] == 23
            hp = a.state['battle']['enemy_hp']
            a.command('attack')
            assert 18 <= hp - a.state['battle']['enemy_hp'] <= 22
            a.command('flee')
            a.close(); a = join(session, cid)
            gear(a, 'unequip')
            db.query(f"DELETE FROM inventory_items WHERE character_id='{cid}' AND definition_id='sword'")
            a.close(); a = join(session, cid)
            assert not a.state['equipment']['weapon_owned']
            v,_ = gear(a, 'equip', ok=False)
            assert v['code'] == 'WEAPON_NOT_OWNED'
            b = join(other, other_id)
            assert b.state['equipment']['weapon'] is None and b.state['equipment']['weapon_owned']
            assert b.state['stats']['attack'] == 18
            print('ONLINE EQUIPMENT: ownership, revisions, replay, rollback, restart, movement, battle damage and isolation PASS')

            if os.environ.get('GODOT_BIN'):
                create('gear_ui')
                client_env = dict(os.environ, SSJX_GEAR_TEST_BASE=base,
                                  SSJX_GEAR_TEST_PASSWORD='owned-equipment-test-password')
                args = [os.environ['GODOT_BIN'], '--path', str(ROOT/'client')]
                if os.environ.get('SSJX_GEAR_RENDER') != '1': args.append('--headless')
                result = subprocess.run(args + ['res://tests/online_equipment_live_test.tscn'],
                    env=client_env, capture_output=True, text=True, encoding='utf-8', timeout=90)
                print(result.stdout); print(result.stderr)
                assert result.returncode == 0 and '0 failures' in result.stdout and 'SCRIPT ERROR' not in result.stderr
        finally:
            for a in sockets:
                try: a.close()
                except OSError: pass
            stop(process)


if __name__ == '__main__': main()
