"""P2b: isolated native Godot consumers under Web target/credential policy.

Two owned HTTP listeners verify accepted routes and zero outsider/redirect traffic.
No actual browser/Godot Web runtime, private config, external endpoints or DB.
"""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import threading
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('/tmp/opencode/vssjx-web-security'))
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    identity = uuid4().hex
    project = output / ('source-' + identity) / 'client'
    shutil.copytree(ROOT / 'client', project, ignore=shutil.ignore_patterns('.godot', '*.import'))
    shutil.copytree(ROOT / 'shared', project.parent / 'shared')
    env = {key: value for key, value in os.environ.items() if not key.startswith('SSJX_')}
    env.update(XDG_DATA_HOME=str(output / ('userdata-' + identity)),
               XDG_CONFIG_HOME=str(output / ('config-' + identity)), XDG_CACHE_HOME=str(output / ('cache-' + identity)))
    godot = env.get('GODOT_BIN', 'godot')
    records, routes, outsiders, sensitive = [], [], [], ['web-policy-password-1234', 'not-sent-password-1234']
    access, refresh = '', ''

    def run(name, command, marker=None):
        result = subprocess.run(command, env=env, cwd=output, capture_output=True, text=True, timeout=240)
        text = result.stdout + result.stderr
        (output / (name + '.log')).write_text(text, encoding='utf8')
        assert not any(secret in text for secret in sensitive), name + ': leaked test credential'
        assert result.returncode == 0 and not re.search(r'(^ERROR:|SCRIPT ERROR|Parse Error)', text, re.M), name + ': see log'
        if marker:
            assert re.search(marker, text), name + ': missing completion marker'
        records.append({'name': name, 'exit_code': result.returncode})
        print(name + ': PASS', flush=True)

    class Outsider(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def do_GET(self):
            outsiders.append(self.path)
            self.send_response(500)
            self.end_headers()

        do_POST = do_GET
        do_OPTIONS = do_GET

    class Service(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def reply(self, status, data=None):
            body = json.dumps(data).encode() if data is not None else b''
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            if status == 302:
                self.send_header('Location', env['SSJX_TEST_OUTSIDER_URL'] + '/redirected')
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self):
            self.handle_api()

        def do_GET(self):
            self.handle_api()

        def handle_api(self):
            nonlocal access, refresh
            routes.append((self.command, self.path))
            data = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))) or '{}')
            account = {'id': '00000000-0000-4000-8000-000000000001', 'username': 'web_policy_user'}
            if self.path == '/ssjx/api/v1/auth/register':
                assert data == {'username': account['username'], 'password': sensitive[0]}
                return self.reply(201, {'account': account})
            if self.path == '/ssjx/api/v1/auth/login':
                assert data == {'username': account['username'], 'password': sensitive[0]}
            elif self.path == '/ssjx/api/v1/auth/refresh':
                assert data == {'refresh_token': refresh}
            else:
                assert self.headers.get('Authorization') == 'Bearer ' + access
                if self.path == '/ssjx/api/v1/characters':
                    return self.reply(200, {'characters': [], 'rules_version': 'creation-v1', 'name_rules_version': 'nickname-v1'})
                if self.path == '/ssjx/api/v1/world/ticket':
                    ticket = uuid4().hex + uuid4().hex
                    sensitive.append(ticket)
                    return self.reply(200, {'ticket': ticket})
                if self.path == '/ssjx/api/v1/auth/me':
                    return self.reply(302, {'code': 'FIXTURE_REDIRECT'})
                if self.path == '/ssjx/api/v1/auth/logout':
                    return self.reply(204)
                return self.reply(404, {'code': 'NOT_FOUND'})
            access, refresh = uuid4().hex + uuid4().hex, uuid4().hex + uuid4().hex
            sensitive.extend([access, refresh])
            return self.reply(200, {'account': account, 'session_id': str(uuid4()), 'access_token': access,
                                   'refresh_token': refresh, 'expires_in': 3600, 'refresh_expires_in': 86400})

    servers = [ThreadingHTTPServer(('127.0.0.1', 0), handler) for handler in [Service, Outsider]]
    threads = [threading.Thread(target=server.serve_forever, daemon=True) for server in servers]
    for thread in threads:
        thread.start()
    env.update(SSJX_TEST_SERVER_URL=f'http://127.0.0.1:{servers[0].server_port}',
               SSJX_TEST_OUTSIDER_URL=f'http://127.0.0.1:{servers[1].server_port}',
               SSJX_CONNECTION_PATH='user://poisoned-native.cfg', SSJX_SAVE_PATH='user://offline-sentinel.json')
    try:
        run('import', [godot, '--headless', '--editor', '--path', str(project), '--import'])
        for suite in ['platform_web_security_test', 'platform_web_network_test']:
            run(suite, [godot, '--headless', '--path', str(project), 'res://tests/' + suite + '.tscn'], r'\d+ checks, 0 failures')
        expected = [('POST', '/ssjx/api/v1/auth/register'), ('POST', '/ssjx/api/v1/auth/login'),
                    ('GET', '/ssjx/api/v1/characters'), ('POST', '/ssjx/api/v1/world/ticket'),
                    ('POST', '/ssjx/api/v1/auth/refresh'), ('GET', '/ssjx/api/v1/auth/me'),
                    ('POST', '/ssjx/api/v1/auth/refresh'), ('POST', '/ssjx/api/v1/auth/logout')]
        assert routes == expected, 'Only exact controlled routes may receive requests'
        assert not outsiders, 'Outsider must receive no login, token, redirect or discovery traffic'
        userdata = Path(env['XDG_DATA_HOME'])
        assert not any(path.name.endswith(('.login', '.login.key', '.login.tmp')) for path in userdata.rglob('*')), 'No remembered credential files'
        assert not list(userdata.rglob('poisoned-native.cfg*')), 'Web policy must not read/write native connection preferences'
        report = {'runs': records, 'failures': 0, 'allowed_requests': len(routes), 'outsider_requests': len(outsiders),
                  'engine': subprocess.check_output([godot, '--version'], text=True).strip(),
                  'scope': 'Native Godot with injected page origin and real HTTP fixture, not Web export/browser/TLS/mobile acceptance'}
        (output / 'report.json').write_text(json.dumps(report, indent=2), encoding='utf8')
        print('WEB SECURITY: controlled routes and zero outsider requests: PASS', flush=True)
    finally:
        for server in servers:
            server.shutdown()
            server.server_close()
        for thread in threads:
            thread.join(timeout=5)


if __name__ == '__main__':
    main()
