"""Independent native-layout anchors, complete icon coverage, and safe item rules."""
import json
from pathlib import Path
import struct
import unittest
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]


class FullShopTests(unittest.TestCase):
    def test_confirmed_ginseng_reuses_original_id_and_fixed_mana(self):
        catalog=json.loads((ROOT/'client/assets/data/shop-v2.json').read_text('utf8'))
        item=next(i for i in catalog['items'] if i['id']=='original/ix14')
        self.assertEqual((item['name'],item['slot'],item['category']),('极品人参','consumable','药品'))
        self.assertEqual((item['restore_hp'],item['restore_mp'],item['price']),(0,4000,10))
        self.assertEqual(item['icon'],'res://assets/items/original/ix14.png')
        self.assertEqual(item['sections'],['hot','elixir'])
        self.assertEqual(item['original_confirmation']['restore_mp'],4000)

    def test_confirmed_herb_reuses_original_id_icon_and_fixed_healing(self):
        catalog=json.loads((ROOT/'client/assets/data/shop-v2.json').read_text('utf8'))
        herb=next(i for i in catalog['items'] if i['id']=='original/ix10')
        self.assertEqual((herb['name'],herb['slot'],herb['category']),('生骨融血草','consumable','药品'))
        self.assertEqual((herb['restore_hp'],herb['restore_mp'],herb['price']),(8000,0,10))
        self.assertEqual(herb['icon'],'res://assets/items/original/ix10.png')
        self.assertEqual(herb['sections'],['hot','elixir'])
        self.assertEqual(herb['original_confirmation']['restore_hp'],8000)

    def test_generated_families_coexist_without_replacing_original_items(self):
        catalog=json.loads((ROOT/'client/assets/data/shop-v2.json').read_text('utf8'))
        self.assertEqual(len(catalog['items']),459)
        self.assertEqual(len([i for i in catalog['items'] if i['id']=='ai/legendary/potian_axe']),1)
        self.assertEqual(len([i for i in catalog['items'] if i['id'].startswith('ai/gravebloom/')]),60)
        self.assertEqual(len([i for i in catalog['items'] if i['id'].startswith('ai/boneglow/')]),60)
        self.assertEqual(len([i for i in catalog['items'] if i['id'].startswith('ai/eva01/')]),60)
        self.assertEqual(len([i for i in catalog['items'] if i['id'].startswith('ai/vow/')]),60)
        self.assertEqual(len({i['id'] for i in catalog['items']}),459)
        scroll=next(i for i in catalog['items'] if i['id']=='restored/shenxing_scroll')
        self.assertEqual((scroll['name'],scroll['price'],scroll['effect']),('神行符',30,'teleport'))
        self.assertIn('rare',scroll['sections'])

    def test_every_original_member_is_available_once(self):
        original=json.loads((ROOT/'client/assets/data/original_items.json').read_text('utf8'))['items']
        full=json.loads((ROOT/'client/assets/data/shop-v2.json').read_text('utf8'))['items']
        raw=[x for x in full if x['id'].startswith('original/')]
        self.assertEqual(len(raw),208)
        self.assertEqual({x['id'] for x in raw},{x['id'] for x in original})
        by_id={x['id']:x for x in original}
        for item in raw:
            self.assertEqual(item['icon'],by_id[item['id']]['icon'])
            self.assertEqual(item['source_sha256'],by_id[item['id']]['source_sha256'])
            self.assertTrue((ROOT/'client'/item['icon'].removeprefix('res://')).is_file())
            self.assertIn('重建',item['rules_basis'])

    def test_all_slots_and_medicine_variants_are_populated(self):
        c=json.loads((ROOT/'client/assets/data/shop-v2.json').read_text('utf8'))
        self.assertEqual(len(c['slots']),10)
        for slot in c['slots']:
            self.assertGreaterEqual(len([i for i in c['items'] if i['slot']==slot]),7 if slot!='weapon' else 56)
        meds=[i for i in c['items'] if i['slot']=='consumable']
        self.assertGreaterEqual(len(meds),20)
        self.assertTrue(any(i['restore_mp']>0 and i['restore_hp']==0 for i in meds))
        self.assertTrue(any(i['restore_mp']>0 and i['restore_hp']>0 for i in meds))
        for i in c['items']:
            self.assertGreater(i['price'],0)
            self.assertTrue(0<=i['attack']<=100 and 0<=i['defense']<=100)
            self.assertIn(i['slot'],c['slots']+['material','consumable','gourd'])

    def test_original_shop_is_two_columns_with_icon_and_four_tabs(self):
        b=(ROOT/'analysis/unpacked/ssjx/gameonline.ext').read_bytes()
        self.assertEqual(struct.unpack_from('<HH',b,0x1a49c),(0x2326,0x2270))
        self.assertEqual(struct.unpack_from('<HH',b,0x1a4f4),(0x2320,0x221c))
        text=(ROOT/'analysis/decoded_text/ssjx/shop.txt').read_text('utf8')
        for n,s in [(10,'热卖'),(11,'奇珍'),(12,'炼制'),(13,'仙丹')]:self.assertIn(f'{n:03}. {s}',text)

    def test_part_atlases_preserve_each_source_pixel(self):
        manifest=json.loads((ROOT/'client/assets/data/hero-parts.json').read_text('utf8'))
        for key,part in manifest['parts'].items():
            with Image.open(ROOT/'client'/part['texture'].removeprefix('res://')) as atlas:
                for index,(x,y,w,h) in enumerate(part['frames']):
                    with Image.open(ROOT/f'analysis/decoded_png/ssjx/hero/{key}_frame{index:03}.png') as source:
                        self.assertEqual(atlas.crop((x,y,x+w,y+h)).tobytes(),source.convert('RGBA').tobytes(),key)


if __name__=='__main__':unittest.main()
