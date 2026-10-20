"""Validate Unit-01 native anatomy, pixel packing and reproducible art provenance."""
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('eva01_builder', ROOT/'tools/build_eva01_equipment.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class Eva01Assets(unittest.TestCase):
    def setUp(self):
        self.manifest = json.loads((ROOT/'client/assets/data/eva01-equipment.json').read_text())
        self.native = json.loads((ROOT/'client/assets/data/hero-parts.json').read_text())

    def test_six_character_sets_and_distinct_reserved_codes(self):
        self.assertEqual([s['stem'] for s in self.manifest['sets']], ['mzs','wzs','mck','wck','mfs','wfs'])
        self.assertEqual(len(self.manifest['parts']), 30)
        for index, row in enumerate(self.manifest['sets']):
            self.assertEqual([row['weapon_code'],row['clothing_code'],row['head_code']], [40+index,24+index,22+index])
            self.assertEqual((row['job'],row['gender']), (index//2,index%2))
            for family in ['boneglow', 'gravebloom']:
                previous = json.loads((ROOT/f'client/assets/data/{family}-equipment.json').read_text())
                for old in previous['sets']:
                    self.assertNotEqual(row['weapon_code'],old['weapon_code'])
                    self.assertNotEqual(row['clothing_code'],old['clothing_code'])
                    self.assertNotEqual(row['head_code'],old['head_code'])

    def test_native_frames_grips_empty_layers_and_hair_seams_preserved(self):
        for part_id, entry in self.manifest['parts'].items():
            original = self.native['parts'][part_id.rsplit('/',1)[-1]]
            self.assertEqual(entry['frames'], original['frames'])
            with Image.open(ROOT/'client'/entry['texture'][6:]) as image, Image.open(ROOT/'client'/original['texture'][6:]) as old:
                self.assertEqual(image.size, old.size)
                self.assertEqual(image.mode, 'RGBA')
                self.assertLessEqual(set(image.getchannel('A').tobytes()), {0,255})
                for frame, (x,y,w,h) in enumerate(entry['frames']):
                    actual = image.crop((x,y,x+w,y+h)).getchannel('A')
                    expected = old.crop((x,y,x+w,y+h)).getchannel('A')
                    self.assertEqual(actual.getbbox() is None, expected.getbbox() is None)
                    if '/parts/' in entry['texture'] and ('t2' not in part_id or frame > 0):
                        self.assertEqual(actual.tobytes(), expected.tobytes(), 'All hands, weapons, legs and lower collars keep their native mask')
                    elif expected.getbbox():
                        bounds = expected.getbbox()
                        self.assertEqual(actual.getbbox()[3], bounds[3], 'Head/collar bottom anchor stays fixed')
                        self.assertEqual(actual.crop((0,h-4,w,h)).tobytes(), expected.crop((0,h-4,w,h)).tobytes(), 'No disconnected lower-hair seam')

    def test_ten_icons_binary_transparency_and_visible_unit01_colors(self):
        for row in self.manifest['sets']:
            folder = ROOT/f"client/assets/generated/equipment/eva01/{row['stem']}/icons"
            self.assertEqual({p.stem for p in folder.glob('*.png')}, set(builder.SLOTS))
            for path in folder.glob('*.png'):
                with Image.open(path) as image:
                    self.assertEqual(image.size, (32,32))
                    self.assertEqual(image.mode,'RGBA')
                    self.assertIsNotNone(image.getbbox())
                    self.assertEqual(image.getpixel((0,0))[3],0)
                    self.assertLessEqual(set(image.getchannel('A').tobytes()),{0,255})
            with Image.open(ROOT/'client'/self.manifest['parts'][row['head']]['texture'][6:]) as head:
                colors = set(head.get_flattened_data())
                for name in ['purple','green','white']:
                    self.assertIn(builder.COLORS[name],colors)

    def test_generated_records_and_original_inputs_match_hashes(self):
        folder=ROOT/'analysis/ai-generated/equipment/eva01'
        report=json.loads((folder/'runtime-import-report.json').read_text())
        self.assertEqual(len(report),90)
        for record in report:
            self.assertEqual(hashlib.sha256((ROOT/'client'/record['path'][6:]).read_bytes()).hexdigest(),record['sha256'])
        provenance=json.loads((folder/'generation-record.json').read_text())
        self.assertEqual(hashlib.sha256((ROOT/provenance['generator']).read_bytes()).hexdigest(),provenance['generator_sha256'])
        for path,checksum in provenance['native_inputs'].items():
            self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(),checksum)
        self.assertIn('未使用外部图片生成服务',provenance['method'])

    def test_items_use_actual_icons_ten_slots_and_explicit_restrictions(self):
        items=builder.equipment_items()
        self.assertEqual(len(items),60)
        self.assertEqual(len({i['id'] for i in items}),60)
        for index,(stem,*_) in enumerate(builder.SETS):
            rows=[i for i in items if i['set_id']=='eva01/'+stem]
            self.assertEqual({i['slot'] for i in rows},set(builder.SLOTS))
            self.assertEqual((sum(i['attack'] for i in rows),sum(i['defense'] for i in rows)),(14,27))
            for item in rows:
                self.assertEqual((item['job'],item['gender']),(index//2,index%2))
                self.assertTrue((ROOT/'client'/item['icon'][6:]).is_file())

    def test_catalog_and_migration_preserve_existing_items_and_slot_constraints(self):
        catalog=json.loads((ROOT/'client/assets/data/shop-v2.json').read_text())['items']
        self.assertEqual(len(catalog),394)
        self.assertEqual([i for i in catalog if i['id'].startswith('ai/eva01/')],builder.equipment_items())
        sql=(ROOT/'server/migrations/0023_eva01_equipment.sql').read_text()
        whitelist=re.search(r'definition_id IN \((.*?)\)\)',sql)[1]
        self.assertEqual(set(re.findall("'([^']+)'",whitelist)),{i['id'] for i in catalog})
        for ids,slot in re.findall(r"WHEN definition_id IN \((.*?)\) THEN '([^']+)'",sql):
            self.assertEqual(set(re.findall("'([^']+)'",ids)),{i['id'] for i in catalog if i['slot']==slot})
        self.assertIn('CREATE UNIQUE INDEX one_equipped_per_slot',sql)
        self.assertNotIn('DELETE FROM',sql.upper())


if __name__ == '__main__':
    unittest.main()
