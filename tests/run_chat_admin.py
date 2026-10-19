"""Chat operator HTTP/WS regression using an owned disposable database only."""
import json
import os
from pathlib import Path
import socket
import subprocess
import threading
from urllib.request import Request,build_opener,ProxyHandler
from urllib.error import HTTPError
from uuid import uuid4
from pg_fixture import PostgresFixture
from run_account_auth import stop
from run_server_connection import wait_for_server
from run_online_maps import MapPlayer

ROOT=Path(__file__).resolve().parents[1]
def main():
    binary=os.environ.get('SSJX_TEST_SERVER_BIN',str(ROOT/'server/target/debug/vssjx-server.exe'))
    opener=build_opener(ProxyHandler({})); checks=[]; peers=[]
    def check(value,label):
        assert value,label
        checks.append(label)
    def request(base,path,data=None,headers=None):
        try:r=opener.open(Request(base+path,data=None if data is None else json.dumps(data).encode(),headers={'Content-Type':'application/json',**(headers or {})}),timeout=15)
        except HTTPError as e:r=e
        with r:
            raw=r.read()
            try:body=json.loads(raw)
            except ValueError:body=raw.decode()
            return r.status,body
    with PostgresFixture() as db:
        env={k:v for k,v in os.environ.items() if not k.startswith('SSJX_')}
        env.update(SSJX_ENV_FILE='',SSJX_DATABASE_URL=db.url,SSJX_BIND_ADDR='127.0.0.1:0',SSJX_LOG_DIR='',RUST_LOG='info',SSJX_AUTH_RATE_IP='1000',SSJX_AUTH_RATE_GLOBAL='10000',SSJX_AUTH_RATE_ACCOUNT='100',SSJX_WORLD_RECONNECT_SECONDS='1',SSJX_CHAT_GLOBAL_PER_SECOND='1')
        def start():
            with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
            private='http://127.0.0.1:'+str(port)
            process=subprocess.Popen([binary],env=dict(env,SSJX_MONITOR_BIND_ADDR='127.0.0.1:'+str(port)),stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8')
            try:base=wait_for_server(process)
            except BaseException:stop(process);raise
            threading.Thread(target=lambda:list(process.stdout),daemon=True).start()
            return process,base,private
        process,base,private=start()
        password='owned-moderation-test-password'
        def login(name):
            code,data=request(base,'/api/v1/auth/login',dict(username=name,password=password));check(code==200,'login '+name);return data
        def character(session,name):
            code,data=request(base,'/api/v1/characters',dict(operation_id=str(uuid4()),display_name=name,job=0,gender=0,school=0,rules_version='creation-v1'),{'Authorization':'Bearer '+session['access_token']});check(code==201,'create '+name);return data['character']['id']
        def user(name):
            check(request(base,'/api/v1/auth/register',dict(username=name,password=password))[0]==201,'register '+name)
            session=login(name);return session,character(session,name)
        def join(session,cid):
            player=MapPlayer(base,session,cid);peers.append(player);return player
        def until(player,predicate):
            for _ in range(200):
                packet,_=player.ws.recv()
                assert packet['type']!='error',packet
                if predicate(packet):return packet
            raise AssertionError('Expected chat packet')
        def send(player,text,final=True):
            mid=str(uuid4());player.ws.send(dict(type='chat.send',client_message_id=mid,channel='public',text=text))
            result=until(player,lambda p:p['type']=='chat.result' and p['result']['client_message_id']==mid and (not final or p['result']['status']!='QUEUED'))
            return mid,result['result']
        def access():return request(private,'/api/chat')[1]
        def action(payload,**changes):
            data=dict(payload,**changes)
            return request(private,'/api/chat/actions',data,{'Origin':private,'X-Operator-Token':access()['csrf_token']})
        try:
            owner,cid=user('mod_owner');other,other_id=user('mod_other')
            alt_id=character(owner,'mod_alt');alternate=login('mod_owner')
            a=join(owner,cid);b=join(other,other_id);alt=join(alternate,alt_id)
            sent_id,sent=send(a,'需要删除的唯一原文[微笑]');message=sent['message_id']
            until(b,lambda p:p['type']=='chat.batch' and any(m['message_id']==message for m in p['messages']))
            data=access();epoch=data['channel_epoch'];aid=owner['account']['id']
            check(any(m.get('account_id')==aid and m['message_id']==message for m in data['messages']),'operator resolves exact message author account')
            for path in ['/chat','/chat.js','/api/chat','/api/chat/actions']:
                check(request(base,path)[0]==404,'public game excludes '+path)
            check(request(private,'/api/chat',headers={'Host':'evil.invalid'})[0]==403,'Host guard retained')
            payload=dict(operation_id=str(uuid4()),channel_epoch=epoch,account_id=aid,message_id=message,action='delete_and_mute',reason='刷屏治理',duration_seconds=600)
            check(request(private,'/api/chat/actions',payload)[0]==403,'operator write requires Origin and CSRF token')
            check(request(private,'/api/chat/actions',payload,{'Origin':'https://evil.invalid','X-Operator-Token':data['csrf_token']})[0]==403,'foreign Origin denied')
            check(action(payload,account_id=other['account']['id'])[0]==404,'cannot attribute another account message')
            check(action(payload,channel_epoch=str(uuid4()))[0]==409,'stale channel refused')
            check(action(payload,duration_seconds=0)[0]==400,'mute duration validated')
            pending,pending_result=send(alt,'排队消息必须取消',final=False)
            check(pending_result['status']=='QUEUED','alternate character has queued message')
            code,result=action(payload);check(code==200,'delete and account mute accepted')
            batch=until(b,lambda p:p['type']=='chat.batch' and message in p.get('removed_message_ids',[]))
            check(any(m.get('system') and '禁言10分钟' in m['text'] for m in batch['messages']),'online peers receive removal and in-box system notice')
            check(until(alt,lambda p:p['type']=='chat.result' and p['result']['client_message_id']==pending and p['result']['status']!='QUEUED')['result']['code']=='CHAT_MUTED','queued alternate message cancelled')
            after=access();check(any(m['message_id']==message and m['deleted'] for m in after['messages']),'deleted row retained as redacted operator record')
            check('需要删除的唯一原文' not in json.dumps(after,ensure_ascii=False),'deleted content absent from operator cache')
            check(not any(m['text']=='排队消息必须取消' for m in after['messages']),'pending message never broadcast')
            check(action(payload)[1]['replayed'],'same operation retries without another action')
            check(action(payload,reason='另一原因')[0]==409,'changed operation intent rejected')
            a.ws.send(dict(type='chat.send',client_message_id=sent_id,channel='public',text='需要删除的唯一原文[微笑]'))
            check(until(a,lambda p:p['type']=='chat.result' and p['result']['client_message_id']==sent_id)['result']['code']=='CHAT_REMOVED','deleted original cannot be replayed')
            check(send(a,'禁言后发言')[1]['code']=='CHAT_MUTED','account sender muted')
            check(send(alt,'换角色绕过')[1]['code']=='CHAT_MUTED','other account character muted')
            check(send(b,'其他账号正常')[1]['status']=='SENT','unrelated account unaffected')
            unmute=dict(payload,operation_id=str(uuid4()),action='unmute',message_id=None,duration_seconds=0)
            check(action(unmute)[0]==200,'operator can unmute')
            check(send(alt,'解除之后正常')[1]['status']=='SENT','unmute restores account chat')
            mute=dict(payload,operation_id=str(uuid4()),action='mute',message_id=None,duration_seconds=60)
            check(action(mute)[0]==200,'account-only timed mute')
            # Audit failure must roll back both mute changes and operation receipt.
            db.query("CREATE FUNCTION owned_reject_chat_audit() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN IF NEW.action='operator.chat' THEN RAISE EXCEPTION 'owned audit probe'; END IF; RETURN NEW; END$$; CREATE TRIGGER owned_reject_chat_audit BEFORE INSERT ON security_audit FOR EACH ROW EXECUTE FUNCTION owned_reject_chat_audit();")
            failed=dict(unmute,operation_id=str(uuid4()))
            check(action(failed)[0]==503,'audit failure blocks moderation transaction')
            check(db.query(f"SELECT chat_muted_until>clock_timestamp() FROM accounts WHERE id='{aid}'")=='t','failed unmute preserves database mute')
            check(db.query(f"SELECT count(*) FROM operator_receipts WHERE operation_id='{failed['operation_id']}'")=='0','failed action leaves no receipt')
            db.query('DROP TRIGGER owned_reject_chat_audit ON security_audit; DROP FUNCTION owned_reject_chat_audit();')
            check('需要删除的唯一原文' not in db.query("SELECT details::text FROM security_audit WHERE action='operator.chat'"),'audit never stores original chat bodies')
            for p in peers:p.close()
            stop(process);process,base,private=start()
            a=join(owner,cid)
            check(send(a,'重启后仍禁言')[1]['code']=='CHAT_MUTED','account mute survives server restart')
            code,view=request(private,'/api/chat?account_id='+aid)
            check(code==200 and not view['messages'] and view['accounts'][0]['muted'],'muted accounts remain manageable without chat history')
            unmute=dict(unmute,operation_id=str(uuid4()),channel_epoch=view['channel_epoch'])
            check(action(unmute)[0]==200,'unmute works after restart without a retained message')
            check(send(a,'重启解除后正常')[1]['status']=='SENT','post-restart unmute restores sending')
            print(json.dumps({'checks':len(checks),'failures':0},ensure_ascii=False))
        finally:
            for p in peers:
                try:p.close()
                except OSError:pass
            stop(process)
if __name__=='__main__':main()
