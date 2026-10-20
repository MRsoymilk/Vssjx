"""Owned disposable PostgreSQL + Rust/WebSocket formation persistence and settlement."""
import copy
import json
import os
from pathlib import Path
import subprocess
import threading
import time
from uuid import uuid4
from pg_fixture import PostgresFixture
from run_online_pve import ROOT, Player, api
from run_account_auth import stop
from run_server_connection import wait_for_server


def main():
    checks = 0
    def check(value, text):
        nonlocal checks
        assert value, text
        checks += 1
    with PostgresFixture() as db:
        env = {k: v for k, v in os.environ.items() if not k.startswith('SSJX_')}
        env.update(SSJX_ENV_FILE='', SSJX_DATABASE_URL=db.url, SSJX_BIND_ADDR='127.0.0.1:0',
                   SSJX_MONITOR_BIND_ADDR='', SSJX_LOG_DIR='', RUST_LOG='info',
                   SSJX_AUTH_RATE_IP='1000', SSJX_AUTH_RATE_ACCOUNT='1000', SSJX_AUTH_RATE_GLOBAL='10000',
                   SSJX_WORLD_RECONNECT_SECONDS='1')
        def start():
            p = subprocess.Popen([os.environ['SSJX_TEST_SERVER_BIN']], env=env,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf8')
            try:
                base = wait_for_server(p)
            except BaseException:
                stop(p)
                raise
            threading.Thread(target=lambda: list(p.stdout), daemon=True).start()
            return p, base
        process, base = start()
        a = None
        try:
            password = 'owned-solo-encounter-password'
            check(api(base, '/api/v1/auth/register', dict(username='solo_test', password=password))[0] == 201, 'register')
            _, session = api(base, '/api/v1/auth/login', dict(username='solo_test', password=password))
            status, created = api(base, '/api/v1/characters', dict(operation_id=str(uuid4()), display_name='阵列修士', job=1, gender=0, school=3, rules_version='creation-v1'), session['access_token'])
            check(status == 201, created)
            char = created['character']['id']
            db.query(f"UPDATE characters SET level=60,hp=1000,mp=400,quest_stage=1 WHERE id='{char}'")
            a = Player(base, session, char)
            a.approach('wolf_a')
            for _ in range(40):
                value, challenge = a.command('', request=dict(operation_id=str(uuid4()), action='challenge', target='wolf_a', encounter_version=1))
                b = value['state']['battle']
                check(1 <= len(b['formation']['enemies']) <= 3, 'bounded solo population')
                replay, _ = a.command('', request=challenge)
                check(replay['replayed'] and replay['state'] == value['state'], 'challenge replay does not reroll formation')
                if len(b['formation']['enemies']) > 1:
                    break
                a.command('flee')
            check(len(b['formation']['enemies']) > 1, 'actual challenge can create reinforcements')
            ids = [e['definition']['id'] for e in b['formation']['enemies']]
            check(len(set(ids)) == len(ids) and ids[0] == 'wolf_a', 'unique residents with requested primary')
            operation = dict(operation_id=str(uuid4()), action='attack', battle_id=b['id'], expected_revision=b['revision'], enemy_slot='m9')
            rejected, _ = a.command('', request=operation, ok=False)
            check(rejected['code'] == 'INVALID_BATTLE_TARGET' and rejected['state']['battle'] == b, 'invalid slot is atomic')
            target = b['formation']['enemies'][-1]['slot']
            operation.update(operation_id=str(uuid4()), enemy_slot=target)
            value, _ = a.command('', request=operation)
            check(any(e['actor'] == char and e['target'] == target and e['action'] == 'attack' for e in value['state']['battle']['formation']['events']), 'selected slot drives authority')
            replay, _ = a.command('', request=operation)
            check(replay['replayed'] and replay['state'] == value['state'], 'turn replay is unchanged')
            stale = dict(operation, operation_id=str(uuid4()))
            rejected, _ = a.command('', request=stale, ok=False)
            check(rejected['code'] == 'STALE_BATTLE' and rejected['state']['battle'] == value['state']['battle'], 'stale turn spends nothing')
            saved = copy.deepcopy(value['state']['battle'])
            a.close(); a = None; stop(process)
            process, base = start(); a = Player(base, session, char)
            check(a.state['battle'] == saved, 'restart restores formation, HP, effects and events exactly')
            # Set only enemy current HP in the disposable DB, preserving frozen templates/rules.
            a.close(); a = None
            time.sleep(.15)
            for e in saved['formation']['enemies']:
                e['hp'] = 1
            saved['enemy_hp'] = 1
            stored = copy.deepcopy(saved)
            stored['revision'] = int(saved['revision'])
            db.query(f"UPDATE pve_battles SET state=$owned${json.dumps(stored)}$owned$::jsonb WHERE id='{saved['id']}'")
            a = Player(base, session, char)
            fixture = ROOT / 'work/solo-server-state.json'
            fixture.write_text(json.dumps(a.state, ensure_ascii=False), encoding='utf8')
            if os.environ.get('GODOT_BIN'):
                result = subprocess.run([os.environ['GODOT_BIN'], '--headless', '--path', str(ROOT/'client'), 'res://tests/solo_wire_test.tscn'],
                    env=dict(os.environ, SSJX_SOLO_STATE=str(fixture)), capture_output=True, text=True, encoding='utf8', timeout=30)
                check(result.returncode == 0 and 'SOLO WIRE: PASS' in result.stdout and 'SCRIPT ERROR' not in result.stderr, result.stdout+result.stderr)
            gold = a.state['character']['gold']
            expected = sum(e['definition']['gold'] for e in saved['formation']['enemies'])
            for _ in range(12):
                b = a.state['battle']
                if b['outcome'] != 'active':
                    break
                target = next(e['slot'] for e in b['formation']['enemies'] if e['hp'] > 0)
                command = dict(operation_id=str(uuid4()), action='attack', battle_id=b['id'], expected_revision=b['revision'], enemy_slot=target)
                value, _ = a.command('', request=command)
            check(a.state['battle']['outcome'] == 'victory', 'victory requires defeating all enemies')
            check(a.state['character']['gold'] == gold+expected, 'whole encounter pays every resident once')
            check(set(ids) <= set(a.state['progress']['defeated']), 'quest and respawn progress records all defeated residents')
            check(all(i in a.state['progress']['respawns'] for i in ids), 'reinforcements receive respawn cooldown')
            replay, _ = a.command('', request=command)
            check(replay['replayed'] and replay['state']['character']['gold'] == gold+expected, 'settlement replay cannot pay twice')
            persisted = int(db.query(f"SELECT gold FROM characters WHERE id='{char}'"))
            check(persisted == gold+expected, 'reward is durable')
            # An expansion map with one mob template can still reinforce its boss;
            # the primary compatibility envelope must keep its original HP template.
            from run_ai_world import AIPlayer
            ai_map = json.loads((ROOT/'shared/data/ai-world-v1.json').read_text(encoding='utf8'))['maps'][0]
            boss = next(d for d in ai_map['residents'] if d['kind'] == 'boss')
            a.close(); a = None; time.sleep(.15)
            db.query(f"UPDATE characters SET map_id='{ai_map['map_id']}',cell_x={boss['cell'][0]},cell_y={boss['cell'][1]} WHERE id='{char}'")
            stop(process); process, base = start()
            a = AIPlayer(base, session, char)
            for _ in range(40):
                a.command('', request=dict(operation_id=str(uuid4()), action='challenge', target=boss['id'], encounter_version=1))
                if len(a.state['battle']['formation']['enemies']) > 1:
                    break
                a.command('flee')
            group = a.state['battle']['formation']
            check(len(group['enemies']) > 1 and sum(e['definition']['kind']=='boss' for e in group['enemies']) == 1, 'expansion reinforcements never duplicate the boss')
            check(sum(e['hp'] for e in group['enemies']) == boss['hp']*4 and a.state['battle']['enemy']['hp'] == boss['hp']*4, 'boss budget and legacy primary template are both preserved')
            if os.environ.get('GODOT_BIN'):
                fixture.write_text(json.dumps(a.state, ensure_ascii=False), encoding='utf8')
                result = subprocess.run([os.environ['GODOT_BIN'], '--headless', '--path', str(ROOT/'client'), 'res://tests/solo_wire_test.tscn'],
                    env=dict(os.environ, SSJX_SOLO_STATE=str(fixture)), capture_output=True, text=True, encoding='utf8', timeout=30)
                check(result.returncode == 0 and 'SOLO WIRE: PASS' in result.stdout and 'SCRIPT ERROR' not in result.stderr, result.stdout+result.stderr)
            print(f'SOLO SERVER: {checks} checks, 0 failures')
        finally:
            if a:
                a.close()
            stop(process)


if __name__ == '__main__':
    main()
