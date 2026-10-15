"""Repository/client split: resource paths and tooling must remain usable."""
import importlib.util
import re
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / 'client'


class ProjectLayoutTests(unittest.TestCase):
    def test_godot_project_is_only_in_client(self):
        self.assertTrue((CLIENT / 'project.godot').is_file())
        for name in ('project.godot', 'assets', 'scenes', 'scripts'):
            self.assertFalse((ROOT / name).exists(), name)
        for folder in ('assets', 'scenes', 'scripts', 'tests'):
            self.assertTrue((CLIENT / folder).is_dir(), folder)

    def test_godot_test_scenes_remain_inside_project(self):
        for stem in ('test_runner', 'motion_regression', 'motion_smoke', 'turn_smoke', 'visual_smoke', 'server_connection_test', 'account_auth_test', 'online_characters_test'):
            for suffix in ('.gd', '.gd.uid', '.tscn'):
                self.assertTrue((CLIENT / 'tests' / (stem + suffix)).is_file())
                self.assertFalse((ROOT / 'tests' / (stem + suffix)).exists())

    def test_literal_resource_paths_resolve_with_new_project_root(self):
        sources = [CLIENT / 'project.godot']
        sources += list((CLIENT / 'scripts').rglob('*.gd'))
        sources += list((CLIENT / 'scenes').glob('*.tscn'))
        sources += list((CLIENT / 'tests').glob('*.gd'))
        sources += list((CLIENT / 'tests').glob('*.tscn'))
        checked = 0
        for source in sources:
            for relative in re.findall(r'''["']res://([^"']+)["']''', source.read_text('utf-8')):
                if '%' in relative:
                    continue  # Formatted resource names are covered by engine tests.
                self.assertTrue((CLIENT / relative).is_file(), (source, relative))
                checked += 1
        self.assertGreater(checked, 20)

    def test_asset_builder_targets_client_without_relocating_analysis(self):
        spec = importlib.util.spec_from_file_location('asset_builder', ROOT / 'tools/import_assets.py')
        builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(builder)
        self.assertEqual(builder.DEST, CLIENT / 'assets')
        self.assertEqual(builder.ANALYSIS, ROOT / 'analysis')
        self.assertTrue(builder.ANALYSIS.is_dir())

    def test_startup_instructions_target_client(self):
        readme = (ROOT / 'README.md').read_text('utf-8')
        self.assertIn('client/project.godot', readme)
        self.assertIn('godot --path client', readme)

    def test_rust_server_is_separate_from_godot(self):
        self.assertTrue((ROOT / 'server/src').is_dir())
        self.assertTrue((ROOT / 'server/migrations').is_dir())
        self.assertTrue((ROOT / 'server/README.md').is_file())
        self.assertTrue((ROOT / 'server/Cargo.toml').is_file())
        self.assertTrue((ROOT / 'server/src/main.rs').is_file())
        self.assertFalse((ROOT / 'server/project.godot').exists())


if __name__ == '__main__':
    unittest.main()
