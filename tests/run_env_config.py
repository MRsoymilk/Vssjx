"""Exercise .env loading in real server processes without opening any database."""
import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile
from urllib.request import urlopen
from run_server_connection import wait_for_server
from run_account_auth import stop

ROOT = Path(__file__).resolve().parents[1]


def main():
    subprocess.run(['cargo', 'build', '--locked', '--manifest-path', str(ROOT / 'server/Cargo.toml')], check=True)
    binary = ROOT / 'server/target/debug/vssjx-server'
    clean = {k: v for k, v in os.environ.items() if not k.startswith('SSJX_') and k != 'RUST_LOG'}
    clean.update(SSJX_MONITOR_BIND_ADDR='', SSJX_LOG_DIR='')
    scratch = '/tmp/opencode' if Path('/tmp/opencode').is_dir() else None
    with tempfile.TemporaryDirectory(prefix='vssjx-env-', dir=scratch) as directory:
        directory = Path(directory)
        config = directory / '.env'
        config.write_text('SSJX_BIND_ADDR=127.0.0.1:0\nSSJX_SERVER_NAME="file server"\nSSJX_DATABASE_URL=\nRUST_LOG=info\n', encoding='utf-8')

        def start(env, expected):
            process = subprocess.Popen([str(binary)], env=env, cwd=directory,
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            try:
                base = wait_for_server(process)
                with urlopen(base + '/api/v1/server-info', timeout=3) as response:
                    info = json.load(response)
                assert info['server_name'] == expected and info['stage'] == 'connection_only'
            finally:
                stop(process)

        start(dict(clean, SSJX_ENV_FILE=str(config)), 'file server')
        start(clean, 'file server')  # Current-directory .env is discovered.
        config.write_text('SSJX_BIND_ADDR=127.0.0.1:0\nSSJX_SERVER_NAME="file server"\nSSJX_DATABASE_URL="not-a-database-url"\n', encoding='utf-8')
        start(dict(clean, SSJX_ENV_FILE=str(config), SSJX_SERVER_NAME='environment wins', SSJX_DATABASE_URL=''), 'environment wins')
        config.write_text('SSJX_POSTGRES_PASSWORD="redacted-fixture-marker\n', encoding='utf-8')
        invalid = subprocess.run([str(binary)], env=dict(clean, SSJX_ENV_FILE=str(config)), cwd=directory,
                                 capture_output=True, text=True, timeout=10)
        assert invalid.returncode != 0 and 'redacted-fixture-marker' not in invalid.stdout + invalid.stderr
        start(dict(clean, SSJX_ENV_FILE='', SSJX_BIND_ADDR='127.0.0.1:0', SSJX_SERVER_NAME='no dotenv'), 'no dotenv')
        missing = subprocess.run([str(binary)], env=dict(clean, SSJX_ENV_FILE=str(directory / 'missing.env')), cwd=directory,
                                 capture_output=True, text=True, timeout=10)
        assert missing.returncode != 0

    assert subprocess.run(['git', 'check-ignore', '--quiet', '.env'], cwd=ROOT).returncode == 0
    assert subprocess.run(['git', 'check-ignore', '--quiet', '.env.sample.txt'], cwd=ROOT).returncode == 1
    tracked = subprocess.run(['git', 'ls-files', '--error-unmatch', '.env'], cwd=ROOT, capture_output=True)
    assert tracked.returncode != 0
    subprocess.run(['docker', 'compose', '--env-file', '.env.sample.txt', '-f', 'deploy/compose.yaml', 'config', '--quiet'],
                   cwd=ROOT, env=dict(clean, SSJX_POSTGRES_PASSWORD=secrets.token_hex(24)), check=True)
    print('PASS: dotenv discovery, explicit path, overrides, opt-out, redacted errors, Git exclusion and Compose sample')


if __name__ == '__main__':
    main()
