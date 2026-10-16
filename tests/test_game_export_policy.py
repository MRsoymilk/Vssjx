"""Developer admin pages stay runnable in source, but never enter game exports."""
import configparser
import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / 'client'


class GameExportPolicyTests(unittest.TestCase):
    def test_web_is_single_threaded_without_pwa_or_private_build_inputs(self):
        config = configparser.ConfigParser(interpolation=None)
        config.read(CLIENT / 'export_presets.cfg', encoding='utf8')
        self.assertEqual(json.loads(config['preset.2']['platform']), 'Web')
        options = config['preset.2.options']
        for name in ['variant/thread_support', 'variant/extensions_support', 'progressive_web_app/enabled']:
            self.assertEqual(options[name], 'false')
        self.assertEqual(json.loads(options['html/custom_html_shell']), 'res://web/shell.html')
        shell = (CLIENT / 'web/shell.html').read_text(encoding='utf8')
        self.assertIn('safe-area-inset-top', shell)
        self.assertIn('aspect-ratio: 2 / 3', shell)
        self.assertNotIn('localStorage', shell)
        self.assertNotIn('serviceWorker.register', shell)

    def test_bundled_cjk_font_has_license_and_verified_provenance(self):
        folder = CLIENT / 'assets/fonts'
        provenance = json.loads((folder / 'provenance.json').read_text(encoding='utf8'))
        self.assertEqual(provenance['license'], 'SIL Open Font License 1.1')
        for record in provenance['files']:
            self.assertEqual(hashlib.sha256((folder / record['file']).read_bytes()).hexdigest(), record['sha256'])
        self.assertIn('SIL OPEN FONT LICENSE', (folder / 'OFL.txt').read_text(encoding='utf8'))

    def test_every_game_preset_excludes_admin_scenes_scripts_and_tests(self):
        config = configparser.ConfigParser(interpolation=None)
        config.read(CLIENT / 'export_presets.cfg', encoding='utf8')
        presets = [section for section in config.sections() if section.startswith('preset.') and not section.endswith('.options')]
        self.assertGreaterEqual(len(presets), 1)
        for section in presets:
            exclusions = {item.strip() for item in json.loads(config[section]['exclude_filter']).split(',')}
            self.assertTrue({'scenes/admin/*', 'scripts/admin/*', 'assets/admin/*', 'tests/*'} <= exclusions, section)
            self.assertIn('assets/data/*.json', json.loads(config[section]['include_filter']))

    def test_runtime_does_not_reference_developer_pages(self):
        sources = [CLIENT / 'project.godot']
        for folder, suffix in [('scripts', '*.gd'), ('scenes', '*.tscn')]:
            sources.extend(path for path in (CLIENT / folder).rglob(suffix) if 'admin' not in path.relative_to(CLIENT).parts)
        for path in sources:
            text = path.read_text('utf8')
            self.assertNotIn('res://scenes/admin/', text, str(path))
            self.assertNotIn('res://scripts/admin/', text, str(path))


if __name__ == '__main__':
    unittest.main()
