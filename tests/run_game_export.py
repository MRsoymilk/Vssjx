"""Build real game PCKs and audit their contents without export templates or user saves."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('/tmp/opencode/vssjx-game-export'))
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    godot = os.environ.get('GODOT_BIN', 'godot')
    identity = uuid4().hex
    project = output / ('source-' + identity)
    shutil.copytree(ROOT / 'client', project, ignore=shutil.ignore_patterns('.godot', '*.import'))
    env = dict(os.environ, XDG_DATA_HOME=str(output / ('userdata-' + identity)),
               XDG_CONFIG_HOME=str(output / ('config-' + identity)), XDG_CACHE_HOME=str(output / ('cache-' + identity)),
               SSJX_SAVE_PATH='user://export_test_save.json')

    def run(name, command, expected=None):
        result = subprocess.run(command, env=env, cwd=output, capture_output=True, text=True, timeout=180)
        text = result.stdout + result.stderr
        (output / (name + '.log')).write_text(text)
        assert result.returncode == 0 and not re.search(r'(^ERROR:|SCRIPT ERROR|Parse Error)', text, re.M), name + ': see log'
        if expected:
            assert re.search(expected, text), name + ': verification did not finish'
        print(name + ': PASS')

    run('import', [godot, '--headless', '--path', str(project), '--editor', '--import'])
    for platform in ['Linux', 'Windows']:
        pack = output / ('game-' + platform.lower() + '.pck')
        run(platform.lower() + '-export', [godot, '--headless', '--path', str(project), '--export-pack', 'Game (' + platform + ')', str(pack)])
        assert pack.is_file() and pack.stat().st_size > 0
        run(platform.lower() + '-audit', [godot, '--headless', '--main-pack', str(pack), '--script', str(ROOT / 'tests/game_export_probe.gd')], r'GAME EXPORT: \d+ checks, 0 failures')


if __name__ == '__main__':
    main()
