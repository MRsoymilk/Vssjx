"""Isolated Compose/rendering checks; no private .env, existing service or CA is touched."""
import argparse
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import tarfile
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--nginx', action='store_true', help='Check cached Nginx with temporary, untrusted test certificate')
    parser.add_argument('--openssl', default=shutil.which('openssl'))
    parser.add_argument('--context', action='store_true', help='Inspect an inert scratch image using the exact build-context allowlist')
    args = parser.parse_args()
    checks = 0

    def check(value, message):
        nonlocal checks
        assert value, message
        checks += 1
        print('PASS: ' + message)

    def run(command, cwd=None):
        result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, encoding='utf-8', timeout=90)
        if result.returncode:
            raise RuntimeError('Isolated deployment check failed: ' + result.stderr)
        return result.stdout

    # Remove inherited deployment values; this fixture contains no real credentials.
    env = {key: value for key, value in os.environ.items() if not key.startswith('SSJX_')}
    with tempfile.TemporaryDirectory(prefix='vssjx-public-check-') as temporary:
        base = Path(temporary)
        (base / 'deploy').mkdir()
        for name in ['compose.yaml', 'public.compose.yaml', 'public.tls.compose.yaml', 'public.web.compose.yaml']:
            shutil.copyfile(ROOT / 'deploy' / name, base / 'deploy' / name)
        (base / '.env').write_text('SSJX_POSTGRES_PASSWORD=owned-test-only\n'
                                 'SSJX_DATABASE_URL=postgresql://vssjx:owned-test-only@127.0.0.1:5432/vssjx\n'
                                 'SSJX_PUBLIC_IP=203.0.113.10\nSSJX_ACME_EMAIL=test@example.invalid\nSSJX_PUBLIC_WEB_ROOT=/owned-fixture/public\n', encoding='utf-8')
        command = ['docker', 'compose', '--env-file', '.env', '-f', 'deploy/compose.yaml', '-f', 'deploy/public.compose.yaml']

        def config(extra=()):
            result = subprocess.run(command + list(extra) + ['--profile', 'tools', 'config', '--format', 'json'],
                                    cwd=base, env=env, capture_output=True, text=True, encoding='utf-8')
            if result.returncode: raise RuntimeError(result.stderr)
            return json.loads(result.stdout)

        initial = config()
        services = initial['services']
        check(initial['name'] == 'vssjx' and initial['volumes']['postgres-data']['name'] == 'vssjx_postgres-data', 'Existing Compose project and database volume retained')
        check(services['postgres']['ports'][0]['host_ip'] == '127.0.0.1', 'PostgreSQL remains loopback-only')
        game = services['game']
        check(str(game['build']['args']['CARGO_BUILD_JOBS']) == '1' and game['build']['args']['CARGO_REGISTRY_MIRROR'] == 'crates-io', 'Default image build limits memory and uses the official Cargo registry')
        check(game['network_mode'] == 'host' and game['environment']['SSJX_BIND_ADDR'] == '127.0.0.1:8080', 'Game shares Linux loopback and never binds public 8080')
        check(game['environment']['SSJX_MONITOR_BIND_ADDR'] == '127.0.0.1:9090', 'Monitor retains its required local peer and listener boundary')
        check(game['environment']['SSJX_ENV_FILE'] == '' and game['environment']['SSJX_DATABASE_URL'].endswith('@127.0.0.1:5432/vssjx'), 'Container uses explicit database environment without embedded .env')
        check(game['depends_on']['postgres']['condition'] == 'service_healthy' and game['healthcheck']['test'][-1].endswith('/readyz'), 'Database readiness precedes game readiness')
        check(services['certbot']['profiles'] == ['tools'] and '--ip-address' in services['certbot']['command'] and 'shortlived' in services['certbot']['command'], 'IP certificate issuance is explicit, with short-lived profile')
        check(not any('docker.sock' in mount.get('source', '') for service in services.values() for mount in service.get('volumes', [])), 'No container receives Docker daemon socket')
        tls = config(['-f', 'deploy/public.tls.compose.yaml'])
        nginx_mounts = tls['services']['nginx']['volumes']
        configs = [mount for mount in nginx_mounts if mount['target'] == '/etc/nginx/conf.d/default.conf']
        check(len(configs) == 1 and configs[0]['source'].endswith('public.https.nginx.conf'), 'TLS overlay replaces only bootstrap config and retains certificate volumes')
        check(initial['volumes'] == tls['volumes'], 'Enabling HTTPS never changes persistent volume identity')
        with (base / '.env').open('a', encoding='utf-8') as fixture:
            fixture.write('SSJX_CARGO_REGISTRY_MIRROR=ustc\n')
        check(config()['services']['game']['build']['args']['CARGO_REGISTRY_MIRROR'] == 'ustc', 'USTC build selection is passed explicitly through Compose')
        web = config(['-f', 'deploy/public.tls.compose.yaml', '-f', 'deploy/public.web.compose.yaml'])
        mounts = web['services']['nginx']['volumes']
        check(len([m for m in mounts if m['target'] == '/etc/nginx/conf.d/default.conf']) == 1 and any(m['source'].endswith('public.web.https.nginx.conf') for m in mounts), 'Web overlay selects exactly one HTTPS configuration')
        check(any(m['target'] == '/usr/share/nginx/html' and m['read_only'] and not m['bind']['create_host_path'] for m in mounts), 'Web export is mounted read-only without creating an empty source directory')
        for name in ['public.http.nginx.conf', 'public.https.nginx.conf', 'public.web.https.nginx.conf']:
            text = (ROOT / 'deploy' / name).read_text(encoding='utf-8')
            check('/.well-known/acme-challenge/' in text and 'root /var/www/acme' in text, 'ACME challenge survives configuration stage: ' + name)
        text = (ROOT / 'deploy/public.https.nginx.conf').read_text(encoding='utf-8')
        check('proxy_set_header Upgrade $http_upgrade' in text and 'proxy_set_header Connection $vssjx_connection_upgrade' in text and 'proxy_set_header Origin' not in text, 'WebSocket upgrade and unchanged browser Origin preserved')
        check('9090' not in text and 'location ^~ /api/v1/' in text and 'return 404' in text, 'Public proxy serves API only, without monitoring or repository files')

        if args.nginx:
            if not args.openssl: raise RuntimeError('--openssl is required for temporary test TLS certificate')
            cert = base / 'certs' / 'live' / 'vssjx-ip'
            cert.mkdir(parents=True)
            run([args.openssl, 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
                 '-subj', '/CN=deployment-fixture.invalid', '-keyout', str(cert / 'privkey.pem'), '-out', str(cert / 'fullchain.pem')])
            for name in ['public.http.nginx.conf', 'public.https.nginx.conf', 'public.web.https.nginx.conf']:
                run(['docker', 'run', '--rm', '--pull=never',
                     '--mount', f'type=bind,source={ROOT / "deploy" / name},target=/etc/nginx/conf.d/default.conf,readonly',
                     '--mount', f'type=bind,source={base / "certs"},target=/etc/letsencrypt,readonly',
                     'nginx:stable-alpine', 'nginx', '-t'])
                check(True, 'Actual Nginx accepts configuration: ' + name)
            script = ROOT / 'tools/renew-public-certificate.sh'
            run(['docker', 'run', '--rm', '--pull=never', '--entrypoint', 'sh',
                 '--mount', f'type=bind,source={script},target=/renew.sh,readonly', 'nginx:stable-alpine', '-n', '/renew.sh'])
            check(True, 'Certificate renewal script passes real POSIX shell parsing')
        if args.context:
            context = base / 'context'
            # Exercise Docker's actual allowlist semantics with tiny owned inputs.
            # No private project files are sent even if an ignore rule regresses.
            for name in ['server/Cargo.toml', 'server/Cargo.lock', 'server/src/main.rs', 'server/src/monitor_assets/index.html',
                         'server/migrations/0001.sql', 'shared/data/map.json', 'client/assets/data/skills-v1.json',
                         '.env', '.git/config', 'analysis/archive.bin', 'work/private.txt', 'server/target/private.bin',
                         'client/assets/actors/private.png', 'client/assets/data/actors/private.json', 'server/.env']:
                item = context / name
                item.parent.mkdir(parents=True, exist_ok=True)
                item.write_text('owned test fixture\n', encoding='utf-8')
            dockerfile = base / 'server.Dockerfile'
            dockerfile.write_text('FROM scratch\nCOPY . /context\nCMD ["/not-executed"]\n', encoding='utf-8')
            shutil.copyfile(ROOT / 'deploy/server.Dockerfile.dockerignore', base / 'server.Dockerfile.dockerignore')
            identity = 'vssjx-context-check-' + uuid4().hex
            try:
                run(['docker', 'build', '-f', str(dockerfile), '-t', identity, str(context)])
                run(['docker', 'create', '--name', identity, identity])
                exported = subprocess.run(['docker', 'export', identity], capture_output=True, check=True).stdout
                with tarfile.open(fileobj=io.BytesIO(exported)) as archive:
                    names = {member.name for member in archive.getmembers() if member.isfile() and member.name.startswith('context/')}
                check('context/server/Cargo.lock' in names and 'context/client/assets/data/skills-v1.json' in names, 'Docker context contains locked Rust build and embedded game definitions')
                expected = {'context/' + name for name in ['server/Cargo.toml', 'server/Cargo.lock', 'server/src/main.rs', 'server/src/monitor_assets/index.html', 'server/migrations/0001.sql', 'shared/data/map.json', 'client/assets/data/skills-v1.json']}
                check(names == expected, 'Actual Docker context excludes private env, archives, history, actors and build outputs; unexpected=' + repr(sorted(names - expected)))
            finally:
                subprocess.run(['docker', 'rm', '-f', identity], capture_output=True)
                subprocess.run(['docker', 'image', 'rm', identity], capture_output=True)
    print(f'PUBLIC DEPLOYMENT: {checks} checks, 0 failures')


if __name__ == '__main__':
    main()
