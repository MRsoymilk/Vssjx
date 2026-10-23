"""Owned real PostgreSQL/WebSocket gathering: no live database or player config."""
import json
import hashlib
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
        command(p,'gather_discard','gancao',request=dict(operation_id=str(uuid4()),action='gather_discard',target='gancao',quantity=998,expected_revision=p.state['character']['state_revision']))
        check(p.state['gathering']['materials']['gancao']==1,'explicit material discard frees capacity without changing equipment')
        check('pve.gather_finish' in fixture.db.query("SELECT action FROM security_audit WHERE outcome='accepted'"),'harvest settlements are durably audited')
        craft_checks(fixture,check,command)
        if os.environ.get('GODOT_BIN'):
            live=fixture.create('gather_ui')
            fixture.db.query(f"INSERT INTO gathering_materials(character_id,material,quantity) SELECT '{live[1]}',m,12 FROM unnest(ARRAY['iron','copper','gancao','danggui']) m")
            env=dict(os.environ,SSJX_GATHERING_TEST=json.dumps(dict(base=fixture.base,character=live[1])))
            client=subprocess.run([os.environ['GODOT_BIN'],'--headless','--path',str(ROOT/'client'),'res://tests/gathering_live_test.tscn'],env=env,text=True,capture_output=True,timeout=180)
            print(client.stdout);print(client.stderr)
            check(client.returncode==0 and '0 failures' in client.stdout and 'SCRIPT ERROR' not in client.stderr,'real Godot client completes mining and herbalism')
        print(f'GATHERING SERVER: {checks} checks, 0 failures')

def craft_checks(fixture,check,command):
    raw=(ROOT/'shared/data/gathering-recipes-v1.json').read_bytes()
    check(raw==(ROOT/'client/assets/data/gathering-recipes-v1.json').read_bytes(),'client and server share identical recipe bytes')
    identity=fixture.create('gather_craft');p=fixture.connect(identity)
    check(p.state['gathering']['recipes_sha256']==hashlib.sha256(raw).hexdigest(),'server announces the exact processing catalog')
    fixture.db.query(f"INSERT INTO gathering_materials(character_id,material,quantity) SELECT '{p.id}',m,30 FROM unnest(ARRAY['iron','copper','gancao','danggui']) m")
    def request(recipe,count=1):
        return dict(operation_id=str(uuid4()),action='gather_craft',target=recipe,quantity=count,expected_revision=p.state['character']['state_revision'])
    def snapshot():
        return fixture.db.query(f"SELECT jsonb_build_object('loot',loot_state,'revision',state_revision,'potions',(SELECT quantity FROM inventory_items WHERE character_id=c.id AND definition_id='potion'),'materials',(SELECT jsonb_object_agg(material,quantity) FROM gathering_materials WHERE character_id=c.id)) FROM characters c WHERE id='{p.id}'")
    before=snapshot()
    for count in [-1,0,11,2147483647]:command(p,'',expected='INVALID_GATHER_COMMAND',request=request('smelt_iron',count))
    command(p,'',expected='INVALID_GATHER_COMMAND',request=request('unknown'))
    command(p,'',expected='INVALID_GATHER_COMMAND',request=dict(request('smelt_iron'),attributes=[0,0,0,0,0]))
    check(snapshot()==before,'malformed recipes leave all inventory and revisions intact')
    scrap=p.state['loot']['state']['scrap'];potions=p.state['potions']
    _,receipt=command(p,'',request=request('smelt_iron',10))
    check('iron' not in p.state['gathering']['materials'] and p.state['loot']['state']['scrap']==scrap+10,'maximum legal batch consumes exactly 30 ore and grants 10 existing scrap')
    credited=snapshot();value,_=command(p,'',request=receipt)
    check(value['replayed'] and snapshot()==credited,'repeated processing operation cannot debit or grant twice')
    command(p,'',expected='PVE_ID_CONFLICT',request=dict(receipt,target='smelt_copper'))
    command(p,'',request=request('smelt_copper',2))
    check(p.state['gathering']['materials']['copper']==24 and p.state['loot']['state']['scrap']==scrap+12,'copper uses the shared output balance and its own ingredient')
    command(p,'',request=request('brew_potion',3))
    check(p.state['gathering']['materials']['gancao']==24 and p.state['gathering']['materials']['danggui']==27 and p.state['potions']==potions+3,'herbal processing debits both herbs and awards existing consumables')
    fixture.db.query(f"DELETE FROM gathering_materials WHERE character_id='{p.id}' AND material='danggui'")
    before=snapshot();command(p,'',expected='MATERIALS_INSUFFICIENT',request=request('brew_potion'))
    check(snapshot()==before,'missing one ingredient leaves the other ingredient and outputs intact')
    fixture.db.query(f"INSERT INTO gathering_materials VALUES('{p.id}','danggui',30)")
    # A late receipt failure must roll back both SQL ingredients and in-memory outputs.
    for recipe in ['smelt_copper','brew_potion']:
        before=snapshot();pending=request(recipe,2)
        fixture.db.query("CREATE FUNCTION reject_craft_receipt() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'owned crafting rollback'; END$$;CREATE TRIGGER reject_craft_receipt BEFORE INSERT ON pve_operation_receipts FOR EACH ROW EXECUTE FUNCTION reject_craft_receipt();")
        p.ws.send(dict(type='pve.command',command=pending));check(p.until('error')['code']=='DATABASE_UNAVAILABLE','failed receipt cannot acknowledge processing')
        check(snapshot()==before,'receipt fault atomically restores ingredients, output and character revision: '+recipe)
        fixture.db.query('DROP TRIGGER reject_craft_receipt ON pve_operation_receipts;DROP FUNCTION reject_craft_receipt();')
        p.close();p=fixture.connect(identity)
        command(p,'',request=pending);credited=snapshot();command(p,'',request=pending)
        check(snapshot()==credited,'retry after rollback commits exactly once: '+recipe)
    revision=p.state['character']['state_revision'];copper=p.state['gathering']['materials']['copper'];scrap=p.state['loot']['state']['scrap']
    first=request('smelt_copper');second=request('smelt_copper')
    p.ws.send(dict(type='pve.command',command=first));p.ws.send(dict(type='pve.command',command=second))
    replies=[p.until('pve.result'),p.until('pve.result')]
    check(sum(r['ok'] for r in replies)==1 and any(r.get('code')=='STALE_GATHERING' for r in replies),'two concurrent batch requests with one revision settle only once')
    check(p.state['loot']['state']['scrap']==scrap+1 and p.state['gathering']['materials']['copper']==copper-3 and int(p.state['character']['state_revision'])==int(revision)+1,'concurrent processing has one exact material debit and revision')
    fixture.db.query(f"UPDATE inventory_items SET quantity=98 WHERE character_id='{p.id}' AND definition_id='potion'")
    command(p,'',request=request('brew_potion'))
    check(p.state['potions']==99,'last available potion slot accepts exactly one output')
    before=snapshot();command(p,'',expected='BAG_FULL',request=request('brew_potion'))
    check(snapshot()==before,'full potion stack refuses processing without herb loss')
    fixture.db.query(f"UPDATE characters SET loot_state=jsonb_set(loot_state,'{{scrap}}','1000000000') WHERE id='{p.id}'")
    before=snapshot();command(p,'',expected='CRAFT_RESOURCE_FULL',request=request('smelt_copper'))
    check(snapshot()==before,'full scrap balance refuses processing without ore loss')
    # Fill the real gear inventory: potion output cannot bypass bag admission.
    goods=json.loads((ROOT/'client/assets/data/shop-v2.json').read_text())['items']
    ids=[i['id'] for i in goods if i['slot'] not in ('consumable','gourd') and i['job'] in (-1,0) and i.get('gender',-1) in (-1,0)][:60]
    check(len(ids)==60,'capacity fixture uses 60 actual compatible catalog items')
    fixture.db.query(f"DELETE FROM inventory_items WHERE character_id='{p.id}';INSERT INTO inventory_items(id,character_id,definition_id,quantity,equipped) SELECT gen_random_uuid(),'{p.id}',d,1,FALSE FROM unnest(ARRAY["+','.join("'"+i+"'" for i in ids)+"]) d")
    p.close();p=fixture.connect(identity);before=snapshot()
    command(p,'',expected='BAG_FULL',request=request('brew_potion'))
    check(snapshot()==before,'first potion requires a free gear-bag slot')
    p.approach('qingwei');p.command('accept','qingwei');p.approach('wolf_a');p.command('challenge','wolf_a')
    before=snapshot();command(p,'',expected='BATTLE_ACTIVE',request=request('brew_potion'))
    check(snapshot()==before,'active combat cannot process materials')
    p.command('flee')
    before=snapshot();fixture.restart();p=fixture.connect(identity)
    check(snapshot()==before,'processed resources survive real server restart')
    audit=fixture.db.query("SELECT details FROM security_audit WHERE action='pve.gather_craft' AND outcome='accepted'")
    check('gathering_materials' in audit and 'scrap' in audit and 'potions' in audit,'processing audit includes both ingredient balances and output resources')

if __name__=='__main__':main()
