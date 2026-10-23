"""Owned PostgreSQL + HTTP/WebSocket security regression. Never touches live players."""
import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import threading
import time
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, build_opener, ProxyHandler
from uuid import uuid4
from pg_fixture import PostgresFixture
from run_account_auth import stop
from run_online_maps import MapPlayer
from run_server_connection import wait_for_server

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--browser', action='store_true')
    parser.add_argument('--output', type=Path, default=ROOT/'work/security-admin')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    binary = os.environ['SSJX_TEST_SERVER_BIN']
    opener = build_opener(ProxyHandler({}))
    checks = 0

    def check(value, message):
        nonlocal checks
        checks += 1
        assert value, message

    def request(base, path, data=None, token=None, headers=None, method=None):
        h = {'Content-Type':'application/json', **(headers or {})}
        if token: h['Authorization'] = 'Bearer '+token
        try: r = opener.open(Request(base+path, data=None if data is None else json.dumps(data).encode(), headers=h, method=method), timeout=15)
        except HTTPError as e: r=e
        with r:
            body=r.read()
            try: payload=json.loads(body)
            except (ValueError, UnicodeDecodeError): payload=body.decode(errors='replace')
            return r.status,payload

    with PostgresFixture() as db:
        env={k:v for k,v in os.environ.items() if not k.startswith('SSJX_')}
        env.update(SSJX_ENV_FILE='', SSJX_DATABASE_URL=db.url, SSJX_BIND_ADDR='127.0.0.1:0',
            SSJX_LOG_DIR='', RUST_LOG='info', SSJX_AUTH_RATE_IP='1000', SSJX_AUTH_RATE_GLOBAL='10000',
            SSJX_AUTH_RATE_ACCOUNT='100', SSJX_WORLD_RECONNECT_SECONDS='1')
        players=[]
        def start():
            with socket.socket() as s: s.bind(('127.0.0.1',0)); port=s.getsockname()[1]
            private=f'http://127.0.0.1:{port}'
            process=subprocess.Popen([binary],env=dict(env,SSJX_MONITOR_BIND_ADDR=f'127.0.0.1:{port}'), stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8')
            try: base=wait_for_server(process)
            except BaseException: stop(process); raise
            threading.Thread(target=lambda:list(process.stdout),daemon=True).start()
            return process,base,private

        password='owned-security-password-1234'
        def create(name):
            code,account=request(base,'/api/v1/auth/register',dict(username=name,password=password));check(code==201,'register')
            code,session=request(base,'/api/v1/auth/login',dict(username=name,password=password));check(code==200,'login')
            op=str(uuid4())
            code,data=request(base,'/api/v1/characters',dict(operation_id=op,display_name=name,job=0,gender=0,school=0,rules_version='creation-v1'),session['access_token']);check(code==201,'create character')
            return session,data['character']['id'],op
        def join(session,cid):
            p=MapPlayer(base,session,cid);players.append(p);return p
        def audits(account=None):
            code,data=request(private,'/api/audit'+(f'?account_id={account}' if account else ''))
            check(code==200,'private audit readable');return data['events']
        def gear(p,action='equip',ok=True,operation=None):
            return p.command('',request=dict(operation_id=operation or str(uuid4()),action=action,target='sword',expected_revision=p.state['character']['state_revision']),ok=ok)

        process,base,private=start()
        try:
            session,cid,create_op=create('audit_first')
            other,other_id,_=create('audit_second')
            aid=session['account']['id']
            token=session['access_token']
            # Public routing does not expose operator reads OR writes.
            for path in ('/api/users','/api/audit',f'/api/users/{aid}',f'/api/users/{aid}/actions','/users.js','/users',f'/users/{aid}','/audit','/announcements','/admin.js','/audit.js'):
                check(request(base,path)[0]==404,'operator route isolated: '+path)
            check(request(base,f'/api/users/{aid}/actions',dict(action='disable'))[0]==404,'public operator POST absent')
            check(request(base,'/api/v1/characters',dict(gold=999999),token)[0]==400,'unknown creation fields rejected')
            check(request(base,'/api/v1/character-operations/'+create_op,token=other['access_token'])[0]==404,'receipt not visible cross account')
            from run_online_pve import HASH
            check(request(base,'/api/v1/world/ticket',dict(character_id=cid,protocol_version=1,config_hash=HASH),other['access_token'])[0]==403,'cross account character ticket denied')
            check(request(base,'/api/v1/characters/'+cid,dict(gold=999999),token,method='PATCH')[0]==404,'no generic asset mutation route')
            denials=audits(aid)
            check(any(e['action']=='http.rejected' and e['details']['method']=='PATCH' and e['details']['route']=='unmatched' for e in denials),'HTTP mutation attempts attributed without raw paths')
            check(request(private,'/api/users',headers={'Host':'evil.test'})[0]==403,'Host rebinding denied')
            check(request(private,'/api/users',headers={'Origin':'https://evil.test'})[0]==403,'foreign Origin denied')
            check(request(private,'/api/users',headers={'Sec-Fetch-Site':'cross-site'})[0]==403,'cross site fetch denied')
            code,users=request(private,'/api/users?q=audit_')
            check(code==200 and len(users['users'])==2,'bounded user search')
            check(users['total']==2 and users['matched']==2,'user list reports total accounts and matched accounts')
            empty=request(private,'/api/users?q=nonexistent')[1]
            check(empty['total']==2 and empty['matched']==0 and empty['users']==[],'empty search preserves overall account total')
            csrf=users['csrf_token'];h={'X-Operator-Token':csrf,'Origin':private}
            check(request(private,'/api/users?offset=-1')[0]==400,'negative pagination denied')
            check(request(private,'/api/users?q=%27%20OR%201%3D1--')[1]['users']==[],'SQL injection stays plain text')
            check(request(private,'/api/audit?outcome=garbage')[0]==400,'invalid outcome denied')
            code,detail=request(private,'/api/users/'+aid)
            check(code==200 and detail['characters'][0]['gold']==30,'safe character and inventory view')
            secrets=[password,token,session['refresh_token'],'password_hash','access_digest','refresh_digest']
            check(not any(s in json.dumps(detail) for s in secrets),'operator detail omits credentials')
            a=join(session,cid)
            equipped,operation=gear(a)
            again,_=a.command('',request=operation)
            check(again['replayed'] and again['state']==equipped['state'],'same operation does not apply twice')
            conflict=dict(operation,action='unequip')
            result,_=a.command('',request=conflict,ok=False)
            check(result['code']=='PVE_ID_CONFLICT','changed intent cannot reuse operation ID')
            result,_=gear(a,ok=False)
            check(result['code']=='EQUIPMENT_UNCHANGED','server checks semantic request')
            events=audits(aid)
            accepted=next(e for e in events if e['action']=='pve.equip' and e['outcome']=='accepted')
            check(accepted['details']['before']['equipment']['weapon'] is None and accepted['details']['after']['equipment']['weapon']=='sword','transactional before/after ledger')
            check(any(e['outcome']=='replayed' for e in events) and any(e['code']=='PVE_ID_CONFLICT' for e in events),'replay and intent conflict visible')
            check(any(e['action']=='auth.login' for e in events) and any(e['action']=='character.create' for e in events),'login and creation attribution')
            # A database audit failure rolls back inventory, revision AND receipt.
            before=a.state['character']['state_revision']; failing=str(uuid4())
            db.query("CREATE FUNCTION owned_reject_audit() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN IF NEW.action='pve.unequip' THEN RAISE EXCEPTION 'owned audit probe'; END IF; RETURN NEW; END$$; CREATE TRIGGER owned_reject_audit BEFORE INSERT ON security_audit FOR EACH ROW EXECUTE FUNCTION owned_reject_audit();")
            a.ws.send(dict(type='pve.command',command=dict(operation_id=failing,action='unequip',target='sword',expected_revision=before)))
            check(a.until('error')['code']=='DATABASE_UNAVAILABLE','audit failure refuses mutation')
            check(db.query(f"SELECT equipped FROM inventory_items WHERE character_id='{cid}' AND definition_id='sword'")=='t','audit failure rolls back gear')
            check(db.query(f"SELECT state_revision FROM characters WHERE id='{cid}'")==before,'audit failure rolls back revision')
            check(db.query(f"SELECT count(*) FROM pve_operation_receipts WHERE operation_id='{failing}'")=='0','audit failure rolls back receipt')
            db.query('DROP TRIGGER owned_reject_audit ON security_audit; DROP FUNCTION owned_reject_audit();')
            a.close();a=join(session,cid)
            # An attempted client-supplied gold value is rejected, not deserialized away.
            a.ws.send(dict(type='pve.command',command=dict(operation_id=str(uuid4()),action='equip',target='sword',gold=999999)))
            check(a.until('error')['code']=='INVALID_MESSAGE','forged client asset field rejected')
            check(db.query(f"SELECT gold FROM characters WHERE id='{cid}'")=='30','forged request cannot change balance')
            check(any(e['code']=='INVALID_MESSAGE' for e in audits(aid)),'malformed authenticated request attributed')
            a.close();a=join(session,cid)
            a.approach('qingwei'); a.command('accept','qingwei')
            a.approach('wolf_a'); a.command('challenge','wolf_a')
            while a.state['battle']['outcome']=='active':
                a.command('skill' if a.state['battle']['mp']>=9 else 'attack');time.sleep(.1)
            balance=a.state['character']['gold']
            check(balance>30,'legitimate server reward granted')
            reward=next(e for e in audits(aid) if e['action'] in ('pve.attack','pve.skill') and e['details'].get('after',{}).get('character',{}).get('gold',30)>30)
            check(reward['details']['before']['character']['gold']==30 and reward['details']['after']['character']['gold']==balance,'reward delta audited in settlement transaction')
            # Owned fixture fast forwards its own budget, not the live database.
            db.query(f"UPDATE gameplay_budgets SET requests=180,window_start=clock_timestamp() WHERE account_id='{aid}'")
            a.ws.send(dict(type='pve.command',command=dict(operation_id=str(uuid4()),action='unequip',target='sword',expected_revision=before)))
            check(a.until('error')['code']=='GAMEPLAY_RATE_LIMITED','account gameplay limit enforced')
            a.close();a=join(session,cid)
            a.ws.send(dict(type='pve.command',command=dict(operation_id=str(uuid4()),action='unequip',target='sword',expected_revision=before)))
            check(a.until('error')['code']=='GAMEPLAY_RATE_LIMITED','reconnect cannot reset budget')
            code,alt=request(base,'/api/v1/characters',dict(operation_id=str(uuid4()),display_name='audit_alt',job=0,gender=0,school=0,rules_version='creation-v1'),token)
            check(code==201,'same account can own another legitimate character')
            by_role=request(private,'/api/users?q=audit_alt')[1]['users']
            check(len(by_role)==1 and by_role[0]['id']==aid,'role name finds its owning account')
            check(any(c['display_name']=='audit_alt' for c in by_role[0]['character_summaries']),'search returns useful role summaries')
            check(request(private,'/api/users?q=AUDIT_ALT')[1]['users'][0]['id']==aid,'ASCII role search is case insensitive')
            check(request(private,'/api/users?q='+alt['character']['id'])[1]['users'][0]['id']==aid,'character UUID search finds account')
            code,chinese=request(base,'/api/v1/characters',dict(operation_id=str(uuid4()),display_name='霜华剑客',job=0,gender=0,school=0,rules_version='creation-v1'),token)
            check(code==201,'create an owned Chinese role fixture')
            chinese_hits=request(private,'/api/users?q='+quote('霜华'))[1]['users']
            check(len(chinese_hits)==1 and chinese_hits[0]['id']==aid,'partial Chinese role name finds owning account')
            alternate=join(session,alt['character']['id'])
            alternate.ws.send(dict(type='pve.command',command=dict(operation_id=str(uuid4()),action='equip',target='sword',expected_revision=alternate.state['character']['state_revision'])))
            check(alternate.until('error')['code']=='GAMEPLAY_RATE_LIMITED','different character cannot bypass account budget')
            alternate.close()
            check(len([e for e in audits(aid) if e['code']=='GAMEPLAY_RATE_LIMITED'])==1,'budget flood audit is bounded')
            a.close();a=join(session,cid)
            # Operator actions require same-origin + process token + reason.
            op=dict(operation_id=str(uuid4()),action='disable',reason='owned security regression')
            path=f'/api/users/{aid}/actions'
            check(request(private,path,op,token)[0]==403,'ordinary player bearer not operator authorization')
            check(request(private,path,op,headers={'X-Operator-Token':csrf})[0]==403,'Origin required on mutations')
            check(request(private,path,dict(op,gold=10000),headers=h)[0]==400,'operator cannot inject asset edits')
            check(request(private,path,dict(op,reason=''),headers=h)[0]==400,'operator reason mandatory')
            check(request(private,path,dict(op,character_id=other_id),headers=h)[0]==403,'selected character must belong to target account')
            db.query("CREATE FUNCTION owned_reject_operator_audit() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN IF NEW.action='operator.disable' THEN RAISE EXCEPTION 'owned operator audit probe'; END IF; RETURN NEW; END$$; CREATE TRIGGER owned_reject_operator_audit BEFORE INSERT ON security_audit FOR EACH ROW EXECUTE FUNCTION owned_reject_operator_audit();")
            check(request(private,path,op,headers=h)[0]==503,'operator audit failure refuses change')
            check(db.query(f"SELECT disabled FROM accounts WHERE id='{aid}'")=='f' and request(base,'/api/v1/auth/me',token=token)[0]==200,'operator audit failure rolls back ban and session revocation')
            db.query('DROP TRIGGER owned_reject_operator_audit ON security_audit; DROP FUNCTION owned_reject_operator_audit();')
            code,result=request(private,path,op,headers=h)
            check(code==200 and result['disabled'] and result['revoked_sessions']>=1,'disable revokes all sessions')
            check(a.until('error')['code']=='SESSION_REVOKED','active socket is revoked')
            check(request(base,'/api/v1/auth/me',token=token)[0]==401,'disabled access token denied')
            check(request(base,'/api/v1/auth/refresh',dict(refresh_token=session['refresh_token']))[0]==401,'disabled refresh denied')
            check(request(base,'/api/v1/auth/login',dict(username='audit_first',password=password))[0]==401,'disabled login denied')
            check(request(private,path,op,headers=h)[1]['replayed'],'operator replay is idempotent')
            check(request(private,path,dict(op,action='enable'),headers=h)[0]==409,'operator intent conflict rejected')
            enable=dict(operation_id=str(uuid4()),action='enable',reason='owned regression restore')
            check(request(private,path,enable,headers=h)[0]==200,'enable account')
            check(request(base,'/api/v1/auth/me',token=token)[0]==401,'enable does not resurrect old tokens')
            check(request(base,'/api/v1/auth/login',dict(username='audit_first',password=password))[0]==200,'fresh login works after enable')
            fresh=request(base,'/api/v1/auth/login',dict(username='audit_first',password=password))[1]
            revoke=dict(operation_id=str(uuid4()),action='revoke_sessions',reason='owned force logout')
            check(request(private,path,revoke,headers=h)[0]==200,'force logout action')
            check(request(base,'/api/v1/auth/me',token=fresh['access_token'])[0]==401,'force logout invalidates new token')
            check(request(base,'/api/v1/auth/me',token=other['access_token'])[0]==200,'other account remains available')
            events=audits(aid)
            check(sum(e['action']=='operator.disable' for e in events)==1,'single durable operator receipt')
            check(any(e['action']=='auth.login' and e['outcome']=='rejected' for e in events),'failed login trace')
            check(not any(s in json.dumps(events) for s in secrets),'ledger omits secrets')
            # Immutable through ordinary UPDATE/DELETE (DB owner can still bypass triggers).
            result=subprocess.run(['docker','exec',db.name,'psql','-U','vssjx','-d','vssjx_auth_test','-v','ON_ERROR_STOP=1','-c','DELETE FROM security_audit WHERE id=(SELECT min(id) FROM security_audit)'],capture_output=True,text=True)
            check(result.returncode!=0 and 'append-only' in result.stderr,'ordinary audit deletion blocked')
            count=db.query('SELECT count(*) FROM security_audit')
            for p in players: p.close()
            stop(process);process,base,private=start()
            check(int(db.query('SELECT count(*) FROM security_audit'))>=int(count),'audit survives process restart')
            check(db.query(f"SELECT requests FROM gameplay_budgets WHERE account_id='{aid}'")=='181','budget survives process restart')
            check(request(private,path,enable,headers={'Origin':private,'X-Operator-Token':csrf})[0]==403,'old process token invalid after restart')
            # Search result limit and audit cursor, using owned fixture rows.
            db.query("INSERT INTO accounts(id,username,password_hash) SELECT md5('owned-account-'||n)::uuid,'owned_'||lpad(n::text,3,'0'),'not-a-real-password-hash' FROM generate_series(1,52)n;")
            code,data=request(private,'/api/users?q=owned_')
            check(code==200 and len(data['users'])==50 and data['more'],'user list bounded at 50')
            check(data['total']==54 and data['matched']==52,'total is independent of search and page limit')
            check(len(request(private,'/api/users?q=owned_&offset=50')[1]['users'])==2,'second user page')
            empty=request(private,'/api/users?q=owned_&offset=100')[1]
            check(empty['total']==54 and empty['matched']==52 and not empty['users'] and not empty['more'],'out-of-range page retains accurate counts')
            db.query(f"INSERT INTO security_audit(account_id,action,outcome,code,details) SELECT '{aid}','fixture.event','observed','OK','{{}}'::jsonb FROM generate_series(1,105);")
            first=request(private,'/api/audit?account_id='+aid)[1]
            second=request(private,f"/api/audit?account_id={aid}&before={first['next_before']}")[1]
            check(len(first['events'])==100 and second['events'] and {e['id'] for e in first['events']}.isdisjoint({e['id'] for e in second['events']}),'audit cursor no duplicate rows')
            if args.browser:
                subprocess.run(['node',str(ROOT/'tests/security_admin_browser.cjs'),private,str(args.output)],env=os.environ,check=True,timeout=90)
            (args.output/'result.json').write_text(json.dumps(dict(checks=checks,failures=0),indent=2))
            print(f'SECURITY ADMIN: {checks} checks, 0 failures; real PostgreSQL + HTTP + WebSocket')
        finally:
            for p in players:
                try:p.close()
                except OSError:pass
            stop(process)


if __name__=='__main__':main()
