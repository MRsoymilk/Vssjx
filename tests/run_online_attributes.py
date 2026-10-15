"""Real owned PostgreSQL/WebSocket attribute allocation, rollback, persistence and combat."""
import os, subprocess, threading, time
from uuid import uuid4
from run_online_pve import Player, api, ROOT
from pg_fixture import PostgresFixture
from run_account_auth import stop
from run_server_connection import wait_for_server

def main():
 with PostgresFixture() as db:
  env={k:v for k,v in os.environ.items() if not k.startswith('SSJX_')}
  env.update(SSJX_ENV_FILE='',SSJX_DATABASE_URL=db.url,SSJX_BIND_ADDR='127.0.0.1:0',SSJX_MONITOR_BIND_ADDR='',SSJX_LOG_DIR='',RUST_LOG='info',SSJX_AUTH_RATE_IP='1000',SSJX_AUTH_RATE_ACCOUNT='100',SSJX_AUTH_RATE_GLOBAL='10000')
  def start():
   p=subprocess.Popen([os.environ['SSJX_TEST_SERVER_BIN']],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8')
   try:base=wait_for_server(p)
   except BaseException:stop(p);raise
   threading.Thread(target=lambda:list(p.stdout),daemon=True).start();return p,base
  process,base=start();clients=[]
  try:
   password='owned-attribute-test-password'
   assert api(base,'/api/v1/auth/register',dict(username='attr_first',password=password))[0]==201
   code,session=api(base,'/api/v1/auth/login',dict(username='attr_first',password=password));assert code==200
   code,data=api(base,'/api/v1/characters',dict(operation_id=str(uuid4()),display_name='属性修士',job=1,gender=0,school=2,rules_version='creation-v1'),session['access_token']);assert code==201
   char=data['character']['id'];a=Player(base,session,char);clients.append(a)
   assert a.state['attributes']['available']==5 and a.state['attributes']['allocated']==[0]*5
   original=a.state
   def command(points,revision=None):return dict(operation_id=str(uuid4()),action='allocate',attributes=points,expected_revision=revision or a.state['character']['state_revision'])
   for points,expected in [([6,0,0,0,0],'ATTRIBUTE_POINTS_EXCEEDED'),([-1,0,0,0,0],'INVALID_ATTRIBUTES'),([0]*5,'NO_ATTRIBUTE_CHANGE')]:
    v,_=a.command('',request=command(points),ok=False);assert v['code']==expected,v
    assert v['state']['attributes']['allocated']==[0]*5
   request=command([0,0,5,0,0]);before=a.state
   db.query("CREATE FUNCTION reject_attribute_receipt() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'owned allocation rollback'; END$$; CREATE TRIGGER reject_receipt BEFORE INSERT ON pve_operation_receipts FOR EACH ROW EXECUTE FUNCTION reject_attribute_receipt();")
   a.ws.send(dict(type='pve.command',command=request));assert a.until('error')['code']=='DATABASE_UNAVAILABLE'
   db.query('DROP TRIGGER reject_receipt ON pve_operation_receipts; DROP FUNCTION reject_attribute_receipt();')
   a.close();time.sleep(.2);a=Player(base,session,char);clients.append(a)
   assert a.state['character']==before['character'] and a.state['attributes']==before['attributes']
   v,_=a.command('',request=request);assert v['state']['attributes']['allocated']==[0,0,5,0,0]
   assert v['state']['stats']['attack']==original['stats']['attack']+10 and v['state']['stats']['hp']==original['stats']['hp']+10
   saved=a.state
   v,_=a.command('',request=request);assert v['replayed'] and v['state']==saved
   v,_=a.command('',request=command([1,0,4,0,0]),ok=False);assert v['code']=='ATTRIBUTE_RESPEC_FORBIDDEN'
   v,_=a.command('',request=command([1,0,5,0,0],original['character']['state_revision']),ok=False);assert v['code']=='STALE_ATTRIBUTES'
   a.close();stop(process);process,base=start();a=Player(base,session,char);clients.append(a)
   assert a.state['attributes']==saved['attributes'] and a.state['stats']==saved['stats']
   assert db.query(f"SELECT allocated_attributes::text FROM characters WHERE id='{char}'")=='{0,0,5,0,0}'
   a.approach('qingwei');a.command('accept','qingwei');a.approach('wolf_a');a.command('challenge','wolf_a')
   before_hp=a.state['battle']['enemy_hp'];v,_=a.command('attack')
   damage=before_hp-v['state']['battle']['enemy_hp'];assert 28<=damage<=32,(damage,a.state)
   v,_=a.command('',request=command([0,0,5,0,0]),ok=False);assert v['code']=='BATTLE_ACTIVE'
   a.command('flee')
   if os.environ.get('SSJX_TEST_ATTRIBUTES_GODOT'):
    # Separate account/character for the real UI test, with its own starting points.
    api(base,'/api/v1/auth/register',dict(username='attr_ui',password=password))
    _,ui=api(base,'/api/v1/auth/login',dict(username='attr_ui',password=password))
    assert api(base,'/api/v1/characters',dict(operation_id=str(uuid4()),display_name='加点修士',job=1,gender=0,school=2,rules_version='creation-v1'),ui['access_token'])[0]==201
    child_env=dict(os.environ,SSJX_ATTRIBUTES_BASE=base,SSJX_ATTRIBUTES_PASSWORD=password)
    r=subprocess.run([os.environ['GODOT_BIN'],'--headless','--path',str(ROOT/'client'),'res://tests/online_allocation_live_test.tscn'],env=child_env,capture_output=True,text=True,encoding='utf-8',timeout=60)
    print(r.stdout);print(r.stderr);assert r.returncode==0 and '0 failures' in r.stdout and 'SCRIPT ERROR' not in r.stderr
   print('ONLINE ATTRIBUTES INTEGRATION: PASS (budget, validation, atomic rollback, replay, restart and combat)')
  finally:
   for c in clients:
    try:c.close()
    except OSError:pass
   stop(process)
if __name__=='__main__':main()
