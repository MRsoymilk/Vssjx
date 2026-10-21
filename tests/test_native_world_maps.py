"""Every playable map has reproducible native presentation; gameplay is untouched."""
import base64
import importlib.util
from pathlib import Path
import re
import struct
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('native_maps', ROOT/'tools/build_godot_maps.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class NativeWorldMapsTests(unittest.TestCase):
    def test_all_native_files_reproducible(self):
        for name, text in builder.build_files().items():
            with self.subTest(file=name):
                self.assertEqual((ROOT/'client'/name).read_bytes(), text.encode())

    def test_complete_directory_no_proposals(self):
        ids = {m['map_id'] for m in builder.maps()}
        self.assertEqual(len(ids), 216)
        self.assertEqual({p.stem for p in (ROOT/'client/scenes/maps').glob('*.tscn')}, ids)
        self.assertFalse(any(i.startswith('proposal_') for i in ids))

    def test_native_tile_encoding_and_navigation_signature(self):
        for m in builder.maps():
            text = builder.scene(m)
            art = builder.presentation(m['map_id'])
            raw = base64.b64decode(re.search(r'tile_map_data = PackedByteArray\("(.*?)"\)', text)[1])
            self.assertEqual(raw[:2], b'\0\0')
            cells = list(struct.iter_unpack('<hhHHHH', raw[2:]))
            self.assertEqual(len(cells), 1024)
            for i, (x, y, source, ax, ay, alt) in enumerate(cells):
                self.assertEqual((x, y, source, ax+32*ay, alt), (i%32, i//32, 0, art['ground'][i], 0))
            self.assertIn(builder.geometry_hash(m), text)

    def test_no_runtime_terrain_generation_or_eager_scene_registry(self):
        text = (ROOT/'client/scripts/shared_world_map.gd').read_text()
        self.assertNotIn('TileSet.new()', text)
        self.assertNotIn('terrain.set_cell', text)
        catalog = builder.build_files()['assets/map_resources/catalog.tres']
        self.assertEqual(catalog.count('[ext_resource'), 1)

    def test_every_map_rebuilt_with_original_tiles_and_unchanged_navigation(self):
        for m in builder.maps():
            art=builder.presentation(m['map_id'])
            with self.subTest(map=m['map_id']):
                self.assertNotEqual(art['composite'],m['tiles'])
                self.assertTrue(all(0<=t<756 for t in art['composite']))
                self.assertEqual(art['scenery'][:len(m['scenery'])],m['scenery'])
                for p in art['scenery']:
                    self.assertTrue(m['blocked'][int(p['y']//16)*32+int(p['x']//16)])
                for b in art['buildings']:
                    x,y=b['cell'];w,h=b['size']
                    for dy in range(h):
                        for dx in range(w):
                            i=(y+dy)*32+x+dx
                            self.assertEqual(art['composite'][i],m['tiles'][i])
                            self.assertTrue(m['blocked'][i])

    def test_reference_stairs_water_and_guardian_are_preserved(self):
        for m in builder.maps():
            art=builder.presentation(m['map_id'])
            if m['map_id']=='ai_021':
                for y in range(12,16):
                    for x in range(14,19):self.assertEqual(art['composite'][y*32+x],72)
            protected=[m['spawn'],*[r['cell'] for r in m.get('residents',[])]]
            protected += [p for g in m.get('exits',[]) for p in g.get('cells',[g['cell']])]
            if m['map_id']=='ai_001':protected.append([12,15])
            for prop in art['scenery'][len(m['scenery']):]:
                x,y=int(prop['x']//16),int(prop['y']//16)
                self.assertFalse(any(abs(x-p[0])<=4 and -1<=y-p[1]<=7 for p in protected))

    def test_flat_fill_vocabulary_has_no_accidental_shore_or_cliff_pixels(self):
        from PIL import Image
        atlas=Image.open(ROOT/'client/assets/tiles/original_tiles.png').convert('RGBA')
        for tile in (88,31,474):
            crop=atlas.crop((tile%32*16,tile//32*16,tile%32*16+16,tile//32*16+16))
            self.assertEqual(len(crop.getcolors(256)),1)
        for m in builder.maps():
            if m.get('biome')=='snow' and m.get('layout_archetype')!='earth_gate_sect':
                self.assertIn(474,builder.presentation(m['map_id'])['ground'])


if __name__ == '__main__':
    unittest.main()
