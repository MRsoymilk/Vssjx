"""Client and authoritative server must ship the same playable map definitions."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SharedWorldDataTests(unittest.TestCase):
    def test_identical_map_and_population_bytes(self):
        for name in ('qingyun-v1.json', 'qingyun-population-v1.json'):
            with self.subTest(name=name):
                self.assertEqual((ROOT / 'shared/data' / name).read_bytes(),
                                 (ROOT / 'client/assets/data' / name).read_bytes())

    def test_shared_residents_have_unique_reachable_spawns(self):
        world = json.loads((ROOT / 'shared/data/qingyun-v1.json').read_bytes())
        residents = json.loads((ROOT / 'shared/data/qingyun-population-v1.json').read_bytes())
        self.assertEqual(len({entry['id'] for entry in residents}), len(residents))
        spawn = tuple(world['spawn'])
        reachable = {spawn}
        pending = [spawn]
        while pending:
            x, y = pending.pop()
            for cell in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                cx, cy = cell
                if (0 <= cx < world['width'] and 0 <= cy < world['height']
                        and not world['blocked'][cy * world['width'] + cx]
                        and cell not in reachable):
                    reachable.add(cell)
                    pending.append(cell)
        for entry in residents:
            with self.subTest(resident=entry['id']):
                self.assertIn(tuple(entry['cell']), reachable)


if __name__ == '__main__':
    unittest.main()
