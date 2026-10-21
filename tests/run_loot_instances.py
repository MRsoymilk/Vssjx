"""UUID equipment transactions in an owned disposable DB; never touches player data."""
import copy
import json
import os
from pathlib import Path
import time
from uuid import uuid4
from balance_fixture import BalanceFixture,ROOT
from run_online_pve import Player,api,HASH
from ws_fixture import WebSocket

class LootPlayer(Player):
    def __init__(self,base,session,character):
        self.base,self.session,self.id=base,session,character
        status,ticket=api(base,'/api/v1/world/ticket',dict(character_id=character,protocol_version=1,config_hash=HASH),session['access_token']);assert status==200,ticket
        self.ws=WebSocket(base.replace('http://','ws://')+'/api/v1/world/ws')
        self.ws.send(dict(type='auth.exchange',ticket=ticket['ticket'],protocol_version=1,config_hash=HASH,world_sync_version=2,population_version=1,pve_version=1,maps_version=2,shop_version=2))
        self.population,self.state,self.seq={},{},0
        self.ready=self.until('auth.ready');self.state=self.until('pve.state')['state'];self.until('population.state')

def main():
    checks=[];snapshots=[]
    def check(value,label):
        assert value,label
        checks.append(label)
    vectors=json.loads(Path(os.environ.get('SSJX_LOOT_VECTORS','/tmp/opencode/loot-vectors.json')).read_text())
    source=next(r['item'] for r in vectors if r['job']==0 and r['gender']==0 and r['item']['level']==30 and r['item']['quality']=='yellow' and r['item']['template']=='original/iw1')
    with BalanceFixture() as f:
        a=f.create('loot_a');b=f.create('loot_b');cid=a[1]
        f.db.query(f"UPDATE characters SET level=60,hp=1,mp=1,quest_stage=1,cell_x=22,cell_y=9,allocated_attributes=ARRAY[60,0,180,60,0] WHERE id='{cid}'")
        def connect(identity):
            p=LootPlayer(f.base,*identity);f.clients.append(p);return p
        def command(action,target,ok=True,request=None):
            request=request or dict(operation_id=str(uuid4()),action=action,target=target,expected_revision=p.state['character']['state_revision'])
            return p.command('',request=request,ok=ok)
        p=connect(a);snapshots.append(copy.deepcopy(p.state));base_attack=p.state['stats']['attack']
        check(len(p.state['loot']['state']['items'])==1 and p.state['loot']['state']['items'][0]['legacy'],'Real login imports fixed equipment with stable UUIDs')
        legacy=copy.deepcopy(p.state['loot']['state']);f.restart();p=connect(a)
        check(p.state['loot']['state']==legacy,'Migration does not repeat across server restart')
        s=copy.deepcopy(legacy);first=copy.deepcopy(source);first.update(id=str(uuid4()),template='ai/eva01/mzs/weapon',equipped=False)
        second=copy.deepcopy(first);second['id']=str(uuid4());s['items'] += [first,second]
        f.db.query(f"UPDATE characters SET loot_state='{json.dumps(s)}'::jsonb WHERE id='{cid}'")
        result,request=command('gear_equip',first['id']);snapshots.append(copy.deepcopy(result['state']))
        check(result['state']['character']['hp']==1 and result['state']['character']['mp']==1,'Equipping never refills world HP or MP')
        check(result['state']['stats']['attack']>base_attack and result['state']['loot']['appearance'][0]==40,'Rolled stats and equipment appearance reach the authoritative snapshot')
        check(sum(i['equipped'] for i in result['state']['loot']['state']['items'])==1,'Only one copy in a slot is equipped')
        before=f.db.query(f"SELECT loot_state,hp,mp,state_revision FROM characters WHERE id='{cid}'")
        replay,_=command('',first['id'],request=request)
        check(replay['replayed'] and f.db.query(f"SELECT loot_state,hp,mp,state_revision FROM characters WHERE id='{cid}'")==before,'Successful equip replay cannot change UUIDs, resources or revisions')
        conflict,_=command('',first['id'],ok=False,request=dict(request,target=second['id']))
        check(conflict['code']=='PVE_ID_CONFLICT','Same operation UUID cannot equip a different copy')
        stale,_=command('',second['id'],ok=False,request=dict(request,operation_id=str(uuid4()),target=second['id']))
        check(stale['code']=='STALE_EQUIPMENT','An old character revision cannot overwrite a newer equipment decision')
        foreign=connect(b).state['loot']['state']['items'][0]['id']
        rejected,_=command('gear_equip',foreign,False);check(rejected['code']=='INSTANCE_NOT_OWNED','Another character instance UUID grants no ownership')
        f.db.query("CREATE FUNCTION reject_loot_write() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN IF NEW.loot_state IS DISTINCT FROM OLD.loot_state THEN RAISE EXCEPTION 'owned rollback'; END IF; RETURN NEW; END$$; CREATE TRIGGER reject_loot BEFORE UPDATE ON characters FOR EACH ROW EXECUTE FUNCTION reject_loot_write();")
        failed=dict(operation_id=str(uuid4()),action='gear_unequip',target=first['id'],expected_revision=p.state['character']['state_revision'])
        p.ws.send(dict(type='pve.command',command=failed));check(p.until('error')['code']=='DATABASE_UNAVAILABLE','Database failure cannot acknowledge an unequip')
        check(f.db.query(f"SELECT loot_state,hp,mp,state_revision FROM characters WHERE id='{cid}'")==before,'Equipment, resources and receipt roll back together')
        f.db.query('DROP TRIGGER reject_loot ON characters; DROP FUNCTION reject_loot_write();')
        p.close();time.sleep(.2);p=connect(a);result,_=command('',first['id'],request=failed)
        check(not result['replayed'] and not any(i['equipped'] for i in result['state']['loot']['state']['items']),'Retry after failed transaction commits only once')
        command('gear_equip',first['id']);f.restart();p=connect(a);snapshots.append(copy.deepcopy(p.state))
        check(next(i for i in p.state['loot']['state']['items'] if i['id']==first['id'])['equipped'],'Equipped copy survives actual process restart')
        status,roster=api(f.base,'/api/v1/characters',token=a[0]['access_token'])
        check(status==200 and roster['characters'][0]['appearance_v2']==p.state['loot']['appearance'],'Character roster uses the same owned rolled appearance')
        status,profile=api(f.base,'/api/v1/social',dict(character_id=b[1],action='profile',target=cid),b[0]['access_token'])
        check(status==200 and profile['profile']['combat']['physical_attack']==p.state['stats']['attack'] and profile['profile']['appearance']==p.state['loot']['appearance'],'Public profile shows the same stats without exposing the inventory')
        frozen=copy.deepcopy(p.state['stats'])
        value,_=p.command('',request=dict(operation_id=str(uuid4()),action='challenge',target='spirit',encounter_version=2));snapshots.append(copy.deepcopy(value['state']))
        check(value['state']['stats']==frozen and value['state']['battle']['formation']['fighters'][0]['stats']==frozen,'New solo encounters freeze the same rolled stats shown in the world')
        rejected,_=command('gear_equip',second['id'],False);check(rejected['code']=='BATTLE_ACTIVE','Equipment mutations cannot alter an in-flight encounter')
        p.command('flee')
        s=copy.deepcopy(p.state['loot']['state'])
        for _ in range(57):
            item=copy.deepcopy(first);item.update(id=str(uuid4()),quality='white',affixes=[],equipped=False,level=1);s['items'].append(item)
        pending=copy.deepcopy(first);pending.update(id=str(uuid4()),equipped=False);s['pending']=[pending]
        f.db.query(f"UPDATE characters SET loot_state='{json.dumps(s)}'::jsonb WHERE id='{cid}'")
        p.close();time.sleep(.2);p=connect(a)
        rejected,_=command('gear_claim',pending['id'],False);check(rejected['code']=='BAG_FULL','Pending storage cannot bypass the shared sixty-slot backpack')
        command('discard','sword');result,_=command('gear_claim',pending['id']);snapshots.append(copy.deepcopy(result['state']))
        check(not result['state']['loot']['state']['pending'] and any(i['id']==pending['id'] for i in result['state']['loot']['state']['items']),'Freeing an actual slot permits claiming the original saved instance')
        rejected,_=command('gear_unequip',first['id'],False);check(rejected['code']=='BAG_FULL','A full backpack cannot unequip and lose equipment')
    output=ROOT/'work/loot-instances';output.mkdir(parents=True,exist_ok=True);(output/'server-fixtures.json').write_text(json.dumps(snapshots,ensure_ascii=False,indent=2))
    print(f'LOOT INSTANCES SERVER: {len(checks)} checks, 0 failures')

if __name__=='__main__':main()
