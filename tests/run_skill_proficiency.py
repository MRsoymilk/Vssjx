"""Real cast counts, atomic receipts and persistence using disposable data only."""
import copy,json,time
from uuid import uuid4
from balance_fixture import BalanceFixture

def main():
    checks=0
    def check(ok,label):
        nonlocal checks
        assert ok,label
        checks+=1;print('PASS: '+label,flush=True)
    with BalanceFixture() as f:
        identity=f.create('skill_probe');cid=identity[1]
        f.db.query(f"UPDATE characters SET level=60,quest_stage=1 WHERE id='{cid}'")
        p=f.connect(identity);p.approach('wolf_a')
        p.command('',request=dict(operation_id=str(uuid4()),action='challenge',target='wolf_a',encounter_version=2))
        bid=p.state['battle']['id'];template=copy.deepcopy(p.state['battle'])
        def seed(skill,count,aoe=False):
            nonlocal p
            p.close();time.sleep(.12)
            b=copy.deepcopy(template);b.pop('revision',None);b['revision']=0
            b['hp']=b['formation']['fighters'][0]['stats']['hp'];b['mp']=b['formation']['fighters'][0]['stats']['mp']
            b['formation']['enemies']=b['formation']['enemies'][:1]
            enemy=b['formation']['enemies'][0];enemy['hp']=enemy['definition']['hp']=100000;enemy['definition']['attack']=1
            if aoe:
                extra=copy.deepcopy(enemy);extra['slot']='m1';b['formation']['enemies'].append(extra)
            for fighter in b['formation']['fighters']:
                fighter['hp']=b['hp'];fighter['mp']=b['mp'];fighter['effects']['balance']['cooldowns']={}
                fighter['effects']['proficiency']={skill:count}
            b['enemy_hp']=b['enemy']['hp']=100000;b['enemy']['attack']=1
            f.db.query(f"UPDATE characters SET skill_proficiency=$owned${json.dumps({skill:count})}$owned$::jsonb,hp={b['hp']},mp={b['mp']} WHERE id='{cid}'; UPDATE pve_battles SET state=$owned${json.dumps(b)}$owned$::jsonb WHERE id='{bid}';")
            p=f.connect(identity)
        for previous,rank in [(99,6),(179,10),(279,15)]:
            seed('sheet_010',previous)
            result,op=p.command('',request=dict(operation_id=str(uuid4()),action='skill',target='sheet_010',enemy_slot='m0',battle_id=bid,expected_revision=p.state['battle']['revision']))
            check(result['state']['character']['skill_proficiency']['sheet_010']==previous+1,'Accepted cast increments durable count at rank '+str(rank))
            check(result['state']['battle']['skills']['last_skill_level']==rank,'Cast freezes exact visual rank '+str(rank))
            check(all(e['skill_level']==rank for e in result['state']['battle']['formation']['events'] if e['skill']=='sheet_010'),'Formation events carry exact cast rank')
            replay,_=p.command('',request=op)
            check(replay['replayed'] and replay['state']['character']['skill_proficiency']['sheet_010']==previous+1,'Receipt retry cannot train twice')
            check(json.loads(f.db.query(f"SELECT skill_proficiency FROM characters WHERE id='{cid}'"))['sheet_010']==previous+1,'Database agrees with reply')
        seed('user_hengsao_qianjun',19,True)
        result,_=p.command('',request=dict(operation_id=str(uuid4()),action='skill',target='user_hengsao_qianjun',enemy_slot='m0',battle_id=bid,expected_revision=p.state['battle']['revision']))
        hits=[e for e in result['state']['battle']['formation']['events'] if e['skill']=='user_hengsao_qianjun']
        check(len(hits)==2 and result['state']['character']['skill_proficiency']['user_hengsao_qianjun']==20,'Two-target AOE trains the caster exactly once')
        seed('sheet_010',19)
        operation=dict(operation_id=str(uuid4()),action='skill',target='sheet_010',enemy_slot='m0',battle_id=bid,expected_revision=p.state['battle']['revision'])
        f.db.query("CREATE FUNCTION owned_reject_practice_receipt() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'owned mastery rollback'; END$$; CREATE TRIGGER owned_reject_practice_receipt BEFORE INSERT ON pve_operation_receipts FOR EACH ROW EXECUTE FUNCTION owned_reject_practice_receipt();")
        p.ws.send(dict(type='pve.command',command=operation));check(p.until('error')['code']=='DATABASE_UNAVAILABLE','Receipt write failure rejects cast')
        f.db.query('DROP TRIGGER owned_reject_practice_receipt ON pve_operation_receipts; DROP FUNCTION owned_reject_practice_receipt();')
        check(json.loads(f.db.query(f"SELECT skill_proficiency FROM characters WHERE id='{cid}'"))['sheet_010']==19,'Failed transaction rolls back training')
        p.close();p=f.connect(identity)
        result,_=p.command('',request=operation)
        check(result['state']['character']['skill_proficiency']['sheet_010']==20,'Retry after rollback trains once')
        f.restart();p=f.connect(identity)
        check(p.state['character']['skill_proficiency']['sheet_010']==20,'Training survives process restart and reconnect')
        # A forged progress field is rejected by the existing strict command shape.
        p.ws.send(dict(type='pve.command',command=dict(operation_id=str(uuid4()),action='guard',skill_proficiency={'sheet_010':280})))
        check(p.until('error')['code']=='INVALID_MESSAGE','Client cannot supply its own proficiency')
    print(f'SKILL PROFICIENCY SERVER: {checks} checks, 0 failures',flush=True)

if __name__=='__main__':main()
