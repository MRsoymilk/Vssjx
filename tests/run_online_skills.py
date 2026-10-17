"""Named skill commands against an owned PostgreSQL/server, never the live service."""
import copy
import json
import os
import subprocess
import threading
import time
from uuid import uuid4
from pg_fixture import PostgresFixture
from run_online_pve import ROOT, Player, api
from run_account_auth import stop
from run_server_connection import wait_for_server


def main():
    catalog = json.loads((ROOT/'client/assets/data/skills-v1.json').read_text('utf8'))
    with PostgresFixture() as db:
        env = {k:v for k,v in os.environ.items() if not k.startswith('SSJX_')}
        env.update(SSJX_ENV_FILE='', SSJX_DATABASE_URL=db.url, SSJX_BIND_ADDR='127.0.0.1:0',
                   SSJX_MONITOR_BIND_ADDR='', SSJX_LOG_DIR='', RUST_LOG='info',
                   SSJX_AUTH_RATE_IP='1000', SSJX_AUTH_RATE_ACCOUNT='100', SSJX_AUTH_RATE_GLOBAL='10000')
        def start():
            p = subprocess.Popen([os.environ['SSJX_TEST_SERVER_BIN']], env=env,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf8')
            try: base = wait_for_server(p)
            except BaseException: stop(p); raise
            threading.Thread(target=lambda:list(p.stdout), daemon=True).start()
            return p, base
        process, base = start()
        clients = []
        try:
            password = 'owned-skills-test-password'
            assert api(base, '/api/v1/auth/register', dict(username='skills_test',password=password))[0] == 201
            code, session = api(base, '/api/v1/auth/login', dict(username='skills_test',password=password)); assert code == 200
            code, created = api(base, '/api/v1/characters', dict(operation_id=str(uuid4()),display_name='技能修士',job=0,gender=0,school=2,rules_version='creation-v1'),session['access_token']); assert code == 201, created
            char = created['character']['id']
            db.query(f"UPDATE characters SET quest_stage=1 WHERE id='{char}'")
            a = Player(base,session,char); clients.append(a)
            a.approach('wolf_a'); a.command('challenge','wolf_a')
            battle_id = a.state['battle']['id']
            template = json.loads(db.query(f"SELECT state::text FROM pve_battles WHERE id='{battle_id}'"))

            def seed(job, school, level=60, mp=400):
                nonlocal a
                a.close(); time.sleep(.15)
                b = copy.deepcopy(template)
                b.update(hp=100,mp=mp,enemy_hp=10000,round=0,revision=0,outcome='active',skills={},skill_rules_version=0)
                b['enemy'].update(hp=10000,attack=150)
                db.query(f"UPDATE characters SET job={job},school={school},level={level},hp=100,mp={mp},state_revision=state_revision+1 WHERE id='{char}'; UPDATE pve_battles SET state=$owned${json.dumps(b)}$owned$::jsonb WHERE id='{battle_id}'")
                a=Player(base,session,char); clients.append(a)

            def request(id):
                return dict(operation_id=str(uuid4()),action='skill',target=id,battle_id=battle_id,expected_revision=a.state['battle']['revision'])

            # Capability is independent of the old shop/world protocol versions.
            assert a.state['skills']['version']=='skills-v1'
            seed(0,2,1,35)
            for id, code in [('not_a_skill','INVALID_SKILL'),('sheet_003','SKILL_ROLE_MISMATCH'),('sheet_010','SKILL_LEVEL_REQUIRED')]:
                before = copy.deepcopy(a.state)
                value,_ = a.command('',request=request(id),ok=False)
                assert value['code']==code, value
                assert value['state']['battle']==before['battle'] and value['state']['character']==before['character']
            seed(0,2,60,0)
            value,_=a.command('',request=request('sheet_010'),ok=False); assert value['code']=='MP_INSUFFICIENT'
            value,_=a.command('',request=request('sheet_014'),ok=False); assert value['code']=='PASSIVE_SKILL'
            value,_=a.command('',request=request('sheet_025'),ok=False); assert value['code']=='SKILL_ROLE_MISMATCH'

            count=0
            for skill in catalog['items']:
                if not skill['source_row']: continue
                seed(skill['job'],max(0,skill['school']))
                assert skill['id'] in a.state['skills']['available']
                before=copy.deepcopy(a.state)
                command=request(skill['id'])
                if not skill['active']:
                    value,_=a.command('',request=command,ok=False); assert value['code']=='PASSIVE_SKILL'
                    assert value['state']['battle']==before['battle']; count+=1; continue
                if skill['id']=='sheet_019':
                    db.query("CREATE FUNCTION reject_skill_receipt() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'owned skill rollback'; END$$; CREATE TRIGGER reject_receipt BEFORE INSERT ON pve_operation_receipts FOR EACH ROW EXECUTE FUNCTION reject_skill_receipt();")
                    a.ws.send(dict(type='pve.command',command=command)); assert a.until('error')['code']=='DATABASE_UNAVAILABLE'
                    db.query('DROP TRIGGER reject_receipt ON pve_operation_receipts; DROP FUNCTION reject_skill_receipt();')
                    a.close();time.sleep(.15);a=Player(base,session,char);clients.append(a)
                    assert a.state['battle']==before['battle'] and a.state['character']==before['character']
                value,_=a.command('',request=command)
                b=value['state']['battle']
                assert b['skills']['last_skill']==skill['id'] and b['round']==1
                assert any(skill['name'] in line for line in value['lines'])
                assert 0<=b['mp']<=value['state']['stats']['mp'] and b['enemy_hp']<=10000,(skill['id'],b)
                expected=400-skill['mp_cost']+(min(20,32) if skill['effect']=='mana_steal' else 0)
                assert b['mp']==expected,(skill,b)
                replay,_=a.command('',request=command);assert replay['replayed'] and replay['state']==value['state']
                stale=dict(command,operation_id=str(uuid4()))
                rejected,_=a.command('',request=stale,ok=False);assert rejected['code']=='STALE_BATTLE'
                assert rejected['state']['battle']==b
                if skill['id']=='sheet_019':
                    a.close();stop(process);process,base=start();a=Player(base,session,char);clients.append(a)
                    assert a.state['battle']==b and b['skills']['enemy_bleed']==1
                    a.command('guard')
                    assert a.state['battle']['skills']['enemy_bleed']==0
                    assert b['enemy_hp']-a.state['battle']['enemy_hp']==b['skills']['bleed_damage']
                count+=1
                time.sleep(.07)
            # Database and allocation rules also permit every point at the new cap.
            seed(0,2)
            a.command('flee')
            command=dict(operation_id=str(uuid4()),action='allocate',attributes=[300,0,0,0,0],expected_revision=a.state['character']['state_revision'])
            value,_=a.command('',request=command)
            assert value['state']['attributes']['available']==0 and value['state']['attributes']['allocated']==[300,0,0,0,0]
            assert count==30
            print('ONLINE SKILLS: PASS (30 named skills, role/school/level/MP/passive guards, atomic rollback, replay, stale turns, restart, DOT expiry, level-60 allocation)')
        finally:
            for c in clients:
                try:c.close()
                except OSError:pass
            stop(process)


if __name__=='__main__': main()
