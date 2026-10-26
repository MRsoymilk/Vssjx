"""Escrow/auction integration against an owned PostgreSQL and real HTTP/WS service."""
import copy
import json
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from uuid import uuid4
from balance_fixture import BalanceFixture, ROOT
from run_online_pve import api
from run_loot_instances import LootPlayer


def main():
    checks = []
    snapshots = []

    def check(ok, label):
        assert ok, label
        checks.append(label)

    prototype = copy.deepcopy(json.loads(Path('/tmp/opencode/loot-vectors.json').read_text())[0]['item'])
    prototype.update(template='original/if2', equipped=False, bound=False, legacy=False, level=1, quality='white', affixes=[])

    with BalanceFixture() as f:
        identities = [f.create('eco_' + name, 0) for name in ['seller', 'buyer', 'rival']]
        ids = [x[1] for x in identities]
        items = []
        for index, (_, cid) in enumerate(identities):
            state = dict(version=1, items=[], pending=[], scrap=0, essence=0, kills=0, bosses=0, difficulty=1, skins=[])
            if index == 0:
                for _ in range(8):
                    item = copy.deepcopy(prototype); item['id'] = str(uuid4()); state['items'].append(item); items.append(item)
                state['items'][-1]['bound'] = True
            f.db.query(f"UPDATE characters SET gold=10000,loot_state='{json.dumps(state)}'::jsonb WHERE id='{cid}'")

        def connect_all():
            for identity in identities:
                player = LootPlayer(f.base, *identity); f.clients.append(player)

        connect_all()

        def call(who, action='snapshot', request=None, status=200, **values):
            payload = request or (dict(character_id=ids[who], action=action) | values)
            if action != 'snapshot' and 'operation_id' not in payload: payload['operation_id'] = str(uuid4())
            code, data = api(f.base, '/api/v1/economy', payload, identities[who][0]['access_token'])
            assert code == status, (code, data, payload)
            if code == 200: snapshots.append(copy.deepcopy(data))
            return data, payload

        def listing(who, item, start=100, buyout=500):
            result, request = call(who, 'list', target=item['id'], amount=start, buyout=buyout, hours=6)
            assert result['ok'], result
            return next(l for l in result['market']['listings'] if l['id'] == result['id']), request

        result, _ = call(1, 'list', target=items[0]['id'], amount=100, buyout=500, hours=6)
        check(result['code'] == 'INSTANCE_NOT_OWNED', 'Cannot escrow another character UUID')
        result, _ = call(0, 'list', target=items[-1]['id'], amount=100, buyout=500, hours=6)
        check(result['code'] == 'EQUIPMENT_BOUND', 'Bound historical equipment cannot be auctioned')
        first, request = listing(0, items[0])
        state, _ = call(0)
        check(not any(i['id'] == items[0]['id'] for i in state['state']['loot']['state']['items']), 'Listing removes the exact unbound instance into durable escrow')
        replay, _ = call(0, 'list', request=request)
        check(replay['replayed'] and replay['id'] == first['id'], 'Lost-response retry does not duplicate an auction')
        changed = dict(request, amount=101)
        call(0, 'list', request=changed, status=409)
        check(True, 'Reusing an operation UUID with a changed price is rejected')
        result, _ = call(0, 'buy', target=first['id'], revision=int(first['revision']))
        check(result['code'] == 'AUCTION_SELF_BUY', 'Sellers cannot bid on or buy their own auction')
        result, _ = call(1, 'bid', target=first['id'], revision=int(first['revision']), amount=100)
        check(result['ok'] and result['state']['character']['gold'] == 9900, 'A valid bid holds currency exactly once')
        current = next(l for l in result['market']['listings'] if l['id'] == first['id'])
        result, _ = call(0, 'cancel', target=first['id'], revision=int(current['revision']))
        check(result['code'] == 'AUCTION_HAS_BIDS', 'A seller cannot withdraw an auction after a bid')
        result, _ = call(2, 'bid', target=first['id'], revision=int(current['revision']), amount=101)
        check(result['code'] == 'BID_TOO_LOW', 'Minimum increment is five percent rounded up')
        result, _ = call(2, 'bid', target=first['id'], revision=int(current['revision']), amount=105)
        check(result['ok'], 'An outbid creates a durable refund for the former high bidder')
        refunded, _ = call(1)
        refund = next(d for d in refunded['market']['deliveries'] if d['reason'] == 'outbid_refund')
        result, request = call(1, 'claim', target=refund['id'])
        check(result['state']['character']['gold'] == 10000, 'Refund is credited only when claimed')
        replay, _ = call(1, 'claim', request=request)
        check(replay['replayed'] and replay['state']['character']['gold'] == 10000, 'Refund claim replay cannot mint currency')
        current = next(l for l in result['market']['listings'] if l['id'] == first['id'])
        result, _ = call(2, 'buy', target=first['id'], revision=int(current['revision']))
        check(result['ok'] and result['state']['character']['gold'] == 9500, 'High bidder buying out pays only the remaining difference')
        delivery = next(d for d in result['market']['deliveries'] if d['item'] is not None)
        result, _ = call(2, 'claim', target=delivery['id'])
        received = next(i for i in result['state']['loot']['state']['items'] if i['id'] == items[0]['id'])
        check(received == items[0] and not received['bound'], 'Auction preserves UUID, affixes and unbound status for the buyer')
        seller, _ = call(0); sale = next(d for d in seller['market']['deliveries'] if d['reason'] == 'auction_sale')
        result, _ = call(0, 'claim', target=sale['id'])
        check(result['state']['character']['gold'] == 10500, 'Seller receives exactly the sale price without hidden fees')
        second, _ = listing(0, items[1])
        def buy(who): return call(who, 'buy', target=second['id'], revision=int(second['revision']))[0]
        with ThreadPoolExecutor(2) as pool: outcomes = list(pool.map(buy, [1, 2]))
        check(sum(r['ok'] for r in outcomes) == 1, 'Simultaneous buyers produce one winner and one charge')
        third, _ = listing(0, items[2])
        result, _ = call(1, 'bid', target=third['id'], revision=int(third['revision']), amount=100)
        f.db.query(f"UPDATE auction_listings SET expires_at=clock_timestamp()-interval '1 second' WHERE id='{third['id']}'")
        result, _ = call(1)
        check(any(d['item'] and d['item']['id'] == items[2]['id'] for d in result['market']['deliveries']), 'Expiry settles the high bid into an item delivery')
        fourth, _ = listing(0, items[3])
        f.db.query(f"UPDATE auction_listings SET expires_at=clock_timestamp()-interval '1 second' WHERE id='{fourth['id']}'")
        result, _ = call(0)
        check(any(d['item'] and d['item']['id'] == items[3]['id'] for d in result['market']['deliveries']), 'An unsold expired auction returns its unchanged instance')
        fifth, _ = listing(0, items[4]); result, _ = call(0, 'cancel', target=fifth['id'], revision=int(fifth['revision']))
        check(result['ok'], 'Unbid auctions may be cancelled and returned through delivery')
        before = f.db.query(f"SELECT loot_state,gold FROM characters WHERE id='{ids[0]}'")
        f.db.query("CREATE FUNCTION reject_market() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'owned rollback'; END$$; CREATE TRIGGER reject_market BEFORE UPDATE ON characters FOR EACH ROW EXECUTE FUNCTION reject_market();")
        failed = dict(character_id=ids[0], action='list', operation_id=str(uuid4()), target=items[5]['id'], amount=100, buyout=500, hours=6)
        call(0, 'list', request=failed, status=503)
        check(f.db.query(f"SELECT loot_state,gold FROM characters WHERE id='{ids[0]}'") == before, 'Commit failure rolls back equipment removal, listing, audit and receipt')
        f.db.query('DROP TRIGGER reject_market ON characters; DROP FUNCTION reject_market();')
        result, _ = call(0, 'list', request=failed)
        check(result['ok'] and not result['replayed'], 'An uncommitted operation retries under the original UUID')
        full, _ = call(1); saved_loot = copy.deepcopy(full['state']['loot']['state'])
        crowded = copy.deepcopy(saved_loot)
        while sum(not i['legacy'] and not i['equipped'] for i in crowded['items']) < 59:
            item = copy.deepcopy(prototype); item['id'] = str(uuid4()); crowded['items'].append(item)
        while len(crowded['pending']) < 20:
            item = copy.deepcopy(prototype); item['id'] = str(uuid4()); crowded['pending'].append(item)
        delivery = next(d for d in full['market']['deliveries'] if d['item'] is not None)
        f.db.query(f"UPDATE characters SET loot_state='{json.dumps(crowded)}'::jsonb WHERE id='{ids[1]}'")
        result, _ = call(1, 'claim', target=delivery['id'])
        check(result['code'] == 'LOOT_STORAGE_FULL' and any(d['id'] == delivery['id'] for d in result['market']['deliveries']), 'Full bag and pending storage never lose a delivery')
        f.db.query(f"UPDATE characters SET loot_state='{json.dumps(saved_loot)}'::jsonb WHERE id='{ids[1]}'")
        result, _ = call(0); cash = next(d for d in result['market']['deliveries'] if d['gold'] > 0)
        balance = result['state']['character']['gold']
        f.db.query(f"UPDATE characters SET gold=2147483647 WHERE id='{ids[0]}'")
        result, _ = call(0, 'claim', target=cash['id'])
        check(result['code'] == 'GOLD_LIMIT' and any(d['id'] == cash['id'] for d in result['market']['deliveries']), 'Wallet overflow retains the unclaimed proceeds')
        f.db.query(f"UPDATE characters SET gold={balance} WHERE id='{ids[0]}'")
        f.restart(); connect_all()
        result, _ = call(0, 'list', request=failed)
        check(result['replayed'], 'Receipt and escrow survive a real process restart')
        result, _ = call(0, 'snapshot', character_id=ids[1], status=403)
        check(True, 'Authenticated users cannot access another account economy')
        result, _ = call(0, job=2, slot='weapon', quality='yellow')
        check(not result['market']['listings'], 'Explicit buyer filters do not fabricate incompatible listings')
    output = ROOT / 'work/economy'; output.mkdir(parents=True, exist_ok=True)
    (output / 'server-fixtures.json').write_text(json.dumps(snapshots, ensure_ascii=False))
    print(f'ECONOMY SERVER: {len(checks)} checks, 0 failures')


if __name__ == '__main__': main()
