"""Validate Unit-01 native anatomy, pixel packing and reproducible art provenance."""
import hashlib
import importlib.util
import json
import sys
from pathlib import Path
import re
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
spec = importlib.util.spec_from_file_location('eva01_builder', ROOT/'tools/build_eva01_equipment.py')
from eva01_native_style import skin
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class Eva01Assets(unittest.TestCase):
    def setUp(self):
        self.manifest = json.loads((ROOT/'client/assets/data/eva01-equipment.json').read_text('utf8'))
        self.native = json.loads((ROOT/'client/assets/data/hero-parts.json').read_text('utf8'))

    def test_six_character_sets_and_distinct_reserved_codes(self):
        self.assertEqual([s['stem'] for s in self.manifest['sets']], ['mzs','wzs','mck','wck','mfs','wfs'])
        self.assertEqual(len(self.manifest['parts']), 30)
        for index, row in enumerate(self.manifest['sets']):
            self.assertEqual([row['weapon_code'],row['clothing_code'],row['head_code']], [40+index,24+index,22+index])
            self.assertEqual((row['job'],row['gender']), (index//2,index%2))
            for family in ['boneglow', 'gravebloom']:
                previous = json.loads((ROOT/f'client/assets/data/{family}-equipment.json').read_text('utf8'))
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
                    self.assertEqual(actual.tobytes(), expected.tobytes(), 'Every body, face, hand, weapon and hair seam retains the original mask')

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
            source = self.native['parts'][row['stem']+'t2']
            entry = self.manifest['parts'][row['head']]
            with Image.open(ROOT/'client'/entry['texture'][6:]) as head, Image.open(ROOT/'client'/source['texture'][6:]) as original:
                self.assertEqual(head.size, original.size)
                changed = 0
                for old, new in zip(original.get_flattened_data(), head.get_flattened_data()):
                    if old != new: changed += 1
                    if skin(old): self.assertEqual(new, old, 'Native face remains untouched')
                self.assertGreater(changed, 0, 'Crest is actually visible')
                self.assertLessEqual(changed, 25, 'Tiny ornament cannot replace a face with a helmet')
                x,y,w,h = entry['frames'][1]
                self.assertEqual(head.crop((x,y,x+w,y+h)).tobytes(), original.crop((x,y,x+w,y+h)).tobytes(), 'Lower hair/neck seam is unchanged')

    def test_generated_records_and_original_inputs_match_hashes(self):
        folder=ROOT/'analysis/ai-generated/equipment/eva01'
        report=json.loads((folder/'runtime-import-report.json').read_text('utf8'))
        self.assertEqual(len(report),90)
        for record in report:
            self.assertEqual(hashlib.sha256((ROOT/'client'/record['path'][6:]).read_bytes()).hexdigest(),record['sha256'])
        provenance=json.loads((folder/'generation-record.json').read_text('utf8'))
        self.assertEqual(hashlib.sha256((ROOT/provenance['generator']).read_bytes()).hexdigest(),provenance['generator_sha256'])
        for path,checksum in provenance['native_inputs'].items():
            self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(),checksum)
        self.assertIn('image_gen',provenance['method'])
        self.assertEqual(hashlib.sha256((ROOT/provenance['style_module']).read_bytes()).hexdigest(),provenance['style_sha256'])

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
        catalog=json.loads((ROOT/'client/assets/data/shop-v2.json').read_text('utf8'))['items']
        self.assertEqual(len(catalog),459)
        self.assertEqual([i for i in catalog if i['id'].startswith('ai/eva01/')],builder.equipment_items())
        sql=(ROOT/'server/migrations/0023_eva01_equipment.sql').read_text('utf8')
        whitelist=re.search(r'definition_id IN \((.*?)\)\)',sql)[1]
        self.assertTrue(set(re.findall("'([^']+)'",whitelist)) <= {i['id'] for i in catalog})
        self.assertEqual(len(set(re.findall("'([^']+)'",whitelist))),394)
        for ids,slot in re.findall(r"WHEN definition_id IN \((.*?)\) THEN '([^']+)'",sql):
            historical=set(re.findall("'([^']+)'",whitelist))
            self.assertEqual(set(re.findall("'([^']+)'",ids)),{i['id'] for i in catalog if i['slot']==slot and i['id'] in historical})
        self.assertIn('CREATE UNIQUE INDEX one_equipped_per_slot',sql)
        self.assertNotIn('DELETE FROM',sql.upper())

    def test_refined_clothes_keep_original_skin_and_seven_tier_anatomy(self):
        from eva01_native_style import skin
        for row in self.manifest['sets']:
            self.assertEqual([p.rsplit('/',1)[-1] for p in row['body']], [row['stem']+'7'+tail for tail in ['', 'q', 'x']])
            for key in row['body']:
                entry = self.manifest['parts'][key]
                original = self.native['parts'][key.rsplit('/',1)[-1]]
                with Image.open(ROOT/'client'/entry['texture'][6:]) as image, Image.open(ROOT/'client'/original['texture'][6:]) as old:
                    kept = 0
                    for before, after in zip(old.get_flattened_data(), image.get_flattened_data()):
                        if skin(before):
                            self.assertEqual(before,after,'Hands and exposed skin must retain their native shades')
                            kept += 1
                    if key == row['body'][0]: self.assertGreater(kept,0)
        paths = list((ROOT/'client/assets/generated/equipment/eva01').rglob('*.png'))
        self.assertEqual(len(paths),90,'Obsolete body atlases cannot remain in export resources')
        for row in self.manifest['sets'][:2]:
            self.assertEqual(row['weapon'],f"eva01/{row['stem']}/ezs9")
            self.assertTrue(row['weapon_name'].endswith('斧'))

    def test_design_reference_and_original_icons_are_recorded(self):
        from eva01_native_style import ICON_SOURCES
        folder=ROOT/'analysis/ai-generated/equipment/eva01/refinement-v2'
        prompt=json.loads((folder/'prompt.json').read_text('utf8'))
        self.assertIn('image_gen',prompt['tool'])
        self.assertTrue((folder/'design-reference.png').is_file())
        provenance=json.loads((ROOT/'analysis/ai-generated/equipment/eva01/generation-record.json').read_text('utf8'))
        for number in ICON_SOURCES.values():
            self.assertIn(f'client/assets/items/original/if{number}.png',provenance['native_inputs'])


if __name__ == '__main__':
    unittest.main()
