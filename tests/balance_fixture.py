"""Owned server/DB fixture for balance and loot checks. Never reads production config."""
import os
from pathlib import Path
import subprocess
import threading
import queue
import re
from uuid import uuid4
from pg_fixture import PostgresFixture
from run_account_auth import stop
from run_online_pve import api, Player
from run_server_connection import wait_for_server

ROOT=Path(__file__).resolve().parents[1]

class BalanceFixture:
    def __enter__(self):
        self.db=PostgresFixture().__enter__();self.clients=[];self.process=None
        self.env={k:v for k,v in os.environ.items() if not k.startswith('SSJX_')}
        self.env.update(SSJX_ENV_FILE='',SSJX_DATABASE_URL=self.db.url,SSJX_BIND_ADDR='127.0.0.1:0',SSJX_MONITOR_BIND_ADDR='',SSJX_LOG_DIR='',RUST_LOG='info',SSJX_AUTH_RATE_IP='10000',SSJX_AUTH_RATE_GLOBAL='100000',SSJX_AUTH_RATE_ACCOUNT='1000',SSJX_WORLD_RECONNECT_SECONDS='1')
        try:self.start();return self
        except BaseException:self.__exit__(None,None,None);raise
    def start(self):
        self.process=subprocess.Popen([os.environ.get('SSJX_TEST_SERVER_BIN',str(ROOT/'server/target/debug/vssjx-server'))],env=self.env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
        addresses=queue.Queue();process=self.process
        def drain():
            announced=False
            path=ROOT/'work/combat-balance-v1/fixture-server.log';path.parent.mkdir(parents=True,exist_ok=True)
            with path.open('a') as log:
                for line in process.stdout:
                    log.write(line);log.flush()
                    match=re.search(r'address=(127\.0\.0\.1:\d+)',line)
                    if match and not announced:addresses.put('http://'+match[1]);announced=True
            if not announced:addresses.put(None)
        threading.Thread(target=drain,daemon=True).start()
        self.base=addresses.get(timeout=20)
        if self.base is None:raise RuntimeError('Owned server failed to start; see work/combat-balance-v1/fixture-server.log')
    def restart(self):
        for p in self.clients:p.close()
        self.clients=[];stop(self.process);self.start()
    def create(self,name,job=0):
        password='owned-balance-test-password'
        assert api(self.base,'/api/v1/auth/register',dict(username=name,password=password))[0]==201
        _,session=api(self.base,'/api/v1/auth/login',dict(username=name,password=password))
        code,value=api(self.base,'/api/v1/characters',dict(operation_id=str(uuid4()),display_name=name,job=job,gender=0,school=3,rules_version='creation-v1'),session['access_token'])
        assert code==201,value
        return session,value['character']['id']
    def connect(self,identity):
        p=Player(self.base,*identity);self.clients.append(p);return p
    def __exit__(self,*args):
        for p in self.clients:p.close()
        if self.process:stop(self.process)
        self.db.__exit__(*args)
