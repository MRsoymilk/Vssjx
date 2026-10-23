"""Daily attendance against owned PostgreSQL/server/browser only; never uses live DB."""
import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import threading
import time
from urllib.error import HTTPError
from urllib.request import Request, build_opener, ProxyHandler
from uuid import uuid4
from pg_fixture import PostgresFixture
from run_account_auth import stop
from run_online_pve import Player
from run_server_connection import wait_for_server

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--browser', action='store_true')
    parser.add_argument('--output', type=Path, default=ROOT/'work/monitor-online')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    checks = 0
    opener = build_opener(ProxyHandler({}))

    def check(ok, message):
        nonlocal checks
        checks += 1
        assert ok, message

    def request(base, path, data=None, token=None, headers=None):
        h = {'Content-Type': 'application/json', **(headers or {})}
        if token: h['Authorization'] = 'Bearer '+token
        try:
            response = opener.open(Request(base+path, data=None if data is None else json.dumps(data).encode(), headers=h), timeout=10)
        except HTTPError as error:
            response = error
        with response:
            body=response.read()
            try: payload=json.loads(body)
            except (ValueError,UnicodeDecodeError): payload=body.decode(errors='replace')
            return response.status, payload

    def eventually(predicate):
        deadline = time.monotonic()+10
        while time.monotonic()<deadline:
            if predicate(): return True
            time.sleep(.05)
        return False

    # Apply migration bytes to an owned legacy schema, with observations predating rollout.
    with PostgresFixture() as db:
        db.query('\n'.join(p.read_text() for p in sorted((ROOT/'server/migrations').glob('*.sql')) if int(p.name[:4])<34))
        aid=str(uuid4())
        db.query(f"INSERT INTO accounts(id,username,password_hash) VALUES('{aid}','owned_legacy','not-a-password');")
        db.query(f"""INSERT INTO security_audit(account_id,action,outcome,code,created_at,details) VALUES
            ('{aid}','world.join','observed','OK',((clock_timestamp() AT TIME ZONE 'Asia/Shanghai')::date-2+time '23:59:59') AT TIME ZONE 'Asia/Shanghai','{{}}'),
            ('{aid}','world.join','observed','OK',((clock_timestamp() AT TIME ZONE 'Asia/Shanghai')::date-1+time '00:00:00') AT TIME ZONE 'Asia/Shanghai','{{}}'),
            ('{aid}','world.movement','observed','OK',clock_timestamp(),'{{}}'),
            ('{aid}','auth.login','accepted','OK',clock_timestamp()-interval '4 days','{{}}'),
            ('{aid}','world.join','rejected','DENIED',clock_timestamp()-interval '5 days','{{}}');""")
        db.query((ROOT/'server/migrations/0034_daily_online_accounts.sql').read_text())
        check(db.query('SELECT count(*) FROM daily_online_accounts')=='3','legacy observations backfill Beijing dates, deduplicate and exclude login/rejections')
        check(db.query('SELECT count(*) FROM online_stats_metadata')=='1','collection start is durable and singleton')

    with PostgresFixture() as db:
        players=[]
        env={k:v for k,v in os.environ.items() if not k.startswith('SSJX_')}
        env.update(SSJX_ENV_FILE='',SSJX_DATABASE_URL=db.url,SSJX_BIND_ADDR='127.0.0.1:0',SSJX_LOG_DIR='',RUST_LOG='info',SSJX_AUTH_RATE_IP='10000',SSJX_AUTH_RATE_GLOBAL='100000',SSJX_AUTH_RATE_ACCOUNT='1000',SSJX_WORLD_RECONNECT_SECONDS='1')
        def start():
            with socket.socket() as s:
                s.bind(('127.0.0.1',0)); port=s.getsockname()[1]
            private=f'http://127.0.0.1:{port}'
            process=subprocess.Popen([os.environ['SSJX_TEST_SERVER_BIN']],env=dict(env,SSJX_MONITOR_BIND_ADDR=f'127.0.0.1:{port}'),stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
            try: base=wait_for_server(process)
            except BaseException: stop(process);raise
            threading.Thread(target=lambda:list(process.stdout),daemon=True).start()
            check(eventually(lambda:request(private,'/api/online/daily')[0]==200),'monitor ready')
            return process,base,private

        process,base,private=start()
        def daily(days=30):
            code,data=request(private,f'/api/online/daily?days={days}')
            check(code==200,'daily statistics readable')
            return data
        def create(name):
            password='owned-daily-stats-password'
            check(request(base,'/api/v1/auth/register',dict(username=name,password=password))[0]==201,'register')
            code,session=request(base,'/api/v1/auth/login',dict(username=name,password=password))
            check(code==200,'login')
            return session
        def character(session,name):
            code,data=request(base,'/api/v1/characters',dict(operation_id=str(uuid4()),display_name=name,job=0,gender=0,school=0,rules_version='creation-v1'),session['access_token'])
            check(code==201,'create character')
            return data['character']['id']
        def connect(session,cid):
            player=Player(base,session,cid);players.append(player);return player
        try:
            initial=daily()
            check(initial['timezone']=='Asia/Shanghai' and initial['metric']=='unique_online_accounts','explicit timezone and attendance metric')
            check(len(initial['days'])==30 and initial['days'][-1]['users']==0,'new collector today is zero')
            check(all(d['users'] is None and d['coverage']=='historical' for d in initial['days'][:-1]),'uncollected history is null, not invented zero')
            for days in (7,90): check(len(daily(days)['days'])==days,'bounded selectable range')
            for query in ('days=0','days=31','days=100000','days=-1','days=abc','extra=1'):
                check(request(private,'/api/online/daily?'+query)[0]==400,'invalid daily query denied')
            check(request(base,'/api/online/daily')[0]==404,'stats absent from public game listener')
            for headers in ({'Host':'evil.test'},{'Origin':'https://evil.test'},{'Sec-Fetch-Site':'cross-site'}):
                check(request(private,'/api/online/daily',headers=headers)[0]==403,'daily stats keep local-only guard')
            a,b=create('daily_a'),create('daily_b')
            ca,alt,cb=character(a,'每日甲'),character(a,'每日甲乙'),character(b,'每日乙')
            check(daily()['days'][-1]['users']==0,'login without entering game is not online attendance')
            connect(a,ca);connect(a,alt)
            check(eventually(lambda:daily()['days'][-1]['users']==1),'two characters from one account count once')
            connect(b,cb)
            check(eventually(lambda:daily()['days'][-1]['users']==2),'another in-game account increases attendance')
            players[0].close();connect(a,ca)
            check(eventually(lambda:daily()['days'][-1]['users']==2),'reconnect cannot inflate daily attendance')
            # Only this fixture's metadata and attendance are adjusted to cover chart boundaries.
            db.query("UPDATE online_stats_metadata SET started_at=clock_timestamp()-interval '3 days';")
            db.query(f"INSERT INTO daily_online_accounts(day,account_id) VALUES ((clock_timestamp() AT TIME ZONE 'Asia/Shanghai')::date-4,'{a['account']['id']}'),((clock_timestamp() AT TIME ZONE 'Asia/Shanghai')::date-2,'{a['account']['id']}'),((clock_timestamp() AT TIME ZONE 'Asia/Shanghai')::date-2,'{b['account']['id']}');")
            sample=daily(7)['days']
            check(sample[0]['users'] is None and sample[2]['users']==1 and sample[2]['coverage']=='historical','known historical counts stay marked incomplete')
            check(sample[4]['users']==2 and sample[4]['coverage']=='complete','complete day aggregates unique accounts')
            check(sample[5]['users']==0 and sample[5]['coverage']=='complete','collected empty day is genuine zero')
            check(sample[-1]['coverage']=='partial','today is explicitly incomplete')
            secrets=[a['account']['id'],ca,a['access_token'],a['refresh_token'],'password_hash']
            check(not any(s in json.dumps(daily()) for s in secrets),'daily API returns aggregate counts only')
            for player in players: player.close()
            players.clear();stop(process);process,base,private=start()
            check(daily()['days'][-1]['users']==2,'daily history survives process restart and disconnects')
            connect(a,ca)
            check(daily()['days'][-1]['users']==2,'post-restart reconnect remains deduplicated')
            if args.browser:
                subprocess.run(['node',str(ROOT/'tests/monitor_online_browser.cjs'),private,str(args.output)],env=os.environ,check=True,timeout=90)
            (args.output/'result.json').write_text(json.dumps(dict(checks=checks,failures=0),indent=2))
            print(f'MONITOR ONLINE: {checks} checks, 0 failures; real PostgreSQL + server + WebSocket')
        finally:
            for player in players: player.close()
            stop(process)


if __name__=='__main__':main()
