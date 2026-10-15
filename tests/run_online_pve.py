"""Owned PostgreSQL + real Rust/WebSocket quests and combat; no user's DB/service."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import threading
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from uuid import uuid4
from pg_fixture import PostgresFixture
from run_account_auth import stop
from run_server_connection import wait_for_server
from ws_fixture import WebSocket

ROOT = Path(__file__).resolve().parents[1]
MAP = json.loads((ROOT / 'shared/data/qingyun-v1.json').read_text())
HASH = hashlib.sha256((ROOT / 'shared/data/qingyun-v1.json').read_bytes()).hexdigest()

class Player:
    def __init__(self, base, session, character):
        self.base, self.session, self.id = base, session, character
        status, ticket = api(base, '/api/v1/world/ticket', dict(character_id=character,protocol_version=1,config_hash=HASH),session['access_token'])
        assert status == 200, ticket
        assert ticket['pve_version'] == ticket['population_version'] == 1
        self.ws = WebSocket(base.replace('http://','ws://')+'/api/v1/world/ws')
        self.ws.send(dict(type='auth.exchange',ticket=ticket['ticket'],protocol_version=1,config_hash=HASH,world_sync_version=2,population_version=1,pve_version=1))
        self.population, self.state, self.seq = {}, {}, 0
        self.ready = self.until('auth.ready')
        self.state = self.until('pve.state')['state']
        self.until('population.state')
    def until(self, kind, operation=None):
        for _ in range(1200):
            value, _ = self.ws.recv()
            if value['type'] == 'error':
                if kind == 'error': return value
                raise AssertionError(value)
            if value['type']=='population.state': self.population={e['id']:e for e in value['entities']}
            if value['type'].startswith('pve.') and 'state' in value: self.state=value['state']
            if value['type']==kind and (operation is None or value['operation_id']==operation): return value
        raise AssertionError('No '+kind)
    def command(self, action, target=None, request=None, ok=True):
        if request is None:
            request=dict(operation_id=str(uuid4()),action=action)
            if target: request['target']=target
            elif action in ('attack','skill','guard','potion','flee'):
                request.update(battle_id=self.state['battle']['id'],expected_revision=self.state['battle']['revision'])
        self.ws.send(dict(type='pve.command',command=request))
        value=self.until('pve.result',request['operation_id'])
        assert value['ok']==ok,value
        return value,request
    def move(self, target):
        self.seq+=1
        self.ws.send(dict(type='world.move_to',target=target,input_seq=str(self.seq),**{k:self.ready[k] for k in ('game_session_id','connection_epoch','world_epoch')}))
    def approach(self,target):
        deadline=time.monotonic()+20
        while time.monotonic()<deadline:
            own=self.ws.entities[self.id]; resident=self.population[target]
            cell=own['cell']; dest=resident['cell']
            if abs(cell[0]-dest[0])+abs(cell[1]-dest[1])<=2 and own['next_cell'] is None: return
            if own['next_cell'] is None:
                # All population cells are walkable, so follow their current authoritative cell.
                self.move(dest)
            for _ in range(4): self.until('world.delta')
            self.ws.send({'type':'ping'})
        raise AssertionError('Could not approach '+target)
    def close(self): self.ws.close()

def api(base,path,payload=None,token=None):
    headers={'Content-Type':'application/json'}
    if token:headers['Authorization']='Bearer '+token
    try:r=urlopen(Request(base+path,data=json.dumps(payload).encode() if payload is not None else None,headers=headers),timeout=12)
    except HTTPError as e:r=e
    with r:return r.code,json.load(r)

def main():
    binary=os.environ.get('SSJX_TEST_SERVER_BIN',str(ROOT/'server/target/debug/vssjx-server'))
    with PostgresFixture() as db:
        env={k:v for k,v in os.environ.items() if not k.startswith('SSJX_')}
        env.update(SSJX_ENV_FILE='',SSJX_DATABASE_URL=db.url,SSJX_BIND_ADDR='127.0.0.1:0',SSJX_MONITOR_BIND_ADDR='',SSJX_LOG_DIR='',RUST_LOG='info',SSJX_AUTH_RATE_IP='1000',SSJX_AUTH_RATE_GLOBAL='10000',SSJX_AUTH_RATE_ACCOUNT='100',SSJX_WORLD_RECONNECT_SECONDS='1')
        def start():
            p=subprocess.Popen([binary],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8')
            try: base=wait_for_server(p)
            except BaseException:stop(p);raise
            threading.Thread(target=lambda:list(p.stdout),daemon=True).start()
            return p,base
        process,base=start(); sockets=[]
        def run_client():
            godot_env=dict(os.environ,SSJX_PVE_BASE=base,SSJX_PVE_USER='pve_second',SSJX_PVE_PASSWORD='owned-pve-test-password')
            result=subprocess.run([os.environ['GODOT_BIN'],'--headless','--path',str(ROOT/'client'),'res://tests/online_pve_live_test.tscn'],env=godot_env,capture_output=True,text=True,encoding='utf-8',timeout=70)
            print(result.stdout);print(result.stderr)
            assert result.returncode==0 and '0 failures' in result.stdout and 'SCRIPT ERROR' not in result.stderr
        try:
            def create(name):
                password='owned-pve-test-password'
                assert api(base,'/api/v1/auth/register',dict(username=name,password=password))[0]==201
                code,session=api(base,'/api/v1/auth/login',dict(username=name,password=password));assert code==200
                code,data=api(base,'/api/v1/characters',dict(operation_id=str(uuid4()),display_name=name,job=0,gender=0,school=0,rules_version='creation-v1'),session['access_token']);assert code==201,data
                return session,data['character']['id']
            session,char=create('pve_first');other,other_id=create('pve_second')
            if os.environ.get('SSJX_TEST_PVE_CLIENT_ONLY') == '1':
                run_client()
                return
            a=Player(base,session,char);sockets.append(a)
            b=Player(base,other,other_id);sockets.append(b)
            assert a.state['character']['quest_stage']==0 and a.state['potions']==6
            value,_=a.command('accept','qingwei',ok=False);assert value['code']=='RESIDENT_TOO_FAR'
            a.approach('qingwei')
            accepted,accept=a.command('accept','qingwei'); assert accepted['state']['character']['quest_stage']==1
            again,_=a.command('',request=accept); assert again['replayed'] and again['state']==accepted['state']
            conflict=dict(accept,action='claim');v,_=a.command('',request=conflict,ok=False);assert v['code']=='PVE_ID_CONFLICT'
            v,_=a.command('claim','qingwei',ok=False);assert v['code']=='QUEST_NOT_READY'
            v,_=a.command('challenge','wolf_a',ok=False);assert v['code']=='RESIDENT_TOO_FAR'
            for index,target in enumerate(('wolf_a','wolf_b','wolf_c')):
                a.approach(target)
                v,challenge=a.command('challenge',target);assert v['state']['battle']['outcome']=='active'
                if index==0:
                    # Movement is disallowed during a durable encounter.
                    a.move([10,14]);assert a.until('error')['code']=='BATTLE_ACTIVE'
                    v,turn=a.command('attack');hp=v['state']['battle']['enemy_hp']
                    replay,_=a.command('',request=turn);assert replay['replayed'] and replay['state']['battle']['enemy_hp']==hp
                    stale=dict(turn,operation_id=str(uuid4()));v,_=a.command('',request=stale,ok=False);assert v['code']=='STALE_BATTLE'
                    # Receipt failure must roll back both potion consumption and combat turn.
                    before=a.state
                    db.query("CREATE FUNCTION reject_pve_receipt() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'owned rollback probe'; END$$; CREATE TRIGGER reject_receipt BEFORE INSERT ON pve_operation_receipts FOR EACH ROW EXECUTE FUNCTION reject_pve_receipt();")
                    pending=dict(operation_id=str(uuid4()),action='potion',battle_id=before['battle']['id'],expected_revision=before['battle']['revision'])
                    a.ws.send(dict(type='pve.command',command=pending));assert a.until('error')['code']=='DATABASE_UNAVAILABLE'
                    db.query('DROP TRIGGER reject_receipt ON pve_operation_receipts; DROP FUNCTION reject_pve_receipt();')
                    # Reconnect resumes persisted battle; retry original unknown command once.
                    a.close();time.sleep(.2)
                    a=Player(base,session,char);sockets.append(a)
                    assert a.state['battle']==before['battle'] and a.state['potions']==6
                    v,_=a.command('',request=pending);assert v['state']['potions']==5
                    v,_=a.command('',request=pending);assert v['replayed'] and v['state']['potions']==5
                    # Real process restart, same DB and login; active battle is durable.
                    battle=a.state['battle'];a.close();b.close();stop(process)
                    process,base=start();a=Player(base,session,char);sockets.append(a)
                    assert a.state['battle']==battle and a.state['potions']==5
                while a.state['battle']['outcome']=='active':
                    v,_=a.command('skill' if a.state['battle']['mp']>=9 else 'attack')
                    time.sleep(.06)
                assert a.state['battle']['outcome']=='victory',a.state
                assert a.state['progress']['kills']==index+1
                reward=a.state['character']['gold']
                # Replaying opening operation after victory cannot recreate battle in memory or DB.
                a.command('',request=challenge)
                a.close();time.sleep(.2);a=Player(base,session,char);sockets.append(a)
                assert a.state['battle'] is None and a.state['character']['gold']==reward
                v,_=a.command('challenge',target,ok=False);assert v['code']=='MONSTER_DEFEATED'
                a.approach('qingwei');a.command('restore','qingwei')
            assert a.state['character']['quest_stage']==2
            claimed,request=a.command('claim','qingwei');assert claimed['state']['character']['quest_stage']==3
            assert claimed['state']['character']['gold']==30+12+14+16+60
            a.command('',request=request)
            value,_=a.command('claim','qingwei',ok=False);assert value['code']=='QUEST_NOT_READY'
            assert db.query(f"SELECT defeated_mask||':'||quest_stage||':'||gold FROM characters WHERE id='{char}'")=='7:3:132'
            assert db.query(f"SELECT COUNT(*) FROM pve_battles WHERE character_id='{char}' AND active")=='0'
            assert db.query(f"SELECT quest_stage||':'||gold FROM characters WHERE id='{other_id}'")=='0:30'
            # Second player's independent progress and shared population remain untouched.
            b=Player(base,other,other_id);sockets.append(b)
            assert b.state['progress']['kills']==0 and len(b.population)==5
            # Same-session socket replacement fences the prior owner.
            replacement=Player(base,session,char);sockets.append(replacement)
            assert replacement.state['character']['quest_stage']==3
            try: assert a.until('error')['code']=='SESSION_REPLACED'
            except (EOFError,ConnectionResetError): pass
            # Optional Godot live client test uses owned test accounts only.
            if os.environ.get('SSJX_TEST_PVE_GODOT'):
                for p in sockets:
                    try:p.close()
                    except OSError:pass
                time.sleep(1.3)
                run_client()
            print('Online PVE integration: PASS (quests, battles, replay, rollback, restart, isolation, ownership)')
        finally:
            for p in sockets:
                try:p.close()
                except OSError:pass
            stop(process)
if __name__=='__main__':main()
