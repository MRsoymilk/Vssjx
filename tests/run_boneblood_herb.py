"""Confirm existing ix10 inventory works as medicine in an owned temporary server."""
from uuid import uuid4
from balance_fixture import BalanceFixture
from run_online_maps import MapPlayer

ID = 'original/ix10'


def main():
    checks = []

    def check(ok, label):
        assert ok, label
        checks.append(label)

    with BalanceFixture() as fixture:
        identity = fixture.create('herb_test')
        cid = identity[1]
        fixture.db.query(f"UPDATE characters SET gold=100,hp=1,mp=7 WHERE id='{cid}'; INSERT INTO inventory_items(id,character_id,definition_id,quantity,equipped) VALUES('{uuid4()}','{cid}','{ID}',2,false)")

        def connect():
            player = MapPlayer(fixture.base, *identity, shop_version=2)
            fixture.clients.append(player)
            return player

        def command(action, ok=True, request=None):
            return player.command('', request=request or dict(operation_id=str(uuid4()), action=action,
                target=ID, expected_revision=player.state['character']['state_revision']), ok=ok)

        player = connect()
        check(player.state['shop']['quantities'][ID] == 2, 'Existing material inventory retains its ID and quantity')
        result, _ = command('buy')
        check(result['state']['character']['gold'] == 90 and result['state']['shop']['quantities'][ID] == 3,
              'Shop sells the same item for 10 copper')
        result, receipt = command('use')
        check(result['state']['character']['hp'] == min(8001, result['state']['stats']['hp']) and result['state']['character']['mp'] == 7,
              'Authoritative consumer heals up to 8000 without changing MP')
        check(result['state']['shop']['quantities'][ID] == 2, 'One use consumes exactly one')
        refused, _ = command('use', False)
        check(refused['code'] == 'HP_FULL' and refused['state']['shop']['quantities'][ID] == 2,
              'Full health refuses use without wasting inventory')
        replay, _ = command('use', request=receipt)
        check(replay['replayed'] and replay['state'] == result['state'], 'A retried use only replays its receipt')
        fixture.restart()
        player = connect()
        check(player.state['shop']['quantities'][ID] == 2 and player.state['character']['hp'] == result['state']['character']['hp'],
              'Restart preserves healed HP and remaining herbs')
        check(fixture.db.query(f"SELECT quantity FROM inventory_items WHERE character_id='{cid}' AND definition_id='{ID}'") == '2',
              'Database stores the unchanged original item ID')
    print(f'BONEBLOOD HERB SERVER: {len(checks)} checks, 0 failures')


if __name__ == '__main__':
    main()
