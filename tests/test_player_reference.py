"""Check provenance and lossless extraction of the user's parallel reference tables."""
import csv
import hashlib
import json
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from import_player_reference import build, DEST


class PlayerReferenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data=(DEST/'source.csv').read_bytes()
        cls.tables=build(cls.data)

    def test_archived_source_and_generated_json_agree(self):
        manifest=self.tables['manifest']
        self.assertEqual(manifest['source']['sha256'],hashlib.sha256(self.data).hexdigest())
        self.assertEqual(manifest['source']['rows_including_headers'],216)
        self.assertEqual(manifest['scope'],'analysis_only')
        self.assertFalse(manifest['source']['original_server_payload'])
        for name,value in self.tables.items():self.assertEqual(json.loads((DEST/(name+'.json')).read_text('utf8')),value)

    def test_map_name_matches_do_not_confuse_indices_with_ids(self):
        maps=self.tables['maps']
        self.assertEqual(len(maps),214)
        self.assertTrue(all(row['native_name_match'] for row in maps))
        self.assertEqual(sum(row['match_method']=='exact' for row in maps),211)
        self.assertEqual((maps[0]['csv_index'],maps[0]['native_map_id']),(0,1))

    def test_incomplete_skills_keep_unknown_values_and_source_location(self):
        skills=self.tables['skills']
        self.assertEqual(len(skills),48)
        self.assertEqual(sum(item['name'] is not None for item in skills),30)
        self.assertEqual(sum(item['name'] is None for item in skills),18)
        self.assertEqual(skills[0]['name'],'仙人指路')
        self.assertEqual(skills[0]['source_row'],3)
        for item in skills:
            self.assertEqual(item['source_columns'],'K:P')
            self.assertEqual(item['level_column_meaning'],'unconfirmed')
            for field in ['original_skill_id','mp_cost','damage_formula','effect_animation','max_rank']:self.assertIsNone(item[field])
            self.assertNotIn('map_csv_index',item)

    def test_right_hand_first_data_row_is_not_lost(self):
        materials=self.tables['materials']
        self.assertEqual(len(materials),21)
        self.assertIn(('一级铁矿',2),[(item['name'],item['source_row']) for item in materials])
        self.assertIn(('茯苓',2),[(item['name'],item['source_row']) for item in materials])
        self.assertEqual(self.tables['gems'][0]['attribute_raw'],'8-')
        self.assertIsNone(self.tables['gems'][0]['numeric_attribute'])
        self.assertEqual(self.tables['equipment'][0]['name'],'孽龙锤')
        self.assertEqual(len(self.tables['equipment']),40)
        self.assertEqual(sum(item['group']=='legendary' for item in self.tables['equipment']),30)

    def test_monster_fields_are_tied_only_to_their_own_map_and_cell(self):
        rows=list(csv.reader(self.data.decode('utf-8-sig').splitlines()))
        self.assertEqual(len(self.tables['monsters']),147)
        for monster in self.tables['monsters']:
            row=rows[monster['source_row']-1]
            column=ord(monster['source_columns'])-ord('A')
            self.assertEqual(monster['label_raw'],row[column])
            self.assertIsNone(monster['animation']);self.assertIsNone(monster['combat_stats'])


if __name__=='__main__':unittest.main()
