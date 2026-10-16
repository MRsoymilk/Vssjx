"""All original entries survive, even unsupported, damaged or missing files."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import import_resource_archive as exporter


class ResourceArchiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = json.loads((ROOT / 'client/assets/admin/archive/catalog.json').read_text('utf-8'))
        cls.records = {row['resource_path']: row for row in cls.catalog['records']}

    def test_all_six_package_directories_and_sidecars_are_archived(self):
        expected = set()
        for directory in (ROOT / 'analysis/unpacked/ssjx').rglob('directory.json'):
            expected.update(row['path'] for row in json.loads(directory.read_text('utf-8')))
        self.assertEqual(len(expected), 1916)
        expected.update(path.relative_to(ROOT / 'analysis/source').as_posix() for path in (ROOT / 'analysis/source').rglob('*') if path.is_file() and path.suffix.lower() != '.mrp')
        self.assertEqual(set(self.records), expected)
        self.assertEqual(len(self.records), 1917)
        self.assertEqual(self.catalog['record_count'], len(self.records))
        self.assertEqual(sum(self.catalog['status_counts'].values()), len(self.records))
        self.assertEqual(len(self.catalog['packages']), 6)
        self.assertEqual(len({row['id'] for row in self.catalog['records']}), len(self.records))

    def test_raw_provenance_and_unsupported_records_remain_visible(self):
        for row in self.records.values():
            raw = (ROOT / row['source_file']).read_bytes()
            self.assertEqual(row['sha256'], hashlib.sha256(raw).hexdigest(), row['id'])
            self.assertEqual(row['size'], len(raw), row['id'])
            self.assertEqual(row['hex_prefix'], raw[:128].hex(), row['id'])
            self.assertTrue(row['reason'])
        for name in ('ssjx.mrp/sfc.bin', 'ssjx.mrp/start.mr'):
            self.assertEqual(self.records[name]['status'], '未解析')
            self.assertEqual(self.records[name]['preview']['kind'], 'unavailable')
        self.assertEqual(self.records['ssjx.mrp/gameonline.ext']['status'], '部分解析')
        self.assertEqual(self.records['ssjx/commonRecord/version']['status'], '已解析')
        self.assertEqual(len(self.records['ssjx/commonRecord/version']['parsed']['local_version_records']), 5)
        self.assertEqual(self.records['ssjx/map.mrp/m0.ani']['parsed']['frames'], [])
        self.assertEqual(self.records['ssjx/map.mrp/m0.ani']['status'], '部分解析')

    def test_all_decoded_image_frames_and_texts_are_available(self):
        from PIL import Image
        manifest = json.loads((ROOT / 'analysis/image_manifest.json').read_text('utf-8'))
        by_source = {row['source_file'].removeprefix('analysis/unpacked/'): row for row in self.records.values()}
        for image in manifest['images']:
            row = by_source[image['file'].replace('\\', '/')]
            self.assertEqual(row['status'], '已解析')
            info = row['preview']['animation']
            index = image['frame']
            x, y = (index % info['columns']) * info['width'], (index // info['columns']) * info['height']
            with Image.open(ROOT / 'client' / info['texture'].removeprefix('res://')) as atlas, Image.open(ROOT / 'analysis' / image['png'].replace('\\', '/')) as original:
                self.assertEqual(atlas.crop((x, y, x + image['width'], y + image['height'])).tobytes(), original.convert('RGBA').tobytes(), row['id'])
        texts = [row for row in self.records.values() if row['resource_path'].endswith('.str')]
        self.assertEqual(len(texts), 37)
        self.assertEqual(sum(len(group) for row in texts for group in row['parsed']['text_groups']), 802)

    def test_unknown_broken_missing_and_checksum_failures_are_never_dropped(self):
        with tempfile.TemporaryDirectory(prefix='vssjx-archive-', dir='/tmp/opencode') as directory:
            root = Path(directory)
            source = root / 'analysis/unpacked/ssjx'
            source.mkdir(parents=True)
            (root / 'analysis/source').mkdir(parents=True)
            members = []
            for name, raw in [('unknown.bin', b'unknown'), ('broken.img', b'\x03'), ('missing.bin', b'missing'), ('checksum.bin', b'expected')]:
                members.append({'name': name, 'path': 'ssjx.mrp/' + name, 'unpacked_length': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()})
                if name != 'missing.bin':
                    (source / name).write_bytes(b'changed!' if name == 'checksum.bin' else raw)
            (source / 'directory.json').write_text(json.dumps(members))
            catalog = exporter.export_catalog(root=root)
            rows = {row['resource_path']: row for row in catalog['records']}
            self.assertEqual(len(rows), 4)
            self.assertEqual(rows['ssjx.mrp/unknown.bin']['status'], '未解析')
            for name in ('broken.img', 'missing.bin', 'checksum.bin'):
                self.assertEqual(rows['ssjx.mrp/' + name]['status'], '解析失败')
                self.assertTrue(rows['ssjx.mrp/' + name]['reason'])
            self.assertIsNone(rows['ssjx.mrp/missing.bin']['sha256'])
            self.assertEqual(rows['ssjx.mrp/unknown.bin']['hex_prefix'], b'unknown'.hex())

    def test_full_regeneration_is_deterministic_and_preserves_unrelated_files(self):
        with tempfile.TemporaryDirectory(prefix='vssjx-archive-rebuild-', dir='/tmp/opencode') as directory:
            destination = Path(directory)
            sentinel = destination / 'preserve.txt'
            sentinel.write_text('unrelated')
            rebuilt = exporter.export_catalog(destination=destination)
            self.assertEqual(json.loads(json.dumps(rebuilt)), self.catalog)
            source = ROOT / 'client/assets/admin/archive'
            for path in source.iterdir():
                if path.suffix in ('.json', '.png'):
                    self.assertEqual((destination / path.name).read_bytes(), path.read_bytes(), path.name)
            self.assertEqual(sentinel.read_text(), 'unrelated')


if __name__ == '__main__':
    unittest.main()
