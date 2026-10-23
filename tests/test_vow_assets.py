"""Check ceremonial joint grids, face seams, actual grips and ten-slot provenance."""
import hashlib
import json
from pathlib import Path
import sys
import unittest

from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import build_vow_equipment as builder


class VowAssets(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data=json.loads((ROOT/'client/assets/data/vow-equipment.json').read_text('utf8'))
        cls.native=json.loads((ROOT/'client/assets/data/hero-parts.json').read_text('utf8'))

    def image(self,spec):
        return Image.open(ROOT/'client'/spec['texture'][6:]).convert('RGBA')

    def test_six_roles_unique_codes_and_complete_slots(self):
        self.assertEqual([s['stem'] for s in self.data['sets']],['mzs','wzs','mck','wck','mfs','wfs'])
        self.assertEqual(len(self.data['parts']),30)
        items=builder.equipment_items()
        self.assertEqual(len({i['id'] for i in items}),60)
        for index,row in enumerate(self.data['sets']):
            self.assertEqual((row['weapon_code'],row['clothing_code'],row['head_code']),(47+index,30+index,28+index))
            members=[i for i in items if i['set_id']==row['id']]
            self.assertEqual({i['slot'] for i in members},set(builder.SLOTS))
            self.assertEqual((sum(i['attack'] for i in members),sum(i['defense'] for i in members)),(14,27))
            for item in members:
                self.assertEqual((item['job'],item['gender']),(index//2,index%2))
                self.assertEqual(item['price'],140 if item['slot']=='weapon' else 70)
            for family in ['boneglow','gravebloom','eva01','legendary']:
                previous=json.loads((ROOT/f'client/assets/data/{family}-equipment.json').read_text('utf8'))
                for old in previous['sets']+previous.get('weapons',[]):
                    for code in ['weapon_code','clothing_code','head_code']:
                        if code in old:self.assertNotEqual(row[code],old[code])

    def test_every_native_frame_fits_and_clothing_joint_masks_remain(self):
        for row in self.data['sets']:
            for source in [row['head']]+row['body']+[row['weapon']]:
                spec=self.data['parts'][source];original=self.native['parts'][source.split('/')[-1]]
                self.assertEqual(spec['frames'],original['frames'])
                image=self.image(spec);old=self.image(original)
                self.assertEqual(image.size,old.size)
                self.assertLessEqual(set(image.getchannel('A').tobytes()),{0,255})
                for x,y,w,h in spec['frames']:
                    rect=(x,y,x+w,y+h);tile=image.crop(rect);base=old.crop(rect)
                    self.assertEqual(tile.getbbox() is None,base.getbbox() is None)
                    if source in row['body']:
                        self.assertEqual(tile.getchannel('A').tobytes(),base.getchannel('A').tobytes(),source+' joint/foot/split mask')
                self.assertNotEqual(image.tobytes(),old.tobytes(),source+' contains new visible artwork')

    def test_native_face_and_lower_hair_are_not_replaced_by_veil(self):
        # Fixed original face rectangles, independent of the generator's mask.
        faces={'mzs':(12,30,28,42),'wzs':(11,32,25,42),'mck':(8,31,24,42),
               'wck':(10,31,25,42),'mfs':(9,30,24,42),'wfs':(10,30,26,42)}
        for row in self.data['sets']:
            spec=self.data['parts'][row['head']];original=self.native['parts'][row['head'].split('/')[-1]]
            image=self.image(spec);old=self.image(original)
            self.assertEqual(image.crop(faces[row['stem']]).tobytes(),old.crop(faces[row['stem']]).tobytes(),row['stem']+' face')
            x,y,w,h=spec['frames'][1]
            self.assertEqual(image.crop((x,y,x+w,y+h)).tobytes(),old.crop((x,y,x+w,y+h)).tobytes())

    def test_weapons_reach_native_grips_in_both_orientations(self):
        anchors={'zs':[(23,19),(23,27)],'ck':[(34,6),(25,4)],'fs':[(27,28),(34,21)]}
        for row in self.data['sets']:
            spec=self.data['parts'][row['weapon']];image=self.image(spec)
            for (x,y,w,h),(gx,gy) in zip(spec['frames'],anchors[row['stem'][1:]]):
                tile=image.crop((x,y,x+w,y+h))
                self.assertEqual(tile.getpixel((gx,gy))[3],255,row['stem']+' handle still meets native hand')
                self.assertGreater(sum(p[3]>0 for p in tile.get_flattened_data()),90)
                # All weapon types have silk and floral highlight pixels.
                pixels=[p for p in tile.get_flattened_data() if p[3]]
                self.assertGreater(sum(min(p[:3])>210 for p in pixels),3)
                self.assertGreater(sum(p[0]>p[1]*1.15 and p[2]>p[1]*1.1 for p in pixels),2)

    def test_ten_readable_binary_icons_and_distinct_tailoring(self):
        armor=[]
        for row in self.data['sets']:
            paths=list((ROOT/f"client/assets/generated/equipment/vow/{row['stem']}/icons").glob('*.png'))
            self.assertEqual({p.stem for p in paths},set(builder.SLOTS))
            for path in paths:
                image=Image.open(path).convert('RGBA')
                self.assertEqual(image.size,(32,32))
                self.assertEqual(image.getpixel((0,0))[3],0)
                self.assertGreater(sum(p[3]>0 for p in image.get_flattened_data()),40)
                self.assertLessEqual(set(image.getchannel('A').tobytes()),{0,255})
                if path.stem=='armor':armor.append(image.tobytes())
        self.assertEqual(len(set(armor)),6)

    def test_all_generated_files_and_native_inputs_match_provenance(self):
        folder=ROOT/'analysis/ai-generated/equipment/vow'
        report=json.loads((folder/'runtime-import-report.json').read_text('utf8'))
        self.assertEqual(len(report),90)
        for entry in report:
            path=ROOT/'client'/entry['path'][6:]
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),entry['sha256'])
        record=json.loads((folder/'generation-record.json').read_text('utf8'))
        for key in ['generator','style']:
            path=record['style_module' if key=='style' else key]
            self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(),record[key+'_sha256'])
        for path,checksum in record['native_inputs'].items():
            self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(),checksum)


if __name__=='__main__':unittest.main()
