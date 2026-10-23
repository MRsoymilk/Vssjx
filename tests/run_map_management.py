"""Owned PostgreSQL, real WebSockets and optional Godot/Chromium map editor checks."""
import copy
import json
import os
from pathlib import Path
import socket
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor
from urllib.request import Request, build_opener, ProxyHandler
from urllib.error import HTTPError
from uuid import uuid4
from balance_fixture import BalanceFixture
from run_online_pve import Player
from run_online_pve import api, HASH
from ws_fixture import WebSocket

ROOT=Path(__file__).resolve().parents[1]
class Fixture(BalanceFixture):
    def connect(self,identity):
        p=Player(self.base,*identity,maps_version=2);self.clients.append(p);return p
    def start(self):
        with socket.socket() as s:
            s.bind(('127.0.0.1',0));port=s.getsockname()[1]
        self.private=f'http://127.0.0.1:{port}'
        self.env['SSJX_MONITOR_BIND_ADDR']=f'127.0.0.1:{port}'
        super().start()

def main():
    checks=0
    def check(ok,message):
        nonlocal checks
        checks+=1
        assert ok,message
    opener=build_opener(ProxyHandler({}))
    def request(base,path,data=None,headers=None):
        try:r=opener.open(Request(base+path,data=None if data is None else json.dumps(data).encode(),headers={'Content-Type':'application/json',**(headers or {})}),timeout=20)
        except HTTPError as e:r=e
        with r:
            raw=r.read()
            try:body=json.loads(raw)
            except ValueError:body=raw.decode()
            return r.status,body
    with Fixture() as f:
        def detail(id='qingyun_trail'):
            code,d=request(f.private,'/api/maps/'+id);check(code==200,'map detail');return d
        _,listing=request(f.private,'/api/maps');token=listing['csrf_token']
        headers={'Origin':f.private,'X-Operator-Token':token}
        def action(d,kind='save',document=None,release=None,expected=200,operation=None):
            payload=operation or dict(operation_id=str(uuid4()),action=kind,revision=d['revision'],reason='专项验证',document=document,release=release)
            code,value=request(f.private,'/api/maps/'+d['id']+'/actions',payload,headers)
            check(code==expected,f'{kind}: {code} {value}')
            if code==200:d['revision']=value['revision'];d['active_revision']=value['active_revision']
            return value,payload
        def publish(d,doc):
            action(d,document=doc);v,_=action(d,'validate');check(not v['errors'],str(v['errors']));v,_=action(d,'publish');return v
        def move(p,cell):
            time.sleep(.13);p.move(cell);end=time.monotonic()+18;ping=0
            while time.monotonic()<end:
                p.until('world.delta');own=p.ws.entities[p.id]
                if own['cell']==cell and own['next_cell'] is None:return
                if time.monotonic()-ping>2:p.ws.send({'type':'ping'});ping=time.monotonic()
            raise AssertionError('move timeout '+str(cell))
        check(len(listing['maps'])==216,'all bundled maps listed')
        for path in ['/maps','/maps.js','/api/maps','/api/maps/qingyun_trail']:
            check(request(f.base,path)[0]==404,'public route isolated '+path)
        check(request(f.private,'/api/maps',headers={'Host':'evil.test'})[0]==403,'Host rebinding rejected')
        check(request(f.private,'/api/maps',headers={'Origin':'https://evil.test'})[0]==403,'foreign Origin rejected')
        d=detail();original=copy.deepcopy(d['document']);bad=copy.deepcopy(original);bad['spawn']=[-1,0]
        payload=dict(operation_id=str(uuid4()),action='save',revision=0,reason='专项验证',document=bad,release=None)
        check(request(f.private,'/api/maps/qingyun_trail/actions',payload)[0]==403,'write requires Origin and operator token')
        check(request(f.private,'/api/maps/qingyun_trail/actions',payload,{'Origin':f.private,'X-Operator-Token':'forged'})[0]==403,'forged operator token rejected')
        action(d,document=bad);v,_=action(d,'validate');check(bool(v['errors']),'invalid walkability shown without activation');action(d,'publish',expected=400)
        check(detail()['active']==original,'invalid draft has no runtime effect')
        forged=copy.deepcopy(original);forged['residents'][0]['id']='forged'
        action(d,document=forged);v,_=action(d,'validate');check(bool(v['errors']),'unknown resident identities rejected')
        forged=copy.deepcopy(original);forged['portals'][0]['target_map']='missing'
        action(d,document=forged);v,_=action(d,'validate');check(bool(v['errors']),'unknown portal destination rejected')
        forged=copy.deepcopy(original);forged['portals'][0]['arrival']=[3,16]
        action(d,document=forged);v,_=action(d,'validate');check(bool(v['errors']),'arrival on destination trigger rejected')
        action(d,document=original)
        # Two editors race the same optimistic revision; exactly one wins.
        rev=d['revision']
        def race(_):return request(f.private,'/api/maps/qingyun_trail/actions',dict(operation_id=str(uuid4()),action='save',revision=rev,reason='并发验证',document=original,release=None),headers)[0]
        with ThreadPoolExecutor(2) as pool:codes=list(pool.map(race,range(2)))
        check(sorted(codes)==[200,409],'concurrent draft cannot overwrite newer edits');d=detail()
        a=f.create('maps_a');f.db.query(f"UPDATE characters SET level=20,hp=200,mp=100,quest_stage=1 WHERE id='{a[1]}'")
        p=f.connect(a);p.approach('wolf_a');p.command('challenge','wolf_a');battle=copy.deepcopy(p.state['battle'])
        gathering=f.create('maps_gather');q=f.connect(gathering);move(q,[15,19])
        begun,_=q.command('',request=dict(operation_id=str(uuid4()),action='gather_start',target='qingyun_trail_ore',expected_revision=q.state['character']['state_revision']))
        frozen=begun['state']['gathering']['active']['token']
        doc=copy.deepcopy(original);doc['station_enabled']=False
        for r in doc['residents']:
            if r['id']=='qingwei':r['cell']=[11,13]
            if r['id']=='wolf_b':r['enabled']=False
            if r['id']=='wolf_a':r['respawn_seconds']=90
        doc['portals'][0].update(cell=[12,16],cells=[[12,16]],target_map='ai_002',arrival=None)
        doc['portals'][1]['enabled']=False
        doc['gathering'][0].update(cell=[13,19],material='copper',duration_ms=1000,respawn_ms=120000)
        action(d,document=doc);v,_=action(d,'validate');check(not v['errors'],str(v['errors']))
        # Receipt failure must roll back release, active pointer, gathering update and draft.
        f.db.query("CREATE FUNCTION reject_map_receipt() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'owned map rollback';END$$;CREATE TRIGGER reject_map_receipt BEFORE INSERT ON map_operator_receipts FOR EACH ROW EXECUTE FUNCTION reject_map_receipt();")
        action(d,'publish',expected=503)
        check(f.db.query('SELECT count(*) FROM map_releases')=='0' and f.db.query("SELECT material FROM gathering_nodes WHERE id='qingyun_trail_ore'")=='iron','publish transaction fully rolls back on failed receipt')
        f.db.query('DROP TRIGGER reject_map_receipt ON map_operator_receipts;DROP FUNCTION reject_map_receipt();')
        published,op=action(d,'publish');release=published['active_revision']
        replay,_=action(d,operation=op);check(replay['replayed'] and replay['active_revision']==release,'publish retry replays one immutable release')
        conflict=copy.deepcopy(op);conflict['reason']='冲突验证';action(d,operation=conflict,expected=409)
        packet=p.until('map.rules');check(packet['rules']['portals'][0]['cell']==[12,16],'connected client receives operational portal snapshot')
        p.until('pve.state');check(p.state['battle']==battle,'publishing does not mutate an ongoing battle')
        until=time.monotonic()+5
        while time.monotonic()<until:
            p.until('population.state')
            if 'wolf_b' not in p.population and p.population['qingwei']['cell']==[11,13]:break
        check('wolf_b' not in p.population and p.population['qingwei']['cell']==[11,13],'resident disable and NPC relocation apply live')
        f.db.query(f"UPDATE gathering_active SET ready_at_ms=(extract(epoch FROM clock_timestamp())*1000)::bigint-1 WHERE character_id='{q.id}'")
        gathered,_=q.command('',request=dict(operation_id=str(uuid4()),action='gather_finish',target=frozen,expected_revision=q.state['character']['state_revision']))
        check(gathered['state']['gathering']['materials'].get('iron',0)>0 and 'copper' not in gathered['state']['gathering']['materials'],'active gathering keeps frozen material despite node edit')
        remaining=next(n for n in gathered['state']['gathering']['nodes'] if n['id']=='qingyun_trail_ore')['available_at_ms']-gathered['state']['server_time_ms']
        check(58000<=remaining<=60000,'active gathering keeps frozen cooldown duration')
        move(q,[11,13]);q.command('accept','qingwei');check(q.state['character']['quest_stage']==1,'relocated NPC remains interactable through existing quest ID');q.close()
        for _ in range(30):
            if p.state['battle']['outcome']!='active':break
            p.command('skill' if p.state['battle']['mp']>=9 else 'attack');time.sleep(.07)
        check(p.state['battle']['outcome']=='victory','ongoing battle can finish after publishing')
        check(88000<=p.state['progress']['respawns']['wolf_a']-p.state['server_time_ms']<=90000,'new defeats use configured respawn interval')
        deadline=p.state['progress']['respawns']['wolf_a']
        check(next(n for n in p.state['gathering']['nodes'] if n['id']=='qingyun_trail_ore')['material']=='copper','published gathering configuration authoritative')
        closed=detail('ai_002');cdoc=copy.deepcopy(closed['document']);cdoc['entry_enabled']=False;publish(closed,cdoc)
        move(p,[12,16]);v,_=p.command('transfer','ruins_gate',ok=False);check(v['code']=='MAP_CLOSED','destination entry disabled authoritatively')
        cdoc['entry_enabled']=True;cdoc['spawn']=[6,16];publish(closed,cdoc)
        p.command('transfer','ruins_gate');check(p.state['character']['map_id']=='ai_002' and [p.state['character']['cell_x'],p.state['character']['cell_y']]==[6,16],'relocated portal uses new destination and arrival spawn')
        cdoc['entry_enabled']=False;publish(closed,cdoc);p.close();p=f.connect(a)
        check(p.state['character']['map_id']=='ai_002' and [p.state['character']['cell_x'],p.state['character']['cell_y']]==[6,16],'closed map lets existing occupants reconnect without silent relocation')
        cdoc['entry_enabled']=True;publish(closed,cdoc)
        before=detail()['active'];action(d,'restore',release=0);check(detail()['active']==before,'rollback restores only draft, not live configuration')
        action(d,'validate');action(d,'publish');check(detail()['active']==original,'explicit publish activates rollback')
        publish(d,doc)
        # Restart preserves releases and existing cooldown deadlines.
        f.restart();headers={'Origin':f.private,'X-Operator-Token':request(f.private,'/api/maps')[1]['csrf_token']}
        check(detail()['active']==doc,'active operational settings survive process restart')
        current_release=detail()['active_revision'];action(d,operation=op)
        check(detail()['active_revision']==current_release,'replaying older release after restart cannot roll back newer publication')
        check(f.db.query(f"SELECT monster_respawns->>'wolf_a' FROM characters WHERE id='{a[1]}'")==str(deadline),'publishing and restart preserve existing cooldown deadline')
        check('operator.map.publish' in f.db.query("SELECT action FROM security_audit WHERE outcome='accepted'"),'configuration publish audited')
        legacy=f.create('maps_legacy');_,ticket=api(f.base,'/api/v1/world/ticket',dict(character_id=legacy[1],protocol_version=1,config_hash=HASH),legacy[0]['access_token'])
        ws=WebSocket(f.base.replace('http://','ws://')+'/api/v1/world/ws');ws.send(dict(type='auth.exchange',ticket=ticket['ticket'],protocol_version=1,config_hash=HASH,world_sync_version=2,population_version=1,pve_version=1,maps_version=2))
        message,_=ws.recv();check(message.get('code')=='MAP_UPDATE_REQUIRED','old client gets explicit upgrade error rather than mismatched portals');ws.close()
        if os.environ.get('GODOT_BIN'):
            ui=f.create('maps_ui');env=dict(os.environ,SSJX_MAP_TEST=json.dumps(dict(base=f.base,character=ui[1])))
            result=subprocess.run([os.environ['GODOT_BIN'],'--headless','--path',str(ROOT/'client'),'res://tests/map_management_live_test.tscn'],env=env,capture_output=True,text=True,timeout=70)
            print(result.stdout);print(result.stderr);check(result.returncode==0 and '0 failures' in result.stdout and 'SCRIPT ERROR' not in result.stderr,'real Godot operational rule integration')
        if os.environ.get('PLAYWRIGHT_MODULE_PATH'):
            result=subprocess.run(['node',str(ROOT/'tests/map_management_browser.cjs'),f.private],env=os.environ,text=True,capture_output=True,timeout=90)
            print(result.stdout);print(result.stderr);check(result.returncode==0,'real Chromium editor integration')
        print(f'MAP MANAGEMENT SERVER: {checks} checks, 0 failures')
if __name__=='__main__':main()
