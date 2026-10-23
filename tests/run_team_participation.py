"""Owned DB and real sockets: absent members cannot block or receive encounters."""
import json
import os
from pathlib import Path
import subprocess
import threading
import time
from uuid import uuid4

from pg_fixture import PostgresFixture
from run_account_auth import stop
from run_online_pve import api
from run_server_connection import wait_for_server
from run_team_follow import Client

ROOT = Path(__file__).resolve().parents[1]


def main():
    binary = os.environ.get('SSJX_TEST_SERVER_BIN', str(ROOT/'work/duel-planning-target/debug/vssjx-server.exe'))
    checks = []
    clients = []
    last_keepalive = [0.0]

    def check(ok, label):
        assert ok, label
        checks.append(label)

    def keepalive():
        if time.monotonic()-last_keepalive[0] < 2:
            return
        last_keepalive[0] = time.monotonic()
        for client in clients:
            if not client.done:
                try:
                    client.ws.send(dict(type='ping'))
                except OSError as error:
                    raise AssertionError([(v.get('type'), v.get('code')) for v in client.events[-12:]]) from error

    def wait(predicate, label, timeout=10):
        deadline = time.monotonic()+timeout
        last_ping = 0
        while time.monotonic() < deadline:
            if predicate():
                return
            if time.monotonic()-last_ping > 2:
                keepalive()
                last_ping = time.monotonic()
            time.sleep(.05)
        raise AssertionError(label)

    with PostgresFixture() as db:
        env = {k: v for k, v in os.environ.items() if not k.startswith('SSJX_')}
        env.update(SSJX_ENV_FILE='', SSJX_DATABASE_URL=db.url, SSJX_BIND_ADDR='127.0.0.1:0',
                   SSJX_MONITOR_BIND_ADDR='', SSJX_LOG_DIR='', RUST_LOG='info',
                   SSJX_AUTH_RATE_IP='10000', SSJX_AUTH_RATE_GLOBAL='100000', SSJX_AUTH_RATE_ACCOUNT='1000',
                   SSJX_WORLD_RECONNECT_SECONDS='1')
        process = subprocess.Popen([binary], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True, encoding='utf8')
        try:
            base = wait_for_server(process)
            server_lines = []
            def drain():
                for line in process.stdout:
                    server_lines.append(line)
            threading.Thread(target=drain, daemon=True).start()

            def create(name):
                password = 'owned-participation-password'
                assert api(base, '/api/v1/auth/register', dict(username=name, password=password))[0] == 201
                _, session = api(base, '/api/v1/auth/login', dict(username=name, password=password))
                status, result = api(base, '/api/v1/characters', dict(operation_id=str(uuid4()), display_name=name,
                                     job=1, gender=0, school=3, rules_version='creation-v1'), session['access_token'])
                assert status == 201, result
                cid = result['character']['id']
                db.query(f"UPDATE characters SET level=20,hp=437,mp=197,quest_stage=1,cell_x=22,cell_y=9 WHERE id='{cid}'")
                return session, cid

            def connect(identity):
                client = Client(base, identity)
                clients.append(client)
                wait(lambda: client.state and client.own() and client.team, 'World and party baseline')
                return client

            def send(who, action, expected='OK', request=None, **fields):
                keepalive()
                payload = request or dict(character_id=who[1], action=action, **fields)
                if request is None and action != 'snapshot':
                    payload['operation_id'] = str(uuid4())
                status, result = api(base, '/api/v1/teams', payload, who[0]['access_token'])
                check(status == 200 and result['code'] == expected, f'{action}: {expected}: {result}')
                return result, payload

            def party(who):
                return send(who, 'snapshot')[0]['state']['team']

            def resources(who):
                return db.query(f"SELECT hp,mp,gold,xp,quest_stage,defeated_mask,monster_respawns,ai_progress FROM characters WHERE id='{who[1]}'; SELECT definition_id,quantity FROM inventory_items WHERE character_id='{who[1]}' ORDER BY definition_id")

            def win(leader, participants):
                battle = party(leader)['battle']
                last = None
                for _ in range(90):
                    if battle['outcome'] != 'active':
                        break
                    if battle.get('selection_starts_ms',0)>int(time.time()*1000):
                        for peer in participants:
                            if any(f['id']==peer[1] and f['hp']>0 for f in battle['fighters']):
                                result,_=send(peer,'playback_done',battle_id=battle['id'],expected_revision=battle['round_revision'])
                                battle=result['state']['team']['battle']
                    who = next(p for p in participants if p[1] == battle['fighters'][battle['turn']]['id'])
                    result, request = send(who, 'attack', battle_id=battle['id'], expected_revision=battle['revision'],
                                           target=next(e['slot'] for e in battle['enemies'] if e['hp'] > 0))
                    battle = result['state']['team']['battle']
                    last = who, request
                check(battle['outcome'] == 'victory', 'Actual participants can finish the encounter')
                # Modern encounters can roll shared loot. Settle it explicitly
                # before testing follow/leave, without relying on a random drop.
                for drop in battle.get('loot_pool',{}).get('drops',[]):
                    for peer in participants:
                        current=party(leader)['battle'];pool=current['loot_pool']
                        item=next(d for d in pool['drops'] if d['item']['id']==drop['item']['id'])
                        if not item['resolved'] and peer[1] in item['eligible'] and peer[1] not in item['choices']:
                            send(peer,'loot_pass',target=item['item']['id'],battle_id=current['id'],expected_revision=pool['revision'])
                return battle, last

            a, b, c = [create('party_'+suffix) for suffix in ('a', 'b', 'c')]
            ca, cb, cc = [connect(identity) for identity in (a, b, c)]
            for identity in (b, c):
                send(a, 'invite', target=identity[1])
                invite = send(identity, 'snapshot')[0]['state']['incoming'][0]['id']
                send(identity, 'accept', target=invite)
            cb.close()
            wait(lambda: not next(m for m in party(a)['members'] if m['id'] == b[1])['online'], 'Offline state observed')
            # These absent-member conditions must never enter fighter loading.
            db.query(f"UPDATE characters SET quest_stage=0,hp=31,mp=12,defeated_mask=63,monster_respawns='{{\"spirit\":253402300799000}}' WHERE id='{b[1]}'")
            absent = resources(b)
            check(next(m for m in party(a)['members'] if m['id']==c[1])['ready'], 'New members default to prepared without blocking every encounter')
            send(c, 'ready', ready=True)
            initial, _ = send(a, 'challenge', target='spirit')
            battle = initial['state']['team']['battle']
            check([f['id'] for f in battle['fighters']] == [a[1], c[1]], 'Offline, unready member is excluded; leader needs no extra ready click')
            check(len(initial['state']['team']['members']) == 3, 'Excluded member keeps team membership')
            original = next(d for d in json.loads((ROOT/'shared/data/qingyun-population-v1.json').read_text()) if d['id'] == 'spirit')
            # Current balanced characters use the shared monster profile; the
            # +35% HP party multiplier belongs only to frozen legacy battles.
            modern=all(f['stats'].get('balance',{}).get('skills_revision',0)>=1 for f in battle['fighters'])
            expected=original.copy()
            if modern:expected['defense']*=json.loads((ROOT/'shared/data/skill-balance-v1.json').read_text())['monster_defense_multiplier']
            check(battle['enemies'][0]['definition']['hp'] == (expected['hp'] if modern else (original['hp']*135+99)//100), 'Monster scaling respects the frozen rule profile and two actual participants')
            # Expire retained ownership so join() reloads the battle fence from DB.
            time.sleep(1.2)
            cb = connect(b)
            rejoined = party(b)
            check(rejoined['battle'] is None and rejoined['battle_active'], 'Reconnect cannot insert an absent member into an existing encounter')
            cb.move([22, 10])
            wait(lambda: any(v.get('code') in ('TEAM_FOLLOWING', 'TEAM_BATTLE_ACTIVE') for v in cb.events), 'Reconnect movement ownership checked')
            check(any(v.get('code') == 'TEAM_FOLLOWING' for v in cb.events), 'Reloaded nonparticipant has the ordinary follow gate, not a false combat fence')
            send(b, 'guard', 'TEAM_NOT_PARTICIPATING', battle_id=battle['id'], expected_revision=battle['revision'])
            completed, _ = win(a, [a, c])
            check(next(m for m in party(a)['members'] if m['id']==c[1])['ready'],'Victory preserves the participating follower readiness')
            check(resources(b) == absent, 'Absent member gets no costs, recovery, quest progress or rewards')
            check(not party(b)['battle_active'], 'Nonparticipant sees that the encounter has ended')

            cb.close()
            wait(lambda: not next(m for m in party(a)['members'] if m['id'] == b[1])['online'], 'Offline again')
            send(c, 'follow', ready=False)
            check(not next(m for m in party(a)['members'] if m['id']==c[1])['ready'], 'Temporary leave clears the one participation state')
            send(c, 'challenge', 'TEAM_LEADER_REQUIRED', target='spirit')
            db.query(f"UPDATE characters SET quest_stage=0,hp=29,mp=11 WHERE id='{c[1]}'")
            away = resources(c)
            db.query(f"UPDATE characters SET monster_respawns='{{}}' WHERE id='{a[1]}'")
            lone, request = send(a, 'challenge', target='spirit')
            battle = lone['state']['team']['battle']
            check(len(battle['fighters']) == 1 and 1<=len(battle['enemies'])<=3 and battle['fighters'][0]['id'] == a[1], 'Offline and temporarily absent members permit a lone leader with the current solo encounter size')
            check(all(battle['enemies'][0]['definition'][k] == expected[k] for k in ('hp', 'attack', 'defense')), 'Lone leader uses the frozen solo monster profile')
            replay, _ = send(a, 'challenge', request=request)
            check(replay['replayed'] and replay['state']['team']['battle']['id'] == battle['id'], 'Entry retry keeps the same participant set and battle')
            solo, last = win(a, [a])
            before = resources(a)
            send(last[0], 'attack', request=last[1])
            check(resources(a) == before, 'Solo victory replay cannot duplicate rewards')
            check(resources(c) == away and resources(b) == absent, 'Offline and away characters remain untouched by solo victory')
            check(len(party(a)['members']) == 3, 'Victory keeps the original roster intact')

            send(a, 'disband')
            send(a, 'create')
            db.query(f"UPDATE characters SET monster_respawns='{{}}' WHERE id='{a[1]}'")
            one, _ = send(a, 'challenge', target='spirit')
            fight = one['state']['team']['battle']
            check(len(one['state']['team']['members']) == len(fight['fighters']) == 1, 'Newly created one-member party does not prevent ordinary combat')
            send(a, 'flee', battle_id=fight['id'], expected_revision=fight['revision'])
            print(f'TEAM PARTICIPATION: {len(checks)} checks passed')
        finally:
            for client in clients:
                if not client.done:
                    client.close()
            stop(process)
            (ROOT/'work/team-participation-server.log').write_text(''.join(locals().get('server_lines', [])), encoding='utf8')


if __name__ == '__main__':
    main()
