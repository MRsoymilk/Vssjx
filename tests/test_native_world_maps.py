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
            raw = base64.b64decode(re.search(r'tile_map_data = PackedByteArray\("(.*?)"\)', text)[1])
            self.assertEqual(raw[:2], b'\0\0')
            cells = list(struct.iter_unpack('<hhHHHH', raw[2:]))
            self.assertEqual(len(cells), 1024)
            for i, (x, y, source, ax, ay, alt) in enumerate(cells):
                self.assertEqual((x, y, source, ax+32*ay, alt), (i%32, i//32, 0, m['tiles'][i], 0))
            self.assertIn(builder.geometry_hash(m), text)

    def test_no_runtime_terrain_generation_or_eager_scene_registry(self):
        text = (ROOT/'client/scripts/shared_world_map.gd').read_text()
        self.assertNotIn('TileSet.new()', text)
        self.assertNotIn('terrain.set_cell', text)
        catalog = builder.build_files()['assets/map_resources/catalog.tres']
        self.assertEqual(catalog.count('[ext_resource'), 1)


if __name__ == '__main__':
    unittest.main()
