"""Independent native slot/frame/mask regression anchors; original evidence stays raw."""
import json
import struct
from pathlib import Path
import sys
import unittest
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.native_ani import native_steps, event_masks
from tools.recover_native_battle import evidence
from tools.import_assets import bake_player_ring, TRANSFORMS


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

    def test_original_acting_side_is_drawn_last(self):
        blob = (ROOT / 'analysis/unpacked/ssjx/gameonline.ext').read_bytes()
        # Side 0 selects team +28 into draw list +48; side 1 selects +24.
        self.assertEqual(struct.unpack_from('<HHHH', blob, 0x2f2e), (0x6ab0, 0x64b0, 0x6a70, 0x64f0))
        self.assertEqual(struct.unpack_from('<HH', blob, 0x2f38), (0x6a70, 0x2300))
        # Both draw entry points read +4c first, +48 second.
        self.assertEqual(struct.unpack_from('<H', blob, 0x3174)[0], 0x6ce8)
        self.assertEqual(struct.unpack_from('<H', blob, 0x317c)[0], 0x6ca8)
        self.assertEqual(struct.unpack_from('<H', blob, 0x394a)[0], 0x6ce8)
        self.assertEqual(struct.unpack_from('<H', blob, 0x3952)[0], 0x6ca8)

    def test_original_recoil_centers_survive_atlas_stabilization(self):
        for key, expected in [('hero/wck', [4,6,7,8,9]), ('monster/langw', [3,4,5,6,7])]:
            info = json.loads((ROOT / 'client/assets/data/actors' / (key + '.json')).read_text('utf8'))
            self.assertEqual(info['native_battle']['pose_x']['hurt'], expected)

    def test_player_ring_preserves_original_pixels_and_native_order(self):
        source = json.loads((ROOT / 'analysis/animations/main/dongtai1.json').read_text('utf8'))
        self.assertEqual(native_steps(source, 0), [[3,1],[2,1],[1,1],[0,1]])
        info = bake_player_ring(write_texture=False)
        self.assertEqual((info['width'], info['height'], info['origin']), (30, 16, [-15, -10]))
        atlas = Image.open(ROOT / 'client/assets/ui/player_ring.png').convert('RGBA')
        self.assertEqual(atlas.size, (120, 16))
        for frame, _ticks in native_steps(source, 0):
            layer = source['frames'][frame][0]
            image = Image.open(ROOT / f"analysis/decoded_png/ssjx/{layer['source']}_frame{layer['frame']:03}.png").convert('RGBA')
            if layer['transform']: image = image.transpose(TRANSFORMS[layer['transform']])
            expected = Image.new('RGBA', (30, 16))
            expected.alpha_composite(image)
            self.assertEqual(atlas.crop((frame * 30, 0, frame * 30 + 30, 16)).tobytes(), expected.tobytes())
        scene = (ROOT / 'client/scenes/actors/player_ring.tscn').read_text('utf8')
        for x in [90,60,30,0]:
            self.assertIn(f'region = Rect2({x}, 0, 30, 16)', scene)
        blob = (ROOT / 'analysis/unpacked/ssjx/gameonline.ext').read_bytes()
        self.assertEqual(struct.unpack_from('<I', blob, 0x2e5b8)[0], 0xa38)

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
