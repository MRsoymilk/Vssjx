"""Talisman economy and map changes on an owned disposable DB; no live saves."""
import json
import os
from pathlib import Path
import subprocess
import threading
from uuid import uuid4
from pg_fixture import PostgresFixture
from run_account_auth import stop
from run_ai_world import AIPlayer, AI_MAPS
from run_online_pve import api
from run_server_connection import wait_for_server

ROOT=Path(__file__).resolve().parents[1]
ITEM='restored/shenxing_scroll'


def main():
    checks=0
    def check(value,message):
        nonlocal checks
        checks+=1
        assert value,message
    with PostgresFixture() as db:
        env={k:v for k,v in os.environ.items() if not k.startswith('SSJX_')}
        env.update(SSJX_ENV_FILE='',SSJX_DATABASE_URL=db.url,SSJX_BIND_ADDR='127.0.0.1:0',
                   SSJX_MONITOR_BIND_ADDR='',SSJX_LOG_DIR='',SSJX_WORLD_RECONNECT_SECONDS='1',
                   SSJX_AUTH_RATE_IP='1000',SSJX_AUTH_RATE_ACCOUNT='100',SSJX_AUTH_RATE_GLOBAL='10000',RUST_LOG='info')
        def start():
            process=subprocess.Popen([os.environ['SSJX_TEST_SERVER_BIN']],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf8')
            try:base=wait_for_server(process)
            except BaseException:stop(process);raise
            threading.Thread(target=lambda:list(process.stdout),daemon=True).start()
            return process,base
        process,base=start();players=[]
        def account(name,quest=0):
            identity=dict(username=name,password='owned-scroll-password-1234')
            check(api(base,'/api/v1/auth/register',identity)[0]==201,'register isolated account')
            code,session=api(base,'/api/v1/auth/login',identity);check(code==200,'login isolated account')
            code,created=api(base,'/api/v1/characters',dict(operation_id=str(uuid4()),display_name=name[:12],job=0,gender=0,school=3,rules_version='creation-v1'),session['access_token'])
            check(code==201,'create isolated character')
            cid=created['character']['id'];db.query(f"UPDATE characters SET gold=300,quest_stage={quest} WHERE id='{cid}'")
            return session,cid
        def join(session,cid):
            player=AIPlayer(base,session,cid);players.append(player);return player
        def quantity(player):return player.state['shop']['quantities'].get(ITEM,0)
        def travel(player,destination,ok=True,**extra):
            command=dict(operation_id=str(uuid4()),action='scroll_travel',target=destination,expected_revision=player.state['character']['state_revision'])
            command.update(extra)
            return player.command('',request=command,ok=ok)
        try:
            session,cid=account('scroll_first');p=join(session,cid)
            value,_=travel(p,'ai_021',False);check(value['code']=='TRAVEL_SCROLL_REQUIRED','empty stock cannot travel')
            request=dict(operation_id=str(uuid4()),action='buy',target=ITEM,quantity=3,expected_revision=p.state['character']['state_revision'])
            bought,_=p.command('',request=request)
            check(quantity(p)==3 and p.state['character']['gold']==210,'buy debits exact copper and credits stack')
            again,_=p.command('',request=request);check(again['replayed'] and quantity(p)==3,'buy replay cannot grant duplicate items')
            for destination,code in [('qingyun_trail','AI_SAME_MAP'),('ancient_ruins','QUEST_REQUIRED'),('ai_999','AI_INVALID_TARGET')]:
                value,_=travel(p,destination,False);check(value['code']==code and quantity(p)==3,'invalid destination retains stock')
            value,_=travel(p,'ai_021',False,expected_revision='9999');check(value['code']=='STALE_EQUIPMENT' and quantity(p)==3,'stale command retains stock')
            value,_=p.command('',request=dict(operation_id=str(uuid4()),action='use',target=ITEM,expected_revision=p.state['character']['state_revision']),ok=False);check(value['code']=='TRAVEL_DESTINATION_REQUIRED' and quantity(p)==3,'generic use requires destination')
            operation=dict(operation_id=str(uuid4()),action='scroll_travel',target='ai_021',expected_revision=p.state['character']['state_revision'])
            db.query("CREATE FUNCTION reject_scroll_receipt() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'owned scroll rollback'; END$$; CREATE TRIGGER scroll_receipt BEFORE INSERT ON pve_operation_receipts FOR EACH ROW EXECUTE FUNCTION reject_scroll_receipt();")
            p.ws.send(dict(type='pve.command',command=operation));check(p.until('error')['code']=='DATABASE_UNAVAILABLE','injected receipt failure surfaces')
            db.query('DROP TRIGGER scroll_receipt ON pve_operation_receipts; DROP FUNCTION reject_scroll_receipt();')
            p.close();p=join(session,cid)
            check(quantity(p)==3 and p.state['character']['map_id']=='qingyun_trail','transaction rollback preserves stock and origin')
            # Starting cell is far from the station: this item requires no waystone.
            hp,mp=p.state['character']['hp'],p.state['character']['mp']
            arrived,_=p.command('',request=operation)
            check(arrived['state']['character']['map_id']=='ai_021' and quantity(p)==2,'consume and direct travel commit together')
            check((p.state['character']['hp'],p.state['character']['mp'])==(hp,mp),'travel does not heal')
            p.close();stop(process);process,base=start();p=join(session,cid)
            check(p.ready['map_id']=='ai_021' and p.ws.entities[cid]['cell']==AI_MAPS['ai_021']['spawn'],'restart resumes at destination spawn')
            replay,_=p.command('',request=operation)
            check(replay['replayed'] and replay['state']==arrived['state'] and quantity(p)==2,'unknown success replay never consumes twice')
            value,_=travel(p,'qingyun_trail');p.close();p=join(session,cid)
            check(quantity(p)==1 and p.ready['map_id']=='qingyun_trail','second choice returns to original map')
            value,_=travel(p,'ai_032');p.close();p=join(session,cid)
            check(quantity(p)==0 and ITEM not in p.state['shop']['owned'],'last charge removes owned stack')
            value,_=travel(p,'ai_004',False);check(value['code']=='TRAVEL_SCROLL_REQUIRED','exhausted talisman cannot travel')
            check(db.query(f"SELECT count(*) FROM security_audit WHERE character_id='{cid}' AND action='pve.scroll_travel' AND outcome='accepted'")=='3','exactly one accepted audit per successful transfer')
            p.close()
            if os.environ.get('GODOT_BIN'):
                account('scroll_ui',quest=3)
                ui=subprocess.run([os.environ['GODOT_BIN'],'--headless','--path',str(ROOT/'client'),'res://tests/travel_scroll_live_test.tscn'],env=dict(os.environ,SSJX_SCROLL_TEST_BASE=base),capture_output=True,text=True,encoding='utf8',timeout=70)
                print(ui.stdout,end='');print(ui.stderr,end='')
                check(ui.returncode==0 and '0 failures' in ui.stdout and 'SCRIPT ERROR' not in ui.stderr,'real online shop and inventory flow')
            print(f'TRAVEL SCROLL SERVER: {checks} checks, 0 failures')
        finally:
            for player in players:
                try:player.close()
                except OSError:pass
            stop(process)


if __name__=='__main__':main()
