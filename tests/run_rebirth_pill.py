"""Original respec consumable over real WebSocket/SQL; disposable DB only."""
import json
import time
from uuid import uuid4
from balance_fixture import BalanceFixture, ROOT
from run_online_maps import MapPlayer

ITEM = 'restored/rebirth_pill'


def main():
    checks = []
    snapshots = []

    def check(value, label):
        assert value, label
        checks.append(label)

    with BalanceFixture() as f:
        identity = f.create('rebirth_a')
        cid = identity[1]
        f.db.query(f"UPDATE characters SET level=20,gold=2000,hp=85,mp=30,balance_revision=1,balance_respec_available=false,allocated_attributes=ARRAY[20,10,30,20,10],quest_stage=1,cell_x=22,cell_y=9 WHERE id='{cid}'")

        def connect():
            player = MapPlayer(f.base, *identity, shop_version=2)
            f.clients.append(player)
            return player

        p = connect()

        def request(action='use', **extra):
            return dict(operation_id=str(uuid4()), action=action, target=ITEM,
                        expected_revision=p.state['character']['state_revision'], **extra)

        def command(action='use', ok=True, **extra):
            time.sleep(.07)
            return p.command('', request=request(action, **extra), ok=ok)[0]

        def durable():
            return f.db.query(f"SELECT hp,mp,allocated_attributes,balance_respec_available,state_revision,(SELECT quantity FROM inventory_items WHERE character_id='{cid}' AND definition_id='{ITEM}') FROM characters WHERE id='{cid}'")

        before = durable()
        check(command(ok=False)['code'] == 'WEAPON_NOT_OWNED' and durable() == before,
              'Cannot reset points without owning the pill')
        command('buy', quantity=3)
        check(p.state['character']['gold'] == 1400 and p.state['shop']['quantities'][ITEM] == 3,
              'Authoritative price and stack purchase')
        check(f.db.query(f"SELECT quantity,equipment_slot IS NULL FROM inventory_items WHERE character_id='{cid}' AND definition_id='{ITEM}'") == '3|t',
              'New whitelist allows a consumable without an equipment slot')
        before = durable()
        check(command(ok=False, quantity=2)['code'] == 'INVALID_QUANTITY' and durable() == before,
              'Batch use cannot consume or reset twice')
        check(command(ok=False, attributes=[0, 0, 0, 0, 0])['code'] == 'INVALID_EQUIPMENT' and durable() == before,
              'Client cannot supply replacement attributes')
        stale = request()
        stale['expected_revision'] = '0'
        value, _ = p.command('', request=stale, ok=False)
        check(value['code'] == 'STALE_EQUIPMENT' and durable() == before,
              'Stale character state cannot consume a pill')

        # Fail after inventory updates but before character/receipt commit.
        original = p.state
        pending = request()
        f.db.query("CREATE FUNCTION reject_rebirth() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN IF OLD.allocated_attributes IS DISTINCT FROM NEW.allocated_attributes THEN RAISE EXCEPTION 'owned rollback probe'; END IF; RETURN NEW; END$$; CREATE TRIGGER reject_rebirth BEFORE UPDATE ON characters FOR EACH ROW EXECUTE FUNCTION reject_rebirth();")
        p.ws.send(dict(type='pve.command', command=pending))
        check(p.until('error')['code'] == 'DATABASE_UNAVAILABLE', 'Failed SQL commit is never acknowledged')
        check(durable() == before, 'SQL failure rolls back inventory and attributes together')
        f.db.query('DROP TRIGGER reject_rebirth ON characters; DROP FUNCTION reject_rebirth();')
        p.close()
        time.sleep(.2)
        p = connect()
        value, _ = p.command('', request=pending)
        state = value['state']
        snapshots.append(state)
        check(state['attributes']['allocated'] == [0]*5 and state['attributes']['available'] == 100,
              'All allocated points returned to the full level budget')
        check(state['character']['hp'] == max(1, original['character']['hp']*state['stats']['hp']//original['stats']['hp'])
              and state['character']['mp'] == original['character']['mp']*state['stats']['mp']//original['stats']['mp'],
              'Reset preserves resource ratios instead of healing')
        check(state['shop']['quantities'][ITEM] == 2 and not state['character']['balance_respec_available'],
              'Consume exactly one without requiring a free reset entitlement')
        check(all(state['character'][key] == original['character'][key] for key in ('level', 'xp', 'job', 'gender', 'school', 'gold'))
              and state['shop']['slots'] == original['shop']['slots'] and state['skills'] == original['skills'],
              'Identity, equipment, skills and money remain unchanged')
        before = durable()
        replay, _ = p.command('', request=pending)
        check(replay['replayed'] and replay['state'] == state and durable() == before,
              'Retrying an unknown successful request cannot consume twice')
        check(command(ok=False)['code'] == 'NO_ALLOCATED_ATTRIBUTES' and durable() == before,
              'No allocation rejects a fresh use without wasting an item')

        # Allocate again and test the active encounter guard.
        time.sleep(.07)
        p.command('', request=dict(operation_id=str(uuid4()), action='allocate', attributes=[0, 0, 70, 10, 20],
                                  expected_revision=p.state['character']['state_revision']))
        p.command('challenge', 'spirit')
        frozen = p.state['battle']
        before = durable()
        check(command(ok=False)['code'] == 'BATTLE_ACTIVE' and durable() == before and p.state['battle'] == frozen,
              'Cannot change attributes or consume a pill in battle')
        p.command('flee')
        # Restore full resources only in our disposable DB to exercise a non-healing consumable.
        hp, mp = p.state['stats']['hp'], p.state['stats']['mp']
        p.close()
        f.db.query(f"UPDATE characters SET hp={hp},mp={mp},balance_respec_available=true WHERE id='{cid}'")
        time.sleep(.2)
        p = connect()
        command()
        check(p.state['character']['hp'] == p.state['stats']['hp'] and p.state['character']['mp'] == p.state['stats']['mp'],
              'Pill is usable at full resources and retains full ratio')
        check(p.state['shop']['quantities'][ITEM] == 1 and p.state['character']['balance_respec_available'],
              'Repeat reset consumes another pill but preserves unused free entitlement')
        expected = durable()
        f.restart()
        p = connect()
        check(durable() == expected and p.state['attributes']['allocated'] == [0]*5
              and p.state['shop']['quantities'][ITEM] == 1, 'Restart preserves refunded points and remaining stack')
        snapshots.append(p.state)
        output = ROOT/'work/rebirth-review/live-fixtures.json'
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(snapshots, ensure_ascii=False, indent=2), encoding='utf8')
    print(f'REBIRTH PILL SERVER: {len(checks)} checks, 0 failures')


if __name__ == '__main__':
    main()
