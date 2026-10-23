"""Reusable supplies, real server/DB receipts, combat boundaries and restart recovery."""
import copy,json,time
from uuid import uuid4
from balance_fixture import BalanceFixture,ROOT
from run_loot_instances import LootPlayer
from run_online_pve import api

HP='supply/hp_gourd';MP='supply/mp_gourd'
def main():
    checks=[];packets=[]
    def check(ok,label):
        assert ok,label
        checks.append(label)
    with BalanceFixture() as f:
        who=f.create('gourd_a',1);cid=who[1]
        f.db.query(f"UPDATE characters SET gold=10000,level=60,hp=10,mp=5,quest_stage=1,cell_x=10,cell_y=14 WHERE id='{cid}'")
        def connect(identity=who):
            p=LootPlayer(f.base,*identity);f.clients.append(p)
            packets.append(dict(type='pve.state',state=copy.deepcopy(p.state)))
            return p
        def record(value):packets.append(copy.deepcopy(value));return value
        def cmd(p,action,target=None,error=None,request=None,**fields):
            time.sleep(.065)
            request=request or dict(operation_id=str(uuid4()),action=action,target=target,expected_revision=p.state['character']['state_revision'],**fields)
            value,request=p.command('',request=request,ok=error is None);record(value)
            if error:check(value['code']==error,action+' rejects '+error)
            return value,request
        def dbstate(id=cid):return f.db.query(f"SELECT hp,mp,gold,gourd_state,state_revision,active_battle_id FROM characters WHERE id='{id}'")
        p=connect();maxima=p.state['stats'];check(p.state['gourds']=={} and p.state['character']['hp']==10,'No container grants no free healing on login')
        initial=p.state['character'].copy()
        bought,buy=cmd(p,'buy',HP)
        check(p.state['character']['hp']==maxima['hp'] and p.state['character']['mp']==5 and p.state['gourds'][HP]==dict(remaining=10000-maxima['hp']+10,enabled=True),'Purchase debits only the missing HP, never mana')
        check(p.state['character']['gold']==initial['gold']-200,'New container uses authoritative catalog price')
        cmd(p,'buy',MP)
        check(p.state['character']['mp']==maxima['mp'] and p.state['gourds'][MP]['remaining']==5000-maxima['mp']+5,'Mana purchase separately supplies exact missing MP')
        cmd(p,'buy',HP,error='ITEM_ALREADY_OWNED');cmd(p,'buy',MP,error='INVALID_QUANTITY',quantity=2)
        cmd(p,'use',HP,error='ITEM_NOT_USABLE');cmd(p,'equip',MP,error='INVALID_EQUIPMENT')
        before=dbstate();cmd(p,'',request=dict(buy,operation_id=str(uuid4())),error='STALE_EQUIPMENT')
        check(dbstate()==before,'Stale command cannot change health or reserves')
        replay,_=cmd(p,'',request=buy)
        check(replay['replayed'] and dbstate()==before,'Old purchase receipt cannot refill or debit gold twice')
        p.close();time.sleep(.2);p=connect()
        check(dbstate()==before,'Reconnect at full resources never consumes again')
        cmd(p,'gourd_disable',HP);cmd(p,'gourd_disable',MP)
        f.db.query(f"UPDATE characters SET hp=1,mp=0,gourd_state=jsonb_set(jsonb_set(gourd_state,'{{{HP},remaining}}','7'),'{{{MP},remaining}}','3') WHERE id='{cid}'")
        p.close();time.sleep(.2);p=connect()
        check(p.state['character']['hp']==1 and p.state['character']['mp']==0,'Disabled reserves persist through reconnect without restoring resources')
        cmd(p,'gourd_enable',HP);cmd(p,'gourd_enable',MP)
        check(p.state['character']['hp']==8 and p.state['character']['mp']==3 and all(v['remaining']==0 for v in p.state['gourds'].values()),'Short reserves supply partially to exhaustion')
        check(p.state['shop']['quantities'][HP]==p.state['shop']['quantities'][MP]==1,'Empty containers remain owned')
        cmd(p,'gourd_refill_hp','wolf_a',error='GOURD_NPC_REQUIRED')
        cmd(p,'gourd_refill_hp','ai_001_guide',error='GOURD_NPC_REQUIRED')
        refill,refill_request=cmd(p,'gourd_refill_hp','qingwei')
        check(p.state['character']['hp']==maxima['hp'] and p.state['gourds'][HP]['remaining']==10000-maxima['hp']+8,'Actual nearby NPC refill immediately supplies an enabled gourd')
        cmd(p,'gourd_refill_hp','qingwei');cmd(p,'gourd_refill_hp','qingwei',error='GOURD_FULL')
        cmd(p,'gourd_disable',MP)
        before=dbstate()
        f.db.query("CREATE FUNCTION reject_gourd_receipt() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'owned gourd rollback'; END$$; CREATE TRIGGER reject_gourd_receipt BEFORE INSERT ON pve_operation_receipts FOR EACH ROW EXECUTE FUNCTION reject_gourd_receipt();")
        request=dict(operation_id=str(uuid4()),action='gourd_refill_mp',target='qingwei',expected_revision=p.state['character']['state_revision'])
        p.ws.send(dict(type='pve.command',command=request))
        check(p.until('error')['code']=='DATABASE_UNAVAILABLE' and dbstate()==before,'Failed receipt rolls refill, resources and revision back together')
        check(f.db.query(f"SELECT count(*) FROM pve_operation_receipts WHERE operation_id='{request['operation_id']}'")=='0','Failed refill has no durable receipt')
        f.db.query('DROP TRIGGER reject_gourd_receipt ON pve_operation_receipts; DROP FUNCTION reject_gourd_receipt();')
        f.restart();p=connect()
        cmd(p,'',request=request)
        check(p.state['gourds'][MP]==dict(remaining=5000,enabled=False) and p.state['character']['mp']==3,'Original failed refill retries once and preserves the off switch')
        before=dbstate();replay,_=cmd(p,'',request=request)
        check(replay['replayed'] and dbstate()==before,'Refill retry cannot multiply supply')
        cmd(p,'gourd_enable',MP)
        # Login supply and its revision are atomic, even without an explicit command.
        f.restart();f.db.query(f"UPDATE characters SET hp=12,mp=4 WHERE id='{cid}'");p=connect()
        reserves=copy.deepcopy(p.state['gourds']);before=dbstate();f.restart();p=connect()
        check(dbstate()==before and p.state['character']['hp']==maxima['hp'] and p.state['character']['mp']==maxima['mp'],'Login recovery persists once across process restart')
        p.approach('spirit')
        cmd(p,'gourd_refill_hp','qingwei',error='RESIDENT_TOO_FAR')
        # Solo formation: seed damage before entry to ensure battle commands cannot heal it.
        f.db.query(f"UPDATE characters SET hp=80,mp=40 WHERE id='{cid}'")
        record(p.command('',request=dict(operation_id=str(uuid4()),action='challenge',target='spirit',encounter_version=2))[0])
        check(p.state['character']['hp']==80 and p.state['gourds']==reserves,'Starting a fight does not run supply inside the encounter')
        cmd(p,'gourd_enable',HP,error='BATTLE_ACTIVE');cmd(p,'gourd_refill_mp','qingwei',error='BATTLE_ACTIVE')
        p.command('guard');record(dict(type='pve.state',state=p.state))
        check(p.state['gourds']==reserves and p.state['battle']['outcome']=='active','Combat damage does not use either gourd')
        before=dbstate();f.restart();p=connect()
        check(dbstate()==before and p.state['gourds']==reserves,'Reconnect during an active battle cannot supply')
        f.db.query("CREATE FUNCTION reject_gourd_finish() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN IF NEW.gourd_state IS DISTINCT FROM OLD.gourd_state THEN RAISE EXCEPTION 'owned settlement rollback'; END IF; RETURN NEW; END$$; CREATE TRIGGER reject_gourd_finish BEFORE UPDATE ON characters FOR EACH ROW EXECUTE FUNCTION reject_gourd_finish();")
        last=dict(operation_id=str(uuid4()),action='flee',battle_id=p.state['battle']['id'],expected_revision=p.state['battle']['revision'])
        saved_battle=f.db.query(f"SELECT state FROM pve_battles WHERE id='{last['battle_id']}'")
        p.ws.send(dict(type='pve.command',command=last))
        check(p.until('error')['code']=='DATABASE_UNAVAILABLE' and dbstate()==before and f.db.query(f"SELECT state FROM pve_battles WHERE id='{last['battle_id']}'")==saved_battle,'Failed battle settlement rolls combat snapshot, health and reserve back together')
        f.db.query('DROP TRIGGER reject_gourd_finish ON characters; DROP FUNCTION reject_gourd_finish();')
        f.restart();p=connect();fled,last=p.command('',request=last);record(fled);world=p.state['character'];battle=p.state['battle']
        for id,resource in [(HP,'hp'),(MP,'mp')]:
            check(world[resource]==maxima[resource] and p.state['gourds'][id]['remaining']==reserves[id]['remaining']-world[resource]+battle[resource],'Flee supplies '+resource+' after retaining the combat snapshot')
        before=dbstate();record(p.command('',request=last)[0]);check(dbstate()==before,'Repeated final combat receipt cannot consume again')
        p.approach('spirit')
        record(p.command('',request=dict(operation_id=str(uuid4()),action='challenge',target='spirit',encounter_version=2))[0]);reserves=copy.deepcopy(p.state['gourds'])
        for turn in range(15):
            if p.state['battle']['outcome']!='active':break
            time.sleep(.065)
            record(p.command('',request=dict(operation_id=str(uuid4()),action='skill',target='sheet_004',battle_id=p.state['battle']['id'],expected_revision=p.state['battle']['revision']))[0] if turn==0 else p.command('attack')[0])
        check(p.state['battle']['outcome']=='victory','Real solo encounter reaches victory')
        check(p.state['character']['mp']==maxima['mp'] and p.state['gourds'][MP]['remaining']==reserves[MP]['remaining']-maxima['mp']+p.state['battle']['mp'],'Victory supplies exact spent mana after combat')
        # Both old consumable gourds retain their original one-dose behavior.
        cmd(p,'buy','original/ix22');cmd(p,'gourd_disable',HP)
        f.db.query(f"UPDATE characters SET hp=1 WHERE id='{cid}'")
        cmd(p,'use','original/ix22')
        check(p.state['character']['hp']==71 and 'original/ix22' not in p.state['shop']['owned'],'Existing red jade medicine remains a 70-HP consumable')
        cmd(p,'discard',HP);check(HP not in p.state['gourds'] and HP not in p.state['shop']['owned'],'Discard removes the container and its saved reserve atomically')
        cmd(p,'buy',HP)
        # Full bag and insufficient gold use the same transaction gates as existing goods.
        poor=f.create('gourd_poor');q=connect(poor);cmd(q,'buy',HP,error='GOLD_INSUFFICIENT')
        check(q.state['gourds']=={},'Insufficient funds creates no supply state')
        catalog=json.loads((ROOT/'client/assets/data/shop-v2.json').read_text())['items']
        bag=[i['id'] for i in catalog if i['id'].startswith('original/')][:58]
        f.db.query('INSERT INTO inventory_items(id,character_id,definition_id,quantity,equipped) VALUES '+','.join(f"(gen_random_uuid(),'{poor[1]}','{id}',1,false)" for id in bag))
        f.db.query(f"UPDATE characters SET gold=1000 WHERE id='{poor[1]}'")
        q.close();time.sleep(.2);q=connect(poor);cmd(q,'buy',HP,error='BAG_FULL')
        check(q.state['gourds']=={} and q.state['character']['gold']==1000,'Full backpack refuses a container without creating reserve or debiting gold')
        # AI provider and endless encounter use the same automatic settlement.
        endless=f.create('gourd_trial',1);eid=endless[1]
        f.db.query(f"UPDATE characters SET map_id='ai_001',cell_x=5,cell_y=16,level=15,hp=300,mp=120,gold=1000,allocated_attributes=ARRAY[15,0,45,15,0] WHERE id='{eid}'")
        e=connect(endless);cmd(e,'buy',HP);cmd(e,'buy',MP)
        e.approach('ai_001_guide');cmd(e,'gourd_refill_hp','ai_001_guide');cmd(e,'gourd_refill_mp','ai_001_guide')
        check(e.state['gourds'][HP]['remaining']==10000 and e.state['gourds'][MP]['remaining']==5000,'Current AI map guide fills both containers')
        rules=json.loads((ROOT/'shared/data/endless-v1.json').read_text());e.approach(rules['npc']['id'])
        cmd(e,'endless',rules['npc']['id'],encounter_version=2);reserve=copy.deepcopy(e.state['gourds'])
        for _ in range(20):
            if e.state['battle']['outcome']!='active':break
            time.sleep(.065);record(e.command('attack')[0])
            if e.state['battle']['outcome']=='active':check(e.state['gourds']==reserve,'Endless live rounds do not use reserves')
        check(e.state['battle']['outcome']=='victory' and e.state['endless']['progress']['best']==1,'Endless win and progress commit with postbattle supply')
        check(e.state['character']['hp']==e.state['stats']['hp'],'Endless victory supplies the surviving character')
        # Defeat cannot use the full reserve to revive a dead character.
        f.db.query(f"UPDATE characters SET hp=1 WHERE id='{eid}'")
        cmd(e,'endless',rules['npc']['id'],encounter_version=2);reserve=copy.deepcopy(e.state['gourds'])
        for _ in range(20):
            if e.state['battle']['outcome']!='active':break
            time.sleep(.065);record(e.command('guard')[0])
        check(e.state['battle']['outcome']=='defeat' and e.state['character']['hp']==0 and e.state['gourds']==reserve,'Death leaves all remaining reserve untouched')
        cmd(e,'gourd_refill_hp','ai_001_guide',error='SOUL_STATE')
        e.close();time.sleep(.2);e=connect(endless)
        check(e.state['character']['corpse'] is not None and e.state['gourds']==reserve,'Soul reconnect cannot trigger either supply')
        # Team rounds write character resources each turn; only settlement may supply.
        members=[f.create('gourd_team_'+str(i),1) for i in range(2)];peers=[]
        for identity in members:
            f.db.query(f"UPDATE characters SET gold=1000,level=60,hp=1000,mp=480,quest_stage=1,cell_x=22,cell_y=9 WHERE id='{identity[1]}'")
            peer=connect(identity);peers.append(peer);cmd(peer,'buy',HP);cmd(peer,'buy',MP)
        def team(identity,action,**fields):
            time.sleep(.065)
            status,value=api(f.base,'/api/v1/teams',dict(character_id=identity[1],action=action,operation_id=str(uuid4()),**fields),identity[0]['access_token'])
            assert status==200 and value['ok'],value
            return value
        team(members[0],'invite',target=members[1][1]);offer=team(members[1],'snapshot')['state']['incoming'][0]['id'];team(members[1],'accept',target=offer)
        for identity in members:f.db.query(f"UPDATE characters SET hp=100,mp=40 WHERE id='{identity[1]}'")
        original=[json.loads(f.db.query(f"SELECT gourd_state FROM characters WHERE id='{i[1]}'")) for i in members]
        team(members[1],'ready',ready=True)
        battle=team(members[0],'challenge',target='spirit',encounter_version=2)['state']['team']['battle']
        cmd(peers[0],'gourd_enable',HP,error='TEAM_BATTLE_ACTIVE')
        for _ in range(20):
            if battle['outcome']!='active':break
            f.db.query("UPDATE team_battles SET state=jsonb_set(state,'{selection_starts_ms}',to_jsonb((extract(epoch FROM statement_timestamp())*1000)::bigint-1)) WHERE active")
            revision=battle['revision'];target=next(e['slot'] for e in battle['enemies'] if e['hp']>0)
            for identity in members:
                battle=team(identity,'attack',target=target,battle_id=battle['id'],expected_revision=revision)['state']['team']['battle']
                if battle['outcome']=='active':
                    check([json.loads(f.db.query(f"SELECT gourd_state FROM characters WHERE id='{i[1]}'")) for i in members]==original,'Shared battle snapshots do not refill between players or rounds')
        check(battle['outcome']=='victory','Real two-player fight reaches victory')
        for i,identity in enumerate(members):
            fighter=next(x for x in battle['fighters'] if x['id']==identity[1])
            saved=json.loads(f.db.query(f"SELECT json_build_object('hp',hp,'mp',mp,'gourds',gourd_state) FROM characters WHERE id='{identity[1]}'"))
            check(saved['hp']==fighter['stats']['hp'] and saved['gourds'][HP]['remaining']==original[i][HP]['remaining']-saved['hp']+fighter['hp'],'Team settlement supplies survivor exactly once after frozen battle snapshot')
            peers[i].close();time.sleep(.2);connect(identity)
        # PK uses independent combat resources; neither damage nor exit consumes supplies.
        from run_duels import DuelPlayer
        duelists=[f.create('gourd_duel_'+str(i),i) for i in range(2)];duel_peers=[]
        for identity in duelists:
            f.db.query(f"UPDATE characters SET gold=1000 WHERE id='{identity[1]}'")
            d=DuelPlayer(f.base,*identity);f.clients.append(d);duel_peers.append(d);cmd(d,'buy',HP);cmd(d,'buy',MP)
        da,db=duel_peers;da.duel('invite',target=db.id)
        invitation=db.synced(lambda s:s.get('incoming') is not None)['incoming']['id'];db.duel('accept',invite_id=invitation)
        arena=da.synced(lambda s:s.get('battle') is not None and s['battle']['status']=='active')['battle']
        db.synced(lambda s:s.get('battle') is not None and s['battle']['id']==arena['id'])
        before=[dbstate(identity[1]) for identity in duelists]
        cmd(da,'gourd_enable',HP,error='DUEL_ACTIVE')
        da.duel('attack',battle_id=arena['id'],expected_revision=arena['decision_revision']);db.duel('attack',battle_id=arena['id'],expected_revision=arena['decision_revision'])
        arena=da.synced(lambda s:s['battle']['resolved_round']==1)['battle']
        check([dbstate(identity[1]) for identity in duelists]==before,'Duel damage does not persist HP changes or spend either reserve')
        da.duel('flee',battle_id=arena['id'],expected_revision=arena['decision_revision'])
        check([dbstate(identity[1]) for identity in duelists]==before,'Leaving an isolated duel does not create a second supply consumption')
        check(int(f.db.query("SELECT count(*) FROM security_audit WHERE action LIKE 'pve.gourd_%' AND details->'after'->'gourds' IS NOT NULL"))>0,'Gourd changes retain readable reserve values in authoritative audit')
    output=ROOT/'work/gourds';output.mkdir(parents=True,exist_ok=True)
    (output/'server-fixtures.json').write_text(json.dumps(packets,ensure_ascii=False))
    print(f'GOURDS SERVER: {len(checks)} checks, 0 failures')

if __name__=='__main__':main()
