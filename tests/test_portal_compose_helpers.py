import json
import os
from pathlib import Path
import shutil
import subprocess
from tempfile import TemporaryDirectory
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ComposeHelperTests(unittest.TestCase):
    def test_optional_apk_file_preserves_web_and_tls_flags_without_reading_game_secrets(self):
        for enabled in (False, True):
            for script in ('public-compose.sh', 'renew-public-certificate.sh'):
                with self.subTest(enabled=enabled, script=script), TemporaryDirectory() as temporary:
                    base = Path(temporary)
                    (base / 'tools').mkdir()
                    (base / 'deploy').mkdir()
                    (base / 'bin').mkdir()
                    shutil.copyfile(ROOT / 'tools' / script, base / 'tools' / script)
                    (base / '.env').write_text('SSJX_PUBLIC_WEB_ROOT=/owned-fixture/public\n')
                    if enabled:
                        (base / 'deploy/portal-apks.local.env').write_text('SSJX_APK_PUBLIC_ROOT=/owned-fixture/apks\n')
                    docker = base / 'bin/docker'
                    docker.write_text('#!/usr/bin/env python3\nimport json,os,sys\n'
                                      'with open(os.environ["FIXTURE_CALLS"],"a") as log: log.write(json.dumps(sys.argv[1:])+"\\n")\n'
                                      'sys.exit(1 if any("test -f" in value for value in sys.argv) else 0)\n')
                    docker.chmod(0o700)
                    environment = {**os.environ, 'PATH': str(base / 'bin') + os.pathsep + os.environ['PATH'],
                                   'FIXTURE_CALLS': str(base / 'calls.jsonl')}
                    subprocess.run(['sh', str(base / 'tools' / script), *(['ps'] if script == 'public-compose.sh' else [])],
                                   env=environment, capture_output=True, check=True, timeout=10)
                    calls = [json.loads(line) for line in (base / 'calls.jsonl').read_text().splitlines()]
                    self.assertTrue(calls)
                    for call in calls:
                        self.assertIn('deploy/public.tls.compose.yaml', call)
                        self.assertIn('deploy/public.web.compose.yaml', call)
                        self.assertEqual('deploy/public.apks.compose.yaml' in call, enabled)
                        self.assertEqual('deploy/portal-apks.local.env' in call, enabled)
                        self.assertEqual(call.count('--env-file'), 2 if enabled else 1)


if __name__ == '__main__':
    unittest.main()
