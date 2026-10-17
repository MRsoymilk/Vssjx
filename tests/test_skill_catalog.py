import json
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from build_skill_catalog import build


class SkillCatalogTests(unittest.TestCase):
    def test_generation_is_reproducible(self):
        self.assertEqual(build(),json.loads((ROOT/'client/assets/data/skills-v1.json').read_text('utf8')))

    def test_only_named_reference_rows_become_playable(self):
        original=json.loads((ROOT/'analysis/references/player-sheet/skills.json').read_text('utf8'))
        items=build()['items']
        indexed={s['source_row']:s for s in items if s['source_row']}
        self.assertEqual(len(indexed),30)
        self.assertEqual(len(items),33)
        for row in original:
            if not row['name']:
                self.assertNotIn(row['source_row'],indexed)
            else:
                skill=indexed[row['source_row']]
                self.assertEqual(skill['name'],row['name'])
                self.assertIsNone(skill['original_skill_id'])
                self.assertEqual(skill['source_role'],row['role_raw'])
                self.assertIn('重建',skill['rules_basis'])

    def test_passive_skills_are_not_paid_attacks(self):
        items=build()['items']
        passive=[s for s in items if not s['active']]
        self.assertEqual({s['name'] for s in passive},{'霸王卸甲','穿衣破甲'})
        self.assertTrue(all(s['mp_cost']==0 and s['damage_percent']==0 for s in passive))
        self.assertTrue(all(s['unlock_level']<=60 and s['mp_cost']>=0 for s in items))


if __name__=='__main__':unittest.main()
