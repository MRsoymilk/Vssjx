"""Disposable DB and real sockets: map/species pressure, retry/restart and elite settlement."""
import copy
import json
import os
from pathlib import Path
import subprocess
import threading
import time
from uuid import uuid4
from pg_fixture import PostgresFixture
from run_online_pve import Player, api, ROOT
from run_account_auth import stop
from run_server_connection import wait_for_server

class HuntPlayer(Player):
    def move(self,target):
        time.sleep(.18)
        super().move(target)

def main():
    checks=0
    def check(ok,label):
        nonlocal checks
        assert ok,label
        checks+=1
    with PostgresFixture() as db:
        env={k:v for k,v in os.environ.items() if not k.startswith('SSJX_')}
        env.update(SSJX_ENV_FILE='',SSJX_DATABASE_URL=db.url,SSJX_BIND_ADDR='127.0.0.1:0',SSJX_MONITOR_BIND_ADDR='',SSJX_LOG_DIR='',RUST_LOG='info',SSJX_AUTH_RATE_IP='10000',SSJX_AUTH_RATE_ACCOUNT='1000',SSJX_AUTH_RATE_GLOBAL='100000',SSJX_WORLD_RECONNECT_SECONDS='1')
        def start():
            p=subprocess.Popen([os.environ['SSJX_TEST_SERVER_BIN']],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf8')
            try: base=wait_for_server(p)
            except BaseException:stop(p);raise
            threading.Thread(target=lambda:list(p.stdout),daemon=True).start()
            return p,base
        process,base=start();clients=[]
        def create(name):
            password='owned-elite-test-password'
            assert api(base,'/api/v1/auth/register',dict(username=name,password=password))[0]==201
            _,s=api(base,'/api/v1/auth/login',dict(username=name,password=password))
            status,c=api(base,'/api/v1/characters',dict(operation_id=str(uuid4()),display_name=name,job=1,gender=0,school=3,rules_version='creation-v1'),s['access_token'])
            assert status==201,c
            cid=c['character']['id'];db.query(f"UPDATE characters SET level=60,hp=1000,mp=400,quest_stage=1 WHERE id='{cid}'")
            return s,cid
        def connect(s,c):
            a=HuntPlayer(base,s,c);clients.append(a);return a
        def close(a):
            a.close();clients.remove(a);time.sleep(.15)
        def pressure(c):return json.loads(db.query(f"SELECT hunt_pressure FROM characters WHERE id='{c}'"))
        def challenge(a,target='wolf_a',version=2,ok=True):
            a.approach(target)
            return a.command('',request=dict(operation_id=str(uuid4()),action='challenge',target=target,encounter_version=version),ok=ok)
        def wire(a):
            if not os.environ.get('GODOT_BIN'):return
            path=ROOT/'work/elite-server-state.json';path.write_text(json.dumps(a.state,ensure_ascii=False),encoding='utf8')
            r=subprocess.run([os.environ['GODOT_BIN'],'--headless','--path',str(ROOT/'client'),'res://tests/elite_wire_test.tscn'],env=dict(os.environ,SSJX_SOLO_STATE=str(path)),capture_output=True,text=True,encoding='utf8',timeout=30)
            check(r.returncode==0 and 'ELITE WIRE: PASS' in r.stdout and 'SCRIPT ERROR' not in r.stderr,r.stdout+r.stderr)
        def store(b):
            raw=copy.deepcopy(b);raw['revision']=int(raw['revision'])
            db.query(f"UPDATE pve_battles SET state=$owned${json.dumps(raw)}$owned$::jsonb WHERE id='{b['id']}'")
        try:
            s,c=create('elite_solo');a=connect(s,c)
            for i in range(4):
                value,request=challenge(a,'wolf_a' if i%2==0 else 'wolf_b')
                check(value['state']['hunt_pressure']['count']==i+1,'Same species at different residents/positions counts together')
                check(value['state']['battle']['formation']['monster_revision']==1,'First four encounters stay ordinary')
                replay,_=a.command('',request=request)
                check(replay['replayed'] and pressure(c)['count']==i+1,'Retry cannot count a second encounter')
                a.command('flee')
            close(a);stop(process);process,base=start();a=connect(s,c)
            check(a.state['hunt_pressure']['count']==4,'Restart and reconnect preserve pressure')
            rejected,_=challenge(a,version=1,ok=False)
            check(rejected['code']=='CLIENT_UPDATE_REQUIRED' and pressure(c)['count']==4,'Old renderer cannot bypass fifth encounter; failed challenge is atomic')
            value,request=challenge(a)
            b=value['state']['battle'];check(b['formation']['monster_revision']==2 and b['formation']['enemies'][0]['elite']['revives_left']==1,'Fifth encounter is a solo elite')
            check(pressure(c)['count']==5,'Accepted elite is durable')
            wire(a)
            a.command('flee');check(pressure(c)['count']==5,'Flee does not clear the elite')
            value,_=challenge(a);b=value['state']['battle'];close(a)
            # Isolate the finite-life transition without modifying frozen definitions/rewards.
            for e in b['formation']['enemies']:e['hp']=0
            b['formation']['enemies'][0]['hp']=1;b['enemy_hp']=1;store(b)
            a=connect(s,c);gold=a.state['character']['gold'];reward=sum(e['definition']['gold'] for e in b['formation']['enemies'])
            saw_revive=False
            for _ in range(12):
                value,last=a.command('attack')
                if any(e['action']=='revive' for e in value['state']['battle']['formation']['events']):saw_revive=True
                if value['state']['battle']['outcome']!='active':break
            check(saw_revive and a.state['battle']['outcome']=='victory','Revival prevents premature victory but final death settles')
            wire(a)
            check(a.state['character']['gold']==gold+reward and pressure(c)['count']==0,'Rewards paid once and pressure cleared on victory')
            replay,_=a.command('',request=last)
            check(replay['replayed'] and pressure(c)['count']==0 and replay['state']['character']['gold']==gold+reward,'Settlement retry cannot repeat rewards or counters')
            close(a)
            db.query(f"UPDATE characters SET monster_respawns='{{}}'::jsonb,hunt_pressure='{{\"map\":\"qingyun_trail\",\"species\":\"monster/langw\",\"count\":4}}'::jsonb WHERE id='{c}'")
            db.query(f"UPDATE characters SET map_id='ancient_ruins' WHERE id='{c}'; UPDATE characters SET map_id='qingyun_trail' WHERE id='{c}'")
            check(pressure(c)=={},'Leaving and returning resets pressure even without an intervening challenge')
            # One actual follower reaches five; the leader need not be the triggering character.
            s2,c2=create('elite_mate');a=connect(s,c);mate=connect(s2,c2);a.approach('spirit');mate.approach('spirit')
            def team(session,cid,action,expected='OK',**fields):
                for client in clients:client.ws.send({'type':'ping'})
                req=dict(character_id=cid,action=action,**fields)
                if action!='snapshot':req['operation_id']=str(uuid4())
                status,v=api(base,'/api/v1/teams',req,session['access_token'])
                check(status==200 and v['code']==expected,f'{action}: {v}')
                return v,req
            team(s,c,'create');team(s,c,'invite',target=c2)
            inv=team(s2,c2,'snapshot')[0]['state']['incoming'][0]['id'];team(s2,c2,'accept',target=inv);team(s2,c2,'ready',ready=True)
            db.query(f"UPDATE characters SET hunt_pressure='{{\"map\":\"qingyun_trail\",\"species\":\"monster/hs1\",\"count\":4}}'::jsonb WHERE id='{c2}'")
            # Deferred commit failure must roll back counters as well as the battle.
            db.query("CREATE FUNCTION reject_elite_commit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.action='team.challenge' AND NEW.outcome='accepted' THEN RAISE EXCEPTION 'owned failure'; END IF; RETURN NEW; END $$; CREATE CONSTRAINT TRIGGER reject_elite_commit AFTER INSERT ON security_audit DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION reject_elite_commit();")
            a.approach('spirit');time.sleep(.8)
            req=dict(character_id=c,action='challenge',target='spirit',encounter_version=2,operation_id=str(uuid4()))
            status,v=api(base,'/api/v1/teams',req,s['access_token']);check(status==503,f'Failed commit cannot report successful elite entry: {status}: {v}')
            check(pressure(c).get('count',0)==0 and pressure(c2)['count']==4,'Team transaction failure rolls every counter back')
            db.query('DROP TRIGGER reject_elite_commit ON security_audit; DROP FUNCTION reject_elite_commit();')
            team(s,c,'snapshot')  # Resolve the conservative movement fence after failed commit.
            a.approach('spirit')
            time.sleep(.8)
            v,_=team(s,c,'challenge',target='spirit',encounter_version=2)
            group=v['state']['team']['battle'];check(group['monster_revision']==2 and group['enemies'][0]['elite']==dict(party_size=2,revives_left=2),'A due follower triggers the stronger party elite')
            check(pressure(c)['count']==1 and pressure(c2)['count']==5,'Only actual participants acquire their own counter')
            team(s,c,'flee',battle_id=group['id'],expected_revision=group['revision']);check(pressure(c2)['count']==5,'Party retreat retains triggering member pressure')
            # Party victory clears the due follower, retaining the leader's incomplete run.
            team(s2,c2,'ready',ready=True)
            a.approach('spirit');time.sleep(.5)
            v,_=team(s,c,'challenge',target='spirit',encounter_version=2)
            group=v['state']['team']['battle']
            for e in group['enemies']:e['hp']=0
            group['enemies'][0]['hp']=1;group['enemies'][0]['elite']['revives_left']=0
            db.query(f"UPDATE team_battles SET state=$owned${json.dumps(group)}$owned$::jsonb WHERE id='{group['id']}'")
            for session,cid in [(s,c),(s2,c2)]:
                v,_=team(session,cid,'attack',target='m0',battle_id=group['id'],expected_revision=group['revision'])
                group=v['state']['team']['battle']
            check(group['outcome']=='victory' and pressure(c2)['count']==0 and pressure(c)['count']==2,'Party settlement clears only matching due participants')
            print(f'ELITE SERVER: {checks} checks, 0 failures')
        finally:
            for client in clients:client.close()
            stop(process)
if __name__=='__main__':main()
