"""Battle casting regressions; --render uses actual isolated X11/Mesa frames."""
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
    parser.add_argument('--output', type=Path, default=Path('/tmp/opencode/vssjx-battle-casting'))
    args = parser.parse_args()
    env = dict(os.environ)
    env.pop('SSJX_BATTLE_CAPTURE_PATH', None)
    command = [os.environ.get('GODOT_BIN', 'godot'), '--headless']
    if args.render:
        args.output.mkdir(parents=True, exist_ok=True)
        env['SSJX_BATTLE_CAPTURE_PATH'] = str(args.output.resolve())
        command = [sys.executable, str(ROOT / 'tests/run_offscreen.py'), '--rendering-driver', 'opengl3_es']
    command += ['--path', str(ROOT / 'client'), 'res://tests/battle_casting_test.tscn']
    result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=90)
    print(result.stdout, end='')
    print(result.stderr, end='', file=sys.stderr)
    assert result.returncode == 0 and '0 failures' in result.stdout
    assert not re.search(r'(^ERROR:|SCRIPT ERROR)', result.stdout + result.stderr, re.M)
    if args.render:
        from PIL import Image
        trace = json.loads((args.output / 'casting_trace.json').read_text())
        assert len(trace) == 120
        for gender in range(2):
            for command, animation in [('skill', 'cast'), ('attack', 'attack')]:
                frames = [frame for frame in trace if frame['gender'] == gender and frame['command'] == command and frame['animation'] == animation]
                assert len({frame['frame'] for frame in frames}) >= 4
                pixels = []
                for frame in frames:
                    with Image.open(args.output / frame['path']) as image:
                        assert image.size == (640, 960)
                        # Character/staff only: excludes the enemy hit effect and move bubble.
                        pixels.append(image.crop((340, 400, 630, 640)).tobytes())
                # Female native attack intentionally holds the first three ANI
                # composites unchanged; casting still has five distinct poses.
                assert len(set(pixels)) >= (4 if command == 'skill' else 3), (gender, command, 'staff/body remained visually static')
        print('PASS: 120 real-rendered battle frames, both mage variants, staff motion and one-shot recovery')


if __name__ == '__main__':
    main()
