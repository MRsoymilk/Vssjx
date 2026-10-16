"""Every original monster composition is browsable without inventing rules."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import import_monster_catalog as exporter
from import_assets import parse_ani


class OriginalMonstersTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.destination = ROOT / 'client/assets/admin/monsters'
        cls.catalog = json.loads((cls.destination / 'catalog.json').read_text('utf-8'))
        cls.source = ROOT / 'analysis/unpacked/ssjx/monster'

    def test_every_original_animation_and_image_member_is_covered(self):
        directory = json.loads((self.source / 'directory.json').read_text('utf-8'))
        animations = {row['name'] for row in directory if row['name'].endswith('.ani')}
        images = {row['path'] for row in directory if row['name'].endswith('.imgs')}
        rows = self.catalog['monsters']
        self.assertEqual(len(rows), 117)
        self.assertEqual(self.catalog['animation_count'], 117)
        self.assertEqual(self.catalog['image_member_count'], 142)
        self.assertEqual({Path(row['source_member']).name for row in rows}, animations)
        self.assertEqual({image['source_member'] for row in rows for image in row['image_sources']}, images)
        self.assertEqual(len({row['id'] for row in rows}), len(rows))

    def test_source_hashes_and_original_sequence_numbers_match(self):
        archive = ROOT / 'analysis/source/ssjx/monster.mrp'
        self.assertEqual(hashlib.sha256(archive.read_bytes()).hexdigest(), self.catalog['source_sha256'])
        for row in self.catalog['monsters']:
            with self.subTest(resource=row['id']):
                ani = self.source / Path(row['source_member']).name
                self.assertEqual(hashlib.sha256(ani.read_bytes()).hexdigest(), row['source_sha256'])
                animation = parse_ani(ani)
                self.assertEqual(len(animation['frames']), row['animation']['count'])
                self.assertEqual([list(map(list, steps)) for steps in animation['sequences']], row['animation']['sequences'])
                self.assertEqual({image['source_member'].rsplit('/', 1)[-1].removesuffix('.imgs') for image in row['image_sources']}, set(animation['sources']))
                for image in row['image_sources']:
                    path = self.source / Path(image['source_member']).name
                    self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), image['source_sha256'])

    def test_atlases_and_unknown_gameplay_fields(self):
        from PIL import Image
        for row in self.catalog['monsters']:
            with self.subTest(resource=row['id']):
                for key in ('original_name', 'original_monster_id', 'level', 'stats'):
                    self.assertIsNone(row[key])
                info = row['animation']
                self.assertNotIn('playback', info)
                texture = ROOT / 'client' / info['texture'].removeprefix('res://')
                self.assertEqual(hashlib.sha256(texture.read_bytes()).hexdigest(), row['texture_sha256'])
                with Image.open(texture) as atlas:
                    self.assertEqual(atlas.size, (info['width'] * info['columns'], info['height'] * ((info['count'] + info['columns'] - 1) // info['columns'])))

    def test_regeneration_is_deterministic_and_preserves_unrelated_files(self):
        with tempfile.TemporaryDirectory(prefix='vssjx-monsters-', dir='/tmp/opencode') as directory:
            destination = Path(directory)
            sentinel = destination / 'preserve.txt'
            sentinel.write_text('unrelated')
            self.assertEqual(json.loads(json.dumps(exporter.export_catalog(destination))), self.catalog)
            for path in self.destination.iterdir():
                if path.suffix not in ('.json', '.png'):
                    continue
                self.assertEqual((destination / path.name).read_bytes(), path.read_bytes(), path.name)
            self.assertEqual(sentinel.read_text(), 'unrelated')


if __name__ == '__main__':
    unittest.main()
