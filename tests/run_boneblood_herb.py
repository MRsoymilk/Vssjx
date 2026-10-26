"""Confirm existing ix10 inventory works as medicine in an owned temporary server."""
import sys
from uuid import uuid4
from balance_fixture import BalanceFixture
from run_online_maps import MapPlayer

ID = 'original/ix10'


def main(item_id=ID, restore_hp=8000, restore_mp=0, price=10):
    item = item_id
    checks = []

    def check(ok, label):
        assert ok, label
        checks.append(label)

    with BalanceFixture() as fixture:
        identity = fixture.create('herb_test')
        cid = identity[1]
        fixture.db.query(f"UPDATE characters SET gold=100,hp=1,mp=7 WHERE id='{cid}'; INSERT INTO inventory_items(id,character_id,definition_id,quantity,equipped) VALUES('{uuid4()}','{cid}','{item}',2,false)")

        def connect():
            player = MapPlayer(fixture.base, *identity, shop_version=2)
            fixture.clients.append(player)
            return player

        def command(action, ok=True, request=None):
            return player.command('', request=request or dict(operation_id=str(uuid4()), action=action,
                target=item, expected_revision=player.state['character']['state_revision']), ok=ok)

        player = connect()
        check(player.state['shop']['quantities'][item] == 2, 'Existing material inventory retains its ID and quantity')
        result, _ = command('buy')
        check(result['state']['character']['gold'] == 100-price and result['state']['shop']['quantities'][item] == 3,
              'Shop sells the same item for its preserved price')
        result, receipt = command('use')
        check(result['state']['character']['hp'] == min(1+restore_hp, result['state']['stats']['hp']) and result['state']['character']['mp'] == min(7+restore_mp,result['state']['stats']['mp']),
              'Authoritative consumer restores the fixed amount to the correct resource')
        check(result['state']['shop']['quantities'][item] == 2, 'One use consumes exactly one')
        refused, _ = command('use', False)
        check(refused['code'] == 'HP_FULL' and refused['state']['shop']['quantities'][item] == 2,
              'Full resource refuses use without wasting inventory')
        replay, _ = command('use', request=receipt)
        check(replay['replayed'] and replay['state'] == result['state'], 'A retried use only replays its receipt')
        fixture.restart()
        player = connect()
        check(player.state['shop']['quantities'][item] == 2 and all(player.state['character'][key] == result['state']['character'][key] for key in ['hp','mp']),
              'Restart preserves resources and remaining medicine')
        check(fixture.db.query(f"SELECT quantity FROM inventory_items WHERE character_id='{cid}' AND definition_id='{item}'") == '2',
              'Database stores the unchanged original item ID')
    print(f'MEDICINE SERVER ({item}): {len(checks)} checks, 0 failures')


if __name__ == '__main__':
    if sys.argv[1:]==['--ginseng']:
        main('original/ix14',0,4000)
    elif sys.argv[1:]==['--chicken']:
        main('original/ix26',6000,0,6)
    else:
        main()
