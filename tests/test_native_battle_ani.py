"""Independent native slot/frame/mask regression anchors; original evidence stays raw."""
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.native_ani import native_steps, event_masks
from tools.recover_native_battle import evidence


class NativeBattleAniTests(unittest.TestCase):
    def test_binary_identity_and_state_5_target_origin_are_pinned(self):
        report = evidence()
        self.assertEqual(report['attack_target'], '0x24636')
        self.assertEqual(report, json.loads((ROOT / 'analysis/recovery/battle/native_action_evidence.json').read_text('utf-8')))

    def test_knight_native_attack_is_the_stab_not_the_six_frame_walk(self):
        source = json.loads((ROOT / 'analysis/animations/hero/mck.json').read_text('utf-8'))
        self.assertEqual(native_steps(source, 0), [[96,1],[95,1],[94,1],[93,1],[92,1],[91,1]])
        self.assertEqual(native_steps(source, 5), [[80,1],[79,1],[78,1],[77,1],[76,1],[75,1],[74,2],[73,1],[72,1]])
        self.assertEqual(native_steps(source, 6), [[84,1],[71,1],[70,1],[69,1],[68,2]])
        self.assertEqual(event_masks(source)[5], 0x4)

    def test_wolf_bite_star_is_an_outgoing_attack_not_the_hurt_sequence(self):
        source = json.loads((ROOT / 'analysis/animations/monster/langw.json').read_text('utf-8'))
        self.assertEqual(native_steps(source, 6), [[4,1],[3,1],[2,1],[1,1],[0,2]])
        self.assertEqual(event_masks(source)[5], 0x8)
        self.assertTrue(any(layer['source'] == 'tx38' for frame, _ in native_steps(source, 5) for layer in source['frames'][frame]))
        self.assertFalse(any(layer['source'] == 'tx38' for frame, _ in native_steps(source, 6) for layer in source['frames'][frame]))

    def test_all_16_runtime_actor_variants_match_native_tables_and_masks(self):
        for folder in ('hero', 'creation', 'monster'):
            for path in (ROOT / 'client/assets/data/actors' / folder).glob('*.json'):
                info = json.loads(path.read_text('utf-8'))
                source = json.loads((ROOT / 'analysis/animations' / ('hero' if folder == 'creation' else folder) / path.name).read_text('utf-8'))
                for mode, native_id in info['native_battle']['sequence_ids'].items():
                    self.assertEqual(info['playback'][mode], native_steps(source, native_id))
                self.assertTrue(info['native_battle']['impact_steps']['attack'])
                x = info['native_battle']['attack_x']
                self.assertGreater(x[0] - min(x), 50)
                self.assertGreater(x[-1] - min(x), 50)


if __name__ == '__main__': unittest.main()
