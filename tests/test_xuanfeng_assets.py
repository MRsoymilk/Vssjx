"""Native atlas/face/anchor checks for the six Xuanfeng outfits."""
import hashlib
import json
from pathlib import Path
import sys
import unittest

from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import build_xuanfeng_equipment as builder
import xuanfeng_native_style as style


class XuanfengAssets(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.native=json.loads((ROOT/'client/assets/data/hero-parts.json').read_text('utf8'))
        cls.data=json.loads((ROOT/'client/assets/data/xuanfeng-equipment.json').read_text('utf8'))

    def image(self,spec):return Image.open(ROOT/'client'/spec['texture'][6:]).convert('RGBA')

    def test_six_roles_ten_slots_distinct_codes(self):
        self.assertEqual([s['stem'] for s in self.data['sets']],['mzs','wzs','mck','wck','mfs','wfs'])
        self.assertEqual(len(self.data['parts']),30)
        items=builder.equipment_items();self.assertEqual(len({i['id']for i in items}),60)
        previous=[]
        for family in ['boneglow','gravebloom','eva01','legendary','vow']:
            d=json.loads((ROOT/f'client/assets/data/{family}-equipment.json').read_text())
            previous+=d['sets']+d.get('weapons',[])
        for n,row in enumerate(self.data['sets']):
            self.assertEqual((row['weapon_code'],row['clothing_code'],row['head_code']),(53+n,36+n,34+n))
            members=[i for i in items if i['set_id']==row['id']]
            self.assertEqual({i['slot']for i in members},set(builder.SLOTS))
            self.assertEqual((sum(i['price']for i in members),sum(i['attack']for i in members),sum(i['defense']for i in members)),(770,14,27))
            for item in members:self.assertEqual((item['job'],item['gender']),(n//2,n%2))
            for old in previous:
                for key in ['weapon_code','clothing_code','head_code']:
                    if key in old:self.assertNotEqual(row[key],old[key])

    def test_native_regions_alpha_and_all_body_joint_masks(self):
        for row in self.data['sets']:
            for key in [row['head']]+row['body']+[row['weapon']]:
                spec=self.data['parts'][key];native=self.native['parts'][key.rsplit('/',1)[-1]]
                image=self.image(spec);original=self.image(native)
                self.assertEqual(spec['frames'],native['frames']);self.assertEqual(image.size,original.size)
                self.assertLessEqual(set(image.getchannel('A').tobytes()),{0,255})
                for x,y,w,h in spec['frames']:
                    a=image.crop((x,y,x+w,y+h));b=original.crop((x,y,x+w,y+h))
                    self.assertEqual(a.getbbox() is None,b.getbbox() is None,key)
                    if key in row['body']:self.assertEqual(a.getchannel('A').tobytes(),b.getchannel('A').tobytes(),key)
                self.assertNotEqual(image.tobytes(),original.tobytes(),key)

    def test_open_faces_and_lower_hair_attachment(self):
        for row in self.data['sets']:
            spec=self.data['parts'][row['head']];native=self.native['parts'][row['head'].rsplit('/',1)[-1]]
            a=self.image(spec);b=self.image(native);box=style.FACE_BOXES[row['stem']];kept=0
            for y in range(box[1],box[3]):
                for x in range(box[0],box[2]):
                    p=b.getpixel((x,y))
                    if p[3] and p[:3] in style.SKIN[row['stem']]:self.assertEqual(a.getpixel((x,y)),p);kept+=1
            self.assertGreater(kept,10)
            x,y,w,h=spec['frames'][1]
            self.assertEqual(a.crop((x,y,x+w,y+h)).getchannel('A').tobytes(),b.crop((x,y,x+w,y+h)).getchannel('A').tobytes())
            self.assertEqual(a.crop((0,41,42,43)).tobytes(),b.crop((0,41,42,43)).tobytes())

    def test_weapons_meet_both_native_grips(self):
        anchors={'zs':[(23,19),(23,27)],'ck':[(34,6),(25,4)],'fs':[(27,28),(34,21)]}
        for row in self.data['sets']:
            spec=self.data['parts'][row['weapon']];image=self.image(spec)
            for (x,y,w,h),(gx,gy) in zip(spec['frames'],anchors[row['stem'][1:]]):
                tile=image.crop((x,y,x+w,y+h))
                self.assertEqual(tile.getpixel((gx,gy))[3],255,(row['stem'],gx,gy))
                self.assertGreater(sum(p[3]>0 for p in tile.get_flattened_data()),30)

    def test_icons_are_independent_binary_native_size_assets(self):
        for row in self.data['sets']:
            folder=ROOT/f"client/assets/generated/equipment/xuanfeng/{row['stem']}/icons"
            self.assertEqual({p.stem for p in folder.glob('*.png')},set(builder.SLOTS))
            for path in folder.glob('*.png'):
                image=Image.open(path).convert('RGBA')
                self.assertEqual(image.size,(32,32));self.assertEqual(image.getpixel((0,0))[3],0)
                self.assertGreater(sum(p[3]>0 for p in image.get_flattened_data()),35,path.name)
                self.assertLessEqual(set(image.getchannel('A').tobytes()),{0,255})
                with Image.open(path) as source:self.assertEqual(source.info,{})

    def test_master_contains_only_the_approved_raster_and_inputs_match(self):
        record=json.loads((builder.SOURCE/'generation-record.json').read_text())
        for path,sha in record['native_inputs'].items():self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(),sha)
        for name in ['generator','style']:
            key='style_module' if name=='style' else name
            self.assertEqual(hashlib.sha256((ROOT/record[key]).read_bytes()).hexdigest(),record[name+'_sha256'])
        report=json.loads((builder.SOURCE/'runtime-import-report.json').read_text());self.assertEqual(len(report),90)
        for row in report:self.assertEqual(hashlib.sha256((ROOT/'client'/row['path'][6:]).read_bytes()).hexdigest(),row['sha256'])
        for stem,*_ in builder.SETS:
            path=builder.SOURCE/'reference'/(stem+'.png')
            with Image.open(path) as image:
                self.assertEqual(image.size,(80,80));self.assertEqual(image.info,{})

    def test_rebuild_is_byte_identical(self):builder.build(check=True)

    def test_catalog_registry_and_forward_only_migration(self):
        import re
        from build_xuanfeng_migration import sql
        catalog=json.loads((ROOT/'client/assets/data/shop-v2.json').read_text())['items']
        self.assertEqual([i for i in catalog if i['id'].startswith('ai/xuanfeng/')],builder.equipment_items())
        text=(ROOT/'server/migrations/0044_xuanfeng_equipment.sql').read_text()
        self.assertEqual(text,sql())
        whitelist=set(re.findall("'([^']+)'",re.search(r'definition_id IN \((.*?)\)\)',text)[1]))
        self.assertEqual(whitelist,{i['id']for i in catalog})
        for ids,slot in re.findall(r"WHEN definition_id IN \((.*?)\) THEN '([^']+)'",text):
            self.assertEqual(set(re.findall("'([^']+)'",ids)),{i['id']for i in catalog if i['slot']==slot})
        self.assertIn('CREATE UNIQUE INDEX one_equipped_per_slot',text)
        self.assertNotIn('DELETE FROM',text.upper());self.assertNotIn('UPDATE CHARACTERS',text.upper())
        registry=(ROOT/'client/scripts/generated_equipment.gd').read_text()
        self.assertIn('"id":"xuanfeng","name":"玄锋行装"',registry)


if __name__=='__main__':unittest.main()
