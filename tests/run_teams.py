"""Owned PostgreSQL and real sockets: consent, shared encounters and exact-once loot."""
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

ROOT=Path(__file__).resolve().parents[1]
class TeamPlayer(Player):
    def move(self,target):
        time.sleep(.16)
        super().move(target)

def main():
    binary=os.environ.get('SSJX_TEST_SERVER_BIN',str(ROOT/'work/duels/target/debug/vssjx-server.exe'))
    checks=[];players=[]
    def check(ok,label):
        assert ok,label
        checks.append(label)
    with PostgresFixture() as db:
        env={k:v for k,v in os.environ.items() if not k.startswith('SSJX_')}
        env.update(SSJX_ENV_FILE='',SSJX_DATABASE_URL=db.url,SSJX_BIND_ADDR='127.0.0.1:0',SSJX_MONITOR_BIND_ADDR='',SSJX_LOG_DIR='',RUST_LOG='info',SSJX_AUTH_RATE_IP='10000',SSJX_AUTH_RATE_GLOBAL='100000',SSJX_AUTH_RATE_ACCOUNT='1000',SSJX_WORLD_RECONNECT_SECONDS='1')
        def start():
            p=subprocess.Popen([binary],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf8')
            try:base=wait_for_server(p)
            except BaseException:stop(p);raise
            threading.Thread(target=lambda:list(p.stdout),daemon=True).start()
            return p,base
        process,base=start()
        try:
            def create(name):
                password='owned-team-test-password'
                assert api(base,'/api/v1/auth/register',dict(username=name,password=password))[0]==201
                _,s=api(base,'/api/v1/auth/login',dict(username=name,password=password))
                code,c=api(base,'/api/v1/characters',dict(operation_id=str(uuid4()),display_name=name,job=1,gender=0,school=3,rules_version='creation-v1'),s['access_token'])
                assert code==201,c
                cid=c['character']['id']
                db.query(f"UPDATE characters SET level=20,hp=437,mp=197,quest_stage=1,cell_x=22,cell_y=9 WHERE id='{cid}'")
                return s,cid
            a,b,c=[create('team_'+s) for s in ['a','b','c']]
            for s,cid in [a,b,c]:players.append(TeamPlayer(base,s,cid))
            def send(who,action,expected='OK',request=None,**fields):
                for p in players:
                    if time.monotonic()-getattr(p,'team_keepalive',0)>2:
                        p.ws.send(dict(type='ping'));p.team_keepalive=time.monotonic()
                payload=request or dict(character_id=who[1],action=action,**fields)
                if action!='snapshot' and request is None:payload['operation_id']=str(uuid4())
                status,v=api(base,'/api/v1/teams',payload,who[0]['access_token'])
                assert status==200 and v['code']==expected,(status,v,expected,action)
                check(v['ok']==(expected=='OK'),action+': '+expected)
                return v,payload
            check(api(base,'/api/v1/teams',dict(character_id=a[1],action='snapshot'),b[0]['access_token'])[0]==403,'Cannot act as another account character')
            check(api(base,'/api/v1/teams',dict(character_id=a[1],action='attack',damage=99999),a[0]['access_token'])[0]==400,'Injected combat values rejected')
            send(a,'invite',target=b[1])
            inv=send(b,'snapshot')[0]['state']['incoming'][0]['id']
            send(c,'accept','TEAM_INVITE_EXPIRED',target=inv)
            send(b,'accept',target=inv)
            check(len(send(a,'snapshot')[0]['state']['team']['members'])==2,'Explicit recipient consent creates a shared team')
            send(b,'invite','TEAM_LEADER_REQUIRED',target=c[1])
            send(a,'challenge','TEAM_NOT_READY',target='spirit')
            send(a,'ready',ready=True);send(b,'ready',ready=True)
            initial,request=send(a,'challenge',target='spirit')
            battle=initial['state']['team']['battle']
            check(len(battle['fighters'])==2 and len(battle['enemies'])>=2,'Both players share one multi-monster encounter')
            check(battle['enemies'][0]['definition']['hp']>next(d for d in json.loads((ROOT/'shared/data/qingyun-population-v1.json').read_text()) if d['id']=='spirit')['hp'],'Monster HP is stronger in a party')
            check(send(b,'snapshot')[0]['state']['team']['battle']['id']==battle['id'],'Teammate receives the identical authoritative battle')
            retried,_=send(a,'challenge',request=request)
            check(retried['replayed'] and retried['state']['team']['battle']['id']==battle['id'],'Retry cannot create another battle')
            value,_=players[0].command('challenge','spirit',ok=False)
            check(value['code']=='TEAM_BATTLE_ACTIVE','Solo PvE cannot bypass an active team encounter')
            turn=battle['fighters'][battle['turn']]['id']
            actor=a if turn==a[1] else b;other=b if actor==a else a
            fields=dict(battle_id=battle['id'],expected_revision=battle['revision'],target='m0')
            send(other,'attack','TEAM_NOT_YOUR_TURN',**fields)
            send(c,'attack','NO_ACTIVE_BATTLE',**fields)
            send(actor,'kick','TEAM_BATTLE_ACTIVE',target=other[1])
            # An injected audit failure rolls back HP, battle revision and receipt.
            db.query("CREATE FUNCTION reject_team_audit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.action LIKE 'team.%' THEN RAISE EXCEPTION 'owned failure'; END IF; RETURN NEW; END $$; CREATE TRIGGER reject_team BEFORE INSERT ON security_audit FOR EACH ROW EXECUTE FUNCTION reject_team_audit();")
            failed=dict(character_id=actor[1],operation_id=str(uuid4()),action='attack',**fields)
            before=db.query('SELECT id,hp,mp,gold,xp,state_revision FROM characters ORDER BY id')
            check(api(base,'/api/v1/teams',failed,actor[0]['access_token'])[0]==503,'Uncommitted combat outcome is not acknowledged')
            check(db.query('SELECT id,hp,mp,gold,xp,state_revision FROM characters ORDER BY id')==before,'Audit failure restores all member resources')
            db.query('DROP TRIGGER reject_team ON security_audit; DROP FUNCTION reject_team_audit();')
            victory_request=None
            for _ in range(60):
                battle=send(a,'snapshot')[0]['state']['team']['battle']
                if battle['outcome']!='active':break
                actor=next(who for who in [a,b] if who[1]==battle['fighters'][battle['turn']]['id'])
                target=next(e['slot'] for e in battle['enemies'] if e['hp']>0)
                result,cmd=send(actor,'attack',battle_id=battle['id'],expected_revision=battle['revision'],target=target)
                if result['state']['team']['battle']['outcome']=='victory':victory_request=actor,cmd;break
            check(victory_request is not None,'Cooperative encounter finishes with team victory')
            totals=db.query('SELECT id,hp,mp,gold,xp,quest_stage FROM characters ORDER BY id')
            send(victory_request[0],'attack',request=victory_request[1])
            check(db.query('SELECT id,hp,mp,gold,xp,quest_stage FROM characters ORDER BY id')==totals,'Victory replay cannot award resources twice')
            send(a,'ready',ready=True);send(b,'ready',ready=True)
            send(a,'challenge','MONSTER_RESPAWNING',target='spirit')
            send(a,'transfer',target=b[1]);send(a,'disband','TEAM_LEADER_REQUIRED')
            send(b,'kick',target=a[1])
            check(send(a,'snapshot')[0]['state']['team'] is None,'Kicked member loses team membership')
            for p in players:p.close()
            players.clear();stop(process);process,base=start()
            restored,_=send(b,'snapshot')
            check(restored['state']['team']['leader'] and len(restored['state']['team']['members'])==1,'Team leadership and membership survive restart')
            players.append(TeamPlayer(base,b[0],b[1]))
            send(b,'disband')
            print(f'TEAMS: {len(checks)} checks passed')
        finally:
            for p in players:p.close()
            stop(process)

if __name__=='__main__':main()
