"""Real sockets + an owned DB: party motion, consent, portals and restart recovery."""
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
from run_online_pve import api
from run_server_connection import wait_for_server
from ws_fixture import WebSocket

ROOT=Path(__file__).resolve().parents[1]
HASH=hashlib.sha256((ROOT/'shared/data/qingyun-v1.json').read_bytes()).hexdigest()

class Client:
    def __init__(self,base,identity):
        self.identity=identity;self.id=identity[1];self.events=[];self.team={};self.state={};self.ready={};self.seq=0;self.done=False
        status,ticket=api(base,'/api/v1/world/ticket',dict(character_id=self.id,protocol_version=1,config_hash=HASH),identity[0]['access_token'])
        assert status==200,ticket
        self.ws=WebSocket(base.replace('http:','ws:')+'/api/v1/world/ws')
        self.ws.send(dict(type='auth.exchange',ticket=ticket['ticket'],protocol_version=1,config_hash=HASH,world_sync_version=2,pve_version=1,maps_version=2,team_version=1))
        self.thread=threading.Thread(target=self.read,daemon=True);self.thread.start()
    def read(self):
        try:
            while not self.done:
                v,_=self.ws.recv()
                if v['type']=='world.team':self.team=v
                if v['type']=='auth.ready':self.ready=v
                if v['type'].startswith('pve.') and 'state' in v:self.state=v['state']
                self.events.append(v)
        except (OSError,EOFError,TimeoutError):pass
    def move(self,cell):
        self.seq+=1
        self.ws.send(dict(type='world.move_to',target=cell,input_seq=str(self.seq),**{k:self.ready[k] for k in ('game_session_id','connection_epoch','world_epoch')}))
    def travel(self,action,target):
        op=str(uuid4());self.ws.send(dict(type='pve.command',command=dict(operation_id=op,action=action,target=target)));return op
    def own(self):return getattr(self.ws,'entities',{}).get(self.id,{})
    def close(self):self.done=True;self.ws.close();self.thread.join(timeout=1)

def main():
    binary=os.environ.get('SSJX_TEST_SERVER_BIN',str(ROOT/'work/team-follow-target/debug/vssjx-server.exe'))
    checks=[];clients=[]
    def check(ok,label):assert ok,label;checks.append(label)
    def wait(predicate,label,timeout=16):
        deadline=time.monotonic()+timeout;ping=0
        while time.monotonic()<deadline:
            if predicate():return
            if time.monotonic()-ping>2:
                for c in clients:
                    if not c.done:
                        try:c.ws.send(dict(type='ping'))
                        except OSError:pass
                ping=time.monotonic()
            time.sleep(.04)
        raise AssertionError(label)
    with PostgresFixture() as db:
        env={k:v for k,v in os.environ.items() if not k.startswith('SSJX_')}
        env.update(RUST_LOG='info',SSJX_ENV_FILE='',SSJX_DATABASE_URL=db.url,SSJX_BIND_ADDR='127.0.0.1:0',SSJX_MONITOR_BIND_ADDR='',SSJX_LOG_DIR='',SSJX_AUTH_RATE_IP='10000',SSJX_AUTH_RATE_GLOBAL='100000',SSJX_AUTH_RATE_ACCOUNT='1000',SSJX_WORLD_RECONNECT_SECONDS='1')
        def start():
            p=subprocess.Popen([binary],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf8')
            try:base=wait_for_server(p)
            except BaseException:stop(p);raise
            threading.Thread(target=lambda:list(p.stdout),daemon=True).start();return p,base
        process,base=start()
        def create(name,quest=3):
            password='owned-follow-test-password'
            assert api(base,'/api/v1/auth/register',dict(username=name,password=password))[0]==201
            _,s=api(base,'/api/v1/auth/login',dict(username=name,password=password))
            status,v=api(base,'/api/v1/characters',dict(operation_id=str(uuid4()),display_name=name,job=1,gender=0,school=3,rules_version='creation-v1'),s['access_token']);assert status==201,v
            cid=v['character']['id'];db.query(f"UPDATE characters SET level=20,quest_stage={quest},cell_x=22,cell_y=9 WHERE id='{cid}'")
            return s,cid
        def connect(identity):
            c=Client(base,identity);clients.append(c);wait(lambda:c.state and c.own() and c.team,'World baseline and party state');return c
        def team(who,action,code='OK',**fields):
            payload=dict(character_id=who[1],action=action,**fields)
            if action!='snapshot':payload['operation_id']=str(uuid4())
            status,v=api(base,'/api/v1/teams',payload,who[0]['access_token']);check(status==200 and v['code']==code,f'{action}: {code}');return v
        def joined(who):return team(who,'snapshot')['state']['team']
        def settled(c,goal=None):return c.own() and c.own()['next_cell'] is None and (goal is None or c.own()['cell']==goal)
        def result(c,op):
            wait(lambda:any(v.get('operation_id')==op for v in c.events),'Travel receipt')
            return next(v for v in c.events if v.get('operation_id')==op)
        try:
            a,b,c=create('follow_a'),create('follow_b'),create('follow_c',1)
            ca,cb,cc=[connect(i) for i in (a,b,c)]
            for identity in (b,c):
                team(a,'invite',target=identity[1]);invite=team(identity,'snapshot')['state']['incoming'][0]['id'];team(identity,'accept',target=invite)
            wait(lambda:len(ca.team['members'])==3,'Live party markers arrive without HTTP polling')
            check(ca.team['members'][a[1]]['leader'] and not ca.team['following'],'Leader has the red-flag role and keeps manual control')
            check(cb.team['following'],'Joining defaults to prepared and following')
            wait(lambda:all(x.team['members'].get(b[1],{}).get('ready') is True for x in (ca,cb,cc)),'All observers receive the default prepared flag state')
            team(b,'ready',ready=True)
            wait(lambda:all(x.team['members'].get(b[1],{}).get('ready') is True for x in (ca,cb,cc)),'Preparing updates the flag for all three clients without polling')
            check(True,'Readiness is broadcast to every map observer')
            team(b,'ready',ready=False)
            wait(lambda:all(x.team['members'].get(b[1],{}).get('ready') is False for x in (ca,cb,cc)),'Temporary leave reaches every observer')
            team(b,'ready',ready=True);team(c,'ready',ready=True)
            team(a,'follow','TEAM_MEMBER_REQUIRED',ready=False)
            ca.move([27,14]);wait(lambda:settled(ca,[27,14]) and settled(cb) and settled(cc) and cb.own()['cell']!=[22,9],'Server moves both followers',8)
            for x in (cb,cc):
                check(sum(abs(x.own()['cell'][i]-ca.own()['cell'][i]) for i in (0,1))<=3,'Followers walk into a short train near the leader')
            cb.move([23,12]);wait(lambda:any(v.get('code')=='TEAM_FOLLOWING' for v in cb.events),'Manual movement is refused while following')
            cb.ws.send(dict(type='ping'));wait(lambda:any(v['type']=='pong' for v in cb.events),'Refused movement keeps the world connection alive')
            check(bool(cb.own()),'Following refusal preserves the world baseline')
            team(b,'follow',ready=False);wait(lambda:not cb.team['following'],'Temporary leave reflected in world')
            check(db.query("SELECT details->>'ready' FROM security_audit WHERE action='team.follow' AND outcome='accepted' ORDER BY created_at DESC LIMIT 1")=='false','Follow preference is recorded in the audit trail')
            old=cb.own()['cell'];ca.move([24,14]);wait(lambda:settled(ca,[24,14]),'Leader move after temporary leave');time.sleep(.5)
            check(cb.own()['cell']==old,'Temporarily absent member is not dragged by the leader')
            cb.move([23,12]);wait(lambda:settled(cb,[23,12]),'Temporarily absent member can move normally')
            team(b,'follow',ready=True);wait(lambda:settled(cb) and cb.own()['cell']!=[23,12],'Resuming follows via normal routes')
            check(next(m for m in joined(b)['members'] if m['id']==b[1])['ready'],'Legacy follow command prepares once instead of clearing readiness')
            ca.move([28,16]);wait(lambda:settled(ca,[28,16]),'Leader reaches portal')
            op=ca.travel('transfer','ruins_gate');check(result(ca,op)['ok'],'Leader portal travel succeeds')
            ca.close();ca=connect(a)
            check(ca.ready['map_id']=='ancient_ruins','Leader reconnects to destination room')
            team(b,'snapshot');team(a,'snapshot')
            wait(lambda:cb.team.get('travel') and cc.team.get('travel') and settled(cb,[28,16]) and settled(cc,[28,16]),'Followers walk to the same portal after leader transfer')
            op=cc.travel(cc.team['travel']['action'],cc.team['travel']['target'])
            check(result(cc,op)['code']=='PORTAL_LOCKED','Follower still has to satisfy their own map-unlock rule')
            check(cc.state['character']['map_id']=='qingyun_trail','Locked follower never teleports into a restricted map')
            op=cb.travel(cb.team['travel']['action'],cb.team['travel']['target']);check(result(cb,op)['ok'],'Eligible follower uses the ordinary durable travel operation')
            cb.close();cb=connect(b);wait(lambda:not cb.team.get('travel') and settled(cb),'Consumed trip is cleared after destination rejoin')
            check(cb.ready['map_id']=='ancient_ruins' and cb.team['following'],'Following survives the room connection change')
            # Server restart restores membership before the first movement command.
            cc.close();ca.close();cb.close();stop(process);process,base=start()
            ca=connect(a);cb=connect(b)
            check(cb.team['following'],'Following preference survives a full service restart')
            ca.move([8,18]);wait(lambda:settled(ca,[8,18]) and settled(cb) and cb.own()['cell']!=[5,16],'Restored followers resume server motion')
            team(a,'transfer',target=b[1]);wait(lambda:not cb.team['following'] and ca.team['following'],'Leader transfer reverses follow ownership')
            cb.move([10,19]);wait(lambda:settled(cb,[10,19]) and settled(ca),'New leader drives the former leader')
            team(b,'kick',target=a[1]);wait(lambda:not ca.team['following'] and a[1] not in ca.team['members'],'Kick immediately removes follow role and marker')
            ca.move([9,19]);wait(lambda:settled(ca,[9,19]),'Kicked member regains manual control')
            team(b,'disband');wait(lambda:not cb.team['members'],'Disband clears all map flags')
            check(db.query('SELECT count(*) FROM team_members')=='0','No persistent team records remain after disband')
            if os.environ.get('GODOT_BIN'):
                ua,ub=create('follow_ui_a'),create('follow_ui_b');leader=connect(ua)
                done=threading.Event();errors=[]
                def drive():
                    try:
                        deadline=time.monotonic()+45;invited=False
                        while time.monotonic()<deadline and not done.is_set():
                            if not invited:
                                _,v=api(base,'/api/v1/teams',dict(character_id=ua[1],action='invite',target=ub[1],operation_id=str(uuid4())),ua[0]['access_token'])
                                if v.get('ok'):invited=True
                                elif v.get('code')!='TEAM_PLAYER_OFFLINE':raise AssertionError(v)
                            else:
                                _,v=api(base,'/api/v1/teams',dict(character_id=ua[1],action='snapshot'),ua[0]['access_token'])
                                if len(v['state']['team']['members'])==2:break
                            leader.ws.send(dict(type='ping'));time.sleep(.2)
                        leader.move([28,16]);wait(lambda:settled(leader,[28,16]),'Live leader reaches portal')
                        time.sleep(.5)
                        op=leader.travel('transfer','ruins_gate');assert result(leader,op)['ok']
                        leader.close();connect(ua)
                    except BaseException as e:errors.append(repr(e))
                worker=threading.Thread(target=drive,daemon=True);worker.start()
                client_env=dict(os.environ,SSJX_TEAM_FOLLOW_TEST=json.dumps(dict(base=base,character=ub[1])))
                run=subprocess.run([os.environ['GODOT_BIN'],'--path',str(ROOT/'client'),'--quit-after','18000','res://tests/team_follow_live_test.tscn'],env=client_env,capture_output=True,text=True,encoding='utf8',timeout=85)
                done.set();worker.join(timeout=5)
                print(run.stdout);print(run.stderr)
                check(not errors,str(errors))
                check(run.returncode==0 and '0 failures' in run.stdout and 'SCRIPT ERROR' not in run.stderr,'Actual game automatically follows and changes rooms')
            print(f'TEAM FOLLOW: {len(checks)} checks passed')
        finally:
            for x in clients:x.close()
            stop(process)

if __name__=='__main__':main()
