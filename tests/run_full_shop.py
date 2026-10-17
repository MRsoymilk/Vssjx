"""Buy every recovered item against an owned disposable DB, never the live service."""
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
CATALOG = json.loads((ROOT/'client/assets/data/shop-v2.json').read_text(encoding='utf-8'))


def main():
    checks = 0
    peers = []

    def check(value, label):
        nonlocal checks
        assert value, label
        checks += 1

    with PostgresFixture() as db:
        env = {k:v for k,v in os.environ.items() if not k.startswith('SSJX_')}
        env.update(SSJX_ENV_FILE='', SSJX_DATABASE_URL=db.url, SSJX_BIND_ADDR='127.0.0.1:0',
            SSJX_MONITOR_BIND_ADDR='', SSJX_LOG_DIR='', RUST_LOG='info',
            SSJX_AUTH_RATE_IP='1000', SSJX_AUTH_RATE_GLOBAL='10000', SSJX_AUTH_RATE_ACCOUNT='100',
            SSJX_WORLD_RECONNECT_SECONDS='1')
        process = subprocess.Popen([os.environ['SSJX_TEST_SERVER_BIN']], env=env,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf-8')
        try:
            base = wait_for_server(process)
            threading.Thread(target=lambda:list(process.stdout), daemon=True).start()

            def create(index, job):
                username = f'full_shop_{index}'
                password = 'full-shop-owned-test'
                check(api(base,'/api/v1/auth/register',dict(username=username,password=password))[0]==201,'register')
                code, session = api(base,'/api/v1/auth/login',dict(username=username,password=password))
                check(code==200,'login')
                code, data = api(base,'/api/v1/characters',dict(operation_id=str(uuid4()),display_name=username,
                    job=job,gender=index%2,school=0,rules_version='creation-v1'),session['access_token'])
                check(code==201,'character')
                cid = data['character']['id']
                db.query(f"UPDATE characters SET gold=500000,hp=1,mp=0 WHERE id='{cid}'")
                player = MapPlayer(base,session,cid,shop_version=2)
                peers.append(player)
                return player

            def command(a,action,item,quantity=1,ok=True):
                time.sleep(0.065) # Respect the production 20 WebSocket messages/second limit.
                request = dict(operation_id=str(uuid4()),action=action,target=item,
                    expected_revision=a.state['character']['state_revision'])
                if quantity!=1: request['quantity']=quantity
                result, _ = a.command('',request=request,ok=ok)
                return result

            actors = [create(i,i//2) for i in range(6)]
            packet=actors[0].until('world.appearance')
            check(packet['looks'] and all(len(look)==3 for look in packet['looks'].values()),'three-component appearance negotiation')
            expected_hash = hashlib.sha256((ROOT/'client/assets/data/shop-v2.json').read_text(encoding='utf-8').encode()).hexdigest()
            check(actors[0].state['shop']['catalog_sha256']==expected_hash,'same fixed catalog on client and server')
            check(len(json.dumps(actors[0].state).encode())<32768,'state stays within client packet limit')
            role_counts = [0,0,0]
            sources = [i for i in CATALOG['items'] if i['id'].startswith('original/')]
            for index, item in enumerate(sources):
                job = item['job']
                if job>=0:
                    a=actors[job*2+role_counts[job]%2]
                    role_counts[job]+=1
                else: a=actors[index%6]
                item_id=item['id']
                equipment=item['slot'] in CATALOG['slots']
                count=1 if equipment else 2
                gold=a.state['character']['gold']
                command(a,'buy',item_id,count)
                check(a.state['character']['gold']==gold-item['price']*count,f'fixed price {item_id}')
                check(a.state['shop']['quantities'][item_id]==count,f'quantity {item_id}')
                if equipment:
                    command(a,'equip',item_id)
                    check(a.state['shop']['slots'][item['slot']]==item_id,f'correct slot {item_id}')
                elif item['slot']=='consumable':
                    previous=a.state['character'].copy()
                    stats=a.state['stats']
                    useful=(item['restore_hp']>0 and previous['hp']<stats['hp']) or (item['restore_mp']>0 and previous['mp']<stats['mp'])
                    result=command(a,'use',item_id,ok=useful)
                    if useful:
                        check(a.state['character']['hp']==min(stats['hp'],previous['hp']+item['restore_hp']),f'hp {item_id}')
                        check(a.state['character']['mp']==min(stats['mp'],previous['mp']+item['restore_mp']),f'mp {item_id}')
                        count-=1
                    else: check(result['code']=='HP_FULL' and a.state['shop']['quantities'][item_id]==2,f'no wasted medicine {item_id}')
                command(a,'discard',item_id,count)
                check(item_id not in a.state['shop']['owned'] and item_id not in a.state['shop']['quantities'],f'remove {item_id}')
                if equipment: check(a.state['shop']['slots'][item['slot']] is None,f'clear equipped {item_id}')
            print(f'ALL ORIGINAL ITEMS: {len(sources)} bought, equipped or used, and removed',flush=True)

            # Separate fresh account for all ten slots, full bag, and malformed commands.
            a=create(6,0)
            base_defense=a.state['stats']['defense']
            selected={slot:next(i for i in sources if i['slot']==slot and i['job'] in [-1,0]) for slot in CATALOG['slots']}
            for slot,item in selected.items():
                command(a,'buy',item['id']);command(a,'equip',item['id'])
            check(sum(v is not None for v in a.state['shop']['slots'].values())==10,'all ten slots at once')
            check(int(db.query(f"SELECT COUNT(*) FROM inventory_items WHERE character_id='{a.id}' AND equipped"))==10,'database slot constraints')
            check(a.state['stats']['defense']==base_defense+sum(i['defense'] for i in selected.values()),'all slots contribute defense')
            code,roster=api(base,'/api/v1/characters',token=a.session['access_token'])
            look=[selected['weapon']['visual'],selected['armor']['visual'],selected['hat']['head_visual']]
            check(code==200 and roster['characters'][0]['appearance_v2']==look,'full head/body/weapon appearance in roster')
            for _ in range(100):
                appearance=actors[0].until('world.appearance')
                if appearance['looks'].get(a.id)==look: break
            check(appearance['looks'].get(a.id)==look,'another player receives equipped head appearance')
            wrong=next(i for i in sources if i['job']==1)
            command(a,'buy',wrong['id'])
            check(command(a,'equip',wrong['id'],ok=False)['code']=='WRONG_JOB','cannot equip another job weapon')
            command(a,'discard',wrong['id'])
            stack=next(i for i in sources if i['slot']=='material')
            command(a,'buy',stack['id'],99)
            gold=a.state['character']['gold']
            check(command(a,'buy',stack['id'],ok=False)['code']=='BAG_FULL','stack overflow rejected')
            check(a.state['character']['gold']==gold,'overflow never debits')
            check(command(a,'buy',stack['id'],0,False)['code']=='INVALID_QUANTITY','zero quantity rejected')
            check(command(a,'buy',stack['id'],100,False)['code']=='INVALID_QUANTITY','excess quantity rejected')
            check(command(a,'use',stack['id'],ok=False)['code']=='ITEM_NOT_USABLE','materials cannot masquerade as medicine')
            command(a,'discard',stack['id'],99)
            check(command(a,'buy','original/fake',ok=False)['code']=='INVALID_EQUIPMENT','unknown ID rejected')

            # Bulk fixture seed only: reach the actual inventory limit without rate limiting the test.
            bag=[i for i in sources if i['id'] not in {v['id'] for v in selected.values()}][:59]
            values=','.join(f"(gen_random_uuid(),'{a.id}','{i['id']}',1,false)" for i in bag)
            db.query('INSERT INTO inventory_items(id,character_id,definition_id,quantity,equipped) VALUES '+values)
            db.query(f"DELETE FROM inventory_items WHERE character_id='{a.id}' AND definition_id='potion'")
            a.close(); a=MapPlayer(base,a.session,a.id,shop_version=2);peers.append(a)
            check(len(a.state['shop']['owned'])==70,'ten equipped plus sixty bag cells including sword')
            fresh=next(i for i in sources if i['id'] not in a.state['shop']['owned'])
            check(command(a,'buy',fresh['id'],ok=False)['code']=='BAG_FULL','full bag refuses new item')
            check(command(a,'buy','potion',ok=False)['code']=='BAG_FULL','full bag refuses first potion stack')
            check(command(a,'unequip',selected['hat']['id'],ok=False)['code']=='BAG_FULL','full bag cannot lose equipped item')
            check(len(json.dumps(a.state).encode())<32768,'full inventory stays below packet limit')
            command(a,'discard',bag[0]['id'])
            command(a,'buy',fresh['id'])
            check(int(db.query(f"SELECT MAX(octet_length(details::text)) FROM security_audit WHERE character_id='{a.id}'"))<16384,'full bag audit fits bound')
            print(f'FULL SHOP: {checks} checks, 0 failures',flush=True)
        finally:
            for peer in peers:
                try: peer.close()
                except OSError: pass
            stop(process)


if __name__=='__main__': main()
