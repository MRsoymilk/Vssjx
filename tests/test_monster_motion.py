"""Visible main-body landmarks must stay planted/native through monster attacks."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('monster_art', ROOT / 'tools/import_assets.py')
art = importlib.util.module_from_spec(spec)
spec.loader.exec_module(art)
MONSTERS = ('langw', 'xt1', 'hs1', 'nt1')


class MonsterMotionTests(unittest.TestCase):
    def test_main_body_pixels_hold_position_and_facing_for_every_runtime_pose(self):
        for name in MONSTERS:
            animation = art.parse_ani(ROOT / f'analysis/unpacked/ssjx/monster/{name}.ani')
            info = json.loads((ROOT / f'client/assets/data/actors/monster/{name}.json').read_text('utf-8'))
            with Image.open(ROOT / 'client' / info['texture'].removeprefix('res://')) as image:
                atlas = image.convert('RGBA')
            with Image.open(ROOT / f"analysis/decoded_png/ssjx/monster/{animation['sources'][0]}_frame000.png") as image:
                body = image.convert('RGBA')
            reverse = body.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            masks = [[(x, y) for y in range(body.height) for x in range(body.width) if template.getpixel((x, y))[3]]
                     for template in (body, reverse)]
            for mode in ('idle', 'walk', 'attack'):
                for index, _ in info['playback'][mode]:
                    with self.subTest(monster=name, mode=mode, frame=index):
                        layer = next(layer for layer in animation['frames'][index]
                                     if layer['source'] == animation['sources'][0] and layer['frame'] == 0)
                        # Search neither coordinates nor direction: inspect the fixed actor
                        # anchor where the original, unmirrored head/body MUST be rendered.
                        x = (index % info['columns']) * info['width'] - body.width // 2 - info['origin'][0]
                        y = (index // info['columns']) * info['height'] + layer['y'] - info['origin'][1]
                        actual = atlas.crop((x, y, x + body.width, y + body.height))
                        scores = [sum(actual.getpixel(point) == template.getpixel(point) for point in points) / len(points)
                                  for template, points in zip((body, reverse), masks)]
                        self.assertGreater(scores[0], 0.78, 'Main body left its fixed anchor or flipped')
                        self.assertGreater(scores[0] - scores[1], 0.15, 'Native facing must win over mirrored pixels')

    def test_original_archive_composites_and_gameplay_frame_order_are_preserved(self):
        catalog = json.loads((ROOT / 'client/assets/admin/monsters/catalog.json').read_text('utf-8'))
        archived = {row['resource_id']: row for row in catalog['monsters']}
        for name in MONSTERS:
            animation = art.parse_ani(ROOT / f'analysis/unpacked/ssjx/monster/{name}.ani')
            original = copy.deepcopy(animation)
            runtime = art.bake('monster/' + name, animation, write_texture=False)
            raw = art.bake('monster/' + name, animation, output_key=name, write_texture=False,
                           texture_prefix='res://assets/admin/monsters/')
            self.assertEqual(animation, original, 'Runtime correction must not mutate parsed ANI')
            raw.pop('playback')
            self.assertEqual(json.loads(json.dumps(raw)), archived[name]['animation'])
            self.assertEqual([list(map(list, seq)) for seq in runtime['sequences']], archived[name]['animation']['sequences'])
            for mode, index in art.MONSTER_PLAYBACK['monster/' + name].items():
                self.assertEqual(runtime['playback'][mode], animation['sequences'][index])
            texture = ROOT / 'client' / raw['texture'].removeprefix('res://')
            self.assertEqual(hashlib.sha256(texture.read_bytes()).hexdigest(), archived[name]['texture_sha256'])

    def test_regenerated_runtime_pixels_and_metadata_match_checked_in_assets(self):
        for name in MONSTERS:
            animation = art.parse_ani(ROOT / f'analysis/unpacked/ssjx/monster/{name}.ani')
            with tempfile.TemporaryDirectory(prefix='monster-motion-') as folder:
                info = art.bake('monster/' + name, animation, texture_dir=folder)
                checked_in = json.loads((ROOT / f'client/assets/data/actors/monster/{name}.json').read_text('utf-8'))
                self.assertEqual(json.loads(json.dumps(info)), checked_in)
                with Image.open(Path(folder) / f'monster_{name}.png') as actual, Image.open(ROOT / 'client' / info['texture'].removeprefix('res://')) as expected:
                    self.assertEqual(actual.size, expected.size)
                    self.assertEqual(actual.convert('RGBA').tobytes(), expected.convert('RGBA').tobytes())


if __name__ == '__main__':
    unittest.main()
