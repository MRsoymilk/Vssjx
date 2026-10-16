"""Static source evidence and bounded scanners; synthetic scenes are not assets."""
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('map_source_audit', ROOT / 'tools/audit_original_map_sources.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


def text(value):
    data = value.encode('utf-16-be')
    return len(data).to_bytes(2, 'big') + data


def synthetic_scene(name='峨眉派'):
    return text('4') + text(name) + bytes([1, 2, 1, 0, 0, 128, 1]) + struct.pack('>h', 14) + bytes([0, 1, 0])


class MapSourceAuditTests(unittest.TestCase):
    def test_embedded_records_do_not_relax_standalone_validation(self):
        data = synthetic_scene()
        scene, consumed = audit.recovery.parse_scene_prefix(data + b'trailer', {4: '峨眉派'})
        self.assertEqual(consumed, len(data))
        self.assertEqual(scene['tiles'], [13, -1])
        with self.assertRaises(ValueError):
            audit.recovery.parse_scene(data + b'trailer', {4: '峨眉派'})
        container = b'prefix' + data + b'gap' + data + b'trailer'
        candidates, identities, numeric = audit.embedded_candidates(container, {4: '峨眉派'})
        self.assertEqual([row['byte_offset'] for row in candidates], [6, 9 + len(data)])
        self.assertEqual((identities, numeric), (2, 2))
        self.assertTrue(all(row['review_required'] for row in candidates))
        self.assertEqual(candidates[0]['payload_sha256'], hashlib.sha256(data).hexdigest())

    def test_nested_gzip_zlib_and_trailing_wrapper_are_found(self):
        raw = synthetic_scene()
        data = b'prefix' + gzip.compress(zlib.compress(raw), mtime=0) + b'trailer'
        scanner = audit.StreamScanner({4: '峨眉派'})
        scanner.scan(data, 'synthetic-container')
        report = scanner.report()
        self.assertEqual(report['candidate_count'], 1)
        self.assertEqual(report['limit_hits'], [])
        self.assertIn('::gzip@0x6::zlib@0x0', report['candidates'][0]['source'])
        before = len(scanner.candidates)
        scanner.scan(raw, 'duplicate-synthetic')
        self.assertEqual(len(scanner.candidates), before)
        self.assertIn('duplicate_of', scanner.streams[-1])

    def test_malformed_and_wrong_identity_never_become_candidates(self):
        raw = synthetic_scene()
        for data in [raw[:-1], synthetic_scene('不匹配'), b'\0\x02\0x', b'\x1f\x8b\x08garbage']:
            scanner = audit.StreamScanner({4: '峨眉派'})
            scanner.scan(data, 'synthetic-invalid')
            self.assertEqual(scanner.report()['candidate_count'], 0)

    def test_expansion_attempt_and_depth_bounds_are_visible(self):
        compressed = gzip.compress(b'x' * 4096, mtime=0)
        for options, reason in [({'maximum_stream': 64}, 'expanded_size'),
                                ({'maximum_expanded': 64}, 'expanded_size'),
                                ({'maximum_depth': 0}, 'compression_depth'),
                                ({'maximum_attempts': 0}, 'compression_attempts')]:
            scanner = audit.StreamScanner({}, **options)
            scanner.scan(compressed, 'synthetic-bomb')
            self.assertIn(reason, {hit['reason'] for hit in scanner.limits})
            self.assertEqual(scanner.report()['candidate_count'], 0)
            self.assertEqual(scanner.expanded, 0)

    def test_native_targets_are_decoded_from_fingerprinted_bytes(self):
        native = (ROOT / 'analysis/unpacked/ssjx/gameonline.ext').read_bytes()
        flow = audit.native_flow(native)
        self.assertEqual(flow['direct_calls']['0x137f2'], '0x25430')
        self.assertEqual(flow['direct_calls']['0x13ada'], '0x27274')
        self.assertEqual(flow['direct_calls']['0x1850c'], '0x137c8')
        self.assertEqual(flow['layout_dispatch_selector'], '0x2001001')
        self.assertEqual(flow['cache_missing_request_value'], '0x2000002')
        self.assertEqual(flow['bundle_names'], ['map', 'hero', 'monster', 'effect', 'item'])
        for row in flow['ranges']:
            self.assertEqual(row['sha256'], audit.digest(native[int(row['start'], 16):int(row['end_exclusive'], 16)]))
        with self.assertRaises(ValueError):
            audit.bl_target(b'\0' * 4, 0)
        with self.assertRaises(ValueError):
            audit.literal(b'\0' * 8, 0)
        with self.assertRaises(ValueError):
            audit.native_flow(bytes([native[0] ^ 1]) + native[1:])

    def test_local_version_table_is_not_scene_geometry(self):
        data = (ROOT / 'analysis/source/ssjx/commonRecord/version').read_bytes()
        rows = audit.parse_local_versions(data, ['map', 'hero', 'monster', 'effect', 'item'])
        self.assertEqual(len(rows), 5)
        self.assertEqual(rows[-1]['bundle'], 'map')
        for row in rows:
            self.assertEqual(row['version_text'], '20120210182728')
            self.assertEqual(row['recorded_package_bytes'], (ROOT / f'analysis/source/ssjx/{row["bundle"]}.mrp').stat().st_size)
        for bad in [data[:-1], data + b'unknown', b'\xff\xff' + data[2:]]:
            with self.assertRaises(ValueError):
                audit.parse_local_versions(bad, ['map', 'hero', 'monster', 'effect', 'item'])

    def test_checked_in_source_audit_is_reproducible_and_read_only(self):
        paths = [ROOT / relative for relative in audit.PACKAGES]
        paths += [ROOT / 'analysis/unpacked/ssjx/gameonline.ext', ROOT / 'analysis/source/ssjx/commonRecord/version']
        before = {path: audit.digest(path.read_bytes()) for path in paths}
        report = audit.audit()
        scratch = '/tmp/opencode' if Path('/tmp/opencode').is_dir() else None
        with tempfile.TemporaryDirectory(prefix='map-audit-exclusion-', dir=scratch) as temporary:
            excluded = Path(temporary) / 'gssjxz'
            excluded.mkdir()
            (excluded / '4.map').write_bytes(synthetic_scene())
            self.assertEqual(audit.audit(extra_roots=[excluded]), report)
        recorded = json.loads((ROOT / 'analysis/recovery/maps/source_audit.json').read_text('utf8'))
        self.assertEqual(report, recorded)
        self.assertEqual(before, {path: audit.digest(path.read_bytes()) for path in paths})
        self.assertEqual(sum(row['members'] for row in report['archives']), 1916)
        self.assertTrue(report['all_declared_payload_hashes_scanned'])
        self.assertTrue(all(row['all_member_payloads_match_unpacked'] for row in report['archives']))
        self.assertTrue(all(not row['scene_named_members'] for row in report['archives']))
        self.assertEqual(report['scene_scan']['candidate_count'], 0)
        self.assertEqual(report['scene_scan']['limit_hits'], [])
        self.assertEqual(report['world_directory_entries'], 214)
        self.assertTrue(all(row['matches_local_package_size'] for row in report['local_version_records']))


if __name__ == '__main__':
    unittest.main()
