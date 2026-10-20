"""Actual purchase/equip/reconnect/replication against an owned disposable DB."""
import hashlib
import json
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
CATALOG = json.loads((ROOT/'client/assets/data/shop-v2.json').read_text('utf8'))


def main(family='boneglow'):
    sets = json.loads((ROOT/f'client/assets/data/{family}-equipment.json').read_text('utf8'))['sets']
    checks, peers, fixtures = 0, [], []

    def check(value, description):
        nonlocal checks
        assert value, description
        checks += 1

    with PostgresFixture() as db:
        env = {k: v for k, v in os.environ.items() if not k.startswith('SSJX_')}
        env.update(SSJX_ENV_FILE='', SSJX_DATABASE_URL=db.url, SSJX_BIND_ADDR='127.0.0.1:0',
            SSJX_MONITOR_BIND_ADDR='', SSJX_LOG_DIR='', RUST_LOG='info',
            SSJX_AUTH_RATE_IP='1000', SSJX_AUTH_RATE_GLOBAL='10000', SSJX_AUTH_RATE_ACCOUNT='100',
            SSJX_WORLD_RECONNECT_SECONDS='1')
        binary = os.environ.get('SSJX_TEST_SERVER_BIN', str(ROOT/'server/target/debug/vssjx-server.exe'))
        process = subprocess.Popen([binary], env=env, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, encoding='utf8')
        try:
            base = wait_for_server(process)
            threading.Thread(target=lambda: list(process.stdout), daemon=True).start()

            def join(session, cid):
                player = MapPlayer(base, session, cid, shop_version=2)
                peers.append(player)
                return player

            def command(player, action, target, ok=True):
                time.sleep(.07)
                request = dict(operation_id=str(uuid4()), action=action, target=target,
                    expected_revision=player.state['character']['state_revision'])
                result, _ = player.command('', request=request, ok=ok)
                return result

            actors = []
            for index, definition in enumerate(sets):
                username, password = f'{family}_{index}', 'owned-equipment-test'
                check(api(base, '/api/v1/auth/register', dict(username=username,password=password))[0]==201, 'register')
                status, session = api(base, '/api/v1/auth/login', dict(username=username,password=password))
                check(status==200, 'login')
                status, payload = api(base, '/api/v1/characters', dict(operation_id=str(uuid4()),
                    display_name=username, job=definition['job'], gender=definition['gender'], school=0,
                    rules_version='creation-v1'), session['access_token'])
                check(status==201, 'create character')
                cid = payload['character']['id']
                db.query(f"UPDATE characters SET gold=10000 WHERE id='{cid}'")
                actors.append(join(session,cid))
            witness = actors[0]
            for index, (definition, actor) in enumerate(zip(sets,actors)):
                base_defense, base_attack = actor.state['stats']['defense'], actor.state['stats']['attack']
                members = [entry for entry in CATALOG['items'] if entry.get('set_id')==definition['id']]
                for entry in members:
                    gold = actor.state['character']['gold']
                    command(actor,'buy',entry['id'])
                    check(actor.state['character']['gold']==gold-entry['price'],'server price')
                    command(actor,'equip',entry['id'])
                    check(actor.state['shop']['slots'][entry['slot']]==entry['id'],'authoritative slot')
                look = [definition['weapon_code'],definition['clothing_code'],definition['head_code']]
                check(actor.state['stats']['defense']==base_defense+27 and actor.state['stats']['attack']==base_attack+(12 if family=='boneglow' else 14),'all set stats')
                check(int(db.query(f"SELECT COUNT(*) FROM inventory_items WHERE character_id='{actor.id}' AND equipped"))==10,'ten database slots')
                expected_hash = hashlib.sha256((ROOT/'client/assets/data/shop-v2.json').read_text('utf8').encode()).hexdigest()
                check(actor.state['shop']['catalog_sha256']==expected_hash,'matching client/server catalog')
                wrong_gender = f"ai/{sets[index^1]['id']}/hat"
                command(actor,'buy',wrong_gender)
                check(command(actor,'equip',wrong_gender,False)['code']=='WRONG_GENDER','server rejects opposite gender')
                wrong_job = f"ai/{sets[(index+2)%6]['id']}/weapon"
                command(actor,'buy',wrong_job)
                check(command(actor,'equip',wrong_job,False)['code']=='WRONG_JOB','server rejects another job')
                check(command(actor,'buy',f'ai/{family}/fake/weapon',False)['code']=='INVALID_EQUIPMENT','unknown item refused')
                if family!='boneglow':
                    old_hat=f"ai/boneglow/{definition['stem']}/hat"
                    command(actor,'buy',old_hat)
                    command(actor,'equip',old_hat)
                    check(actor.state['shop']['slots']['hat']==old_hat,'prior family items remain usable and mix with the new set')
                    command(actor,'equip',f"ai/{definition['id']}/hat")
                if index:
                    for _ in range(120):
                        packet = witness.until('world.appearance')
                        if packet['looks'].get(actor.id)==look: break
                    check(packet['looks'].get(actor.id)==look,'another client receives full outfit')
                actor.close()
                time.sleep(.15)
                restored = join(actor.session,actor.id)
                check(all(restored.state['shop']['slots'][e['slot']]==e['id'] for e in members),'all items persist on reconnect')
                check(restored.state['stats']==actor.state['stats'],'stats persist')
                if index==0: witness = restored
                status, roster = api(base,'/api/v1/characters',token=actor.session['access_token'])
                check(status==200 and roster['characters'][0]['appearance_v2']==look,'roster persistence')
                fixtures.append(dict(character=roster['characters'][0], state=restored.state))
            output = ROOT/f'work/{family}-production/live-fixtures.json'
            output.write_text(json.dumps(fixtures,ensure_ascii=False,indent=2),encoding='utf8')
            print(f'{family.upper()} SERVER: {checks} checks, 0 failures',flush=True)
        finally:
            for peer in peers:
                try: peer.close()
                except OSError: pass
            stop(process)


if __name__ == '__main__':
    main()
