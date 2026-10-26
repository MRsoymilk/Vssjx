"""Group targeting through real WebSocket commands and an owned disposable DB."""
import copy
import json
import time
from uuid import uuid4
from balance_fixture import BalanceFixture


def main():
    checks = 0
    def check(value, label):
        nonlocal checks
        assert value, label
        checks += 1
        print('PASS: ' + label, flush=True)

    with BalanceFixture() as fixture:
        for index, (skill, job, cases) in enumerate([
            ('user_hengsao_qianjun', 0, [(5, False)]),
            ('sheet_004', 1, [(5, False)]),
            ('user_shuanglong_xizhu', 2, [(1, False), (2, False), (5, False), (5, True)]),
            ('sheet_045', 2, [(5, False)]),
        ]):
            identity = fixture.create('grp_probe' + str(index), job)
            cid = identity[1]
            fixture.db.query(f"UPDATE characters SET level=60,quest_stage=1 WHERE id='{cid}'")
            player = fixture.connect(identity)
            player.approach('wolf_a')
            player.command('', request=dict(operation_id=str(uuid4()), action='challenge', target='wolf_a', encounter_version=2))
            template = copy.deepcopy(player.state['battle'])
            bid = template['id']
            for count, dead_first in cases:
                player.close()
                time.sleep(.15)
                battle = copy.deepcopy(template)
                fighter = battle['formation']['fighters'][0]
                battle.update(hp=fighter['stats']['hp'], mp=fighter['stats']['mp'], revision=0)
                fighter.update(hp=battle['hp'], mp=battle['mp'])
                fighter['effects']['proficiency'] = {skill: 99}
                fighter['effects']['balance']['cooldowns'] = {}
                enemy = copy.deepcopy(battle['formation']['enemies'][0])
                enemy['hp'] = enemy['definition']['hp'] = 100000
                enemy['definition']['attack'] = 1
                battle['formation']['enemies'] = [dict(copy.deepcopy(enemy), slot='m' + str(i)) for i in range(count)]
                if dead_first:
                    battle['formation']['enemies'][0]['hp'] = 0
                battle['enemy_hp'] = battle['enemy']['hp'] = 100000
                battle['enemy']['attack'] = 1
                fixture.db.query(f"UPDATE characters SET skill_proficiency=$owned${json.dumps({skill:99})}$owned$::jsonb,hp={battle['hp']},mp={battle['mp']} WHERE id='{cid}'; UPDATE pve_battles SET state=$owned${json.dumps(battle)}$owned$::jsonb WHERE id='{bid}';")
                player = fixture.connect(identity)
                operation = dict(operation_id=str(uuid4()), action='skill', target=skill, enemy_slot='m' + str(count - 1), battle_id=bid, expected_revision=player.state['battle']['revision'])
                result, _ = player.command('', request=operation)
                state = result['state']
                formation = state['battle']['formation']
                hits = [e for e in formation['events'] if e['skill'] == skill and e['actor'] == cid]
                expected = ['m' + str(count - 1)] + (['m1' if dead_first else 'm0'] if count > 1 else []) if skill == 'user_shuanglong_xizhu' else ['m' + str(i) for i in range(count)]
                check([e['target'] for e in hits] == expected, f'{skill}: exact living targets {expected}')
                cost = 12 if skill in ('sheet_004','sheet_045') else 15
                check(state['battle']['mp'] == battle['mp'] - cost, 'One fixed MP charge per cast')
                check(state['character']['skill_proficiency'][skill] == 100 and all(e['skill_level'] == 6 for e in hits), 'One durable proficiency increase and a shared effect rank')
                if skill == 'user_shuanglong_xizhu':
                    check(all(e['hp'] == old['hp'] for e, old in zip(formation['enemies'], battle['formation']['enemies']) if e['slot'] not in expected), 'Unselected enemies receive no damage')
                replay, _ = player.command('', request=operation)
                check(replay['replayed'] and replay['state'] == state, 'Receipt replay preserves the resolved cast')
                saved = json.loads(fixture.db.query(f"SELECT skill_proficiency FROM characters WHERE id='{cid}'"))
                check(saved[skill] == 100, 'Database stores one cast only')
            player.close()
    print(f'GROUP SKILLS SERVER: {checks} checks, 0 failures', flush=True)


if __name__ == '__main__':
    main()
