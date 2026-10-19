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

    def test_battleaxe_has_balanced_opposing_blades(self):
        path=ROOT/'client/assets/generated/equipment/gravebloom/mzs/parts/ezs11.png'
        with Image.open(path) as image:
            alpha=image.getchannel('A')
            # First native pose is horizontal. Compare the blade silhouette above
            # and below its centerline, independently of material shading.
            blade={(x,y) for x in range(40,69) for y in range(36) if alpha.getpixel((x,y))>0}
            mirrored={(x,35-y) for x,y in blade}
            self.assertGreater(len(blade & mirrored)/len(blade | mirrored),0.9,
                'A giant lower crescent and tiny upper blade must not return')

if __name__ == '__main__':
    unittest.main()
