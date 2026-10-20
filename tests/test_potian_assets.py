"""Approved bitmap provenance, native packing, and standalone weapon registration."""
import hashlib
import json
from pathlib import Path
import unittest
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


class PotianAssets(unittest.TestCase):
    def test_exact_approved_source_and_import_checksums(self):
        folder = ROOT/'analysis/ai-generated/equipment/legendary'
        report = json.loads((folder/'potian-import.json').read_text('utf8'))
        digest = hashlib.sha256((folder/'potian-approved.png').read_bytes()).hexdigest()
        self.assertEqual(digest, '3ccb7861833d950ed46a2db25c13da1eea5f3c0b07b8952f1088c73f202dc610')
        self.assertEqual(report['source_sha256'], digest)
        for record in report['outputs']:
            path = ROOT/'client'/record['path'].removeprefix('res://')
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), record['sha256'])

    def test_two_native_poses_keep_grips_and_transparent_padding(self):
        manifest = json.loads((ROOT/'client/assets/data/legendary-equipment.json').read_text('utf8'))
        native = json.loads((ROOT/'client/assets/data/hero-parts.json').read_text('utf8'))
        part = manifest['parts']['legendary/potian_axe']
        self.assertEqual(part['frames'],native['parts']['ezs9']['frames'])
        with Image.open(ROOT/'client'/part['texture'].removeprefix('res://')) as atlas:
            self.assertEqual(atlas.size,(148,47))
            for (x,y,w,h), grip in zip(part['frames'],[(13,18),(13,33)]):
                image = atlas.crop((x,y,x+w,y+h))
                alpha = image.getchannel('A')
                self.assertEqual(set(alpha.tobytes()),{0,255})
                box = alpha.getbbox()
                self.assertTrue(box[0]>0 and box[1]>0 and box[2]<w and box[3]<h,'Weapon outline must not be clipped')
                self.assertIsNotNone(alpha.crop((grip[0]-1,grip[1]-1,grip[0]+2,grip[1]+2)).getbbox(),'Weapon crosses original grip')
        with Image.open(ROOT/'client/assets/generated/equipment/legendary/potian-icon.png') as icon:
            self.assertEqual(icon.size,(32,32))
            self.assertEqual(icon.getpixel((0,0))[3],0)

    def test_standalone_registry_and_migration_keep_previous_items(self):
        manifest = json.loads((ROOT/'client/assets/data/legendary-equipment.json').read_text('utf8'))
        self.assertEqual(manifest['sets'],[])
        self.assertEqual({row['stem'] for row in manifest['weapons']},{'mzs','wzs'})
        self.assertTrue(all(row['weapon_code']==46 and 'head_code' not in row and 'clothing_code' not in row for row in manifest['weapons']))
        catalog = json.loads((ROOT/'client/assets/data/shop-v2.json').read_text('utf8'))
        sql = (ROOT/'server/migrations/0027_potian_equipment.sql').read_text('utf8')
        whitelist = sql.split('CHECK(definition_id IN (',1)[1].split('));',1)[0]
        for row in catalog['items']:
            self.assertIn("'"+row['id']+"'",whitelist)
        self.assertIn('CREATE UNIQUE INDEX one_equipped_per_slot',sql)
        self.assertNotIn('DELETE FROM',sql)


if __name__ == '__main__':
    unittest.main()
