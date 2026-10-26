"""Owned DB: real settlements, global notices, rankings, retries and rollback."""
import json,time
from uuid import uuid4
from balance_fixture import BalanceFixture,ROOT
from run_online_pve import api
from run_loot_instances import LootPlayer
from chat_checks import ChatProbe


def main():
    checks=0
    def check(value,label):
        nonlocal checks
        assert value,label
        checks+=1;print('PASS: '+label,flush=True)
    with BalanceFixture() as f:
        identity=f.create('board_user',1);watcher=f.create('board_watch',2);cid=identity[1]
        f.db.query(f"UPDATE characters SET level=15,map_id='ai_001',cell_x=11,cell_y=15 WHERE id='{cid}'")
        def connect(who):
            p=LootPlayer(f.base,*who);f.clients.append(p);return p
        p=connect(identity);watch=connect(watcher);probe=ChatProbe(watch.ws)
        def board(who=identity,character=cid):
            code,value=api(f.base,'/api/v1/endless/leaderboard',{'character_id':character},who[0]['access_token'])
            assert code==200,value
            return value['leaderboard']
        check(board()['entries']==[] and board()['self']=={'rank':None,'best':0},'Empty board and unranked personal record')
        code,_=api(f.base,'/api/v1/endless/leaderboard',{'character_id':cid});check(code==401,'Authentication is required')
        code,_=api(f.base,'/api/v1/endless/leaderboard',{'character_id':watcher[1]},identity[0]['access_token']);check(code==403,'Personal rank lookup requires character ownership')
        def begin(stage,best):
            nonlocal p
            p.close();time.sleep(.15)
            progress=dict(stage=stage,best=best,level=15,in_progress=False)
            f.db.query(f"UPDATE characters SET endless_state=$owned${json.dumps(progress)}$owned$::jsonb,hp={p.state['stats']['hp']},mp={p.state['stats']['mp']} WHERE id='{cid}'")
            p=connect(identity)
            p.command('',request=dict(operation_id=str(uuid4()),action='endless',target='ai_001_endless',expected_revision=p.state['character']['state_revision'],encounter_version=2))
            bid=p.state['battle']['id'];b=json.loads(f.db.query(f"SELECT state FROM pve_battles WHERE id='{bid}'"));enemy=b['formation']['enemies'][0]
            # Lower only our owned fixture opponent; production definitions stay untouched.
            enemy['hp']=b['enemy_hp']=1;enemy['definition']['attack']=b['enemy']['attack']=1
            enemy['definition']['defense']=b['enemy']['defense']=0
            f.db.query(f"UPDATE pve_battles SET state=$owned${json.dumps(b)}$owned$::jsonb WHERE id='{b['id']}'")
        def win(request=None):
            last=request
            for _ in range(20):
                result,last=p.command('',request=last or dict(operation_id=str(uuid4()),action='attack',enemy_slot='m0',battle_id=p.state['battle']['id'],expected_revision=p.state['battle']['revision']))
                if result['state']['battle']['outcome']=='victory':return result,last
                last=None
            raise AssertionError('Owned enemy did not settle')
        def notice(stage):
            probe.until(lambda packet:any(m.get('system') and f'第{stage}层' in m['text'] for m in probe.messages))
            matches=[m for m in probe.messages if m.get('system') and f'第{stage}层' in m['text']]
            check(len(matches)==1 and 'board_user' in matches[0]['text'] and matches[0]['channel']=='public','Exactly one global system notice at '+str(stage))
        begin(100,99)
        f.db.query("CREATE FUNCTION owned_reject_milestone() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'owned milestone rollback'; END$$; CREATE TRIGGER owned_reject_milestone BEFORE INSERT ON endless_milestones FOR EACH ROW EXECUTE FUNCTION owned_reject_milestone();")
        failed=None
        for _ in range(20):
            command=dict(operation_id=str(uuid4()),action='attack',enemy_slot='m0',battle_id=p.state['battle']['id'],expected_revision=p.state['battle']['revision'])
            try:p.command('',request=command)
            except AssertionError as error:
                assert error.args[0]['code']=='DATABASE_UNAVAILABLE',error.args
                failed=command;break
        check(failed is not None,'Winning milestone transaction is fault injected')
        check(f.db.query('SELECT count(*) FROM endless_records')=='0' and f.db.query('SELECT count(*) FROM endless_milestones')=='0','Record and notice both roll back with the failed win')
        f.db.query('DROP TRIGGER owned_reject_milestone ON endless_milestones; DROP FUNCTION owned_reject_milestone();')
        f.restart();p=connect(identity);watch=connect(watcher);probe=ChatProbe(watch.ws)
        result,receipt=win(failed);notice(100)
        check(board()['self']=={'rank':1,'best':100},'Actual victory ranks the cleared stage, not next stage')
        replay,_=p.command('',request=receipt);check(replay['replayed'],'Winning operation is replayed')
        check(f.db.query('SELECT count(*) FROM endless_milestones')=='1','Replay cannot enqueue another notice')
        begin(101,100);win();check(board()['self']['best']==101 and f.db.query('SELECT count(*) FROM endless_milestones')=='1','Non-milestone new best updates rank without a notice')
        begin(110,109);win();notice(110)
        achieved=f.db.query(f"SELECT achieved_at FROM endless_records WHERE character_id='{cid}'")
        begin(100,110);win()
        check(f.db.query('SELECT count(*) FROM endless_milestones')=='2' and f.db.query(f"SELECT achieved_at FROM endless_records WHERE character_id='{cid}'")==achieved,'Re-clearing an old milestone neither spams nor changes tie order')
        begin(120,119);p.command('flee')
        check(f.db.query('SELECT count(*) FROM endless_milestones')=='2','Retreat cannot announce a milestone')
        begin(120,119);win();notice(120)
        f.restart();p=connect(identity)
        check(board()['self']=={'rank':1,'best':120},'Rank survives a server restart')
        check(f.db.query('SELECT count(*) FROM endless_milestones WHERE announced_at IS NULL')=='0','Processed milestones remain deduplicated after restart')
        # Bulk seed only disposable records to exercise a rank beyond the top 100.
        f.db.query(f"""DO $owned$ DECLARE i integer; aid uuid; cid_new uuid; BEGIN FOR i IN 1..105 LOOP
          aid:=gen_random_uuid();cid_new:=gen_random_uuid();
          INSERT INTO accounts SELECT (jsonb_populate_record(NULL::accounts,to_jsonb(a)||jsonb_build_object('id',aid,'username','board_seed_'||i))).* FROM accounts a WHERE a.id=(SELECT account_id FROM characters WHERE id='{watcher[1]}');
          INSERT INTO characters SELECT (jsonb_populate_record(NULL::characters,to_jsonb(c)||jsonb_build_object('id',cid_new,'account_id',aid,'slot',0,'display_name','rank_'||lpad(i::text,3,'0'),'name_key','rank_'||lpad(i::text,3,'0'),'endless_state',jsonb_build_object('stage',1,'best',200,'level',0,'in_progress',false)))).* FROM characters c WHERE c.id='{watcher[1]}';
          INSERT INTO endless_records(character_id,best,achieved_at) VALUES(cid_new,200,timestamp '2000-01-01'+i*interval '1 second');
        END LOOP; END $owned$;""")
        final=board()
        check(len(final['entries'])==100 and final['total']==106 and final['self']=={'rank':106,'best':120},'Top 100 is bounded while personal rank works beyond the list')
        check(final['entries'][0]['display_name']=='rank_001' and final['entries'][-1]['display_name']=='rank_100','Equal clears use earlier record time as the tie breaker')
        f.db.query("UPDATE characters SET deleted_at=clock_timestamp() WHERE display_name='rank_001'; UPDATE accounts SET disabled=true WHERE username='board_seed_2';")
        final=board();check(final['total']==104 and final['self']['rank']==104 and final['entries'][0]['display_name']=='rank_003','Deleted characters and disabled accounts are excluded')
        output=ROOT/'work/endless-board-server.json';output.write_text(json.dumps(final,ensure_ascii=False,indent=2),'utf8')
    print(f'ENDLESS LEADERBOARD SERVER: {checks} checks, 0 failures',flush=True)


if __name__=='__main__':main()
