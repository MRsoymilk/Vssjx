"""The browser includes every effect ANI without inventing skill mappings."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import import_effect_catalog as exporter
from import_assets import parse_ani


class OriginalEffectsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.destination = ROOT / 'client/assets/admin/effects'
        cls.catalog = json.loads((cls.destination / 'catalog.json').read_text('utf-8'))
        cls.source = ROOT / 'analysis/unpacked/ssjx/effect'

    def test_all_animation_and_image_members_are_covered(self):
        directory = json.loads((self.source / 'directory.json').read_text('utf-8'))
        rows = self.catalog['effects']
        self.assertEqual(len(rows), 159)
        self.assertEqual(self.catalog['animation_count'], 159)
        self.assertEqual(self.catalog['image_member_count'], 75)
        self.assertEqual({Path(row['source_member']).name for row in rows}, {row['name'] for row in directory if row['name'].endswith('.ani')})
        self.assertEqual({image['source_member'] for row in rows for image in row['image_sources']}, {row['path'] for row in directory if row['name'].endswith('.imgs')})
        self.assertEqual(len({row['id'] for row in rows}), len(rows))
        self.assertTrue({'t00', 't1', 't180', 'flash'} <= {row['resource_id'] for row in rows})

    def test_provenance_original_sequences_and_unknown_skill_rules(self):
        from PIL import Image
        self.assertEqual(hashlib.sha256((ROOT / 'analysis/source/ssjx/effect.mrp').read_bytes()).hexdigest(), self.catalog['source_sha256'])
        for row in self.catalog['effects']:
            with self.subTest(effect=row['id']):
                ani = self.source / Path(row['source_member']).name
                self.assertEqual(hashlib.sha256(ani.read_bytes()).hexdigest(), row['source_sha256'])
                original = parse_ani(ani)
                info = row['animation']
                self.assertEqual(info['count'], len(original['frames']))
                self.assertEqual(info['sequences'], json.loads(json.dumps(original['sequences'])))
                self.assertNotIn('playback', info)
                for key in ('original_name', 'original_effect_id', 'skill_mapping'):
                    self.assertIsNone(row[key])
                texture = ROOT / 'client' / info['texture'].removeprefix('res://')
                self.assertEqual(hashlib.sha256(texture.read_bytes()).hexdigest(), row['texture_sha256'])
                with Image.open(texture) as atlas:
                    self.assertEqual(atlas.size, (info['width'] * info['columns'], info['height'] * ((info['count'] + info['columns'] - 1) // info['columns'])))

    def test_regeneration_is_deterministic(self):
        with tempfile.TemporaryDirectory(prefix='vssjx-effects-', dir='/tmp/opencode') as directory:
            destination = Path(directory)
            sentinel = destination / 'preserve.txt'
            sentinel.write_text('unrelated')
            self.assertEqual(json.loads(json.dumps(exporter.export_catalog(destination))), self.catalog)
            for path in self.destination.iterdir():
                if path.suffix in ('.png', '.json'):
                    self.assertEqual((destination / path.name).read_bytes(), path.read_bytes(), path.name)
            self.assertEqual(sentinel.read_text(), 'unrelated')


if __name__ == '__main__':
    unittest.main()
