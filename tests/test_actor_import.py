"""Visible regressions: mixed facings and a disconnected sword in male knight."""
from collections import deque
from pathlib import Path
import json
import unittest
from PIL import Image

ROOT = Path(__file__).resolve().parents[1] / 'client'


def runtime_actors():
    index = json.loads((ROOT / 'assets/data/actors.json').read_text('utf8'))
    return {key: json.loads((ROOT / path.removeprefix('res://')).read_text('utf8'))
            for key, path in index['actors'].items()}


def original_animations():
    folder = ROOT.parent / 'analysis/animations'
    index = json.loads((folder / 'index.json').read_text('utf8'))
    return {key: json.loads((folder / path).read_text('utf8'))
            for key, path in index['animations'].items()}


def components(image):
    alpha = image.getchannel('A')
    points = {(x, y) for y in range(image.height) for x in range(image.width) if alpha.getpixel((x, y))}
    sizes = []
    while points:
        queue = deque([points.pop()])
        count = 0
        while queue:
            x, y = queue.popleft()
            count += 1
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    neighbor = (x + dx, y + dy)
                    if neighbor in points:
                        points.remove(neighbor)
                        queue.append(neighbor)
        sizes.append(count)
    return sorted(sizes, reverse=True)


class ActorImportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.actors = runtime_actors()
        cls.source = original_animations()

    def test_all_six_characters_hold_facing_through_the_entire_walk(self):
        for name in ('mck', 'wck', 'mzs', 'wzs', 'mfs', 'wfs'):
            key = 'hero/' + name
            source = self.source[key]
            steps = self.actors[key]['playback']['walk']
            self.assertEqual(len(steps), 6)
            for index, _ in steps:
                layers = source['frames'][index]
                head = next(layer for layer in layers if layer['source'] == source['sources'][0] and layer['frame'] == 0)
                self.assertEqual(head['transform'], 0, (key, index))
                self.assertTrue(any(layer['source'].endswith('x') for layer in layers), (key, index))

    def test_all_characters_and_previews_have_a_real_native_idle_loop(self):
        for group in ('hero', 'creation'):
            for name in ('mck', 'wck', 'mzs', 'wzs', 'mfs', 'wfs'):
                key = group + '/' + name
                info = self.actors[key]
                source = self.source['hero/' + name]
                steps = info['playback']['idle']
                self.assertEqual(steps, [[info['count'] - 14, 4], [info['count'] - 13, 4]], key)
                atlas = Image.open(ROOT / info['texture'].removeprefix('res://')).convert('RGBA')
                pixels = []
                for index, _ in steps:
                    layers = source['frames'][index]
                    head = next(layer for layer in layers if layer['source'] == source['sources'][0] and layer['frame'] == 0)
                    self.assertEqual(head['transform'], 0, (key, index))
                    self.assertFalse(any(layer['source'].endswith('x') or layer['source'].startswith('tx') for layer in layers), (key, index))
                    x, y = index % info['columns'] * info['width'], index // info['columns'] * info['height']
                    pixels.append(atlas.crop((x, y, x + info['width'], y + info['height'])).tobytes())
                self.assertNotEqual(pixels[0], pixels[1], key)

    def test_knight_blades_remain_attached_to_the_character(self):
        info = self.actors['hero/mck']
        atlas = Image.open(ROOT / info['texture'].replace('res://', '')).convert('RGBA')
        for index, _ in info['playback']['idle'] + info['playback']['walk']:
            x = index % info['columns'] * info['width']
            y = index // info['columns'] * info['height']
            frame = atlas.crop((x, y, x + info['width'], y + info['height']))
            # The old mapping leaves a detached 59-pixel sword to the left.
            # Small isolated shadow/antialias pixels are not weapon islands.
            large = [size for size in components(frame) if size >= 40]
            self.assertEqual(len(large), 1, (index, large))
            self.assertGreater(large[0], 850)

    def test_mage_attacks_and_casts_keep_native_facing_and_staff_motion(self):
        for key in ('hero/mfs', 'hero/wfs'):
            source = self.source[key]
            playback = self.actors[key]['playback']
            self.assertEqual(playback['attack'], source['sequences'][4])
            self.assertEqual(playback['cast'], source['sequences'][6])
            for mode in ('attack', 'cast'):
                for index, _ in playback[mode]:
                    head = next(layer for layer in source['frames'][index]
                                if layer['source'] == source['sources'][0] and layer['frame'] == 0)
                    self.assertEqual(head['transform'], 0, (key, mode, index))
            staff = source['sources'][2]
            poses = {(layer['x'], layer['y'], layer['transform']) for index, _ in playback['cast']
                     for layer in source['frames'][index] if layer['source'] == staff}
            self.assertGreaterEqual(len(poses), 3, key)


if __name__ == '__main__':
    unittest.main()
