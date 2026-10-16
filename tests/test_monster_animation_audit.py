"""Complete source coverage and honest boundaries of the monster animation audit."""
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('monster_audit', ROOT / 'tools/audit_monster_animations.py')
audit = importlib.util.module_from_spec(spec)
# Import as a package so the audit can use the same importer as the build.
audit.__package__ = 'tools'
import sys
sys.path.insert(0, str(ROOT))
spec.loader.exec_module(audit)


class MonsterAnimationAuditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.report = audit.audit()

    def test_all_117_animations_142_image_members_and_every_sequence_are_checked(self):
        source = ROOT / 'analysis/animations/monster'
        names = {path.stem for path in source.glob('*.json')}
        self.assertEqual({row['resource_id'] for row in self.report['monsters']}, names)
        self.assertEqual(self.report['summary']['animation_count'], 117)
        self.assertEqual(self.report['summary']['image_member_count'], 142)
        self.assertEqual(self.report['summary']['frame_count'], 3133)
        self.assertEqual(self.report['summary']['sequence_count'], 969)
        self.assertEqual(self.report['errors'], [])
        for row in self.report['monsters']:
            self.assertEqual(row['structural_errors'], [])
            self.assertEqual([seq['sequence'] for seq in row['sequences']], list(range(row['sequence_count'])))

    def test_published_report_is_reproducible(self):
        self.assertEqual(self.report, json.loads(audit.REPORT.read_text('utf-8')))

    def test_unknown_archive_actions_are_not_claimed_as_fixed_or_assigned(self):
        corrected = {row['resource_id'] for row in self.report['monsters'] if row['runtime_status'] == 'corrected'}
        self.assertEqual(corrected, {'langw', 'xt1', 'hs1', 'nt1'})
        self.assertEqual(self.report['summary']['archive_only'], 113)
        for row in self.report['monsters']:
            if row['runtime_status'] == 'archive_only':
                self.assertEqual(row['hurt_policy'], 'unassigned')
            for sequence in row['sequences']:
                self.assertNotIn('action', sequence)
                if not sequence['landmark_complete']:
                    self.assertIsNone(sequence['landmark_x_span'])

    def test_detects_changed_archive_pixels_instead_of_silently_accepting_them(self):
        digest = audit.digest
        def tampered(path):
            if path.as_posix().endswith('/admin/monsters/langw.png'):
                return 'tampered'
            return digest(path)
        with patch.object(audit, 'digest', side_effect=tampered):
            result = audit.audit()
        self.assertEqual(result['errors'], ['langw: Archive atlas checksum mismatch'])


if __name__ == '__main__':
    unittest.main()
