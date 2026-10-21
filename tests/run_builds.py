"""Six equipment styles through actual persisted solo turns in an owned server."""
import copy
import json
import os
from pathlib import Path
import time
from uuid import uuid4
from balance_fixture import BalanceFixture,ROOT
from run_loot_instances import LootPlayer

def main():
    rows=json.loads(Path(os.environ.get('SSJX_BUILD_VECTORS','/tmp/opencode/build-vectors.json')).read_text())
    checks=[];fixtures=[]
    def check(ok,label):
        assert ok,label
        checks.append(label)
    with BalanceFixture() as f:
        identities=[];expected=[]
        def connect(identity):
            p=LootPlayer(f.base,*identity);f.clients.append(p);return p
        for i in range(6):
            row=next(row for row in rows if row['index']==i and row['gender']==0 and len(row['loot']['items'])==5)
            identity=f.create('style_'+str(i),row['job']);identities.append(identity);cid=identity[1]
            f.db.query(f"UPDATE inventory_items SET equipped=false WHERE character_id='{cid}'; UPDATE characters SET level=60,hp=800,mp=480,quest_stage=1,cell_x=22,cell_y=9,loot_state='{json.dumps(row['loot'])}'::jsonb WHERE id='{cid}'")
            p=connect(identity)
            check(p.state['stats']==row['stats'],'Actual stat aggregation and set thresholds match Rust vectors')
            value,_=p.command('',request=dict(operation_id=str(uuid4()),action='challenge',target='spirit',encounter_version=2))
            battle=copy.deepcopy(value['state']['battle']);battle['enemy_hp']=100000;battle['revision']=int(battle['revision'])
            battle['enemy']['hp']=100000
            for e in battle['formation']['enemies']:e['hp']=100000;e['definition']['hp']=100000
            p.close();time.sleep(.17)
            f.db.query(f"UPDATE pve_battles SET state='{json.dumps(battle)}'::jsonb WHERE id='{battle['id']}'")
            p=connect(identity)
            check(p.state['battle']['formation']['fighters'][0]['stats']==row['stats'],'Live encounter freezes artifact identity and four-piece procs')
            first=row['turns'][0]['skill']
            for attempt in range(12):
                battle=p.state['battle'];fx=battle['formation']['fighters'][0]['effects']
                action='guard' if fx.get('balance',{}).get('cooldowns',{}).get(first,0)>0 else 'skill'
                request=dict(operation_id=str(uuid4()),action=action,battle_id=battle['id'],expected_revision=battle['revision'],enemy_slot='m0')
                if action=='skill':request['target']=first
                value,_=p.command('',request=request)
                effects=value['state']['battle']['formation']['fighters'][0]['effects']
                if effects.get('builds') is not None:break
            else:raise AssertionError('No successful cast in twelve turns')
            check(value['state']['battle']['formation']['round']==battle['formation']['round']+1,'Legendary never grants an extra full turn')
            if i in (0,2,4,5):check(effects['builds']['charges'][i]>0,'Actual skill turn primes the appropriate persistent style charge')
            if i==1:check(value['state']['battle']['formation']['enemies'][0]['effects']['enemy_bleed']==1,'Two-tick bleeding expires on the complete-round clock')
            replay,_=p.command('',request=request)
            check(replay['replayed'] and replay['state']==value['state'],'Skill replay never doubles a style charge or healing')
            expected.append(copy.deepcopy(value['state']['battle']));fixtures.append(copy.deepcopy(value['state']))
        f.restart()
        for identity,battle in zip(identities,expected):
            p=connect(identity);check(p.state['battle']==battle,'Restart preserves frozen builds, proc charges, resources and effects')
    path=ROOT/'work/builds-v1';path.mkdir(parents=True,exist_ok=True);(path/'server-fixtures.json').write_text(json.dumps(fixtures,ensure_ascii=False))
    print(f'BUILDS SERVER: {len(checks)} checks, 0 failures')

if __name__=='__main__':main()
