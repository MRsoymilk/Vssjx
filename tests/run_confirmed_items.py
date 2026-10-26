"""Confirmed medicine and stone mappings through an owned server and database."""
from uuid import uuid4
import time
from balance_fixture import BalanceFixture
from run_online_maps import MapPlayer

MEDICINES = [(10,'生骨融血草',8000,0,10),(14,'极品人参',0,4000,10),
    (15,'金疮药',500,0,5),(16,'小金疮药',800,0,10),(17,'中金疮药',1000,0,8),(18,'大金疮药',1500,0,14),(26,'荷叶烧鸡',6000,0,6)]
STONES = [(31,'敏捷石'),(32,'力量石'),(33,'体质石'),(34,'灵性石'),(35,'定力石')]


def main():
    checks = 0
    def check(ok,label):
        nonlocal checks
        assert ok,label
        checks += 1

    with BalanceFixture() as fixture:
        identity = fixture.create('item_probe')
        cid = identity[1]
        fixture.db.query(f"UPDATE characters SET level=60,gold=10000,hp=1,mp=7 WHERE id='{cid}'")
        for spec in MEDICINES + STONES:
            fixture.db.query(f"INSERT INTO inventory_items(id,character_id,definition_id,quantity,equipped) VALUES('{uuid4()}','{cid}','original/ix{spec[0]}',2,false)")
        def connect():
            p = MapPlayer(fixture.base,*identity,shop_version=2)
            fixture.clients.append(p)
            return p
        player = connect()
        def command(action,item,ok=True,request=None):
            time.sleep(.065)
            return player.command('',request=request or dict(operation_id=str(uuid4()),action=action,target=item,
                expected_revision=player.state['character']['state_revision']),ok=ok)

        for number,name,hp,mp,price in MEDICINES:
            item = f'original/ix{number}'
            maxima = player.state['stats']
            player.close();time.sleep(.15)
            previous_hp = maxima['hp'] - 1 if hp else 1
            previous_mp = maxima['mp'] - 1 if mp else 7
            fixture.db.query(f"UPDATE characters SET hp={previous_hp},mp={previous_mp} WHERE id='{cid}'")
            player = connect()
            check(player.state['shop']['quantities'][item]==2,'Existing quantity: '+item)
            gold = player.state['character']['gold']
            result,_ = command('buy',item)
            check(result['state']['character']['gold']==gold-price and any(name in line for line in result['lines']),'Correct purchase identity and price: '+item)
            result,receipt = command('use',item)
            character = result['state']['character']
            check(character['hp']==min(maxima['hp'],previous_hp+hp) and character['mp']==min(maxima['mp'],previous_mp+mp),'Only intended resource restored and capped: '+item)
            check(result['state']['shop']['quantities'][item]==2,'One item consumed: '+item)
            refused,_ = command('use',item,False)
            check(refused['code']=='HP_FULL' and refused['state']['shop']['quantities'][item]==2,'Full resource does not consume: '+item)
            replay,_ = command('use',item,request=receipt)
            check(replay['replayed'] and replay['state']==result['state'],'Retry replays the same use: '+item)

        for number,name in STONES:
            item = f'original/ix{number}'
            before = player.state['attributes']['allocated'][:]
            result,_ = command('buy',item)
            check(any(name in line for line in result['lines']) and result['state']['shop']['quantities'][item]==3,'Named stone purchase stacks with old inventory: '+item)
            refused,_ = command('use',item,False)
            check(refused['code']=='ITEM_NOT_USABLE' and refused['state']['shop']['quantities'][item]==3 and refused['state']['attributes']['allocated']==before,'Stone remains material without invented bonuses: '+item)
        fixture.restart();player = connect()
        for spec in MEDICINES + STONES:
            item = f'original/ix{spec[0]}'
            quantity = 2 if spec in MEDICINES else 3
            check(player.state['shop']['quantities'][item]==quantity,'Inventory survives restart: '+item)
            check(fixture.db.query(f"SELECT quantity FROM inventory_items WHERE character_id='{cid}' AND definition_id='{item}'")==str(quantity),'Original ID remains durable: '+item)
    print(f'CONFIRMED ITEMS SERVER: {checks} checks, 0 failures',flush=True)


if __name__=='__main__':main()
