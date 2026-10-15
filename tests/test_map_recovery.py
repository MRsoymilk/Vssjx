"""Scene parser safety/self-consistency. Fixtures are synthetic, not original maps."""
import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('scene_recovery', ROOT / 'tools/recover_original_maps.py')
recovery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recovery)


def text(value):
    encoded = value.encode('utf-16-be')
    return len(encoded).to_bytes(2, 'big') + encoded


def synthetic_scene(map_id='4', name='峨眉派', marker=(1, 0)):
    # 2 rows x 2 columns, 2 tile IDs, arbitrary unclassified interaction bytes.
    return (text(map_id) + text(name) + bytes([2, 2, 1, 2, 0, 1, 0, 128, 32, 1, 2])
            + struct.pack('>hh', 14, 15) + bytes([0, 1, 1])
            + text('合成测试文本A') + text('合成测试文本B') + bytes(marker))


class MapRecoveryTests(unittest.TestCase):
    def test_synthetic_tile_palette_and_uninterpreted_layer(self):
        scene = recovery.parse_scene(synthetic_scene(), {4: '峨眉派'})
        self.assertEqual(scene['tiles'], [13, 14, -1, 13])
        self.assertEqual(scene['interaction_bytes'], [0, 128, 32, 1])
        self.assertEqual(scene['metadata_bytes'], [0, 1])
        self.assertEqual(scene['interaction_records'][0]['x'], 1)
        self.assertNotIn('blocked', scene)
        self.assertNotIn('npc', scene)

    def test_prefix_and_truncation_rejection(self):
        original = synthetic_scene()
        for prefix in (b'', b'\x12\x34\x56\x78'):
            found = recovery.find_scene(prefix + original, {4: '峨眉派'})
            self.assertEqual(found['cache_prefix_bytes'], len(prefix))
            self.assertEqual(found['scene']['original_map_id'], 4)
        for end in range(len(original)):
            with self.subTest(end=end):
                self.assertIsNone(recovery.find_scene(original[:end], {4: '峨眉派'}))
        self.assertIsNone(recovery.find_scene(original + b'extra', {4: '峨眉派'}))

    def test_invalid_identity_geometry_palette_are_rejected(self):
        for data in (synthetic_scene('5'), synthetic_scene(name='错误名称'),
                     synthetic_scene(marker=(2, 0)), synthetic_scene('xx')):
            with self.assertRaises(ValueError):
                recovery.parse_scene(data, {4: '峨眉派'})
        original = bytearray(synthetic_scene())
        offset = len(text('4') + text('峨眉派'))
        for index, value in ((offset, 0), (offset + 2, 3), (offset + 12, 0)):
            bad = original.copy()
            bad[index] = value
            with self.assertRaises(ValueError):
                recovery.parse_scene(bad, {4: '峨眉派'})

    def test_scan_is_read_only_and_excludes_rejected_games(self):
        with tempfile.TemporaryDirectory(prefix='synthetic-map-test-') as temporary:
            folder = Path(temporary)
            (folder / '4.map').write_bytes(synthetic_scene())
            (folder / 'other.bin').write_bytes(b'not a scene')
            (folder / 'gssjxz').mkdir()
            (folder / 'gssjxz/4.map').write_bytes(synthetic_scene())
            before = {p: p.read_bytes() for p in folder.rglob('*') if p.is_file()}
            scan = recovery.scan_tree(folder, {4: '峨眉派'})
            self.assertEqual(scan['files_examined'], 2)
            self.assertEqual(len(scan['scene_candidates']), 1)
            self.assertTrue(scan['scene_candidates'][0]['review_required'])
            self.assertEqual(before, {p: p.read_bytes() for p in folder.rglob('*') if p.is_file()})


if __name__ == '__main__':
    unittest.main()
