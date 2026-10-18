"""Native frame and artifact checks for the new user-referenced equipment."""
import json
import unittest
from PIL import Image
import test_boneglow_assets

ROOT = test_boneglow_assets.ROOT


class GravebloomAssets(test_boneglow_assets.BoneglowAssets):
    FAMILY = 'gravebloom'

    def test_distinct_weapon_types_and_reference_heads(self):
        manifest = json.loads((ROOT/'client/assets/data/gravebloom-equipment.json').read_text('utf8'))
        self.assertEqual([s['weapon'].rsplit('/',1)[1] for s in manifest['sets']],
                         ['ezs11','ezs14','eck9','eck17','efs11','efs7'])
        self.assertEqual(manifest['sets'][4]['head'],'gravebloom/mfs/mfst6')
        self.assertEqual(manifest['sets'][5]['head'],'gravebloom/wfs/wfst4')
        for set_ in manifest['sets']:
            with Image.open(ROOT/f"client/assets/generated/equipment/gravebloom/{set_['stem']}/parts/{set_['head'].rsplit('/',1)[1]}.png") as head:
                colors = head.convert('RGBA').get_flattened_data()
                self.assertTrue(any(g>r*1.2 and g>b*1.2 and g>100 and a==255 for r,g,b,a in colors), 'Visible jade/green accents')
        self.assertEqual(len({s['weapon_code'] for s in manifest['sets']}),6)

if __name__ == '__main__':
    unittest.main()
