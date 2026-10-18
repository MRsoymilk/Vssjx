"""Preserve player evidence while testing the authored runtime assignments."""
import collections,json,sys,unittest
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from ai_world_monsters import sheet_records,ART_KEYS
from build_ai_monster_art import build_asset,LEGACY
from import_assets import parse_ani
from native_ani import native_steps

class MonsterTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.maps=json.loads((ROOT/'shared/data/ai-world-v1.json').read_text(encoding='utf8'))['maps']
  cls.monsters=[(m,r) for m in cls.maps for r in m['residents'] if r['kind']!='npc']

 def test_every_sheet_placement_is_present_once_without_inventing_evidence(self):
  expected={(r['map_csv_index']+1,r['source_row'],r['source_columns']):r for r in sheet_records()}
  found=[]
  for m,r in self.monsters:
   ref=r['reference']
   if not ref['source'].startswith('用户'):continue
   key=(m['original_map_id'],ref['source_row'],ref['source_columns']);found.append(key)
   self.assertEqual(ref['label_raw'],expected[key]['label_raw'])
   self.assertEqual(ref['reported_level'],expected[key]['reported_level'])
   if ref['reported_level'] is not None:self.assertEqual(r['level'],ref['reported_level'])
   self.assertIn('AI',ref['appearance']);self.assertIn('AI',ref['stats'])
  self.assertEqual(collections.Counter(found),collections.Counter({k:1 for k in expected}))

 def test_diverse_runtime_assets_and_table_specific_maps(self):
  self.assertGreaterEqual(len({r['art'] for m,r in self.monsters}),70)
  maps={m['original_map_id']:m for m in self.maps}
  for num,art in [(9,'xt4'),(12,'srh2'),(55,'yuanling1'),(64,'x1'),(84,'ysg3'),(94,'dyq3')]:
   self.assertIn('monster/'+art,[r['art'] for r in maps[num]['residents']])
  for m,r in self.monsters:
   path=ROOT/'client/assets/data/actors'/(r['art']+'.json')
   self.assertTrue(path.is_file(),r['art'])

 def test_added_art_keeps_original_native_states_and_rebuilds(self):
  for name in sorted(ART_KEYS-LEGACY):
   with self.subTest(monster=name):
    meta=json.loads((ROOT/'client/assets/data/actors/monster'/(name+'.json')).read_text(encoding='utf8'))
    source=parse_ani(ROOT/'analysis/unpacked/ssjx/monster'/(name+'.ani'))
    for mode,slot in [('idle',4),('walk',4),('attack',5),('hurt',6)]:
     self.assertEqual(meta['playback'][mode],native_steps(source,slot))
    self.assertNotEqual(meta['playback']['attack'],meta['playback']['hurt'])
    # JSON normalization makes native tuple pairs comparable with serialized arrays.
    self.assertEqual(meta,json.loads(json.dumps(build_asset(name,False))))
    with Image.open(ROOT/'client'/meta['texture'].removeprefix('res://')) as image:
     self.assertEqual(image.width,meta['width']*meta['columns'])
     self.assertEqual(image.height,meta['height']*((meta['count']+meta['columns']-1)//meta['columns']))

if __name__=='__main__':unittest.main()
