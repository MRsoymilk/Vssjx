import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def tool(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'tools' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FlarumDeploymentTests(unittest.TestCase):
    def test_private_install_inputs_disable_registration_and_do_not_reuse_game_database(self):
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / 'private'
            tool('initialize_flarum_config').prepare(target, 'https://47.93.114.190/flarum')
            self.assertEqual(target.stat().st_mode & 0o777, 0o700)
            config = json.loads((target / 'install.json').read_text())
            self.assertEqual((target / 'admin-credentials.json').stat().st_mode & 0o777, 0o600)
            self.assertEqual(config['settings']['allow_sign_up'], '0')
            self.assertEqual(config['databaseConfiguration']['driver'], 'sqlite')
            self.assertGreater(len(config['adminUser']['password']), 32)
            with self.assertRaises(FileExistsError):
                tool('initialize_flarum_config').prepare(target, 'https://47.93.114.190/flarum')

    def test_proxy_merge_only_replaces_reserved_forum_locations(self):
        original = (ROOT / 'deploy/public.web.https.nginx.conf').read_text()
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / 'candidate.conf'
            tool('configure_flarum_proxy').configure(ROOT / 'deploy/public.web.https.nginx.conf', target)
            candidate = target.read_text()
            start = original.index('    location = /flarum { return 404; }')
            end = original.index('    location ^~ /flarum/ { return 404; }') + len('    location ^~ /flarum/ { return 404; }')
            self.assertTrue(candidate.startswith(original[:start]))
            self.assertTrue(candidate.endswith(original[end:]))
            self.assertIn('proxy_pass http://127.0.0.1:8082;', candidate)
            self.assertNotIn('proxy_pass http://127.0.0.1:8082/;', candidate)
            with self.assertRaises(FileExistsError):
                tool('configure_flarum_proxy').configure(ROOT / 'deploy/public.web.https.nginx.conf', target)
            with self.assertRaises(ValueError):
                tool('configure_flarum_proxy').configure(target, Path(temporary) / 'again.conf')

    def test_forum_is_explicitly_enabled_without_changing_game_links(self):
        source = (ROOT / 'deploy/portal/index.html').read_text()
        result = tool('prepare_portal').enable_forum(source)
        self.assertNotIn('筹备中', result)
        self.assertEqual(result.count('href="/flarum/"'), 3)
        for href in re.findall(r'href="([^"]+)"', source):
            if href.startswith('/go/'):
                self.assertIn('href="' + href + '"', result)
        with self.assertRaises(ValueError):
            tool('prepare_portal').enable_forum(result)

    def test_forum_is_separate_limited_and_does_not_mount_game_or_docker(self):
        text = (ROOT / 'deploy/flarum/compose.yaml').read_text()
        self.assertIn('name: vssjx-forum', text)
        self.assertIn('127.0.0.1:8082:80', text)
        self.assertIn('mem_limit: 384m', text)
        self.assertIn('read_only: true', text)
        for forbidden in ('docker.sock', 'postgres', 'SSJX_DATABASE_URL', 'network_mode: host'):
            self.assertNotIn(forbidden, text)
        self.assertIn("'9f941e27", (ROOT / 'deploy/flarum/Dockerfile').read_text())
        self.assertIn('Require all denied', (ROOT / 'deploy/flarum/apache.conf').read_text())


if __name__ == '__main__':
    unittest.main()
