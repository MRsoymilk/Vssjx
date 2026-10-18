"""Validate final native texture packing independently of the importer."""
import hashlib
import json
from pathlib import Path
import unittest
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


class BoneglowAssets(unittest.TestCase):
    def test_native_frames_and_design_icons(self):
        manifest = json.loads((ROOT/'client/assets/data/boneglow-equipment.json').read_text('utf8'))
        native = json.loads((ROOT/'client/assets/data/hero-parts.json').read_text('utf8'))
        self.assertEqual(len(manifest['sets']), 6)
        self.assertEqual(len(manifest['parts']), 30)
        for set_ in manifest['sets']:
            for part_id in [set_['head'], *set_['body'], set_['weapon']]:
                part = manifest['parts'][part_id]
                source = native['parts'][part_id.rsplit('/', 1)[1]]
                self.assertEqual(part['frames'], source['frames'], 'Preserve every native frame rectangle')
                with Image.open(ROOT/'client'/part['texture'].removeprefix('res://')) as img, Image.open(ROOT/'client'/source['texture'].removeprefix('res://')) as old:
                    self.assertEqual(img.size, old.size)
                    self.assertEqual(img.mode, 'RGBA')
                    for x, y, w, h in part['frames']:
                        expected = old.crop((x, y, x+w, y+h)).getchannel('A').getbbox()
                        actual = img.crop((x, y, x+w, y+h)).getchannel('A').getbbox()
                        self.assertEqual(actual is None, expected is None, f'No missing or invented frames in {part_id}')
                        if expected:
                            self.assertLessEqual(abs(actual[0]-expected[0]), 1)
                            self.assertLessEqual(abs(actual[3]-expected[3]), 1)
            folder = ROOT/f"client/assets/generated/equipment/boneglow/{set_['stem']}/icons"
            self.assertEqual(len(list(folder.glob('*.png'))), 10)
            for path in folder.glob('*.png'):
                with Image.open(path) as icon:
                    self.assertEqual(icon.size, (32, 32))
                    self.assertIsNotNone(icon.getchannel('A').getbbox())
                    self.assertEqual(icon.getpixel((0, 0))[3], 0)

    def test_import_checksums(self):
        report = json.loads((ROOT/'analysis/ai-generated/equipment/boneglow/runtime-import-report.json').read_text('utf8'))
        self.assertEqual(len(report), 90)
        for record in report:
            path = ROOT/'client'/record['path'].removeprefix('res://')
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), record['sha256'])


if __name__ == '__main__':
    unittest.main()
