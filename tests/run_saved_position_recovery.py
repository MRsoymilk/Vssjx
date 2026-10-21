"""Owned DB: recover old blocked map positions without changing player resources."""
import json
from uuid import uuid4

from balance_fixture import BalanceFixture, ROOT
from run_loot_instances import LootPlayer
from run_online_pve import api, HASH
from ws_fixture import WebSocket


def main():
    checks = []

    def check(ok, label):
        assert ok, label
        checks.append(label)

    catalog = json.loads((ROOT/'shared/data/ai-world-v1.json').read_text(encoding='utf8'))
    map_data = next(m for m in catalog['maps'] if m['map_id'] == 'ai_214')
    check(map_data['blocked'][23 * 32 + 29], 'The observed production coordinate is blocked in the current map')
    with BalanceFixture() as f:
        identity = f.create('saved_pos', 1)
        cid = identity[1]

        def resources(character=cid):
            return f.db.query(f"SELECT hp,mp,gold,xp,level,loot_state,allocated_attributes,corpse FROM characters WHERE id='{character}'")

        def connect(who=identity):
            p = LootPlayer(f.base, *who)
            f.clients.append(p)
            return p

        # Finish the existing first-login equipment/balance migration before
        # comparing resource bytes across a returning player's map recovery.
        connect()
        f.restart()
        f.db.query(f"UPDATE characters SET map_id='ai_214',cell_x=29,cell_y=23,hp=1,mp=1 WHERE id='{cid}'")
        before = resources()
        p = connect()
        fixed = [p.state['character']['cell_x'], p.state['character']['cell_y']]
        check(p.ready['map_id'] == 'ai_214' and fixed != [29, 23], 'A blocked saved position can enter the same map')
        check(not map_data['blocked'][fixed[1] * 32 + fixed[0]], 'The authoritative destination is walkable')
        check(abs(fixed[0]-29) + abs(fixed[1]-23) == 1, 'Recovery chooses a nearby reachable cell')
        check(p.ws.entities[cid]['cell'] == fixed, 'World motion and private character snapshot agree')
        check(resources() == before, 'Recovery does not heal, grant currency, reset allocations or change inventory')
        check(f.db.query(f"SELECT cell_x||','||cell_y FROM characters WHERE id='{cid}'") == ','.join(map(str, fixed)), 'The repaired position is durable before the ready snapshot')
        event = json.loads(f.db.query(f"SELECT details FROM security_audit WHERE character_id='{cid}' AND action='world.position_recovered'"))
        check(event['from'] == [29, 23] and event['to'] == fixed and event['map_id'] == 'ai_214', 'Recovery records an attributed position audit')
        f.restart()
        p = connect()
        check([p.state['character']['cell_x'], p.state['character']['cell_y']] == fixed, 'Server restart retains the repaired coordinate')
        check(f.db.query(f"SELECT count(*) FROM security_audit WHERE character_id='{cid}' AND action='world.position_recovered'") == '1', 'A valid coordinate is not repaired or audited repeatedly')

        # A failed repair audit must not publish an actor or partially claim
        # ownership. Login recovery follows the same transaction rule as PvE.
        f.restart()
        f.db.query(f"UPDATE characters SET cell_x=29,cell_y=23 WHERE id='{cid}'")
        ownership = f.db.query(f"SELECT owner_epoch,position_revision,state_revision FROM characters WHERE id='{cid}'")
        f.db.query("CREATE FUNCTION reject_owned_position() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN IF NEW.action='world.position_recovered' THEN RAISE EXCEPTION 'owned recovery failure'; END IF; RETURN NEW; END$$; CREATE TRIGGER reject_owned_position BEFORE INSERT ON security_audit FOR EACH ROW EXECUTE FUNCTION reject_owned_position();")
        status, ticket = api(f.base, '/api/v1/world/ticket', dict(character_id=cid, protocol_version=1, config_hash=HASH), identity[0]['access_token'])
        check(status == 200, 'Repair failure still uses an authenticated owned ticket')
        ws = WebSocket(f.base.replace('http://', 'ws://')+'/api/v1/world/ws')
        try:
            ws.send(dict(type='auth.exchange', ticket=ticket['ticket'], protocol_version=1,
                         config_hash=HASH, world_sync_version=2, population_version=1, pve_version=1, maps_version=2, shop_version=2))
            packet, _ = ws.recv()
            check(packet['type'] == 'error' and packet['code'] == 'DATABASE_UNAVAILABLE', 'A failed repair cannot report successful world admission')
        finally:
            ws.close()
        check(f.db.query(f"SELECT owner_epoch,position_revision,state_revision FROM characters WHERE id='{cid}'") == ownership
              and f.db.query(f"SELECT cell_x||','||cell_y FROM characters WHERE id='{cid}'") == '29,23',
              'Repair failure rolls back ownership, revision and position together')
        check(resources() == before, 'Failed recovery also leaves all resources untouched')
        f.db.query('DROP TRIGGER reject_owned_position ON security_audit; DROP FUNCTION reject_owned_position();')
        f.restart()
        p = connect()
        check([p.state['character']['cell_x'], p.state['character']['cell_y']] == fixed, 'Retry after a database fault recovers deterministically')
        check(resources() == before, 'Retry still does not refill HP or MP')

        f.restart()
        corpse = dict(id=str(uuid4()), map_id='ai_214', cell=map_data['spawn'])
        f.db.query(f"UPDATE characters SET cell_x=29,cell_y=23,hp=0,corpse='{json.dumps(corpse)}'::jsonb WHERE id='{cid}'")
        before = resources()
        p = connect()
        check(p.state['character']['corpse'] == corpse and p.state['character']['hp'] == 0, 'Recovery preserves a valid corpse and does not revive a soul')
        check(resources() == before, 'Soul admission preserves the complete resource and corpse record')

        battling = f.create('pos_battle', 1)
        battle_cid = battling[1]
        f.db.query(f"UPDATE characters SET level=60,hp=1000,mp=400,quest_stage=1,cell_x=22,cell_y=9 WHERE id='{battle_cid}'")
        p = connect(battling)
        p.approach('wolf_a')
        p.command('', request=dict(operation_id=str(uuid4()), action='challenge', target='wolf_a', encounter_version=2))
        frozen = p.state['battle']
        before = resources(battle_cid)
        f.restart()
        f.db.query(f"UPDATE characters SET cell_x=8,cell_y=8 WHERE id='{battle_cid}'")
        p = connect(battling)
        check(p.state['battle'] == frozen, 'Blocked-position recovery retains the exact existing active battle')
        check(resources(battle_cid) == before, 'Battle admission recovery preserves HP, MP, loot and currency')
        p.command('flee')
        check(p.state['battle']['outcome'] == 'fled', 'The recovered player can finish the existing battle normally')
        print(f'SAVED POSITION RECOVERY: {len(checks)} checks, 0 failures')


if __name__ == '__main__':
    main()
