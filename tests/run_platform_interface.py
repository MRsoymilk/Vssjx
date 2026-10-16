"""P1 native platform regression in an isolated source copy and user directory."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--render', action='store_true')
    parser.add_argument('--network', action='store_true', help='Also run real Rust discovery and two-process address persistence')
    parser.add_argument('--output', type=Path, default=Path('/tmp/opencode/vssjx-platform-p1'))
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    identity = uuid4().hex
    project = output / ('source-' + identity) / 'client'
    shutil.copytree(ROOT / 'client', project, ignore=shutil.ignore_patterns('.godot', '*.import'))
    # Protocol regression scenes resolve their golden vectors beside client/.
    shutil.copytree(ROOT / 'shared', project.parent / 'shared')
    # Never inherit developer endpoints, credentials, capture paths or test phases.
    env = {key: value for key, value in os.environ.items() if not key.startswith('SSJX_')}
    env.update(XDG_DATA_HOME=str(output / ('userdata-' + identity)),
               XDG_CONFIG_HOME=str(output / ('config-' + identity)), XDG_CACHE_HOME=str(output / ('cache-' + identity)),
               SSJX_SAVE_PATH='user://platform_runner_save.json', SSJX_CONNECTION_PATH='user://platform_runner_connection.cfg',
               SSJX_TEST_CLIENT_PATH=str(project))
    godot = env.get('GODOT_BIN', 'godot')
    records = []

    def run(name, command, expected=None):
        try:
            result = subprocess.run(command, env=env, cwd=ROOT, capture_output=True, text=True, timeout=240)
        except subprocess.TimeoutExpired as error:
            def decode(value):
                return value.decode('utf8', errors='replace') if isinstance(value, bytes) else value or ''
            (output / (name + '.log')).write_text(decode(error.stdout) + decode(error.stderr), encoding='utf8')
            raise RuntimeError(name + ': timed out; see ' + str(output / (name + '.log'))) from error
        text = result.stdout + result.stderr
        (output / (name + '.log')).write_text(text, encoding='utf8')
        if result.returncode or re.search(r'(^ERROR:|SCRIPT ERROR|Parse Error)', text, re.M):
            raise RuntimeError(name + ': see ' + str(output / (name + '.log')))
        if expected and not re.search(expected, text):
            raise RuntimeError(name + ': completion marker missing')
        records.append({'name': name, 'exit_code': result.returncode})
        print(name + ': PASS', flush=True)

    run('import', [godot, '--headless', '--editor', '--path', str(project), '--import'])
    suites = ['platform_interface_test', 'test_runner', 'server_connection_test',
              'world_delta_test', 'public_chat_test', 'shared_interface_test',
              'local_mode_test', 'login_ui_test', 'character_selection_test',
              'game_menu_test', 'movement_control_test', 'motion_regression', 'battle_transition_test']
    for suite in suites:
        run(suite, [godot, '--headless', '--path', str(project), 'res://tests/' + suite + '.tscn'], r'\d+ checks, 0 failures')
    run('auth-character-contract-fixture', [sys.executable, str(ROOT / 'tests/run_registration_flow.py')],
        r'ACCOUNT AUTH UI: \d+ checks, 0 failures')
    if args.render:
        for suite in ['platform_interface_test', 'visual_smoke']:
            if suite == 'visual_smoke':
                capture = output / 'screenshots'
                capture.mkdir(exist_ok=True)
                env['SSJX_CAPTURE_PATH'] = str(capture)
            run(suite + '-rendered', [sys.executable, str(ROOT / 'tests/run_offscreen.py'), '--path', str(project),
                                    '--rendering-driver', 'opengl3_es', 'res://tests/' + suite + '.tscn'],
                r'PLATFORM INTERFACE: \d+ checks, 0 failures' if suite == 'platform_interface_test' else r'VISUAL SMOKE: 37 screenshots saved')
            if suite == 'visual_smoke' and len(list(capture.glob('*.png'))) != 37:
                raise RuntimeError('visual_smoke: expected 37 actual PNG captures')
    if args.network:
        run('rust-discovery-persistence', [sys.executable, str(ROOT / 'tests/run_server_connection.py')],
            r'PASS: Rust discovery')
    (output / 'report.json').write_text(json.dumps({'runs': records, 'failures': 0,
        'engine': subprocess.check_output([godot, '--version'], text=True).strip(),
        'scope': 'P1 native only; not Web export, Windows runtime or mobile browser acceptance'}, indent=2), encoding='utf8')


if __name__ == '__main__':
    main()
