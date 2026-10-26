"""Fixed mana and solid-guard persistence in a disposable owned PostgreSQL fixture."""
import copy
import json
from uuid import uuid4
from balance_fixture import BalanceFixture, ROOT


def main():
    checks = []

    def check(ok, label):
        assert ok, label
        checks.append(label)

    with BalanceFixture() as fixture:
        identity = fixture.create('fixed_costs')
        cid = identity[1]
        fixture.db.query(f"UPDATE characters SET level=60,hp=1000,mp=400,quest_stage=1 WHERE id='{cid}'")
        player = fixture.connect(identity)
        player.approach('wolf_a')
        player.command('challenge', 'wolf_a')
        bid = player.state['battle']['id']
        template = json.loads(fixture.db.query(f"SELECT state::text FROM pve_battles WHERE id='{bid}'"))
        modern_stats = copy.deepcopy(player.state['stats'])
        for maximum in [400, 800]:
            player.close()
            battle = copy.deepcopy(template)
            stats = copy.deepcopy(modern_stats)
            stats.update(hp=1000, mp=maximum)
            battle.update(hp=1000, mp=maximum, enemy_hp=10000, round=0, revision=0,
                          outcome='active', skill_rules_version=1, frozen_stats=stats, skills={})
            battle['enemy'].update(hp=10000, attack=1)
            fixture.db.query(f"UPDATE pve_battles SET state=$owned${json.dumps(battle)}$owned$::jsonb WHERE id='{bid}'; UPDATE characters SET hp=1000,mp={maximum},state_revision=state_revision+1 WHERE id='{cid}'")
            player = fixture.connect(identity)
            request = dict(operation_id=str(uuid4()), action='skill', target='sheet_012',
                           battle_id=bid, expected_revision=player.state['battle']['revision'])
            result, _ = player.command('', request=request)
            actual = result['state']['battle']
            check(actual['mp'] == maximum - 15, f'Modern max MP {maximum} still costs 15 points')
            check(actual['skills']['defense_flat'] == 25 and actual['skills']['defense_percent'] == 0,
                  'Fixed protection is authoritative and persisted')
            check(actual['skills']['defense'] == 1, 'Protection remains after the casting round')
            check(actual['hp'] == 1000, 'Weak physical hits are fully blocked without self damage')
            saved = json.loads(fixture.db.query(f"SELECT state::text FROM pve_battles WHERE id='{bid}'"))
            check(all(saved[key] == actual[key] for key in ['hp', 'mp', 'skills']),
                  'Database contains the acknowledged resources and protection')
            replay, _ = player.command('', request=request)
            check(replay['replayed'] and replay['state'] == result['state'], 'Retry never pays or casts twice')
        fixture.restart()
        player = fixture.connect(identity)
        check(player.state['battle']['skills']['defense_flat'] == 25 and player.state['battle']['skills']['defense'] == 1,
              'Server restart preserves remaining fixed protection')
        before = player.state['battle']['hp']
        value, _ = player.command('guard')
        check(value['state']['battle']['hp'] == before and value['state']['battle']['skills']['defense'] == 0,
              'Second round remains protected and then expires')
        output = ROOT / 'work/fixed-skill-server-fixture.json'
        output.write_text(json.dumps(result['state'], ensure_ascii=False, indent=2), encoding='utf8')
    print(f'FIXED SKILL SERVER: {len(checks)} checks, 0 failures')


if __name__ == '__main__':
    main()
