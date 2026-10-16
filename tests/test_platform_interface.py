"""Platform boundaries and explicit initialization; behavioral checks run in Godot."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / 'client'
INTERFACE = CLIENT / 'scripts/interface'


class PlatformBoundaryTests(unittest.TestCase):
    def test_facade_and_adapters_do_not_depend_on_business(self):
        sources = list(INTERFACE.rglob('*.gd'))
        self.assertGreaterEqual(len(sources), 10)
        for path in sources:
            text = path.read_text('utf8')
            self.assertNotRegex(text, r'\b(?:Game|OnlineAccount)\.')
            self.assertNotIn('res://scenes/', text)
            self.assertNotIn('res://scripts/network/', text)

    def test_environment_path_rules_live_in_the_native_adapter(self):
        for name in ['game_state.gd', 'network/server_connection_settings.gd']:
            text = (CLIENT / 'scripts' / name).read_text('utf8')
            for direct_call in ['OS.get_environment', 'OS.get_name', 'FileAccess.', 'DirAccess.']:
                self.assertNotIn(direct_call, text, name)

    def test_dependencies_explicitly_gate_readiness(self):
        config = (CLIENT / 'project.godot').read_text('utf8')
        self.assertIn('Platform="*res://scripts/interface/platform.gd"', config)
        for name in ['game_state.gd', 'main.gd']:
            self.assertIn('await Platform.when_ready()', (CLIENT / 'scripts' / name).read_text('utf8'))
        account = (CLIENT / 'scripts/network/online_account.gd').read_text('utf8')
        self.assertIn('if not Platform.is_available()', account)
        self.assertIn('"PLATFORM_NOT_READY"', account)

    def test_native_config_is_named_and_client_only(self):
        text = (INTERFACE / 'adapters/native/native_runtime_config.gd').read_text('utf8')
        self.assertEqual(set(re.findall(r'"(SSJX_[A-Z_]+)"', text)), {'SSJX_SAVE_PATH', 'SSJX_CONNECTION_PATH'})
        for literal in re.findall(r'"([^"\n]*)"', text):
            self.assertNotIn('.env', literal)

    def test_game_canvas_and_existing_exports_are_preserved(self):
        config = (CLIENT / 'project.godot').read_text('utf8')
        for setting in ['window/size/viewport_width=320', 'window/size/viewport_height=480',
                        'renderer/rendering_method="gl_compatibility"']:
            self.assertIn(setting, config)
        presets = (CLIENT / 'export_presets.cfg').read_text('utf8')
        for platform in ['Game (Linux)', 'Game (Windows)']:
            self.assertIn(platform, presets)

    def test_threaded_loading_is_not_a_page_responsibility(self):
        main = (CLIENT / 'scripts/main.gd').read_text('utf8')
        self.assertNotIn('ResourceLoader.', main)
        self.assertIn('Platform.context.resource_loader.prepare(', main)
        self.assertIn('request.generation != epoch', main)
        self.assertIn('battle_resource_request.cancel()', main)


if __name__ == '__main__':
    unittest.main()
