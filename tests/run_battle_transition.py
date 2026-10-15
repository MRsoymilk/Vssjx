"""Actual encounter warning / resource preparation, without a developer save."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--render', action='store_true')
    parser.add_argument('--output', type=Path, default=Path('/tmp/opencode/vssjx-battle-transition'))
    args = parser.parse_args()
    env = dict(os.environ)
    env.pop('SSJX_ENCOUNTER_CAPTURE_PATH', None)
    command = [os.environ.get('GODOT_BIN', 'godot'), '--headless']
    if args.render:
        args.output.mkdir(parents=True, exist_ok=True)
        env['SSJX_ENCOUNTER_CAPTURE_PATH'] = str(args.output.resolve())
        command = [sys.executable, str(ROOT / 'tests/run_offscreen.py'), '--rendering-driver', 'opengl3_es']
    command += ['--path', str(ROOT / 'client'), 'res://tests/battle_transition_test.tscn']
    result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=90)
    print(result.stdout, end='')
    print(result.stderr, end='', file=sys.stderr)
    assert result.returncode == 0 and '0 failures' in result.stdout
    assert not re.search(r'(^ERROR:|SCRIPT ERROR)', result.stdout + result.stderr, re.M)
    if args.render:
        from PIL import Image
        trace = json.loads((args.output / 'encounter_trace.json').read_text())
        for zone in range(2):
            frames = [frame for frame in trace if frame['zone'] == zone]
            loading = [frame for frame in frames if frame['mode'] == 'battle_loading']
            assert loading and frames[-1]['mode'] == 'battle'
            progress = [frame['progress'] for frame in loading]
            assert progress == sorted(progress) and min(progress) == 0 and max(progress) == 1
            crops = []
            for frame in loading:
                with Image.open(args.output / frame['path']) as image:
                    assert image.size == (640, 960)
                    crops.append(image.crop((96, 740, 544, 780)).tobytes())
            assert len(set(crops)) >= 2, 'Preparation bar never changed in the rendered image'
        print('PASS: real encounter warning, progressing loading frame and battle handoff on both maps')


if __name__ == '__main__':
    main()
