"""Real receipt/reconnect checks for own-attack Lishi reflection; owned DB only."""
import copy
import json
from uuid import uuid4
from balance_fixture import BalanceFixture

def main():
    checks=0
    def check(ok,message):
        nonlocal checks
        checks+=1
        assert ok,message
    with BalanceFixture() as f:
        identity=f.create('lishi_test');cid=identity[1]
        f.db.query(f"UPDATE characters SET quest_stage=1,level=60,hp=1000,mp=400 WHERE id='{cid}'")
        p=f.connect(identity);p.approach('wolf_a');p.command('challenge','wolf_a')
        bid=p.state['battle']['id'];template=json.loads(f.db.query(f"SELECT state::text FROM pve_battles WHERE id='{bid}'"))
        for own_attack,enemy_attack in [(120,50),(120,500),(240,50)]:
            for action,defense in [('guard',0),('skill',0),('guard',50)]:
                p.close();b=copy.deepcopy(template)
                # A durable legacy-style frozen encounter avoids random hit rolls;
                # both the reflected damage and receipt remain real server output.
                b.update(hp=1000,mp=400,enemy_hp=10000,round=0,revision=0,outcome='active',skill_rules_version=1,
                    frozen_stats=dict(hp=1000,mp=400,attack=own_attack,defense=20,attributes=[0]*5,balance=None),
                    skills=dict(defense=2 if defense else 0,defense_percent=defense))
                b['enemy'].update(hp=10000,attack=enemy_attack)
                f.db.query(f"UPDATE pve_battles SET state=$owned${json.dumps(b)}$owned$::jsonb WHERE id='{bid}';UPDATE characters SET hp=1000,mp=400,state_revision=state_revision+1 WHERE id='{cid}'")
                p=f.connect(identity)
                request=dict(operation_id=str(uuid4()),action=action,battle_id=bid,expected_revision=p.state['battle']['revision'])
                if action=='skill':request['target']='sheet_011'
                result,_=p.command('',request=request);battle=result['state']['battle']
                expected=own_attack*(30 if action=='skill' else 20)//100+(6 if action=='guard' else 0)
                check(battle['skills']['last_reflected']==expected,f'own {own_attack}, enemy {enemy_attack}, action {action}, defense {defense}')
                check(battle['enemy_hp']==10000-expected,'authoritative enemy HP matches own-attack reflection')
                replay,_=p.command('',request=request)
                check(replay['replayed'] and replay['state']==result['state'],'reflection action retry cannot apply damage twice')
                p.close();p=f.connect(identity)
                check(p.state['battle']['enemy_hp']==10000-expected,'reconnect preserves already settled reflection')
        print(f'LISHI REFLECTION SERVER: {checks} checks, 0 failures')
if __name__=='__main__':main()
