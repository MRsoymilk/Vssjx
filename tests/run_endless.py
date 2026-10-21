"""Main-city NPC and persistent endless PvE; only an owned disposable DB."""
import copy,json
from uuid import uuid4
from balance_fixture import BalanceFixture,ROOT
from run_loot_instances import LootPlayer
from run_online_pve import api
def main():
    rules=json.loads((ROOT/'shared/data/endless-v1.json').read_text());checks=[];fixtures=[]
    def check(ok,label):
        assert ok,label
        checks.append(label)
    with BalanceFixture() as f:
        identity=f.create('endless_a',1);cid=identity[1]
        f.db.query(f"UPDATE characters SET map_id='ai_001',cell_x=5,cell_y=16,level=15,hp=467,mp=217,gold=1000,allocated_attributes=ARRAY[15,0,45,15,0] WHERE id='{cid}'")
        def connect(identity=identity):
            p=LootPlayer(f.base,*identity);f.clients.append(p);return p
        def start(ok=True,request=None):
            request=request or dict(operation_id=str(uuid4()),action='endless',target=rules['npc']['id'],expected_revision=p.state['character']['state_revision'],encounter_version=2)
            return p.command('',request=request,ok=ok)
        p=connect();fixtures.append(copy.deepcopy(p.state));hunt=copy.deepcopy(p.state['hunt_pressure'])
        check(rules['npc']['id'] in p.population and p.population[rules['npc']['id']]['kind']=='npc','The actual hub population contains the new clickable NPC with existing art')
        check(p.state['endless']['progress']==dict(stage=1,best=0,level=0,in_progress=False),'Migration gives existing characters an independent empty trial record')
        rejected,_=start(False);check(rejected['code']=='RESIDENT_TOO_FAR','A forged remote request cannot enter without approaching the main-city NPC')
        p.approach(rules['npc']['id'])
        rejected,_=start(False,dict(operation_id=str(uuid4()),action='endless',target='ai_001_guide',expected_revision=p.state['character']['state_revision'],encounter_version=2))
        check(rejected['code']=='ENDLESS_NPC_REQUIRED','Other NPCs cannot open the trial through forged requests')
        rejected,_=start(False,dict(operation_id=str(uuid4()),action='endless',target=rules['npc']['id'],expected_revision='0',encounter_version=2))
        check(rejected['code']=='STALE_ENDLESS','An old character revision cannot overwrite the current trial record')
        before=f.db.query(f"SELECT endless_state,hp,mp,gold,loot_state,state_revision FROM characters WHERE id='{cid}'")
        f.db.query("CREATE FUNCTION reject_endless_entry() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN IF NEW.endless_state IS DISTINCT FROM OLD.endless_state THEN RAISE EXCEPTION 'owned entry rollback'; END IF; RETURN NEW; END$$; CREATE TRIGGER reject_endless_entry BEFORE UPDATE ON characters FOR EACH ROW EXECUTE FUNCTION reject_endless_entry();")
        request=dict(operation_id=str(uuid4()),action='endless',target=rules['npc']['id'],expected_revision=p.state['character']['state_revision'],encounter_version=2)
        p.ws.send(dict(type='pve.command',command=request));check(p.until('error')['code']=='DATABASE_UNAVAILABLE','A failed transaction cannot acknowledge trial entry')
        check(f.db.query(f"SELECT endless_state,hp,mp,gold,loot_state,state_revision FROM characters WHERE id='{cid}'")==before and f.db.query('SELECT count(*) FROM pve_battles')=='0','Entry failure rolls back the run, battle, resources, rewards and receipt together')
        f.db.query('DROP TRIGGER reject_endless_entry ON characters; DROP FUNCTION reject_endless_entry();')
        f.restart();p=connect();hp=p.state['character']['hp'];mp=p.state['character']['mp']
        value,_=start(request=request);check(not value['replayed'] and p.state['character']['hp']==hp and p.state['character']['mp']==mp,'Retry of failed entry starts exactly one stage without refilling resources')
        first=copy.deepcopy(p.state['battle']);fixtures.append(copy.deepcopy(p.state))
        check(first['endless']==dict(stage=1,level=15) and len(first['formation']['enemies'])==1 and p.state['endless']['progress']['in_progress'],'The first real encounter freezes entry level and stage with one synthetic opponent')
        replay,_=start(request=request);check(replay['replayed'] and replay['state']['battle']==first,'Entry replay cannot create a new enemy or skip a stage')
        f.restart();p=connect();check(p.state['battle']==first and p.state['endless']['progress']['in_progress'],'Server restart resumes the exact existing trial battle and pending record')
        f.db.query("CREATE FUNCTION reject_endless_win() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN IF OLD.endless_state->>'in_progress'='true' AND NEW.endless_state->>'in_progress'='false' THEN RAISE EXCEPTION 'owned settlement rollback'; END IF; RETURN NEW; END$$; CREATE TRIGGER reject_endless_win BEFORE UPDATE ON characters FOR EACH ROW EXECUTE FUNCTION reject_endless_win();")
        settlement_failed=False
        for _ in range(20):
            if p.state['battle']['outcome']!='active':break
            last=dict(operation_id=str(uuid4()),action='attack',battle_id=p.state['battle']['id'],expected_revision=p.state['battle']['revision'])
            before=f.db.query(f"SELECT endless_state,gold,xp,loot_state,hp,mp FROM characters WHERE id='{cid}'")
            battle_before=f.db.query(f"SELECT state FROM pve_battles WHERE id='{first['id']}'")
            try:value,_=p.command('',request=last)
            except AssertionError as error:
                packet=error.args[0]
                assert isinstance(packet,dict) and packet.get('code')=='DATABASE_UNAVAILABLE',packet
                settlement_failed=True
                check(f.db.query(f"SELECT endless_state,gold,xp,loot_state,hp,mp FROM characters WHERE id='{cid}'")==before and f.db.query(f"SELECT state FROM pve_battles WHERE id='{first['id']}'")==battle_before,'Winning-turn failure rolls back the exact battle, record, rewards and character resources')
                f.db.query('DROP TRIGGER reject_endless_win ON characters; DROP FUNCTION reject_endless_win();')
                # Database faults deliberately close this world connection.
                f.restart();p=connect()
                value,_=p.command('',request=last)
                check(not value['replayed'] and value['state']['battle']['outcome']=='victory','The same winning command can retry a failed settlement without duplicating rewards')
        check(settlement_failed,'The actual winning-turn transaction was fault-injected, not just arena entry')
        check(p.state['battle']['outcome']=='victory' and p.state['endless']['progress']==dict(stage=2,best=1,level=15,in_progress=False),'Actual victory advances one stage and permanently records the cleared stage')
        check(not p.state['progress']['defeated'] and not p.state['progress']['respawns'] and not p.state['ai_world']['respawns'] and p.state['hunt_pressure']==hunt,'Trial kills do not create fake world quest, respawn or elite-hunt progress')
        fixtures.append(copy.deepcopy(p.state));before=f.db.query(f"SELECT endless_state,gold,xp,loot_state FROM characters WHERE id='{cid}'")
        replay,_=p.command('',request=last);check(replay['replayed'] and f.db.query(f"SELECT endless_state,gold,xp,loot_state FROM characters WHERE id='{cid}'")==before,'Winning turn replay does not duplicate records, gear, materials, gold or XP')
        hp=p.state['character']['hp'];value,_=start();second=p.state['battle'];fixtures.append(copy.deepcopy(p.state))
        check(second['endless']['stage']==2 and second['enemy']['hp']>first['enemy']['hp'] and second['enemy']['attack']>first['enemy']['attack'] and second['enemy']['defense']>=first['enemy']['defense'],'The actual second opponent gets stronger in the live server, not just in its label')
        check(p.state['character']['hp']==hp,'Entering the next stage does not silently heal the character')
        p.command('flee');fixtures.append(copy.deepcopy(p.state));check(p.state['endless']['progress']==dict(stage=1,best=1,level=0,in_progress=False),'Retreat resets only the current run and retains the best clear')
        f.db.query(f"UPDATE characters SET hp=1 WHERE id='{cid}'");start()
        for _ in range(16):
            if p.state['battle']['outcome']!='active':break
            value,last=p.command('guard')
        corpse=copy.deepcopy(p.state['character']['corpse']);fixtures.append(copy.deepcopy(p.state))
        check(p.state['battle']['outcome']=='defeat' and corpse['map_id']=='ai_001' and p.state['character']['hp']==0 and p.state['endless']['progress']==dict(stage=1,best=1,level=0,in_progress=False),'Trial defeat uses the existing same-map soul/corpse system while preserving the record')
        replay,_=p.command('',request=last);check(replay['replayed'] and p.state['character']['corpse']==corpse,'Defeat replay cannot create another grave or reset the best record')
        rejected,_=start(False);check(rejected['code']=='SOUL_STATE','A soul cannot enter to bypass corpse recovery')
        other=f.create('endless_b',1);mate=f.create('endless_c',1)
        for who in [other,mate]:f.db.query(f"UPDATE characters SET map_id='ai_001',cell_x=11,cell_y=15 WHERE id='{who[1]}'")
        q=connect(other);connect(mate)
        def team(who,action,**fields):
            status,value=api(f.base,'/api/v1/teams',dict(character_id=who[1],action=action,operation_id=str(uuid4()),**fields),who[0]['access_token']);assert status==200 and value['ok'],value
            return value
        team(other,'invite',target=mate[1]);incoming=team(mate,'snapshot')['state']['incoming'][0]['id'];team(mate,'accept',target=incoming)
        rejected,_=q.command('',request=dict(operation_id=str(uuid4()),action='endless',target=rules['npc']['id'],expected_revision=q.state['character']['state_revision'],encounter_version=2),ok=False)
        check(rejected['code']=='ENDLESS_SOLO_ONLY','A queued party cannot bypass normal shared-battle and ROLL eligibility through the solo NPC')
        check(json.loads(f.db.query(f"SELECT endless_state FROM characters WHERE id='{other[1]}'"))['best']==0,'Personal trial records cannot leak into another character')
    output=ROOT/'work/endless';output.mkdir(parents=True,exist_ok=True);(output/'server-fixtures.json').write_text(json.dumps(fixtures,ensure_ascii=False))
    print(f'ENDLESS SERVER: {len(checks)} checks, 0 failures')
if __name__=='__main__':main()
