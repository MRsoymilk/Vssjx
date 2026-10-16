"""Original root naming and additional-source review boundaries; no false maps."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('cache_paths', ROOT / 'tools/audit_original_map_cache_paths.py')
cache = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cache)


class MapCachePathTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.package = (ROOT / 'analysis/source/ssjx.mrp').read_bytes()
        cls.native = (ROOT / 'analysis/unpacked/ssjx/gameonline.ext').read_bytes()

    def test_actual_internal_filename_drives_root_instead_of_download_name(self):
        flow = cache.cache_path_evidence(self.native, self.package)
        self.assertEqual(flow['internal_filename'], 'ssjx.mpr')
        self.assertEqual(flow['map_directory_relative_to_runtime_directory'], 'gwy/ssjx/map')
        self.assertEqual(flow['header_selector_target'], '0x2ced4')
        self.assertEqual(flow['calls']['0x24ba0'], '0x2ce1c')
        for row in flow['evidence']:
            self.assertEqual(row['sha256'], cache.audit.digest(self.native[int(row['start'], 16):int(row['end_exclusive'], 16)]))
        renamed = bytearray(self.package)
        renamed[16:28] = b'demo.v1.mrp\0'
        self.assertEqual(cache.cache_path_evidence(self.native, renamed)['basename'], 'demo.v1')
        with self.assertRaises(ValueError):
            cache.cache_path_evidence(self.native[:-1], self.package)

    def test_cache_tree_is_read_only_and_excluded_game_is_skipped(self):
        with tempfile.TemporaryDirectory(prefix='cache-path-test-') as temporary:
            folder = Path(temporary)
            (folder / 'gwy/ssjx/map').mkdir(parents=True)
            (folder / 'gwy/ssjx/map/4.map').write_bytes(b'not original terrain')
            (folder / 'other').mkdir()
            (folder / 'other/4.map').write_bytes(b'other game')
            (folder / 'gssjxz').mkdir()
            (folder / 'gssjxz/4.map').write_bytes(b'excluded')
            before = {p: p.read_bytes() for p in folder.rglob('*') if p.is_file()}
            scanner = cache.audit.StreamScanner({4: '峨眉派'})
            row = cache.inspect_folder(folder, 'gwy/ssjx/map', scanner)
            self.assertTrue(row['expected_directory_present'])
            self.assertEqual(len(row['expected_cache_files']), 1)
            self.assertEqual(row['other_map_files_not_promoted'], 1)
            self.assertEqual(scanner.report()['candidate_count'], 0)
            self.assertEqual(before, {p: p.read_bytes() for p in folder.rglob('*') if p.is_file()})
            self.assertEqual(cache.inspect_folder(folder / 'gssjxz', 'map', scanner)['files_examined'], 0)

    def test_duplicate_sources_are_counted_once_and_not_imported(self):
        with tempfile.TemporaryDirectory(prefix='cache-source-test-') as temporary:
            folder = Path(temporary)
            first, second = folder / 'first.mrp', folder / 'renamed.mrp'
            first.write_bytes(self.package)
            second.write_bytes(self.package)
            report = cache.build_report([first, second])
            self.assertEqual(report['additional_sources'][1]['duplicate_of'], str(first))
            row = report['additional_sources'][0]['package']
            self.assertTrue(row['native_matches_reference'])
            self.assertEqual(row['different_reference_members'], [])
            self.assertEqual(row['scene_scan']['candidate_count'], 0)
            self.assertFalse(row['imported'])
            self.assertTrue(row['review_required'])

    def test_wrong_appid_and_unsafe_archive_cannot_be_imported(self):
        with tempfile.TemporaryDirectory(prefix='cache-identity-test-') as temporary:
            folder = Path(temporary)
            wrong = bytearray(self.package)
            wrong[68:72] = (479992).to_bytes(4, 'little')
            source = folder / 'same-name.mrp'
            source.write_bytes(wrong)
            report = cache.build_report([source])
            row = report['additional_sources'][0]['package']
            self.assertEqual(row['status'], 'different_appid_not_scanned_or_imported')
            self.assertNotIn('scene_scan', row)
            archive = folder / 'unsafe.zip'
            with zipfile.ZipFile(archive, 'w') as out:
                out.writestr('../escape.map', b'not a map')
            with self.assertRaises(ValueError):
                cache.build_report([archive])

    def test_checked_in_path_evidence_keeps_native_and_source_identities(self):
        report = json.loads((ROOT / 'analysis/recovery/maps/cache_path_audit.json').read_text('utf-8'))
        self.assertEqual(report['cache_path_evidence'], cache.cache_path_evidence(self.native, self.package))
        self.assertEqual(report['cache_scene_scan']['candidate_count'], 0)
        self.assertEqual(report['cache_scene_scan']['limit_hits'], [])
        for row in report['additional_sources']:
            self.assertFalse(row['imported'])
            if 'package' in row:
                self.assertEqual(row['sha256'], row['package']['sha256'])
                self.assertTrue(row['package']['review_required'])


if __name__ == '__main__':
    unittest.main()
