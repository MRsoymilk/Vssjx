"""Cooldown/AI/persistence checks against real Rust sockets in an owned fixture."""
import json
from uuid import uuid4
from balance_fixture import BalanceFixture,ROOT

def main():
    checks=[];fixtures=[]
    def check(value,label):
        assert value,label
        checks.append(label)
    skills=json.loads((ROOT/'client/assets/data/skills-v1.json').read_text())['items']
    area=next(s for s in skills if s['job']==1 and s['active'] and s['target']=='all_enemies')
    with BalanceFixture() as f:
        identity=f.create('skill_budget',1);cid=identity[1]
        f.db.query(f"UPDATE characters SET level=60,hp=1500,mp=500,allocated_attributes=ARRAY[60,0,180,60,0],quest_stage=1,cell_x=22,cell_y=9 WHERE id='{cid}'")
        p=f.connect(identity);p.command('challenge','spirit');bid=p.state['battle']['id']
        # Keep an owned training enemy alive, without changing production monster data.
        f.db.query(f"UPDATE pve_battles SET state=jsonb_set(jsonb_set(state,'{{enemy,hp}}','9000'),'{{enemy_hp}}','9000') WHERE id='{bid}'")
        def cast(ok=True):
            return p.command('',request=dict(operation_id=str(uuid4()),action='skill',target=area['id'],battle_id=p.state['battle']['id'],expected_revision=p.state['battle']['revision']),ok=ok)
        value,request=cast();s=value['state'];fixtures.append(s)
        cost=area['mp_cost']
        check(s['battle']['mp']==500-cost,'Actual action spends the same fixed MP shown by the picker')
        check(s['battle']['skills']['balance']['cooldowns'][area['id']]==2,'Fresh area cast starts two full intervening cooldown rounds')
        before=dict(round=s['battle']['round'],mp=s['battle']['mp'],enemy_hp=s['battle']['enemy_hp'])
        failed,_=cast(False);fixtures.append(failed['state'])
        check(failed['code']=='SKILL_COOLDOWN','Server rejects cooling skill even when bypassing the UI')
        check(all(failed['state']['battle'][key]==val for key,val in before.items()),'Cooling refusal consumes no MP and does not advance the clock')
        f.restart();p=f.connect(identity)
        check(p.state['battle']['skills']['balance']['cooldowns'][area['id']]==2,'Cooldown survives actual server restart')
        replay,_=p.command('',request=request)
        check(replay['replayed'],'A repeated successful cast is only a receipt replay')
        p.command('guard');value,_=p.command('guard');fixtures.append(value['state'])
        check(value['state']['battle']['skills']['balance']['last_enemy_magical'],'Caster monster really uses magic on its announced third round')
        check(area['id'] not in value['state']['battle']['skills']['balance']['cooldowns'],'Two complete intervening rounds expire the cooldown')
        value,_=cast();check(value['ok'],'Skill is usable again without reconnecting or resetting battle')
        check(value['state']['skills']['balance_sha256'],'Snapshot announces the versioned skill-budget contract')
        output=ROOT/'work/combat-balance-v1/skill-server-fixtures.json';output.write_text(json.dumps(fixtures,ensure_ascii=False,indent=2))
    print(f'SKILL BALANCE SERVER: {len(checks)} checks, 0 failures')

if __name__=='__main__':main()
