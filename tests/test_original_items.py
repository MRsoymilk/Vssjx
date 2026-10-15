"""Every recovered item member must be available in the Godot data browser."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('item_exporter', ROOT / 'tools/import_item_catalog.py')
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)


class OriginalItemsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = json.loads((ROOT / 'client/assets/data/original_items.json').read_text('utf-8'))

    def test_complete_source_member_coverage(self):
        source = ROOT / 'analysis/unpacked/ssjx/item'
        expected = {p.name for p in source.iterdir() if p.suffix in ('.img', '.imgs')}
        actual = {Path(row['source_member']).name for row in self.catalog['items']}
        self.assertEqual(actual, expected)
        self.assertEqual(len(actual), 208)
        self.assertEqual(self.catalog['counts'], {'weapons': 56, 'equipment': 81, 'other': 71})

    def test_unique_ids_and_no_assumed_contiguous_numbers(self):
        rows = self.catalog['items']
        self.assertEqual(len({row['id'] for row in rows}), len(rows))
        ids = {row['resource_id'] for row in rows}
        self.assertIn('iw56', ids)
        self.assertIn('ix0', ids)
        self.assertIn('if83', ids)
        self.assertNotIn('if15', ids)  # Gaps in the real package must stay gaps.

    def test_icons_are_lossless_copies_and_provenance_matches(self):
        from PIL import Image
        for row in self.catalog['items']:
            with self.subTest(item=row['id']):
                raw = ROOT / 'analysis/unpacked' / row['source_member']
                decoded = ROOT / 'analysis' / row['decoded_png']
                exported = ROOT / 'client' / row['icon'].removeprefix('res://')
                self.assertEqual(hashlib.sha256(raw.read_bytes()).hexdigest(), row['source_sha256'])
                self.assertEqual(raw.stat().st_size, row['source_bytes'])
                self.assertEqual(decoded.read_bytes(), exported.read_bytes())
                self.assertEqual(hashlib.sha256(exported.read_bytes()).hexdigest(), row['png_sha256'])
                with Image.open(exported) as icon:
                    self.assertEqual(icon.size, (row['width'], row['height']))

    def test_no_fabricated_names_ids_levels_slots_or_stats(self):
        for row in self.catalog['items']:
            for key in ('original_name', 'original_item_id', 'level', 'stats', 'equipment_slot'):
                self.assertIsNone(row[key], (row['id'], key))

    def test_regeneration_matches_checked_in_catalog(self):
        self.assertEqual(exporter.build_catalog(), self.catalog)
        with tempfile.TemporaryDirectory(prefix='ssjx-items-') as directory:
            dest = Path(directory)
            sentinel = dest / 'preserve.txt'
            sentinel.write_text('unrelated')
            exporter.export_catalog(destination=dest)
            first = (dest / 'data/original_items.json').read_bytes()
            exporter.export_catalog(destination=dest)
            self.assertEqual(first, (dest / 'data/original_items.json').read_bytes())
            self.assertEqual(first, (ROOT / 'client/assets/data/original_items.json').read_bytes())
            self.assertEqual(len(list((dest / 'items/original').glob('*.png'))), 208)
            self.assertEqual(sentinel.read_text(), 'unrelated')

    def test_resource_paths_cannot_escape_source_tree(self):
        for path in ('../private', '/private', 'C:/private', '..\\private'):
            with self.assertRaises(ValueError):
                exporter.safe_file(ROOT / 'analysis', path)


if __name__ == '__main__':
    unittest.main()
