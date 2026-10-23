"""Owned real PostgreSQL/WebSocket gathering: no live database or player config."""
import json
import os
from pathlib import Path
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4
from balance_fixture import BalanceFixture
from run_online_pve import api

ROOT=Path(__file__).resolve().parents[1]
def main():
    checks=0
    def check(ok,text):
        nonlocal checks
        checks+=1
        assert ok,text
    with BalanceFixture() as fixture:
        a,b=fixture.create('gather_a'),fixture.create('gather_b')
        p=fixture.connect(a);q=fixture.connect(b)
        def command(player,action,target=None,expected=None,request=None):
            request=request or dict(operation_id=str(uuid4()),action=action,target=target,expected_revision=player.state['character']['state_revision'])
            value,_=player.command('',request=request,ok=expected is None)
            if expected:check(value['code']==expected,action+': '+expected)
            return value,request
        def go(player,node):
            time.sleep(.12)
            player.move(node['cell'])
            end=time.monotonic()+15;ping=0
            while time.monotonic()<end:
                player.until('world.delta');own=player.ws.entities[player.id]
                if own['cell']==node['cell'] and own['next_cell'] is None:return
                if time.monotonic()-ping>2:player.ws.send(dict(type='ping'));ping=time.monotonic()
            raise AssertionError('Cannot reach resource')
        def ready(player):
            fixture.db.query(f"UPDATE gathering_active SET ready_at_ms=(extract(epoch FROM clock_timestamp())*1000)::bigint-1 WHERE character_id='{player.id}'")
        def reset(player,node):
            fixture.db.query(f"DELETE FROM gathering_cooldowns WHERE character_id='{player.id}' AND node_id='{node['id']}';")
        nodes=p.state['gathering']['nodes'];ore=next(n for n in nodes if n['material'] in ('iron','copper'));herb=next(n for n in nodes if n['material'] in ('gancao','danggui'))
        check(len(nodes)==2 and p.state['gathering']['materials']=={},'new character receives reachable resource nodes and empty material bag')
        check(fixture.db.query('SELECT count(DISTINCT map_id) FROM gathering_nodes')=='209','safe reachable gathering points seeded without changing map navigation')
        command(p,'gather_start',ore['id'],'GATHER_TOO_FAR')
        go(p,ore)
        started,operation=command(p,'gather_start',ore['id']);active=started['state']['gathering']['active'];token=active['token']
        check(active['ready_at_ms']>started['state']['server_time_ms'],'resource uses a real server-side completion deadline')
        check('quantity' not in active and 'snapshot' not in active,'pre-rolled yield stays private until completion')
        replay,_=command(p,'',request=operation)
        check(replay['replayed'] and replay['state']==started['state'],'start replay keeps original token and deadline')
        command(p,'gather_start',ore['id'],'GATHER_BUSY')
        command(p,'gather_finish',token,'GATHER_NOT_READY')
        # At least one completion waits the real configured 3 seconds.
        time.sleep(max(0,(active['ready_at_ms']-int(time.time()*1000))/1000)+.1)
        awarded,receipt=command(p,'gather_finish',token);quantity=awarded['state']['gathering']['materials']['iron']
        check(1<=quantity<=3 and awarded['state']['gathering']['active'] is None,'completed mining yields a bounded stack and consumes the active token')
        check(next(n for n in awarded['state']['gathering']['nodes'] if n['id']==ore['id'])['available_at_ms']>awarded['state']['server_time_ms'],'successful completion starts personal cooldown')
        replay,_=command(p,'',request=receipt)
        check(replay['replayed'] and fixture.db.query(f"SELECT quantity FROM gathering_materials WHERE character_id='{p.id}' AND material='iron'")==str(quantity),'lost finish receipt cannot grant twice')
        command(p,'gather_finish',token,'GATHER_INTERRUPTED')
        command(p,'gather_start',ore['id'],'GATHER_COOLDOWN')
        go(q,ore);second,_=command(q,'gather_start',ore['id']);ready(q);command(q,'gather_finish',second['state']['gathering']['active']['token'])
        check(fixture.db.query('SELECT count(*) FROM gathering_materials')=='2','another player can mine independently without抢点')
        go(p,herb);started,_=command(p,'gather_start',herb['id']);token=started['state']['gathering']['active']['token'];ready(p)
        # A movement and return must invalidate even when finishing at the original location.
        start_revision=p.ws.entities[p.id]['entity_revision']
        p.move([herb['cell'][0]+1,herb['cell'][1]])
        end=time.monotonic()+5
        while time.monotonic()<end:
            p.until('world.delta')
            if p.ws.entities[p.id]['entity_revision']!=start_revision:break
        go(p,herb);command(p,'gather_finish',token,'GATHER_INTERRUPTED');command(p,'gather_cancel',token)
        started,_=command(p,'gather_start',herb['id']);token=started['state']['gathering']['active']['token'];ready(p)
        # A receipt/audit failure rolls back grant, cooldown and token deletion together.
        fixture.db.query("CREATE FUNCTION reject_gather_receipt() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'owned gathering rollback'; END$$;CREATE TRIGGER reject_gather_receipt BEFORE INSERT ON pve_operation_receipts FOR EACH ROW EXECUTE FUNCTION reject_gather_receipt();")
        request=dict(operation_id=str(uuid4()),action='gather_finish',target=token,expected_revision=p.state['character']['state_revision'])
        p.ws.send(dict(type='pve.command',command=request));check(p.until('error')['code']=='DATABASE_UNAVAILABLE','failed receipt cannot acknowledge a harvest')
        check(fixture.db.query(f"SELECT count(*) FROM gathering_active WHERE character_id='{p.id}'")=='1' and fixture.db.query(f"SELECT count(*) FROM gathering_materials WHERE character_id='{p.id}' AND material='gancao'")=='0','failed transaction preserves token and does not award materials')
        fixture.db.query('DROP TRIGGER reject_gather_receipt ON pve_operation_receipts;DROP FUNCTION reject_gather_receipt();')
        p.close();p=fixture.connect(a)
        command(p,'gather_finish',token,'GATHER_INTERRUPTED')
        command(p,'gather_cancel',token);go(p,herb)
        started,_=command(p,'gather_start',herb['id']);ready(p);command(p,'gather_finish',started['state']['gathering']['active']['token'])
        check(1<=p.state['gathering']['materials']['gancao']<=3,'herbalism awards herbs separately from mined ore')
        reset(p,herb)
        fixture.db.query(f"UPDATE gathering_materials SET quantity=999 WHERE character_id='{p.id}' AND material='gancao'")
        command(p,'gather_start',herb['id'],'MATERIAL_BAG_FULL')
        check(fixture.db.query(f"SELECT count(*) FROM gathering_cooldowns WHERE character_id='{p.id}' AND node_id='{herb['id']}'")=='0','full material bag neither consumes a resource nor starts cooldown')
        # Client cannot choose a quantity or bypass map binding.
        forged=dict(operation_id=str(uuid4()),action='gather_start',target=herb['id'],quantity=10,expected_revision=p.state['character']['state_revision'])
        command(p,'',expected='INVALID_GATHER_COMMAND',request=forged)
        command(p,'gather_start','ancient_ruins_ore','GATHER_NOT_FOUND')
        before=fixture.db.query('SELECT character_id,material,quantity FROM gathering_materials ORDER BY character_id,material')
        fixture.restart();p=fixture.connect(a)
        check(before==fixture.db.query('SELECT character_id,material,quantity FROM gathering_materials ORDER BY character_id,material'),'material stacks and personal cooldowns survive server restart')
        check(p.state['gathering']['materials']['gancao']==999,'reconnect exposes authoritative persisted material bag')
        check('pve.gather_finish' in fixture.db.query("SELECT action FROM security_audit WHERE outcome='accepted'"),'harvest settlements are durably audited')
        if os.environ.get('GODOT_BIN'):
            live=fixture.create('gather_ui')
            env=dict(os.environ,SSJX_GATHERING_TEST=json.dumps(dict(base=fixture.base,character=live[1])))
            client=subprocess.run([os.environ['GODOT_BIN'],'--headless','--path',str(ROOT/'client'),'res://tests/gathering_live_test.tscn'],env=env,text=True,capture_output=True,timeout=80)
            print(client.stdout);print(client.stderr)
            check(client.returncode==0 and '0 failures' in client.stdout and 'SCRIPT ERROR' not in client.stderr,'real Godot client completes mining and herbalism')
        print(f'GATHERING SERVER: {checks} checks, 0 failures')

if __name__=='__main__':main()
