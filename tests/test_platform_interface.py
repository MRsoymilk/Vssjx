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

    def test_web_config_uses_only_origin_and_build_profile(self):
        text = (INTERFACE / 'adapters/web/web_runtime_config.gd').read_text('utf8')
        self.assertEqual(re.findall(r'JavaScriptBridge\.eval\(([^\n]+)\)', text), ['"window.location.origin", true'])
        for forbidden in ['OS.get_environment(', 'FileAccess.', 'localStorage', 'sessionStorage',
                          'location.search', 'location.hash', 'location.href', 'document.', 'window.config']:
            self.assertNotIn(forbidden, text)
        profile = (INTERFACE / 'profiles/web_runtime.tres').read_text('utf8')
        self.assertIn('api_prefix = ""', profile)
        self.assertIn('allow_loopback_http = false', profile)
        factory = (INTERFACE / 'platform_factory.gd').read_text('utf8')
        self.assertIn('if selected != "native": return null', factory)

    def test_credential_io_has_an_unconditional_web_guard(self):
        text = (CLIENT / 'scripts/network/remembered_login.gd').read_text('utf8')
        self.assertIn('not OS.has_feature("web") and Platform.is_available()', text)
        self.assertIn('runtime_config.allows_remembered_login()', text)
        for name in ['load_saved', 'remember', 'forget']:
            body = text.split('func ' + name + '(', 1)[1].split('\nfunc ', 1)[0]
            self.assertLess(body.index('if not _allowed():'), body.index('FileAccess.'))

    def test_every_network_consumer_checks_the_platform_target(self):
        for name, request in [('online_account.gd', '_request.request('),
                              ('server_discovery.gd', 'request.request('),
                              ('online_world_client.gd', 'socket.connect_to_url(')]:
            text = (CLIENT / 'scripts/network' / name).read_text('utf8')
            self.assertLess(text.index('runtime_config.check_network_target('), text.index(request), name)

    def test_save_business_consumers_explicitly_await_results(self):
        for name in ['main.gd', 'battle.gd', 'inventory.gd']:
            text = (CLIENT / 'scripts' / name).read_text('utf8')
            for line in text.splitlines():
                if re.search(r'Game\.(?:save_game|load_game|probe_save)\(', line):
                    self.assertIn('await Game.', line, name)
            self.assertNotIn('Game.has_save()', text)
        game = (CLIENT / 'scripts/game_state.gd').read_text('utf8')
        for direct in ['storage.exists(', 'storage.read_text(', 'storage.write_text_atomic(']:
            self.assertNotIn(direct, game)
        self.assertIn('"SAVE_UNCONFIRMED"', game)
        self.assertIn('"STORAGE_BUSY"', game)

    def test_web_factory_remains_disabled_despite_storage_adapter(self):
        factory = (INTERFACE / 'platform_factory.gd').read_text('utf8')
        self.assertIn('if OS.has_feature("web"): return null', factory)
        self.assertTrue((INTERFACE / 'adapters/web/web_storage.gd').exists())

    def test_web_storage_has_no_native_or_query_credentials_fallback(self):
        gd = (INTERFACE / 'adapters/web/web_storage.gd').read_text('utf8')
        js = (INTERFACE / 'adapters/web/indexeddb_storage.js').read_text('utf8')
        for text in [gd, js]:
            for forbidden in ['localStorage', 'sessionStorage', 'syncfs(', 'force_fs_sync(', 'location.', 'OS.get_environment(']:
                self.assertNotIn(forbidden, text)
        self.assertNotIn('FileAccess.open(', gd)
        self.assertNotIn('write_text_atomic(', gd)
        self.assertIn('weakref(self)', gd)
        self.assertIn('NOTIFICATION_PREDELETE', gd)
        self.assertIn('transaction.oncomplete', js)
        self.assertIn('transaction.onabort', js)
        self.assertIn('store.openCursor(KEY)', js)
        self.assertIn("durability: 'browser_sync'", js)
        self.assertIn("'vssjx-offline-v1'", js)
        presets = (CLIENT / 'export_presets.cfg').read_text('utf8')
        self.assertEqual(presets.count('scripts/interface/adapters/web/*.js'), 2)

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

    def test_game_text_entry_uses_platform_guards(self):
        for name in ['server_login.gd', 'character_creation.gd', 'online_creation_flow.gd', 'online_world_view.gd']:
            text = (CLIENT / 'scripts' / name).read_text('utf8')
            self.assertIn('text_input.check_submission(', text, name)
            self.assertNotIn('.has_ime_text()', text, name)
            self.assertNotIn('.grab_focus()', text, name)
        common = (INTERFACE / 'adapters/common/godot_text_input.gd').read_text('utf8')
        self.assertIn('field.has_ime_text()', common)
        self.assertNotRegex(common, r'\bfield\.text\b')

    def test_game_exit_is_a_platform_action(self):
        main = (CLIENT / 'scripts/main.gd').read_text('utf8')
        self.assertNotIn('get_tree().quit()', main)
        self.assertIn('Platform.context.system_actions.request_exit()', main)


if __name__ == '__main__':
    unittest.main()
