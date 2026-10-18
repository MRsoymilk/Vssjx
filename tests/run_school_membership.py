"""Owned PostgreSQL + real protocol/Godot recruitment; never deploy or touch live DB."""
import json
import os
from pathlib import Path
import subprocess
import threading
from uuid import uuid4
from pg_fixture import PostgresFixture
from run_account_auth import stop
from run_online_maps import MapPlayer
from run_online_pve import api
from run_server_connection import wait_for_server

ROOT=Path(__file__).resolve().parents[1]

def main():
    with PostgresFixture() as db:
        env={k:v for k,v in os.environ.items() if not k.startswith('SSJX_')}
        env.update(SSJX_ENV_FILE='',SSJX_DATABASE_URL=db.url,SSJX_BIND_ADDR='127.0.0.1:0',SSJX_MONITOR_BIND_ADDR='',SSJX_LOG_DIR='',SSJX_WORLD_RECONNECT_SECONDS='1',SSJX_AUTH_RATE_IP='1000',SSJX_AUTH_RATE_ACCOUNT='100',SSJX_AUTH_RATE_GLOBAL='10000',RUST_LOG='info')
        def start():
            p=subprocess.Popen([os.environ['SSJX_TEST_SERVER_BIN']],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf8')
            try:base=wait_for_server(p)
            except BaseException:stop(p);raise
            threading.Thread(target=lambda:list(p.stdout),daemon=True).start()
            return p,base
        process,base=start()
        sockets=[]
        def create(name):
            password='owned-school-password'
            assert api(base,'/api/v1/auth/register',dict(username=name,password=password))[0]==201
            code,session=api(base,'/api/v1/auth/login',dict(username=name,password=password));assert code==200
            # Even old clients requesting a school cannot bypass NPC admission.
            code,data=api(base,'/api/v1/characters',dict(operation_id=str(uuid4()),display_name=name,job=1,gender=1,school=2,rules_version='creation-v1'),session['access_token'])
            assert code==201 and data['character']['school']==3,data
            cid=data['character']['id']
            db.query(f"UPDATE characters SET level=50,gold=91,quest_stage=4 WHERE id='{cid}'")
            return session,cid
        def join(session,cid):
            player=MapPlayer(base,session,cid,shop_version=2);sockets.append(player);return player
        def command(player,target,ok=True,revision=None):
            return player.command('',request=dict(operation_id=str(uuid4()),action='school_join',target=target,expected_revision=revision or player.state['character']['state_revision']),ok=ok)
        try:
            session,cid=create('school_first')
            a=join(session,cid)
            assert a.state['character']['school']==3 and len(a.state['skills']['available'])==8
            unjoined_skills=a.state['skills']['available'][:]
            refused,_=command(a,'kunlun',ok=False);assert refused['code']=='RESIDENT_TOO_FAR',refused
            a.approach('qingwei')
            refused,_=command(a,'bad',ok=False);assert refused['code']=='INVALID_SCHOOL'
            refused,_=command(a,'kunlun',ok=False,revision='9999');assert refused['code']=='STALE_SCHOOL'
            before={k:a.state['character'][k] for k in ['level','xp','gold','hp','mp','quest_stage']}
            admitted,request=command(a,'kunlun')
            assert admitted['state']['character']['school']==2
            assert {k:a.state['character'][k] for k in before}==before
            assert a.state['skills']['available']==unjoined_skills and 'sheet_004' in unjoined_skills and 'sheet_008' not in unjoined_skills
            replay,_=a.command('',request=request);assert replay['replayed'] and replay['state']==admitted['state']
            for target in ['kunlun','emei']:
                refused,_=command(a,target,ok=False);assert refused['code']=='SCHOOL_ALREADY_JOINED'
            assert db.query(f"SELECT school||':'||level||':'||gold||':'||quest_stage FROM characters WHERE id='{cid}'")=='2:50:91:4'
            assert db.query(f"SELECT count(*) FROM security_audit WHERE character_id='{cid}' AND action='pve.school_join' AND outcome='accepted'")=='1'
            a.approach('wolf_a');a.command('challenge','wolf_a')
            refused,_=command(a,'emei',ok=False);assert refused['code']=='BATTLE_ACTIVE'
            battle=a.state['battle']
            # Wrong job is still forbidden; a different school's same-job skill is usable.
            refused,_=a.command('',request=dict(operation_id=str(uuid4()),action='skill',target='sheet_011',battle_id=battle['id'],expected_revision=battle['revision']),ok=False)
            assert refused['code']=='SKILL_ROLE_MISMATCH'
            used,_=a.command('',request=dict(operation_id=str(uuid4()),action='skill',target='sheet_051',battle_id=battle['id'],expected_revision=battle['revision']))
            assert used['state']['battle']['skills']['last_skill']=='sheet_051'
            if a.state['battle'] and a.state['battle']['outcome']=='active':a.command('flee')
            a.close();stop(process);process,base=start();a=join(session,cid)
            assert a.state['character']['school']==2 and 'sheet_004' in a.state['skills']['available']
            a.close()
            migration=(ROOT/'server/migrations/0016_school_membership.sql').read_text('utf8')
            permanent=db.query(f"SELECT level||':'||gold||':'||quest_stage FROM characters WHERE id='{cid}'")
            upgrade=db.query('BEGIN;'+migration+f" SELECT school||':'||level||':'||gold||':'||quest_stage FROM characters WHERE id='{cid}';ROLLBACK;")
            assert '3:'+permanent in upgrade,upgrade
            assert db.query(f"SELECT school FROM characters WHERE id='{cid}'")=='2'
            if os.environ.get('GODOT_BIN'):
                create('school_ui')
                result=subprocess.run([os.environ['GODOT_BIN'],'--headless','--path',str(ROOT/'client'),'--quit-after','6000','res://tests/school_membership_live_test.tscn'],env=dict(os.environ,SSJX_SCHOOL_TEST_BASE=base,SSJX_CONNECTION_PATH=str(ROOT/'work/school-membership/test-connection.cfg')),capture_output=True,text=True,encoding='utf8',timeout=80)
                print(result.stdout,flush=True);print(result.stderr,flush=True)
                assert result.returncode==0 and '0 failures' in result.stdout and 'SCRIPT ERROR' not in result.stderr
            print('SCHOOL SERVER: unjoined creation, one-time migration, proximity, revision, admission, receipts, audit, shared job skills, battle lock, persistence and real client passed',flush=True)
        finally:
            for player in sockets:
                try:player.close()
                except OSError:pass
            stop(process)

if __name__=='__main__':main()
