"""Disposable PostgreSQL, real WebSockets: authoritative purchases and appearance.

Never reads the live database or replaces a running game service.
"""
import os
import hashlib
from pathlib import Path
import subprocess
import threading
from uuid import uuid4
from pg_fixture import PostgresFixture
from run_account_auth import stop
from run_online_maps import MapPlayer
from run_online_pve import api
from run_server_connection import wait_for_server

ROOT = Path(__file__).resolve().parents[1]


def main():
    binary = os.environ['SSJX_TEST_SERVER_BIN']
    sockets = []
    checks = 0

    def check(value):
        nonlocal checks
        assert value, f'check {checks+1}'
        checks += 1

    with PostgresFixture() as db:
        env = {k:v for k,v in os.environ.items() if not k.startswith('SSJX_')}
        env.update(SSJX_ENV_FILE='', SSJX_DATABASE_URL=db.url, SSJX_BIND_ADDR='127.0.0.1:0',
            SSJX_MONITOR_BIND_ADDR='', SSJX_LOG_DIR='', RUST_LOG='info', SSJX_AUTH_RATE_IP='1000',
            SSJX_AUTH_RATE_ACCOUNT='100', SSJX_WORLD_RECONNECT_SECONDS='1')

        def start():
            p = subprocess.Popen([binary], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf-8')
            try: address = wait_for_server(p)
            except BaseException: stop(p); raise
            threading.Thread(target=lambda:list(p.stdout),daemon=True).start()
            return p,address

        def create(name, job=1, gender=0):
            password = 'shop-test-password'
            check(api(base,'/api/v1/auth/register',dict(username=name,password=password))[0] == 201)
            code,session = api(base,'/api/v1/auth/login',dict(username=name,password=password))
            check(code == 200)
            code,data = api(base,'/api/v1/characters',dict(operation_id=str(uuid4()),display_name=name,
                job=job,gender=gender,school=0,rules_version='creation-v1'),session['access_token'])
            check(code == 201)
            return session,data['character']['id']

        def join(session,cid,version=2):
            a=MapPlayer(base,session,cid,shop_version=version)
            sockets.append(a)
            return a

        def command(a,action,target,ok=True,revision=None):
            return a.command('',request=dict(operation_id=str(uuid4()),action=action,target=target,
                expected_revision=revision or a.state['character']['state_revision']),ok=ok)

        process,base=start()
        try:
            session,cid=create('shop_first')
            second,cid2=create('shop_second',2,1)
            a=join(session,cid)
            b=join(second,cid2,version=1)
            check(b.state['shop']['version']=='shop-v1' and len(b.state['shop']['catalog'])==6)
            check(a.state['shop']['owned'] == ['sword'])
            catalog = ROOT/'client/assets/data/shop-v2.json'
            check(a.state['shop']['version'] == 'shop-v2' and a.state['shop']['catalog_sha256'] == hashlib.sha256(catalog.read_text(encoding='utf-8').encode()).hexdigest())
            v,_=command(a,'buy','weapon_2',False)
            check(v['code']=='GOLD_INSUFFICIENT' and a.state['character']['gold']==30)
            v,_=command(a,'equip','weapon_2',False)
            check(v['code']=='WEAPON_NOT_OWNED')
            # Test fixture balance: no gameplay mutation endpoint accepts this field.
            a.close()
            db.query(f"UPDATE characters SET gold=500 WHERE id='{cid}'")
            a=join(session,cid)
            v,request=command(a,'buy','weapon_2')
            check(v['state']['character']['gold']==460 and 'weapon_2' in v['state']['shop']['owned'])
            check(v['state']['shop']['weapon'] is None)
            repeat,_=a.command('',request=request)
            check(repeat['replayed'] and repeat['state']['character']['gold']==460)
            v,_=command(a,'buy','weapon_2',False)
            check(v['code']=='ITEM_ALREADY_OWNED' and a.state['character']['gold']==460)
            v,_=command(a,'buy','armor_2',revision='0',ok=False)
            check(v['code']=='STALE_EQUIPMENT')
            command(a,'buy','armor_2')
            command(a,'equip','sword')
            command(a,'equip','weapon_2')
            command(a,'equip','armor_2')
            check(a.state['stats']['attack']==31 and a.state['stats']['defense']==7)
            check(a.state['attributes']['combat']['physical_attack']==31 and a.state['attributes']['combat']['physical_defense']==7)
            check(db.query(f"SELECT COUNT(*) FROM inventory_items WHERE character_id='{cid}' AND equipped")=='2')
            for _ in range(30):
                packet=b.until('world.appearance')
                if packet['looks'].get(cid)==[2,1]: break
            check(packet['looks'][cid]==[2,1])
            check(b.state['character']['gold']==30 and b.state['shop']['weapon'] is None)
            command(a,'unequip','weapon_2')
            for _ in range(30):
                packet=b.until('world.appearance')
                if packet['looks'].get(cid)==[0,1]: break
            check(packet['looks'][cid]==[0,1])
            command(a,'equip','weapon_2')
            a.close(); b.close(); stop(process)
            process,base=start()
            a=join(session,cid)
            check(a.state['shop']['weapon']=='weapon_2' and a.state['shop']['armor']=='armor_2')
            check(a.state['character']['gold']==425)
            code,roster=api(base,'/api/v1/characters',token=session['access_token'])
            check(code==200 and roster['characters'][0]['appearance']==[2,1])
            # A failed receipt write rolls back both balance and ownership.
            db.query("CREATE FUNCTION reject_shop() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'rollback probe'; END$$; CREATE TRIGGER reject_shop BEFORE INSERT ON pve_operation_receipts FOR EACH ROW EXECUTE FUNCTION reject_shop();")
            a.ws.send(dict(type='pve.command',command=dict(operation_id=str(uuid4()),action='buy',target='armor_3',expected_revision=a.state['character']['state_revision'])))
            check(a.until('error')['code']=='DATABASE_UNAVAILABLE')
            check(db.query(f"SELECT gold FROM characters WHERE id='{cid}'")=='425')
            check(db.query(f"SELECT COUNT(*) FROM inventory_items WHERE character_id='{cid}' AND definition_id='armor_3'")=='0')
            db.query('DROP TRIGGER reject_shop ON pve_operation_receipts; DROP FUNCTION reject_shop();')
            a.close();a=join(session,cid)
            # Zero-potion row can be recreated by a purchase.
            a.close();db.query(f"DELETE FROM inventory_items WHERE character_id='{cid}' AND definition_id='potion'")
            a=join(session,cid);command(a,'buy','potion')
            check(a.state['potions']==1 and a.state['character']['gold']==417)
            a.approach('qingwei');a.command('accept','qingwei')
            a.approach('wolf_a');a.command('challenge','wolf_a')
            v,_=command(a,'buy','weapon_3',False)
            check(v['code']=='BATTLE_ACTIVE')
            hp=a.state['battle']['enemy_hp'];a.command('attack')
            check(26 <= hp-a.state['battle']['enemy_hp'] <= 30)
            a.command('flee')
            before=a.state['character']['gold']
            revision=a.state['character']['state_revision']
            first=dict(operation_id=str(uuid4()),action='buy',target='armor_3',expected_revision=revision)
            second_request=dict(first,operation_id=str(uuid4()))
            a.ws.send(dict(type='pve.command',command=first))
            a.ws.send(dict(type='pve.command',command=second_request))
            v=a.until('pve.result',first['operation_id'])
            stale=a.until('pve.result',second_request['operation_id'])
            check(v['ok'] and stale['code']=='STALE_EQUIPMENT' and stale['state']['character']['gold']==before-80)
            a.state=stale['state']
            forged=dict(operation_id=str(uuid4()),action='buy',target='weapon_3',expected_revision=a.state['character']['state_revision'],price=0)
            a.ws.send(dict(type='pve.command',command=forged))
            check(a.until('error')['code']=='INVALID_MESSAGE')
            check(db.query(f"SELECT gold FROM characters WHERE id='{cid}'")==str(before-80))
            check(int(db.query(f"SELECT COUNT(*) FROM security_audit WHERE character_id='{cid}' AND action='pve.buy'"))>=7)
            if os.environ.get('GODOT_BIN'):
                a.close()
                client_env=dict(os.environ,SSJX_SHOP_TEST_BASE=base)
                args=[os.environ['GODOT_BIN'],'--headless','--path',str(ROOT/'client'),'--quit-after','18000','res://tests/online_shop_live_test.tscn']
                result=subprocess.run(args,env=client_env,capture_output=True,text=True,encoding='utf-8',timeout=90)
                print(result.stdout);print(result.stderr)
                check(result.returncode==0 and '0 failures' in result.stdout and 'SCRIPT ERROR' not in result.stderr)
            print(f'ONLINE SHOP: {checks} checks, 0 failures (buy/equip/replay/rollback/restart/appearance/authority)')
        finally:
            for a in sockets:
                try: a.close()
                except OSError: pass
            stop(process)


if __name__=='__main__': main()
