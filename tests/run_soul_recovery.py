"""Exercise real death/recovery transactions only on an owned temporary server/DB."""
import json
import os
from pathlib import Path
import subprocess
import threading
import time
from uuid import uuid4

from pg_fixture import PostgresFixture
from run_account_auth import stop
from run_online_pve import api, Player
from run_server_connection import wait_for_server

ROOT = Path(__file__).resolve().parents[1]


def main():
    checks = 0
    fixtures = []
    def check(value, label):
        nonlocal checks
        assert value, label
        checks += 1
    with PostgresFixture() as db:
        env = {key:value for key,value in os.environ.items() if not key.startswith('SSJX_')}
        env.update(SSJX_ENV_FILE='',SSJX_DATABASE_URL=db.url,SSJX_BIND_ADDR='127.0.0.1:0',SSJX_MONITOR_BIND_ADDR='',SSJX_LOG_DIR='',RUST_LOG='info',SSJX_AUTH_RATE_IP='1000',SSJX_AUTH_RATE_GLOBAL='10000',SSJX_WORLD_RECONNECT_SECONDS='1')
        def start():
            process=subprocess.Popen([os.environ.get('SSJX_TEST_SERVER_BIN',str(ROOT/'server/target/debug/vssjx-server'))],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
            try:base=wait_for_server(process)
            except BaseException:stop(process);raise
            threading.Thread(target=lambda:list(process.stdout),daemon=True).start()
            return process,base
        process,base=start();player=None
        try:
            password='owned-soul-fixture-password'
            check(api(base,'/api/v1/auth/register',dict(username='soul_fixture',password=password))[0]==201,'Own account created')
            _,session=api(base,'/api/v1/auth/login',dict(username='soul_fixture',password=password))
            code,payload=api(base,'/api/v1/characters',dict(operation_id=str(uuid4()),display_name='寻魂夹具',job=1,gender=0,school=3,rules_version='creation-v1'),session['access_token'])
            check(code==201,'Own character created')
            cid=payload['character']['id']
            db.query(f"UPDATE characters SET hp=1,quest_stage=1,cell_x=22,cell_y=9 WHERE id='{cid}'")
            player=Player(base,session,cid)
            player.approach('spirit')
            origin=player.ws.entities[cid]['cell'][:]
            gold=player.state['character']['gold'];xp=player.state['character']['xp']
            player.command('challenge','spirit')
            for _ in range(20):
                value,_=player.command('guard')
                if value['state']['character'].get('corpse'):break
                time.sleep(.08)
            soul=player.state
            corpse=soul['character'].get('corpse')
            check(corpse is not None and corpse['cell']==origin,'Authoritative combat leaves a corpse at actual encounter origin')
            check(soul['character']['hp']==0 and [soul['character']['cell_x'],soul['character']['cell_y']]==[10,16],'Death atomically saves soul and fixed map spawn')
            check(soul['character']['gold']==gold and soul['character']['xp']==xp,'Death does not charge money or XP')
            fixtures.append(soul)
            for action,target in [('restore','qingwei'),('challenge','spirit'),('accept','qingwei'),('buy','potion')]:
                value,_=player.command(action,target,ok=False)
                check(value['code']=='SOUL_STATE','Soul cannot bypass recovery: '+action)
            revive=dict(operation_id=str(uuid4()),action='revive',target=corpse['id'],expected_revision=soul['character']['state_revision'])
            value,_=player.command('',request=revive,ok=False)
            check(value['code']=='CORPSE_TOO_FAR','Far recovery rejected')
            wrong=dict(revive,operation_id=str(uuid4()),target=str(uuid4()))
            value,_=player.command('',request=wrong,ok=False)
            check(value['code']=='CORPSE_NOT_FOUND','Foreign corpse identity rejected')
            player.close();stop(process);process,base=start();player=Player(base,session,cid)
            check(player.state['character']['corpse']==corpse and player.state['character']['hp']==0,'Corpse and soul survive real process restart')
            player.move(origin)
            deadline=time.monotonic()+15
            while time.monotonic()<deadline:
                player.until('world.delta')
                entity=player.ws.entities[cid]
                if entity['cell']==origin and entity['next_cell'] is None:break
                player.ws.send({'type':'ping'})
            check(player.ws.entities[cid]['cell']==origin,'Soul walks normally back to corpse')
            db.query("CREATE FUNCTION reject_soul_restore() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN IF OLD.corpse IS NOT NULL AND NEW.corpse IS NULL THEN RAISE EXCEPTION 'owned soul rollback'; END IF; RETURN NEW; END$$; CREATE TRIGGER reject_restore BEFORE UPDATE ON characters FOR EACH ROW EXECUTE FUNCTION reject_soul_restore();")
            revive.update(operation_id=str(uuid4()),expected_revision=player.state['character']['state_revision'])
            player.ws.send(dict(type='pve.command',command=revive))
            check(player.until('error')['code']=='DATABASE_UNAVAILABLE','Failed recovery transaction is not acknowledged')
            check(db.query(f"SELECT hp=0 AND corpse IS NOT NULL FROM characters WHERE id='{cid}'")=='t','Failed restore leaves persistent soul/corpse intact')
            db.query('DROP TRIGGER reject_restore ON characters; DROP FUNCTION reject_soul_restore();')
            player.close();time.sleep(.2);player=Player(base,session,cid)
            value,_=player.command('',request=revive)
            check(value['state']['character']['corpse'] is None and value['state']['character']['hp']==value['state']['stats']['hp'],'Nearby recovery clears corpse and restores resources atomically')
            fixtures.append(value['state'])
            again,_=player.command('',request=revive)
            check(again['replayed'] and again['state']==value['state'],'Exact operation replay cannot restore twice')
            stale=dict(revive,operation_id=str(uuid4()))
            value,_=player.command('',request=stale,ok=False)
            check(value['code']=='NO_CORPSE','Already-recovered corpse cannot be reused')
            output=ROOT/'work/soul-recovery/server-fixtures.json'
            output.write_text(json.dumps(fixtures,ensure_ascii=False,indent=2))
            print(f'SOUL SERVER: {checks} checks, 0 failures')
        finally:
            if player is not None:player.close()
            stop(process)


if __name__=='__main__':main()
