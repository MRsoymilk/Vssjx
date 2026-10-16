"""Build a storage-only Godot Web fixture; never enables the game Web factory.

Only copied public interface/Game/auth guard code, isolated browser profile and
owned loopback listener. No private .env, player saves, database or real account.
"""
import argparse
import hashlib
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import threading
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE_SHA256 = '08962aefef811b603541d7951ac67ef00413aad2d978855183c28adee98f626a'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--template', type=Path, required=True, help='Verified matching web_nothreads_debug.zip, not a game preset')
    parser.add_argument('--output', type=Path, default=Path('/tmp/opencode/vssjx-web-storage'))
    args = parser.parse_args()
    assert hashlib.sha256(args.template.read_bytes()).hexdigest() == TEMPLATE_SHA256, 'Expected pinned official Godot 4.7.2 single-threaded debug Web template'
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    project = output / ('source-' + uuid4().hex)
    fixture = ROOT / 'tests/fixtures/web_storage'
    (project / 'scripts/network').mkdir(parents=True)
    shutil.copytree(ROOT / 'client/scripts/interface', project / 'scripts/interface')
    shutil.copytree(fixture, project / 'tests')
    shutil.copy2(ROOT / 'client/scripts/game_state.gd', project / 'scripts/game_state.gd')
    for name in ['remembered_login.gd', 'online_account.gd', 'server_connection_settings.gd']:
        shutil.copy2(ROOT / 'client/scripts/network' / name, project / 'scripts/network' / name)
    (project / 'project.godot').write_text('''config_version=5
[application]
config/name="Vssjx Storage Only Fixture"
run/main_scene="res://tests/main.tscn"
config/features=PackedStringArray("4.7", "GL Compatibility")
[autoload]
Platform="*res://tests/platform.gd"
Game="*res://scripts/game_state.gd"
OnlineAccount="*res://scripts/network/online_account.gd"
[display]
window/size/viewport_width=96
window/size/viewport_height=96
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
''', encoding='utf8')
    (project / 'export_presets.cfg').write_text('''[preset.0]
name="Storage (Web test)"
platform="Web"
runnable=true
export_filter="all_resources"
include_filter="scripts/interface/adapters/web/*.js"
exclude_filter=""
script_export_mode=2
[preset.0.options]
custom_template/debug=%s
variant/extensions_support=false
variant/thread_support=false
html/head_include=%s
html/export_icon=false
progressive_web_app/enabled=false
''' % (json.dumps(str(args.template.resolve())), json.dumps((fixture / 'head.html').read_text('utf8'))), encoding='utf8')
    env = {key: value for key, value in os.environ.items() if not key.startswith('SSJX_')}
    env.update(XDG_DATA_HOME=str(output / 'godot-userdata'), XDG_CONFIG_HOME=str(output / 'godot-config'), XDG_CACHE_HOME=str(output / 'godot-cache'))
    godot = env.get('GODOT_BIN', 'godot')
    public = output / 'public'
    public.mkdir(exist_ok=True)
    for name, command in [('import', [godot, '--headless', '--editor', '--path', str(project), '--import']),
                          ('export', [godot, '--headless', '--path', str(project), '--export-debug', 'Storage (Web test)', str(public / 'index.html')])]:
        result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=240)
        text = result.stdout + result.stderr
        (output / (name + '.log')).write_text(text, encoding='utf8')
        assert result.returncode == 0 and not re.search(r'(^ERROR:|SCRIPT ERROR|Parse Error)', text, re.M), name + ': see log'
    (public / 'core.html').write_text('<!doctype html><title>Owned storage core fixture, not the game</title>', encoding='utf8')
    requests = []
    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, *parts, **kwargs):
            super().__init__(*parts, directory=str(public), **kwargs)

        def log_message(self, *_args):
            pass

        def do_GET(self):
            requests.append(self.path)
            if self.path == '/favicon.ico':
                self.send_response(204)
                self.end_headers()
                return
            super().do_GET()

        def end_headers(self):
            self.send_header('Cache-Control', 'no-store')
            super().end_headers()
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        base = f'http://127.0.0.1:{server.server_port}'
        result = subprocess.run(['node', str(ROOT / 'tests/web_storage_browser.cjs'), base, str(output)],
                                env=env, capture_output=True, text=True, timeout=240)
        text = result.stdout + result.stderr
        (output / 'browser.log').write_text(text, encoding='utf8')
        assert result.returncode == 0 and 'WEB STORAGE BROWSER:' in text, 'Browser fixture failed; see browser.log'
        assert not any('/api/v1/' in request for request in requests), 'Storage fixture must not send account/world HTTP requests'
        report = {'failures': 0, 'scope': 'Real Godot Web storage-only fixture and Chromium IndexedDB; not full game/mobile/production TLS acceptance',
                  'native_editor': subprocess.check_output([godot, '--version'], text=True).strip(),
                  'template_sha256': hashlib.sha256(args.template.read_bytes()).hexdigest(),
                  'source_sha256': hashlib.sha256((ROOT / 'client/scripts/interface/adapters/web/indexeddb_storage.js').read_bytes()).hexdigest(),
                  'git_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()}
        (output / 'report.json').write_text(json.dumps(report, indent=2), encoding='utf8')
        print(text, end='')
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


if __name__ == '__main__':
    main()
