"""Validate final native texture packing independently of the importer."""
import hashlib
import json
from pathlib import Path
import unittest
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


class BoneglowAssets(unittest.TestCase):
    FAMILY = 'boneglow'

    def test_native_frames_and_design_icons(self):
        manifest = json.loads((ROOT/f'client/assets/data/{self.FAMILY}-equipment.json').read_text('utf8'))
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
            folder = ROOT/f"client/assets/generated/equipment/{self.FAMILY}/{set_['stem']}/icons"
            self.assertEqual(len(list(folder.glob('*.png'))), 10)
            for path in folder.glob('*.png'):
                with Image.open(path) as icon:
                    self.assertEqual(icon.size, (32, 32))
                    self.assertIsNotNone(icon.getchannel('A').getbbox())
                    self.assertEqual(icon.getpixel((0, 0))[3], 0)

    def test_import_checksums(self):
        report = json.loads((ROOT/f'analysis/ai-generated/equipment/{self.FAMILY}/runtime-import-report.json').read_text('utf8'))
        self.assertEqual(len(report), 90)
        for record in report:
            path = ROOT/'client'/record['path'].removeprefix('res://')
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), record['sha256'])

    def test_frost_icons_exclude_previous_row_feet(self):
        if self.FAMILY != 'boneglow':
            self.skipTest('Regression concerns the boneglow review atlas')
        report = json.loads((ROOT/'analysis/ai-generated/equipment/boneglow/runtime-import-report.json').read_text('utf8'))
        expected = {'weapon': 407, 'hat': 421, 'armor': 761, 'wrist': 211}
        cleaned = {Path(r['path']).stem: r['removed_border_pixels'] for r in report if 'removed_border_pixels' in r}
        self.assertEqual(cleaned, expected, 'Only the four clipped foot fragments need cleanup')
        for slot in expected:
            with Image.open(ROOT/f'client/assets/generated/equipment/boneglow/wck/icons/{slot}.png') as icon:
                alpha = icon.getchannel('A')
                bbox = alpha.getbbox()
                # Detached feet previously left a large blank stripe above the item.
                occupied = [any(alpha.getpixel((x, y)) for x in range(32)) for y in range(bbox[1], bbox[3])]
                self.assertTrue(all(occupied), f'{slot}: no detached fragment above the item')


    def test_female_lishi_face_preserves_aspect_neck_and_back_frame(self):
        if self.FAMILY != 'boneglow':
            self.skipTest('Face correction concerns boneglow female lishi')
        folder = ROOT/'analysis/ai-generated/equipment/boneglow'
        config = json.loads((folder/'face-correction-config.json').read_text('utf8'))
        override = config['atlas_overrides']['02_female_lishi']
        self.assertEqual(override['cells'], [0])
        self.assertTrue(override['preserve_aspect'])
        with Image.open(folder/'02_female_lishi-head-before.png') as old, Image.open(ROOT/'client/assets/generated/equipment/boneglow/wzs/parts/wzst2.png') as current, Image.open(folder/override['file']) as source:
            self.assertEqual(current.size, old.size)
            self.assertEqual(current.crop((42,0,62,16)).tobytes(), old.crop((42,0,62,16)).tobytes(), 'Back-facing head must remain unchanged')
            alpha = current.crop((0,0,42,43)).getchannel('A')
            actual = alpha.getbbox()
            self.assertEqual(actual[3], old.crop((0,0,42,43)).getchannel('A').getbbox()[3], 'Neck remains at the native anchor')
            cell = source.crop((0,0,int(source.width/4+.5),int(source.height/5+.5)))
            bounds = cell.getchannel('A').point(lambda a: 255 if a >= 128 else 0).getbbox()
            width, height = bounds[2]-bounds[0], bounds[3]-bounds[1]
            self.assertLessEqual(abs((actual[2]-actual[0])*height-(actual[3]-actual[1])*width), max(width,height), 'Import must not stretch the new eyes and jaw')
            self.assertLessEqual(set(alpha.tobytes()), {0,255}, 'Native sprite has no blended alpha fringe')

if __name__ == '__main__':
    unittest.main()
