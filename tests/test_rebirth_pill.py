"""Recovered naming evidence and the new catalog/database boundary."""
import json
from pathlib import Path
import re
import unittest

ROOT=Path(__file__).resolve().parents[1]
ITEM='restored/rebirth_pill'


class RebirthPill(unittest.TestCase):
    def test_name_and_effect_match_original_tip(self):
        text=(ROOT/'analysis/decoded_text/ssjx/tips0.txt').read_text('utf8')
        self.assertIn('使用“重生再造丹”能够让你重新分配点数',text)
        catalog=json.loads((ROOT/'client/assets/data/shop-v2.json').read_text('utf8'))
        matches=[row for row in catalog['items'] if row['id']==ITEM]
        self.assertEqual(len(matches),1)
        row=matches[0]
        self.assertEqual((row['name'],row['slot'],row['effect']),('重生再造丹','consumable','reset_attributes'))
        self.assertEqual((row['price'],row['restore_hp'],row['restore_mp']),(200,0,0))
        self.assertIn('elixir',row['sections'])
        self.assertTrue((ROOT/'client'/row['icon'].removeprefix('res://')).is_file())
        self.assertIn('重建映射',row['appearance_basis'])

    def test_migration_adds_whitelist_without_changing_equipped_slots(self):
        sql=(ROOT/'server/migrations/0029_rebirth_pill.sql').read_text('utf8')
        allowed=set(re.findall(r"'([^']*)'",sql))
        previous=(ROOT/'server/migrations/0027_potian_equipment.sql').read_text('utf8')
        old=previous.split('CHECK(definition_id IN (',1)[1].split('));',1)[0]
        self.assertTrue(set(re.findall(r"'([^']*)'",old))<=allowed)
        self.assertIn(ITEM,allowed)
        self.assertNotIn('DELETE',sql)
        self.assertNotIn('DROP INDEX',sql)
        self.assertNotIn('DROP COLUMN',sql)


if __name__=='__main__':unittest.main()
