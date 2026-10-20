"""Real numeric migration/respec/frozen encounters, only on a disposable database."""
import json
import time
from uuid import uuid4
from balance_fixture import BalanceFixture,ROOT

def main():
    checks=[];snapshots=[]
    def check(value,label):
        assert value,label
        checks.append(label)
    with BalanceFixture() as f:
        identity=f.create('balance_a');cid=identity[1]
        f.db.query(f"UPDATE characters SET level=30,hp=100,mp=50,allocated_attributes=ARRAY[30,0,90,30,0],quest_stage=1,cell_x=22,cell_y=9 WHERE id='{cid}'")
        p=f.connect(identity);s=p.state;snapshots.append(s)
        check(s['character']['balance_revision']==1 and s['attributes']['formula_revision']==3,'Migrates old character once to active balance')
        check(s['character']['hp']==100*998//882 and s['character']['mp']==50,'Migration preserves resource ratios, not a free refill')
        check(s['stats']['balance']['magic_attack']==126 and s['stats']['attack']==314,'Separate physical and magical power reaches the authoritative snapshot')
        before=f.db.query(f"SELECT hp,mp,state_revision FROM characters WHERE id='{cid}'")
        f.restart();p=f.connect(identity)
        check(f.db.query(f"SELECT hp,mp,state_revision FROM characters WHERE id='{cid}'")==before,'Restart cannot repeat migration or refill resources')
        request=dict(operation_id=str(uuid4()),action='respec',expected_revision=p.state['character']['state_revision'])
        f.db.query("CREATE FUNCTION reject_balance() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN IF OLD.balance_respec_available AND NOT NEW.balance_respec_available THEN RAISE EXCEPTION 'owned rollback'; END IF; RETURN NEW; END$$; CREATE TRIGGER reject_balance BEFORE UPDATE ON characters FOR EACH ROW EXECUTE FUNCTION reject_balance();")
        p.ws.send(dict(type='pve.command',command=request))
        check(p.until('error')['code']=='DATABASE_UNAVAILABLE','Uncommitted respec is not acknowledged')
        check(f.db.query(f"SELECT balance_respec_available FROM characters WHERE id='{cid}'")=='t','Failed respec retains free entitlement')
        f.db.query('DROP TRIGGER reject_balance ON characters; DROP FUNCTION reject_balance();')
        p.close();time.sleep(.2);p=f.connect(identity)
        value,_=p.command('',request=request);snapshots.append(value['state'])
        check(value['state']['attributes']['allocated']==[0]*5 and not value['state']['character']['balance_respec_available'],'Free respec returns all points and consumes one entitlement')
        replay,_=p.command('',request=request)
        check(replay['replayed'] and replay['state']==value['state'],'Respec receipt replay cannot change resources again')
        request=dict(request,operation_id=str(uuid4()),expected_revision=p.state['character']['state_revision'])
        failed,_=p.command('',request=request,ok=False)
        check(failed['code']=='RESPEC_USED','A second free respec is rejected')
        p.command('challenge','spirit');frozen=p.state['battle']['frozen_stats'];snapshots.append(p.state)
        f.restart();p=f.connect(identity)
        check(p.state['battle']['frozen_stats']==frozen,'New encounter freezes full balance inputs across service restart')
        p.command('flee')
        f.restart()
        # Install an owned pre-upgrade durable encounter, deliberately omitting frozen_stats.
        enemy=next(r for r in json.loads((ROOT/'shared/data/qingyun-population-v1.json').read_text()) if r['id']=='spirit')
        bid=str(uuid4());legacy=dict(id=bid,enemy=enemy,hp=100,mp=30,potions=6,enemy_hp=enemy['hp'],round=0,revision=0,outcome='active',skill_rules_version=0)
        f.db.query(f"INSERT INTO pve_battles(id,character_id,rules_version,state,active) VALUES('{bid}','{cid}','qingyun-pve-v1','{json.dumps(legacy)}'::jsonb,TRUE); UPDATE characters SET balance_revision=0,hp=100,mp=30,active_battle_id='{bid}' WHERE id='{cid}'")
        p=f.connect(identity)
        check(p.state['character']['balance_revision']==0 and 'balance' not in p.state['stats'],'Legacy in-flight encounter retains explicit legacy stats')
        p.command('guard');check('frozen_stats' not in p.state['battle'],'A resumed legacy encounter is never silently upgraded')
        p.command('flee');p.close();time.sleep(.2);p=f.connect(identity)
        check(p.state['character']['balance_revision']==1,'Migration proceeds after the old encounter ends')
        output=ROOT/'work/combat-balance-v1/activation-fixtures.json';output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(snapshots,ensure_ascii=False,indent=2))
    print(f'BALANCE ACTIVATION SERVER: {len(checks)} checks, 0 failures')

if __name__=='__main__':main()
