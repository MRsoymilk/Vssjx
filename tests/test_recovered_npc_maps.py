"""NPC atlas/placement integration, separate from original ANI recovery fixtures."""
import hashlib
import json
from pathlib import Path
import sys
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from build_recovered_npc_art import build_assets, actor_key
from npc_screenshot_bindings import apply_appearance, ROLE_APPEARANCES, SERVICE_PROFILE


class RecoveredNpcMapTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.world = json.loads((ROOT / 'shared/data/ai-world-v1.json').read_text('utf8'))
        cls.index = json.loads((ROOT / 'client/assets/data/actors.json').read_text('utf8'))['actors']
        cls.assets = build_assets(write_textures=False)

    def test_all_twenty_actors_are_loadable_small_and_foot_anchored(self):
        self.assertEqual(len(self.assets), 20)
        for key, meta in self.assets.items():
            self.assertEqual(json.loads((ROOT / 'client' / self.index[key].removeprefix('res://')).read_text('utf8')), meta)
            with Image.open(ROOT / 'client' / meta['texture'].removeprefix('res://')) as im:
                self.assertEqual(im.mode, 'RGBA')
                self.assertEqual(im.size, (meta['width'], meta['height']))
                self.assertTrue(40 <= im.height - 4 <= 60)
                self.assertTrue(im.width <= 76)
                low, high = im.getchannel('A').getextrema()
                self.assertEqual(low, 0)
                self.assertGreaterEqual(high, 250)
                self.assertEqual(meta['origin'][1] + im.height - 2, 0)
            source = ROOT / meta['provenance']['source_asset']
            self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), meta['provenance']['source_sha256'])
            self.assertEqual(meta['count'], 1)
            self.assertTrue(all(steps == [[0, 1]] for steps in meta['playback'].values()))

    def test_both_modes_use_identical_art_and_all_twenty_are_placed(self):
        self.assertEqual((ROOT / 'shared/data/ai-world-v1.json').read_bytes(),
                         (ROOT / 'client/assets/data/ai-world-v1.json').read_bytes())
        used = {r['art'] for m in self.world['maps'] for r in m['residents'] if r['kind'] == 'npc' and r['art'].startswith('npc/')}
        self.assertEqual(used, set(self.assets))
        for m in self.world['maps']:
            for r in m['residents']:
                self.assertIn(r['art'], self.index)
                if r['art'].startswith('npc/'):
                    self.assertEqual(r['kind'], 'npc')
                    self.assertIn('appearance_reference', r['npc_reference'])

    def test_known_names_keep_existing_maps_and_roles(self):
        expected = {'ai_007_guide': ('齐霞儿', 'qi-xiaer'), 'ai_021_survey': ('五毒天王', 'wudu-tianwang'),
                    'ai_023_guide': ('周轻云', 'zhou-qingyun'), 'ai_028_guide': ('诸有功', 'brown-mask-full'),
                    'ai_028_survey': ('博浪沙火鹤', 'crane-daren'), 'ai_032_courier': ('隐名剑仙', 'yi-jing'),
                    'ai_032_survey': ('天池上人', 'tianchi-shangren'), 'ai_041_survey': ('杂货店老板', 'grocery-boss'),
                    'ai_087_guide': ('博浪沙火鹤', 'crane-daren')}
        residents = {r['id']: r for m in self.world['maps'] for r in m['residents']}
        for rid, (name, asset) in expected.items():
            self.assertEqual((residents[rid]['name'], residents[rid]['art']), (name, actor_key(asset)))
            self.assertEqual(residents[rid]['npc_reference']['appearance_reference']['basis'], 'name_match')
        self.assertTrue(all(not r['art'].startswith('npc/') for r in self.world['maps'][0]['residents']))

    def test_style_borrowing_does_not_rename_npcs_or_infer_unseen_identity(self):
        person = dict(role='npc03', name='测试旅人', source='AI生成', service_label='旅人', art='hero/mfs')
        apply_appearance(14, 3, 'forest', person)
        self.assertEqual(person['name'], '测试旅人')
        self.assertEqual(person['appearance_reference']['basis'], 'authored_appearance')
        unknown = dict(role='npc04', name='未匹配表格人物', source='用户表格（待核对）', art='hero/mck')
        apply_appearance(14, 4, 'forest', unknown)
        self.assertEqual(unknown['art'], 'hero/mck')
        with self.assertRaises(ValueError):
            apply_appearance(32, 0, 'snow', dict(role='guide', name='身份已变', source='AI生成'))

    def test_explicit_child_elder_and_female_services_override_every_biome(self):
        from npc_screenshot_bindings import THEMES
        for service, expected in [('净水道童', {'zhi-xian', 'jiang-xier'}),
                                  ('辨草老人', {'tan-chang', 'school-daily', 'zhu-liang'}),
                                  ('采药苗女', {'zhen-gen', 'qi-xiaer', 'zhou-qingyun'})]:
            for biome in THEMES:
                for index in range(9):
                    person = dict(role='npc10', name='不据名字推定性别', source='AI生成', service_label=service)
                    apply_appearance(50, index, biome, person)
                    self.assertIn(person['appearance_reference']['asset_id'], expected)
                    self.assertEqual(person['service_label'], service)

    def test_runtime_professions_have_reviewed_compatible_appearances(self):
        from ai_world_npcs import PROFILES
        self.assertTrue({s for roles in PROFILES.values() for s in roles}.issubset(SERVICE_PROFILE))
        for m in self.world['maps']:
            for r in m['residents']:
                ref = r.get('npc_reference', {}).get('appearance_reference', {})
                if ref.get('basis') != 'authored_appearance':
                    continue
                profile = ref['role_profile']
                self.assertIn(ref['asset_id'], ROLE_APPEARANCES[profile], r['id'])
                if profile in ('courier', 'guard', 'commander'):
                    self.assertNotIn(ref['asset_id'], {'budai-xianren', 'zhi-xian', 'jiang-xier'}, r['id'])
                if profile == 'artisan':
                    self.assertIn(ref['asset_id'], {'baishouxian', 'grocery-boss'}, r['id'])


if __name__ == '__main__':
    unittest.main()
