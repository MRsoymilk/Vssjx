"""Real protocol + owned disposable PostgreSQL; no production migrations/deployment."""
import hashlib
from collections import deque
import json
import os
from pathlib import Path
import subprocess
import threading
import time
from uuid import uuid4
from pg_fixture import PostgresFixture
from run_online_maps import MapPlayer
from run_online_pve import HASH,api
from run_account_auth import stop
from run_server_connection import wait_for_server
from ws_fixture import WebSocket

ROOT=Path(__file__).resolve().parents[1]
AI_HASH=hashlib.sha256((ROOT/"shared/data/ai-world-v1.json").read_bytes().replace(b"\r\n",b"\n")).hexdigest()
AI_MAPS={m['map_id']:m for m in json.loads((ROOT/'shared/data/ai-world-v1.json').read_text(encoding='utf8'))['maps']}

class AIPlayer(MapPlayer):
    def move(self,target):
        # Fixture may consume buffered deltas in a tight loop; honor the real
        # input budget rather than flooding movement + ping pairs.
        time.sleep(.12)
        return super().move(target)
    def __init__(self,base,session,character,version=2):
        self.base,self.session,self.id=base,session,character
        code,ticket=api(base,'/api/v1/world/ticket',dict(character_id=character,protocol_version=1,config_hash=HASH),session['access_token'])
        assert code==200,ticket
        self.ws=WebSocket(base.replace('http://','ws://')+'/api/v1/world/ws')
        self.ws.send(dict(type='auth.exchange',ticket=ticket['ticket'],protocol_version=1,config_hash=HASH,world_sync_version=2,population_version=1,pve_version=1,maps_version=version,shop_version=2))
        self.population,self.state,self.seq={},{},0
        self.closed,self.keepalive=False,time.monotonic();self.instances.append(self)
        self.ready=self.until('auth.ready');self.state=self.until('pve.state')['state'];self.until('population.state')
        if self.ready['map_id'].startswith('ai_'):assert self.ready['map_hash']==AI_HASH
        assert self.state['ai_world']['catalog_sha256']==AI_HASH
        assert len(json.dumps(self.state).encode())<32768

def main():
    binary=os.environ['SSJX_TEST_SERVER_BIN']
    sockets=[]
    with PostgresFixture() as db:
        env={k:v for k,v in os.environ.items() if not k.startswith('SSJX_')}
        env.update(SSJX_ENV_FILE='',SSJX_DATABASE_URL=db.url,SSJX_BIND_ADDR='127.0.0.1:0',SSJX_MONITOR_BIND_ADDR='',SSJX_LOG_DIR='',RUST_LOG='info',SSJX_AUTH_RATE_IP='1000',SSJX_AUTH_RATE_GLOBAL='10000',SSJX_AUTH_RATE_ACCOUNT='100',SSJX_WORLD_RECONNECT_SECONDS='1')
        def start():
            p=subprocess.Popen([binary],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf8')
            try:base=wait_for_server(p)
            except BaseException:stop(p);raise
            p.ai_logs=deque(maxlen=150)
            def drain():
                for line in p.stdout:p.ai_logs.append(line)
            threading.Thread(target=drain,daemon=True).start();return p,base
        process,base=start()
        def create(name,level=8,map_id='qingyun_trail'):
            password='owned-ai-world-password'
            assert api(base,'/api/v1/auth/register',dict(username=name,password=password))[0]==201
            code,session=api(base,'/api/v1/auth/login',dict(username=name,password=password));assert code==200
            code,data=api(base,'/api/v1/characters',dict(operation_id=str(uuid4()),display_name=name,job=0,gender=0,school=0,rules_version='creation-v1'),session['access_token']);assert code==201,data
            cid=data['character']['id']
            db.query(f"UPDATE characters SET level={level},hp=120,mp=35,map_id='{map_id}',cell_x=5,cell_y=16 WHERE id='{cid}'")
            return session,cid
        def join(session,cid,version=2):
            p=AIPlayer(base,session,cid,version);sockets.append(p);return p
        try:
            session,cid=create('ai_first');other,other_id=create('ai_second')
            a=join(session,cid);b=join(other,other_id)
            a.walk([10,13]);value,_=a.command('ai_travel','ai_001',ok=False);assert value['code']=='PORTAL_TOO_FAR'
            a.walk([3,16]);a.command('ai_travel','ancient_ruins',ok=False)
            a.command('ai_travel','ai_001');a.close();a=join(session,cid)
            assert a.ready['map_id']=='ai_001' and len(a.population)==len(AI_MAPS['ai_001']['residents'])+1
            assert a.population['ai_001_endless']['kind']=='npc'
            a.flush();b.ws.snapshot(lambda entities:cid not in entities,limit=500)
            assert other_id not in a.ws.entities and cid not in b.ws.entities
            value,_=a.command('ai_accept','ai_001_q1',ok=False);assert value['code']=='RESIDENT_TOO_FAR'
            a.approach('ai_001_guide');v,request=a.command('ai_accept','ai_001_q1')
            again,_=a.command('',request=request);assert again['replayed'] and again['state']==v['state']
            a.command('ai_claim','ai_001_q1',ok=False)
            a.command('ai_accept','ai_002_q1',ok=False)
            a.approach('ai_001_courier');v,_=a.command('ai_interact','ai_001_courier',ok=False);assert v['code']=='AI_NO_OBJECTIVE'
            a.approach('ai_001_survey');a.command('ai_interact','ai_001_survey')
            a.approach('ai_001_courier');a.command('ai_interact','ai_001_courier')
            a.approach('ai_001_guide')
            before=a.state['character']['gold']
            # Force a receipt failure: quest, reward and AI JSON must all roll back.
            db.query("CREATE FUNCTION reject_ai_receipt() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'owned AI rollback'; END$$; CREATE TRIGGER ai_receipt BEFORE INSERT ON pve_operation_receipts FOR EACH ROW EXECUTE FUNCTION reject_ai_receipt();")
            claim=dict(operation_id=str(uuid4()),action='ai_claim',target='ai_001_q1')
            a.ws.send(dict(type='pve.command',command=claim));assert a.until('error')['code']=='DATABASE_UNAVAILABLE'
            db.query('DROP TRIGGER ai_receipt ON pve_operation_receipts; DROP FUNCTION reject_ai_receipt();')
            a.close();a=join(session,cid)
            assert a.state['character']['gold']==before and 'ai_001_q1' in a.state['ai_world']['active']
            a.command('',request=claim);gold=a.state['character']['gold']
            a.command('',request=claim);assert a.state['character']['gold']==gold
            a.command('ai_claim','ai_001_q1',ok=False)
            a.command('ai_accept','ai_001_q2')
            a.approach('ai_001_mob');a.command('challenge','ai_001_mob')
            while a.state['battle']['outcome']=='active':a.command('attack');time.sleep(.06)
            assert a.state['battle']['outcome']=='victory',a.state
            assert a.state['ai_world']['active']['ai_001_q2']==[1]
            assert a.state['character']['quest_stage']==0 and a.state['progress']['defeated']==[]
            deadline=a.state['ai_world']['respawns']['ai_001_mob']
            a.close();b.close();stop(process);process,base=start();a=join(session,cid)
            assert a.state['ai_world']['respawns']['ai_001_mob']==deadline
            a.approach('ai_001_mob');v,_=a.command('challenge','ai_001_mob',ok=False);assert v['code']=='MONSTER_RESPAWNING'
            # Run the real Godot client while the server-owned respawn clock elapses.
            if os.environ.get('GODOT_BIN'):
                create('ai_ui',map_id='ai_001')
                result=subprocess.run([os.environ['GODOT_BIN'],'--headless','--path',str(ROOT/'client'),'--quit-after','18000','res://tests/ai_world_live_test.tscn'],env=dict(os.environ,SSJX_AI_TEST_BASE=base),text=True,encoding='utf8',capture_output=True,timeout=125)
                print(result.stdout,flush=True);print(result.stderr,flush=True)
                if result.returncode!=0 or '0 failures' not in result.stdout or 'SCRIPT ERROR' in result.stderr:
                    print(''.join(process.ai_logs),flush=True)
                    raise AssertionError('Godot expansion integration failed')
            # UI run can outlast socket keepalive; reconnect resumes the character's progress.
            a.close();a=join(session,cid)
            while int(time.time()*1000)<=deadline:
                a.ws.send(dict(type='ping'));a.until('pong');time.sleep(.5)
            # Respawn creates a fresh moving resident; do not approach its stale
            # pre-respawn cell from the previous population snapshot.
            a.until('population.state')
            a.approach('ai_001_mob');a.command('challenge','ai_001_mob')
            while a.state['battle']['outcome']=='active':a.command('attack');time.sleep(.06)
            assert a.state['ai_world']['active']['ai_001_q2']==[2]
            a.approach('ai_001_guide');a.command('ai_claim','ai_001_q2');a.command('ai_accept','ai_001_q3')
            a.command('ai_restore','ai_001_guide')
            a.approach('ai_001_boss');a.command('challenge','ai_001_boss')
            while a.state['battle']['outcome']=='active':a.command('attack');time.sleep(.06)
            assert a.state['battle']['outcome']=='victory'
            a.approach('ai_001_guide');a.command('ai_claim','ai_001_q3')
            assert a.state['ai_world']['completed_count']==3
            a.walk([4,16]);a.command('ai_travel','ai_214');a.close();a=join(session,cid)
            assert a.ready['map_id']=='ai_214' and a.state['ai_world']['completed_count']==3
            assert len(a.state['ai_world']['completed'])==0
            assert sum(r['kind']=='npc' for r in a.population.values())==5
            a.approach('ai_214_guide');v,_=a.command('ai_accept','ai_214_q1',ok=False);assert v['code']=='AI_LEVEL_REQUIRED'
            a.walk(AI_MAPS['ai_214']['portal']['cell']);a.command('ai_travel','ai_213');a.close();a=join(session,cid)
            assert sum(r['kind']=='npc' for r in a.population.values())==7
            a.walk(AI_MAPS['ai_213']['portal']['cell']);a.command('ai_travel','qingyun_trail');a.close();a=join(session,cid)
            b=join(other,other_id);assert b.state['ai_world']['completed_count']==0
            # Screenshot-derived multi-cell pads: noncentral visible tiles must
            # be authorized by the server, and adjacent ordinary path must not.
            a.walk([3,16]);a.command('ai_travel','ai_021');a.close();a=join(session,cid)
            assert {r['name'] for r in a.population.values() if r['kind']=='npc'}=={'火修罗','五毒天王','哈哈老祖','孔灵子'}
            a.walk([4,27]);value,_=a.command('ai_travel','ai_022',ok=False);assert value['code']=='PORTAL_TOO_FAR'
            a.walk([3,26]);a.command('ai_travel','ai_022');a.close();a=join(session,cid)
            assert a.ready['map_id']=='ai_022'
            a.walk(AI_MAPS['ai_022']['portal']['cell']);a.command('ai_travel','ai_021');a.close();a=join(session,cid)
            # Approach the lower tile from its side; a direct diagonal route
            # correctly stops on the upper/middle tile first.
            a.walk([28,28]);a.walk([29,28]);a.command('ai_travel','ai_023');a.close();a=join(session,cid)
            assert a.ready['map_id']=='ai_023'
            legacy=join(*create('ai_legacy'),version=1);legacy.walk([3,16])
            legacy.ws.send(dict(type='pve.command',command=dict(operation_id=str(uuid4()),action='ai_travel',target='ai_001')))
            assert legacy.until('error')['code']=='MAP_UPDATE_REQUIRED'
            assert 'ai_001_q3' in db.query("SELECT details::text FROM security_audit WHERE action='pve.ai_claim' AND outcome='accepted'")
            print('AI WORLD SERVER: travel, proximity, isolation, ordered goals, receipts, rollback, full chain, durable respawn, restart, level gates and real client passed',flush=True)
        finally:
            for p in sockets:
                try:p.close()
                except OSError:pass
            stop(process)

if __name__=='__main__':main()
