"""Two-party consent, immutable escrow and recovery; disposable database only."""
import copy
import json
import os
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from uuid import uuid4
from balance_fixture import BalanceFixture, ROOT
from run_online_pve import api
from run_loot_instances import LootPlayer


def main():
    checks, fixtures = [], []
    def check(value, label):
        assert value, label
        checks.append(label)
    prototype = copy.deepcopy(json.loads(Path(os.environ.get('SSJX_LOOT_VECTORS', '/tmp/opencode/loot-vectors.json')).read_text())[0]['item'])
    prototype.update(template='original/if2', equipped=False, bound=False, quality='white', level=1, affixes=[])
    with BalanceFixture() as f:
        identities = [f.create('swap_' + name, 0) for name in ['a', 'b', 'c']]
        ids = [identity[1] for identity in identities]
        owned = []
        for index, cid in enumerate(ids):
            item = copy.deepcopy(prototype); item['id'] = str(uuid4()); owned.append(item)
            if index == 0: item['template'] = 'ai/eva01/wfs/weapon'
            bound = copy.deepcopy(item); bound.update(id=str(uuid4()), bound=True)
            state = dict(version=1, items=[item, bound], pending=[], scrap=0, essence=0, kills=0, bosses=0, difficulty=1, skins=[])
            f.db.query(f"UPDATE characters SET gold=1000,loot_state='{json.dumps(state)}'::jsonb WHERE id='{cid}'")
        players = []
        def connect_all():
            players.clear()
            for identity in identities:
                p = LootPlayer(f.base, *identity); f.clients.append(p); players.append(p)
        connect_all()
        def call(who, action='snapshot', request=None, status=200, **fields):
            payload = request or (dict(character_id=ids[who], action=action) | fields)
            if action != 'snapshot' and 'operation_id' not in payload: payload['operation_id'] = str(uuid4())
            code, result = api(f.base, '/api/v1/economy', payload, identities[who][0]['access_token'])
            assert code == status, (code, result, payload)
            if code == 200: fixtures.append(copy.deepcopy(result))
            return result, payload
        def do(who, action, trade, **fields):
            return call(who, action, target=trade['id'], revision=int(trade['revision']), **fields)
        def trade(result): return result['market']['trade']
        result, _ = call(0, 'trade_invite', name='swap_a')
        check(result['code'] == 'SELF_TARGET', 'Self-trades are rejected')
        result, _ = call(0, 'trade_invite', name='swap_b'); current = trade(result)
        check(current['status'] == 'pending', 'Exact-name invite waits for recipient consent')
        notification = players[1].until('pve.state')['state']
        check(notification['economy']['incoming_trade'] == current['id'], 'The recipient receives a private live invitation even with the market closed')
        result, _ = do(0, 'trade_accept', current)
        check(result['code'] == 'TRADE_NOT_PENDING', 'The inviter cannot accept on behalf of the recipient')
        result, _ = call(2, 'trade_cancel', target=current['id'], revision=int(current['revision']))
        check(result['code'] == 'TRADE_CLOSED', 'A third party cannot cancel or access a private trade')
        result, _ = call(2, 'trade_invite', name='swap_b')
        check(result['code'] == 'TRADE_BUSY', 'A participant cannot enter overlapping trades')
        result, _ = do(1, 'trade_accept', current); current = trade(result)
        result, _ = do(0, 'trade_offer', current, items=[owned[0]['id']], amount=100); current = trade(result)
        check(result['ok'] and result['state']['character']['gold'] == 900 and not any(i['id'] == owned[0]['id'] for i in result['state']['loot']['state']['items']), 'Offering locks currency and the exact instance out of the backpack')
        bound = next(i for i in result['state']['loot']['state']['items'] if i['bound'] and not i['legacy'])
        result, _ = do(0, 'trade_offer', current, items=[bound['id']], amount=100)
        check(result['code'] == 'EQUIPMENT_BOUND' and trade(result)['offers'][0]['items'] == [owned[0]], 'A bound replacement cannot alter existing escrow')
        result, _ = do(1, 'trade_offer', current, items=[owned[0]['id']], amount=0)
        check(result['code'] == 'INSTANCE_NOT_OWNED', 'The counterparty cannot offer someone else\'s escrowed UUID')
        result, _ = do(1, 'trade_offer', current, items=[owned[1]['id']], amount=200); current = trade(result)
        result, _ = do(0, 'trade_confirm', current)
        check(result['code'] == 'TRADE_NOT_LOCKED', 'Final confirmation requires both quotations to be locked')
        for who, action in [(0, 'trade_lock'), (1, 'trade_lock'), (0, 'trade_confirm')]:
            result, _ = do(who, action, current); assert result['ok'], result; current = trade(result)
        stale = copy.deepcopy(current)
        result, _ = do(1, 'trade_offer', current, items=[owned[1]['id']], amount=201); current = trade(result)
        check(result['ok'] and all(not o['locked'] and not o['confirmed'] for o in current['offers']), 'Changing either quote atomically clears BOTH locks and confirmations')
        result, _ = do(0, 'trade_confirm', stale)
        check(result['code'] == 'STALE_TRADE', 'A confirmation for an earlier quote cannot execute a changed exchange')
        for who, action in [(0, 'trade_lock'), (1, 'trade_lock'), (0, 'trade_confirm')]:
            result, _ = do(who, action, current); assert result['ok'], result; current = trade(result)
        saved = copy.deepcopy(current); f.restart(); connect_all(); result, _ = call(1)
        check(trade(result) == saved, 'Open escrow, locks and first confirmation survive server restart')
        f.db.query("CREATE FUNCTION reject_exchange() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'owned rollback'; END$$; CREATE TRIGGER reject_exchange BEFORE INSERT ON economy_deliveries FOR EACH ROW EXECUTE FUNCTION reject_exchange();")
        last = dict(character_id=ids[1], action='trade_confirm', operation_id=str(uuid4()), target=current['id'], revision=int(current['revision']))
        call(1, 'trade_confirm', request=last, status=503)
        result, _ = call(1)
        check(trade(result) == saved and not result['market']['deliveries'], 'Failed exchange rolls back BOTH transfers and the second confirmation')
        f.db.query('DROP TRIGGER reject_exchange ON economy_deliveries; DROP FUNCTION reject_exchange();')
        with ThreadPoolExecutor(2) as pool:
            outcomes = list(pool.map(lambda _: call(1, 'trade_confirm', request=last)[0], range(2)))
        check(all(r['ok'] for r in outcomes) and sum(r['replayed'] for r in outcomes) == 1, 'Concurrent retries execute exactly one atomic exchange')
        for who in [0, 1]:
            result, _ = call(who)
            received = [d for d in result['market']['deliveries'] if d['item'] is not None]
            check(len(received) == 1 and received[0]['item'] == owned[1-who], 'Each participant receives only the other immutable unbound item')
            for delivery in result['market']['deliveries']: result, _ = call(who, 'claim', target=delivery['id'])
            check(result['state']['character']['gold'] == [1101, 899][who], 'Net copper is conserved after both parties claim exchanged funds')
        result, _ = call(0, 'trade_invite', name='swap_b'); current = trade(result)
        result, _ = do(1, 'trade_accept', current); current = trade(result)
        result, request = do(0, 'trade_offer', current, items=[owned[1]['id']], amount=50); current = trade(result)
        result, _ = call(0, 'trade_offer', request=request)
        check(result['replayed'], 'Offer replay does not deduct copper or duplicate escrow')
        result, cancel = do(1, 'trade_cancel', current)
        result, _ = call(1, 'trade_cancel', request=cancel)
        seller, _ = call(0)
        check(result['replayed'] and len(seller['market']['deliveries']) == 2, 'Either participant can cancel; item and copper return once to their original owner')
        for d in seller['market']['deliveries']: call(0, 'claim', target=d['id'])
        result, _ = call(0, 'trade_invite', name='swap_b'); current = trade(result)
        result, _ = do(1, 'trade_accept', current); current = trade(result)
        result, _ = do(0, 'trade_offer', current, items=[owned[1]['id']], amount=50); current = trade(result)
        f.db.query(f"UPDATE equipment_trades SET expires_at=clock_timestamp()-interval '1 second' WHERE id='{current['id']}'")
        result, _ = call(0)
        check(trade(result)['status'] == 'expired' and len(result['market']['deliveries']) == 2, 'Timeout returns original escrow without another player remaining connected')
        f.db.query(f"UPDATE characters SET map_id='ai_001',cell_x=6,cell_y=18 WHERE id='{ids[2]}'")
        f.restart(); connect_all()
        result, _ = call(0, 'trade_invite', name='swap_c')
        check(result['code'] == 'TRADE_TOO_FAR', 'Direct exchange cannot target a character in another map')
        result, _ = call(0, 'trade_invite', name='swap_b'); current = trade(result)
        result, _ = do(1, 'trade_accept', current); current = trade(result)
        result, _ = do(0, 'trade_offer', current, items=[], amount=5); current = trade(result)
        players[1].close()
        import time
        time.sleep(.2)
        result, _ = do(0, 'trade_cancel', current)
        check(result['ok'] and any(d['gold'] == 5 and d['source_id'] == current['id'] for d in result['market']['deliveries']), 'A participant may safely cancel and recover escrow after the other disconnects')
        result, _ = call(0, 'trade_invite', name='swap_b')
        check(result['code'] == 'TEAM_PLAYER_OFFLINE', 'A new exchange cannot silently target an offline player')
    output = ROOT / 'work/direct-trade'; output.mkdir(parents=True, exist_ok=True)
    (output / 'server-fixtures.json').write_text(json.dumps(fixtures, ensure_ascii=False))
    print(f'DIRECT TRADE SERVER: {len(checks)} checks, 0 failures')


if __name__ == '__main__': main()
