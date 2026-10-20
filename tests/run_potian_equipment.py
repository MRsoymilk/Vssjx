"""Buy/equip the approved axe through real HTTP/WebSocket on an owned temporary DB."""
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
ITEM = 'ai/legendary/potian_axe'


def main():
    checks, peers, fixtures = 0, [], []

    def check(ok, message):
        nonlocal checks
        assert ok, message
        checks += 1

    with PostgresFixture() as db:
        env = {k: v for k, v in os.environ.items() if not k.startswith('SSJX_')}
        env.update(SSJX_ENV_FILE='', SSJX_DATABASE_URL=db.url, SSJX_BIND_ADDR='127.0.0.1:0',
                   SSJX_MONITOR_BIND_ADDR='', SSJX_LOG_DIR='', RUST_LOG='info',
                   SSJX_AUTH_RATE_IP='1000', SSJX_AUTH_RATE_GLOBAL='10000',
                   SSJX_AUTH_RATE_ACCOUNT='100', SSJX_WORLD_RECONNECT_SECONDS='1')
        process = subprocess.Popen([os.environ['SSJX_TEST_SERVER_BIN']], env=env,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True, encoding='utf8')
        try:
            base = wait_for_server(process)
            threading.Thread(target=lambda: list(process.stdout), daemon=True).start()

            def join(session, cid):
                peer = MapPlayer(base, session, cid, shop_version=2)
                peers.append(peer)
                return peer

            def command(peer, action, target, ok=True):
                time.sleep(.08)
                request = dict(operation_id=str(uuid4()), action=action, target=target,
                               expected_revision=peer.state['character']['state_revision'])
                return peer.command('', request=request, ok=ok)

            actors = []
            for index, (job, gender) in enumerate([(0,0), (0,1), (1,0), (2,1)]):
                name, password = f'potian_{index}', 'owned-potian-test-password'
                check(api(base, '/api/v1/auth/register', dict(username=name,password=password))[0] == 201, 'register')
                status, session = api(base, '/api/v1/auth/login', dict(username=name,password=password))
                check(status == 200, 'login')
                status, packet = api(base, '/api/v1/characters', dict(
                    operation_id=str(uuid4()), display_name=name, job=job, gender=gender,
                    school=0, rules_version='creation-v1'), session['access_token'])
                check(status == 201, 'create')
                cid = packet['character']['id']
                db.query(f"UPDATE characters SET gold=10000 WHERE id='{cid}'")
                actors.append(join(session,cid))
            for index, actor in enumerate(actors):
                before_gold = actor.state['character']['gold']
                command(actor,'buy',ITEM)
                check(actor.state['character']['gold'] == before_gold-250,'server price')
                check(command(actor,'buy',ITEM,False)[0]['code']=='ITEM_ALREADY_OWNED','no duplicate equipment')
                if index >= 2:
                    check(command(actor,'equip',ITEM,False)[0]['code']=='WRONG_JOB','server denies other jobs')
                    continue
                if actor.state['shop']['weapon'] is not None:
                    command(actor,'unequip',actor.state['shop']['weapon'])
                base_attack = actor.state['stats']['attack']
                command(actor,'equip',ITEM)
                check(actor.state['shop']['slots']['weapon']==ITEM,'authoritative weapon slot')
                check(actor.state['stats']['attack']==base_attack+20,'authoritative attack bonus')
                check(int(db.query(f"SELECT count(*) FROM inventory_items WHERE character_id='{actor.id}' AND equipped AND definition_id='{ITEM}'"))==1,'database stores equipped axe')
                look = [46,0,0]
                witness = actors[1-index]
                for _ in range(120):
                    packet = witness.until('world.appearance')
                    if packet['looks'].get(actor.id)==look: break
                check(packet['looks'].get(actor.id)==look,'other client receives axe appearance')
                if index == 1:
                    for item in ['ai/boneglow/wzs/armor','ai/gravebloom/wzs/hat']:
                        command(actor,'buy',item)
                        command(actor,'equip',item)
                    look = [46,13,17]
                expected_hash = hashlib.sha256((ROOT/'client/assets/data/shop-v2.json').read_text('utf8').encode()).hexdigest()
                check(actor.state['shop']['catalog_sha256']==expected_hash,'matching client/server catalog')
                stats = actor.state['stats']
                actor.close()
                time.sleep(.15)
                restored = join(actor.session,actor.id)
                actors[index] = restored
                check(restored.state['shop']['weapon']==ITEM and restored.state['stats']==stats,'reconnect restores gear and stats')
                status, roster = api(base,'/api/v1/characters',token=actor.session['access_token'])
                check(status==200 and roster['characters'][0]['appearance_v2']==look,'character selection retains axe')
                fixtures.append(dict(character=roster['characters'][0], state=restored.state))
                command(restored,'unequip',ITEM)
                check(restored.state['shop']['weapon'] is None,'server can unequip axe')
            output = ROOT/'work/potian-review/live-fixtures.json'
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(json.dumps(fixtures,ensure_ascii=False,indent=2),encoding='utf8')
            print(f'POTIAN SERVER: {checks} checks, 0 failures',flush=True)
        finally:
            for peer in peers:
                try: peer.close()
                except OSError: pass
            stop(process)


if __name__ == '__main__':
    main()
