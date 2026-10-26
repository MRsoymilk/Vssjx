import json
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from build_skill_catalog import build, build_coverage


class SkillCatalogTests(unittest.TestCase):
    def test_thunder_stun_is_authored_and_keeps_its_original_damage_budget(self):
        skills=build()['items']
        thunder=next(s for s in skills if s['id']=='sheet_010')
        self.assertEqual(thunder['stun'],{'chance':35,'actions':1,'cooldown':3})
        self.assertEqual((thunder['effect'],thunder['damage_percent'],thunder['mp_cost'],thunder['unlock_level']),('damage',180,9,5))
        self.assertIn('非原版恢复',thunder['rules_basis'])
        self.assertEqual([s['id'] for s in skills if 'stun' in s],['sheet_010'])
    def test_reference_gaps_are_ui_metadata_not_playable_definitions(self):
        coverage=build_coverage()
        self.assertEqual(coverage,json.loads((ROOT/'client/assets/data/skill-reference-coverage.json').read_text('utf8')))
        self.assertEqual(coverage['roles']['1/0']['named_count'],0)
        self.assertEqual(coverage['roles']['1/0']['missing_levels'],[15,25,35,45,55])
        self.assertEqual(sum(len(role['missing_levels']) for role in coverage['roles'].values()),18)

    def test_generation_is_reproducible(self):
        self.assertEqual(build(),json.loads((ROOT/'client/assets/data/skills-v1.json').read_text('utf8')))

    def test_only_named_reference_rows_become_playable(self):
        original=json.loads((ROOT/'analysis/references/player-sheet/skills.json').read_text('utf8'))
        items=build()['items']
        indexed={s['source_row']:s for s in items if s['source_row']}
        self.assertEqual(len(indexed),30)
        self.assertEqual(len(items),37)
        added=[s for s in items if s['id'].startswith('user_')]
        self.assertEqual({s['name'] for s in added},{'石破天惊','横扫千军','清风荣新','双龙戏珠'})
        self.assertTrue(all(s['unlock_level']==25 and s['active'] for s in added))
        for row in original:
            if not row['name']:
                self.assertNotIn(row['source_row'],indexed)
            else:
                skill=indexed[row['source_row']]
                self.assertEqual(skill['name'],row['name'])
                self.assertIsNone(skill['original_skill_id'])
                self.assertEqual(skill['source_role'],row['role_raw'])
                self.assertIn('重建',skill['rules_basis'])

    def test_requested_group_attacks_have_distinct_target_limits(self):
        items=build()['items']
        for name,job,limit in [('横扫千军',0,0),('沧海明月',1,0),('双龙戏珠',2,2)]:
            found=[s for s in items if s['name']==name]
            self.assertEqual(len(found),1)
            skill=found[0]
            self.assertEqual((skill['job'],skill['target'],skill.get('max_targets',0)),(job,'all_enemies',limit))
        self.assertEqual((skill['unlock_level'],skill['mp_cost']),(25,15))

    def test_passive_skills_are_not_paid_attacks(self):
        items=build()['items']
        passive=[s for s in items if not s['active']]
        self.assertEqual({s['name'] for s in passive},{'霸王卸甲','穿衣破甲'})
        self.assertTrue(all(s['mp_cost']==0 and s['damage_percent']==0 for s in passive))
        self.assertTrue(all(s['unlock_level']<=60 and s['mp_cost']>=0 for s in items))

    def test_active_reflection_is_sixty_percent_for_two_turns(self):
        reflection=[s for s in build()['items'] if s['effect'] in ('reflect_physical','reflect_magic')]
        self.assertEqual({s['id'] for s in reflection},{'sheet_011','sheet_014','sheet_033','sheet_036'})
        for skill in reflection:
            self.assertEqual(skill['value'],60 if skill['active'] else 20)
            self.assertEqual(skill['duration'],2 if skill['active'] else 0)


if __name__=='__main__':unittest.main()
