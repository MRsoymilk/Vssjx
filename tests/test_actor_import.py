"""Visible regressions: mixed facings and a disconnected sword in male knight."""
from collections import deque
from pathlib import Path
import json
import unittest
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


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
        cls.actors = json.loads((ROOT / 'assets/data/actors.json').read_text('utf8'))
        cls.source = json.loads((ROOT / 'assets/data/original_animations.json').read_text('utf8'))

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


if __name__ == '__main__':
    unittest.main()
