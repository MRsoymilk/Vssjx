"""Actual AI boss rewards and crafting transactions; disposable database only."""
import copy
import json
import os
from pathlib import Path
import time
from uuid import uuid4
from balance_fixture import BalanceFixture,ROOT
from run_loot_instances import LootPlayer

def main():
    checks=[];fixtures=[]
    def check(value,label):
        assert value,label
        checks.append(label)
    world=json.loads((ROOT/'shared/data/ai-world-v1.json').read_text())
    area=next(m for m in world['maps'] if m['map_id']=='ai_010');boss=next(r for r in area['residents'] if r['kind']=='boss')
    cell=next([boss['cell'][0]+x,boss['cell'][1]+y] for x,y in [(0,-1),(1,0),(-1,0),(0,1)] if [boss['cell'][0]+x,boss['cell'][1]+y] not in area['blocked'])
    initial=copy.deepcopy(json.loads(Path(os.environ.get('SSJX_PROGRESSION_VECTORS','/tmp/opencode/progression-vectors.json')).read_text())['crafts'][1]['before'])
    initial['bosses']=7;prototype=initial['items'][0];initial['items']=[]
    for _ in range(58):
        item=copy.deepcopy(prototype);item.update(id=str(uuid4()),quality='white',level=1,affixes=[]);initial['items'].append(item)
    filler=initial['items'][0]['id']
    with BalanceFixture() as f:
        identity=f.create('economy_a',1);cid=identity[1]
        f.db.query(f"UPDATE characters SET map_id='ai_010',cell_x={cell[0]},cell_y={cell[1]},level=60,hp=1000,mp=480,gold=100000,allocated_attributes=ARRAY[60,0,180,60,0],loot_state='{json.dumps(initial)}'::jsonb WHERE id='{cid}'; UPDATE inventory_items SET quantity=99 WHERE character_id='{cid}' AND definition_id='potion'")
        def connect():
            p=LootPlayer(f.base,*identity);f.clients.append(p);return p
        def command(action,target,quantity=None,ok=True,request=None):
            request=request or dict(operation_id=str(uuid4()),action=action,target=target,expected_revision=p.state['character']['state_revision'])
            if quantity is not None:request['quantity']=quantity
            return p.command('',request=request,ok=ok)
        p=connect();command('gear_focus','weapon');check(p.state['loot']['state']['focus']=='weapon','Directed-drop selection is owned, revised and persisted')
        p.command('',request=dict(operation_id=str(uuid4()),action='challenge',target=boss['id'],encounter_version=2))
        for _ in range(16):
            b=p.state['battle']
            if b['outcome']!='active':break
            target=next(e['slot'] for e in b['formation']['enemies'] if e['hp']>0)
            value,last=p.command('',request=dict(operation_id=str(uuid4()),action='skill',target='legacy_1',battle_id=b['id'],expected_revision=b['revision'],enemy_slot=target))
        check(p.state['battle']['outcome']=='victory','An unmodified eligible AI-map boss can be defeated through real authoritative skill turns')
        loot=p.state['loot']['state'];check(loot['bosses']==8 and len(loot['pending'])==2 and any(i['legendary'] or i['set_id'] for i in loot['pending']),'Eighth real boss guarantees a build drop; full backpack safely receives both saved instances in pending storage')
        check(loot['scrap']==10004 and loot['essence']==101,'Boss material income is awarded exactly once with victory')
        before=f.db.query(f"SELECT loot_state,gold,state_revision FROM characters WHERE id='{cid}'")
        replay,_=p.command('',request=last);check(replay['replayed'] and f.db.query(f"SELECT loot_state,gold,state_revision FROM characters WHERE id='{cid}'")==before,'Victory replay never duplicates loot, material income or pity')
        fixtures.append(copy.deepcopy(p.state));item_id=loot['pending'][0]['id']
        value,_=command('gear_claim',item_id,ok=False);check(value['code']=='BAG_FULL','Claim cannot discard or overwrite items in a full backpack')
        command('discard','potion',99);command('gear_claim',item_id)
        def item():return next(i for i in p.state['loot']['state']['items'] if i['id']==item_id)
        original=copy.deepcopy(item())
        for step in range(1,7):
            command('gear_upgrade',item_id);check(item()['upgrade']==step and item()['affixes']==original['affixes'],'Each small upgrade preserves identity and every rolled affix')
        value,_=command('gear_upgrade',item_id,ok=False);check(value['code']=='UPGRADE_LIMIT','Seventh upgrade is rejected rather than multiplying without bound')
        command('gear_reroll',item_id,2);check(item()['reroll_index']==1 and item()['rerolls']==1 and item()['affixes'][0]==original['affixes'][0] and item()['affixes'][2:]==original['affixes'][2:],'One chosen affix changes; other affixes, legendary/set identity and upgrade remain intact')
        value,_=command('gear_reroll',item_id,1,False);check(value['code']=='REROLL_SLOT_LOCKED','A second affix cannot be rerolled after locking the first')
        before=f.db.query(f"SELECT loot_state,gold,hp,mp,state_revision FROM characters WHERE id='{cid}'")
        f.db.query("CREATE FUNCTION reject_economy() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN IF NEW.loot_state IS DISTINCT FROM OLD.loot_state THEN RAISE EXCEPTION 'owned rollback'; END IF; RETURN NEW; END$$; CREATE TRIGGER reject_economy BEFORE UPDATE ON characters FOR EACH ROW EXECUTE FUNCTION reject_economy();")
        request=dict(operation_id=str(uuid4()),action='gear_reroll',target=item_id,quantity=2,expected_revision=p.state['character']['state_revision'])
        p.ws.send(dict(type='pve.command',command=request));check(p.until('error')['code']=='DATABASE_UNAVAILABLE','A failed database commit never acknowledges crafting')
        check(f.db.query(f"SELECT loot_state,gold,hp,mp,state_revision FROM characters WHERE id='{cid}'")==before,'Failure rolls back affix, currency, materials, resources and revision as one transaction')
        f.db.query('DROP TRIGGER reject_economy ON characters; DROP FUNCTION reject_economy();');p.close();time.sleep(.2);p=connect()
        result,_=p.command('',request=request);check(not result['replayed'] and item()['rerolls']==2,'Retry of a failed operation pays once and rolls only a newly committed result')
        replay,_=p.command('',request=request);check(replay['replayed'] and item()['rerolls']==2,'Committed reroll replay returns the same affix, never a new draw')
        saved=copy.deepcopy(p.state['loot']['state']);f.restart();p=connect();check(p.state['loot']['state']==saved,'Restart preserves focus, upgrades, affix lock, material balances and pending reward UUIDs')
        fixtures.append(copy.deepcopy(p.state));command('gear_salvage',filler);command('gear_equip',item_id)
        value,_=command('gear_salvage',item_id,ok=False);check(value['code']=='UNEQUIP_BEFORE_SALVAGE','Equipped equipment cannot be destroyed')
        command('gear_unequip',item_id);state=copy.deepcopy(p.state['loot']['state']);quality=item()['quality'];template=item()['template']
        result,request=command('gear_salvage',item_id)
        check(not any(i['id']==item_id for i in p.state['loot']['state']['items']) and template in p.state['loot']['state']['skins'],'Explicit salvage removes only the selected UUID and retains the appearance unlock')
        amount=json.loads((ROOT/'shared/data/progression-v1.json').read_text())['salvage_scrap'][quality]
        check(p.state['loot']['state']['scrap']==state['scrap']+amount,'Salvage income matches the authored quality price')
        saved=copy.deepcopy(p.state['loot']['state']);p.command('',request=request);check(p.state['loot']['state']==saved,'Salvage replay cannot mint a second set of materials')
        fixtures.append(copy.deepcopy(p.state))
        pending=saved['pending'][0]
        while len(saved['pending'])<18:
            i=copy.deepcopy(pending);i['id']=str(uuid4());saved['pending'].append(i)
        f.db.query(f"UPDATE characters SET loot_state='{json.dumps(saved)}'::jsonb WHERE id='{cid}'")
        p.close();time.sleep(.2);p=connect();value,_=p.command('',request=dict(operation_id=str(uuid4()),action='challenge',target=boss['id'],encounter_version=2),ok=False)
        check(value['code']=='LOOT_STORAGE_FULL' and p.state['loot']['state']['bosses']==8,'Unclaimed near-full storage blocks new encounters before any loot, pity or hunt is consumed')
    output=ROOT/'work/progression-v1';output.mkdir(parents=True,exist_ok=True);(output/'server-fixtures.json').write_text(json.dumps(fixtures,ensure_ascii=False))
    print(f'PROGRESSION SERVER: {len(checks)} checks, 0 failures')

if __name__=='__main__':main()
