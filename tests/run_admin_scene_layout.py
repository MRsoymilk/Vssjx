"""Standalone desktop admin layout regression; --render captures actual pixels."""
import argparse
from contextlib import contextmanager
import ctypes
import ctypes.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]


@contextmanager
def display(env):
    xvfb = env.get('XVFB_BIN') or shutil.which('Xvfb')
    if not xvfb:
        raise RuntimeError('Real rendering requires Xvfb or XVFB_BIN')
    read_fd, write_fd = os.pipe()
    try:
        server = subprocess.Popen([xvfb, '-displayfd', str(write_fd), '-screen', '0', '1600x1000x24', '-nolisten', 'tcp', '-ac'], pass_fds=(write_fd,), env=env)
    finally:
        os.close(write_fd)
    try:
        with os.fdopen(read_fd) as ready:
            number = ready.readline().strip()
        if not number:
            raise RuntimeError('Xvfb did not initialize')
        yield dict(env, DISPLAY=':' + number)
    finally:
        server.terminate()
        server.wait(timeout=10)


@contextmanager
def portrait_editor_host(env):
    """Reproduce F6's real --wid parent and 640x960 resolution, not just resize UI."""
    x = ctypes.CDLL(ctypes.util.find_library('X11') or 'libX11.so.6')
    pointer, ulong, integer = ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int
    for name, arguments, result in [
        ('XOpenDisplay', [ctypes.c_char_p], pointer), ('XDefaultRootWindow', [pointer], ulong),
        ('XCreateSimpleWindow', [pointer, ulong, integer, integer, ctypes.c_uint, ctypes.c_uint, ctypes.c_uint, ulong, ulong], ulong),
        ('XMapWindow', [pointer, ulong], integer), ('XSync', [pointer, integer], integer),
        ('XDestroyWindow', [pointer, ulong], integer), ('XCloseDisplay', [pointer], integer),
    ]:
        function = getattr(x, name)
        function.argtypes, function.restype = arguments, result
    connection = x.XOpenDisplay(env['DISPLAY'].encode())
    if not connection:
        raise RuntimeError('Cannot open owned Xvfb display')
    window = x.XCreateSimpleWindow(connection, x.XDefaultRootWindow(connection), 0, 0, 640, 960, 0, 0, 0)
    try:
        x.XMapWindow(connection, window)
        x.XSync(connection, 0)
        yield str(window)
    finally:
        x.XDestroyWindow(connection, window)
        x.XCloseDisplay(connection)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--render', action='store_true')
    parser.add_argument('--output', type=Path, default=Path('/tmp/opencode/vssjx-admin-desktop'))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    output = args.output.resolve()
    # A unique user data directory avoids every real player's saves/preferences.
    identity = uuid4().hex
    project = output / ('source-' + identity)
    shutil.copytree(ROOT / 'client', project, ignore=shutil.ignore_patterns('.godot', '*.import'))
    env = dict(os.environ, XDG_DATA_HOME=str(output / ('userdata-' + identity)),
               XDG_CONFIG_HOME=str(output / ('config-' + identity)), XDG_CACHE_HOME=str(output / ('cache-' + identity)),
               SSJX_SAVE_PATH='user://admin_scene_layout_test_save.json')
    env.pop('SSJX_ADMIN_LAYOUT_CAPTURE', None)
    godot = env.get('GODOT_BIN', 'godot')
    records = []

    def run(name, flags, scene, user_args=(), capture=None, process_env=None):
        current = dict(process_env or env)
        if capture:
            current['SSJX_ADMIN_LAYOUT_CAPTURE'] = str(capture)
        command = [godot, *flags, '--path', str(project), scene]
        if user_args:
            command += ['--', *user_args]
        result = subprocess.run(command, env=current, capture_output=True, text=True, timeout=90)
        text = result.stdout + result.stderr
        (output / (name + '.log')).write_text(text)
        assert result.returncode == 0 and not re.search(r'(^ERROR:|SCRIPT ERROR|Parse Error)', text, re.M), name + ': see its log'
        if name.startswith('layout-'):
            assert re.search(r'ADMIN SCENE LAYOUT: \d+ checks, 0 failures', text), name
        elif name.startswith('catalog-'):
            assert re.search(r'Data browser: \d+ checks, 0 failures', text), name
        elif name != 'import':
            assert 'ADMIN SCENE LAUNCH: PASS' in text, name
        records.append({'name':name, 'exit_code':result.returncode})
        print(name + ': PASS')
        return text

    run('import', ['--headless', '--editor'], '--import')
    run('layout-headless', ['--headless'], 'res://tests/admin_scene_layout_test.tscn')
    run('catalog-headless', ['--headless'], 'res://tests/data_browser_test.tscn')
    for stem in ['data_browser', 'world_overview']:
        run(stem + '-standalone', ['--headless'], 'res://tests/admin_scene_launch_probe.tscn', ['--admin-scene', 'res://scenes/admin/' + stem + '.tscn'])
    if args.render:
        with display(env) as rendered_env:
            flags = ['--display-driver', 'x11', '--audio-driver', 'Dummy', '--rendering-driver', 'opengl3_es']
            run('layout-rendered', flags, 'res://tests/admin_scene_layout_test.tscn', capture=output, process_env=rendered_env)
            for stem in ['data_browser', 'world_overview']:
                run(stem + '-desktop', flags, 'res://tests/admin_scene_launch_probe.tscn',
                    ['--admin-scene', 'res://scenes/admin/' + stem + '.tscn'], output / (stem + '-desktop.png'), rendered_env)
                with portrait_editor_host(rendered_env) as parent:
                    run(stem + '-f6-host', flags + ['--resolution', '640x960', '--wid', parent], 'res://tests/admin_scene_launch_probe.tscn',
                        ['--admin-scene', 'res://scenes/admin/' + stem + '.tscn', '--expect-editor-host'],
                        output / (stem + '-f6-desktop.png'), rendered_env)
    (output / 'report.json').write_text(json.dumps({'runs':records, 'failures':0, 'rendered':args.render}, indent=2))


if __name__ == '__main__':
    main()
