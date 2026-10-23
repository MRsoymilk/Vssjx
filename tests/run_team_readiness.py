"""Two persistent participation states, exercised only in a disposable database."""
import os
import time
from uuid import uuid4
from balance_fixture import BalanceFixture, ROOT
from run_loot_instances import LootPlayer
from run_online_pve import api


def main():
    checks=[]
    def check(ok,text):
        assert ok,text
        checks.append(text)
    with BalanceFixture() as f:
        a,b=[f.create('ready_'+name,1) for name in ('a','b')]
        players=[]
        for who in (a,b):
            f.db.query(f"UPDATE characters SET level=60,hp=1000,mp=480,quest_stage=1,cell_x=22,cell_y=9 WHERE id='{who[1]}'")
        def connect():
            players.clear()
            for who in (a,b):
                player=LootPlayer(f.base,*who);players.append(player);f.clients.append(player)
        connect()
        def send(who,action,expected='OK',**fields):
            for player in players:player.ws.send({'type':'ping'})
            payload=dict(character_id=who[1],action=action,**fields)
            if action!='snapshot':payload['operation_id']=str(uuid4())
            status,result=api(f.base,'/api/v1/teams',payload,who[0]['access_token'])
            check(status==200 and result['code']==expected,action+': '+expected)
            return result['state']['team']
        send(a,'invite',target=b[1])
        _,snap=api(f.base,'/api/v1/teams',dict(character_id=b[1],action='snapshot'),b[0]['access_token'])
        party=send(b,'accept',target=snap['state']['incoming'][0]['id'])
        def member(party,who):return next(m for m in party['members'] if m['id']==who[1])
        check(member(party,a)['ready'] and member(party,a)['following'],'Leader is always prepared')
        check(member(party,b)['ready'] and member(party,b)['following'],'A new member defaults to prepared and following')
        f.db.query(f"UPDATE team_members SET ready=FALSE,following=TRUE WHERE character_id='{b[1]}'")
        f.db.query((ROOT/'server/migrations/0033_team_participation_states.sql').read_text())
        party=send(b,'snapshot')
        check(member(party,b)['ready'] and member(party,b)['following'],'Migration removes the old unready-following state by preparing default followers')
        party=send(b,'follow',ready=True)
        check(member(party,b)['ready'] and member(party,b)['following'],'Legacy follow is an alias of preparation')
        party=send(b,'ready',ready=False)
        check(not member(party,b)['ready'] and not member(party,b)['following'],'One away action also releases manual movement')
        party=send(b,'ready',ready=True)
        time.sleep(.5)
        for _ in range(2):
            party=send(a,'challenge',target='spirit',encounter_version=2);battle=party['battle']
            check(len(battle['fighters'])==2,'The same prepared follower joins successive encounters')
            party=send(a,'flee',battle_id=battle['id'],expected_revision=battle['revision'])
            check(member(party,b)['ready'] and member(party,b)['following'],'Ending an encounter preserves the standing preference')
        for player in players:player.close()
        f.restart();connect();party=send(b,'snapshot')
        check(member(party,b)['ready'] and member(party,b)['following'],'Readiness survives server restart and real socket rejoin')
        send(b,'ready',ready=False);party=send(a,'transfer',target=b[1])
        check(member(party,b)['leader'] and member(party,b)['ready'] and member(party,b)['following'],'Promoting an away member makes the new leader prepared')
        send(b,'ready','TEAM_MEMBER_REQUIRED',ready=False)
        send(b,'disband')
    print(f'TEAM READINESS: {len(checks)} checks, 0 failures')


if __name__=='__main__':main()
