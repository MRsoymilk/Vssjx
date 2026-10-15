"""Lazy metadata correctness plus same-process metadata-only comparison."""
import argparse
import base64
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import zlib

from test_actor_import import ROOT


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, default=Path('/tmp/opencode/vssjx-actor-catalog'))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='actor-baseline-', dir='/tmp/opencode') as folder:
        legacy = Path(folder) / 'actors-v1.json'
        fixture = ROOT.parent / 'tests/fixtures/actors_v1.json.zlib.b64'
        legacy.write_bytes(zlib.decompress(base64.b64decode(fixture.read_text())))
        assert legacy.stat().st_size == 50026
        env = dict(os.environ, SSJX_ACTOR_CATALOG_REPORT=str((args.output / 'catalog.json').resolve()),
                   SSJX_ACTOR_CATALOG_LEGACY=str(legacy), XDG_DATA_HOME=str(args.output / 'userdata'))
        godot = os.environ.get('GODOT_BIN', 'godot')
        imported = subprocess.run([godot, '--headless', '--path', str(ROOT), '--import'], env=env, capture_output=True, text=True, check=True)
        (args.output / 'import.log').write_text(imported.stdout + imported.stderr)
        assert not re.search(r'(^ERROR:|SCRIPT ERROR)', imported.stdout + imported.stderr, re.M)
        result = subprocess.run([godot, '--headless', '--path', str(ROOT), 'res://tests/actor_catalog_test.tscn'], env=env, capture_output=True, text=True, timeout=60)
        (args.output / 'catalog.log').write_text(result.stdout + result.stderr)
        print(result.stdout, end='')
        assert result.returncode == 0 and '0 failures' in result.stdout, result.stderr
        assert not re.search(r'(^ERROR:|SCRIPT ERROR)', result.stdout + result.stderr, re.M)
        print(json.dumps(json.loads((args.output / 'catalog.json').read_text()), ensure_ascii=False, indent=2))


if __name__ == '__main__': main()
