"""Drive the actual release ELF with X11 mouse/keyboard on an owned Xvfb.

No editor, injected game API, test autoload or production test scene. Saves are
observed, not modified. Only synthetic offline data in an isolated XDG profile.
"""
import argparse
import ctypes as C
from ctypes.util import find_library
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
from PIL import Image


class Data(C.Union):
    _fields_ = [('b', C.c_char * 20), ('s', C.c_short * 10), ('l', C.c_long * 5)]


class ClientMessage(C.Structure):
    _fields_ = [('type', C.c_int), ('serial', C.c_ulong), ('send_event', C.c_int),
                ('display', C.c_void_p), ('window', C.c_ulong), ('message_type', C.c_ulong),
                ('format', C.c_int), ('data', Data)]


class Event(C.Union):
    _fields_ = [('xclient', ClientMessage), ('pad', C.c_long * 24)]


class X11:
    def __init__(self, display):
        self.lib = C.CDLL(find_library('X11') or 'libX11.so.6')
        self.test = C.CDLL(find_library('Xtst') or 'libXtst.so.6')
        self.lib.XOpenDisplay.argtypes = [C.c_char_p]
        self.lib.XOpenDisplay.restype = C.c_void_p
        self.lib.XDefaultRootWindow.argtypes = [C.c_void_p]
        self.lib.XDefaultRootWindow.restype = C.c_ulong
        self.lib.XQueryTree.argtypes = [C.c_void_p, C.c_ulong, C.POINTER(C.c_ulong), C.POINTER(C.c_ulong), C.POINTER(C.POINTER(C.c_ulong)), C.POINTER(C.c_uint)]
        self.lib.XGetGeometry.argtypes = [C.c_void_p, C.c_ulong, C.POINTER(C.c_ulong), C.POINTER(C.c_int), C.POINTER(C.c_int), C.POINTER(C.c_uint), C.POINTER(C.c_uint), C.POINTER(C.c_uint), C.POINTER(C.c_uint)]
        self.lib.XTranslateCoordinates.argtypes = [C.c_void_p, C.c_ulong, C.c_ulong, C.c_int, C.c_int, C.POINTER(C.c_int), C.POINTER(C.c_int), C.POINTER(C.c_ulong)]
        self.lib.XFetchName.argtypes = [C.c_void_p, C.c_ulong, C.POINTER(C.c_void_p)]
        self.lib.XFree.argtypes = [C.c_void_p]
        self.lib.XSetInputFocus.argtypes = [C.c_void_p, C.c_ulong, C.c_int, C.c_ulong]
        self.lib.XRaiseWindow.argtypes = [C.c_void_p, C.c_ulong]
        self.lib.XFlush.argtypes = [C.c_void_p]
        self.lib.XCloseDisplay.argtypes = [C.c_void_p]
        self.lib.XStringToKeysym.argtypes = [C.c_char_p]
        self.lib.XStringToKeysym.restype = C.c_ulong
        self.lib.XKeysymToKeycode.argtypes = [C.c_void_p, C.c_ulong]
        self.lib.XKeysymToKeycode.restype = C.c_ubyte
        self.lib.XInternAtom.argtypes = [C.c_void_p, C.c_char_p, C.c_int]
        self.lib.XInternAtom.restype = C.c_ulong
        self.lib.XSendEvent.argtypes = [C.c_void_p, C.c_ulong, C.c_int, C.c_long, C.POINTER(Event)]
        self.test.XTestFakeMotionEvent.argtypes = [C.c_void_p, C.c_int, C.c_int, C.c_int, C.c_ulong]
        self.test.XTestFakeButtonEvent.argtypes = [C.c_void_p, C.c_uint, C.c_int, C.c_ulong]
        self.test.XTestFakeKeyEvent.argtypes = [C.c_void_p, C.c_uint, C.c_int, C.c_ulong]
        self.display = self.lib.XOpenDisplay(display.encode())
        if not self.display:
            raise RuntimeError('Cannot open the owned virtual display')
        # A normal window manager creates these atoms before clients start.
        # Bare Xvfb has no WM; Godot interns WM_DELETE_WINDOW with only-if-exists.
        for atom in [b'WM_PROTOCOLS', b'WM_DELETE_WINDOW']:
            self.lib.XInternAtom(self.display, atom, 0)
        self.lib.XFlush(self.display)
        self.root = self.lib.XDefaultRootWindow(self.display)
        self.window = None
        self.bounds = None

    def find_game(self):
        root, parent, count = C.c_ulong(), C.c_ulong(), C.c_uint()
        children = C.POINTER(C.c_ulong)()
        if not self.lib.XQueryTree(self.display, self.root, C.byref(root), C.byref(parent), C.byref(children), C.byref(count)):
            return False
        try:
            for index in range(count.value):
                window = children[index]
                name = C.c_void_p()
                if not self.lib.XFetchName(self.display, window, C.byref(name)) or not name.value:
                    continue
                title = C.string_at(name.value).decode('utf8', errors='replace')
                self.lib.XFree(name)
                if '蜀山剑侠' not in title:
                    continue
                x, y, width, height, border, depth = C.c_int(), C.c_int(), C.c_uint(), C.c_uint(), C.c_uint(), C.c_uint()
                if not self.lib.XGetGeometry(self.display, window, C.byref(root), C.byref(x), C.byref(y), C.byref(width), C.byref(height), C.byref(border), C.byref(depth)):
                    continue
                if width.value < 320 or height.value < 480:
                    continue
                child = C.c_ulong()
                self.lib.XTranslateCoordinates(self.display, window, self.root, 0, 0, C.byref(x), C.byref(y), C.byref(child))
                self.window = window
                self.bounds = (x.value, y.value, width.value, height.value)
                self.lib.XRaiseWindow(self.display, window)
                self.lib.XSetInputFocus(self.display, window, 2, 0)
                self.lib.XFlush(self.display)
                return True
        finally:
            if children:
                self.lib.XFree(children)
        return False

    def key(self, name, pressed):
        code = self.lib.XKeysymToKeycode(self.display, self.lib.XStringToKeysym(name.encode('ascii')))
        if not code:
            raise ValueError('Unavailable test key: ' + name)
        self.test.XTestFakeKeyEvent(self.display, code, int(pressed), 0)
        self.lib.XFlush(self.display)

    def press(self, name, duration=0.06):
        self.key(name, True)
        time.sleep(duration)
        self.key(name, False)
        time.sleep(0.15)

    def type_text(self, text):
        for char in text:
            self.press(char, 0.05)

    def click(self, x, y):
        left, top, width, height = self.bounds
        self.test.XTestFakeMotionEvent(self.display, 0, round(left + x / 320 * width), round(top + y / 480 * height), 0)
        self.test.XTestFakeButtonEvent(self.display, 1, 1, 0)
        self.lib.XFlush(self.display)
        time.sleep(0.06)
        self.test.XTestFakeButtonEvent(self.display, 1, 0, 0)
        self.lib.XFlush(self.display)
        time.sleep(0.5)

    def close_window(self):
        event = Event()
        event.xclient.type = 33
        event.xclient.send_event = 1
        event.xclient.display = self.display
        event.xclient.window = self.window
        event.xclient.message_type = self.lib.XInternAtom(self.display, b'WM_PROTOCOLS', 0)
        event.xclient.format = 32
        event.xclient.data.l[0] = self.lib.XInternAtom(self.display, b'WM_DELETE_WINDOW', 0)
        if not self.lib.XSendEvent(self.display, self.window, 0, 0, C.byref(event)):
            raise RuntimeError('Window close event was not sent')
        self.lib.XFlush(self.display)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--executable', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--xvfb', type=Path, default=Path(os.environ.get('XVFB_BIN') or shutil.which('Xvfb') or '/tmp/opencode/vssjx-async-xvfb/usr/bin/Xvfb'))
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists() and any(output.iterdir()):
        raise ValueError('Use a fresh test output/profile directory')
    output.mkdir(parents=True, exist_ok=True)
    env = {key: value for key, value in os.environ.items() if not key.startswith('SSJX_')}
    env.pop('WAYLAND_DISPLAY', None)
    env.update(XDG_DATA_HOME=str(output / 'userdata'), XDG_CONFIG_HOME=str(output / 'config'), XDG_CACHE_HOME=str(output / 'cache'),
               LIBGL_ALWAYS_SOFTWARE='1', VK_LOADER_DRIVERS_DISABLE='*')
    # Exercise shipped fallback without relying on this host's Chinese fonts.
    empty_fonts = output / 'empty-fonts'
    empty_fonts.mkdir()
    fontconfig = output / 'fontconfig.xml'
    fontconfig.write_text('<fontconfig><dir>' + str(empty_fonts) + '</dir><cachedir>' + str(output / 'font-cache') + '</cachedir></fontconfig>')
    env['FONTCONFIG_FILE'] = str(fontconfig)
    xvfb_env = os.environ.copy()
    prefix = args.xvfb.resolve().parents[2]
    libraries = [str(p) for p in [prefix / 'usr/lib/x86_64-linux-gnu', prefix / 'lib/x86_64-linux-gnu'] if p.is_dir()]
    if libraries:
        xvfb_env['LD_LIBRARY_PATH'] = ':'.join(libraries + ([xvfb_env['LD_LIBRARY_PATH']] if xvfb_env.get('LD_LIBRARY_PATH') else []))
    read_fd, write_fd = os.pipe()
    server_log = (output / 'xvfb.log').open('w')
    try:
        server = subprocess.Popen([str(args.xvfb), '-displayfd', str(write_fd), '-screen', '0', '640x960x24', '-nolisten', 'tcp', '-ac'],
                                  env=xvfb_env, pass_fds=(write_fd,), stdout=server_log, stderr=server_log)
    finally:
        os.close(write_fd)
    process = None
    x11 = None
    logs = []
    checks = 0

    def check(value, description):
        nonlocal checks
        if not value:
            raise AssertionError(description)
        checks += 1
        print('PASS: ' + description, flush=True)

    def saved():
        for file in (output / 'userdata').rglob('shushan_save.json'):
            try:
                return json.loads(file.read_text(encoding='utf8'))
            except (FileNotFoundError, json.JSONDecodeError):
                pass
        return None

    def wait_save(predicate, timeout=18):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            value = saved()
            if predicate(value):
                return value
            if process.poll() is not None:
                raise RuntimeError('Game exited before the expected save')
            time.sleep(0.15)
        raise RuntimeError('Expected committed save not reached; actual: ' + json.dumps(saved(), ensure_ascii=False))

    def screenshot(name):
        path = output / (name + '.png')
        subprocess.run(['import', '-display', env['DISPLAY'], '-window', 'root', str(path)], env=env, check=True, timeout=15)
        with Image.open(path) as image:
            check(image.size == (640, 960) and len(image.convert('RGB').getcolors(1000000) or []) > 64, 'Rendered nonblank screenshot: ' + name)

    def launch(name):
        nonlocal process
        log = output / (name + '.log')
        logs.append(log)
        with log.open('w') as stream:
            process = subprocess.Popen([str(args.executable.resolve()), '--display-driver', 'x11', '--audio-driver', 'Dummy',
                                        '--rendering-driver', 'opengl3_es', '--max-fps', '60', '--verbose'],
                                       cwd=args.executable.resolve().parent, env=env, stdout=stream, stderr=stream)
        deadline = time.monotonic() + 25
        while not x11.find_game():
            if process.poll() is not None or time.monotonic() >= deadline:
                raise RuntimeError('Release game window did not start: ' + log.read_text())
            time.sleep(0.15)
        time.sleep(1.2)

    def enter_local():
        x11.click(235, 414)
        x11.click(170, 126)
        x11.key('Control_L', True)
        x11.press('a')
        x11.key('Control_L', False)
        x11.type_text('local')
        x11.click(160, 318)

    try:
        with os.fdopen(read_fd) as ready:
            display = ready.readline().strip()
        if not display.isdigit():
            raise RuntimeError('Owned Xvfb failed to start; see xvfb.log')
        env['DISPLAY'] = ':' + display
        x11 = X11(env['DISPLAY'])
        launch('first-process')
        check(saved() is None, 'Fresh isolated native profile has no save')
        screenshot('01-cover')
        enter_local()
        screenshot('02-empty-selection')
        x11.click(24, 464)
        x11.click(60, 372)
        screenshot('02b-creation')
        x11.click(160, 278)
        x11.type_text('linuxhero')
        x11.click(20, 467)
        initial = wait_save(lambda value: value and value.get('name') == 'linuxhero')
        check(initial['version'] == 1 and initial['gold'] == 30, 'Real release UI creates and commits v1 character')
        screenshot('03-character-selection')
        x11.click(160, 464)
        time.sleep(0.8)
        screenshot('04-world')
        x11.press('e')
        time.sleep(1.2)
        screenshot('05-npc-dialogue')
        x11.click(100, 319)
        quest = wait_save(lambda value: value and value.get('quest') == 1)
        check(quest['name'] == 'linuxhero', 'NPC quest commits through actual UI')
        x11.press('d', 0.5)
        moved = wait_save(lambda value: value and value['cell'][0] > quest['cell'][0])
        check(moved['kills'] == 0, 'X11 keyboard movement reaches saved map position')
        screenshot('06-world-moved')
        x11.click(160 + (18 - moved['cell'][0]) * 16, 215.5 + (10 - moved['cell'][1]) * 16)
        time.sleep(4)
        screenshot('07-battle-ready')
        x11.press('0')
        won = wait_save(lambda value: value and value.get('kills') == 1, timeout=75)
        check(won['gold'] == 42 and won['xp'] == 16 and 'wolf_a' in won['defeated'], 'Actual release battle settles wolf rewards exactly once')
        screenshot('08-victory')
        x11.click(160, 325)
        x11.press('s', 0.4)
        x11.close_window()
        check(process.wait(timeout=15) == 0, 'Real WM close exits release process successfully')
        closed = saved()
        check(closed['kills'] == 1 and closed['cell'][1] > won['cell'][1], 'Window close preserves latest movement and settled rewards')
        launch('restarted-process')
        enter_local()
        screenshot('09-restored-selection')
        x11.click(160, 464)
        time.sleep(0.8)
        x11.press('s', 0.4)
        restored = wait_save(lambda value: value and value['cell'][1] != closed['cell'][1])
        check(restored['name'] == 'linuxhero' and restored['kills'] == 1 and restored['gold'] == 42, 'New native process restores and continues actual saved Game without replaying reward')
        screenshot('10-restored-world')
        x11.close_window()
        check(process.wait(timeout=15) == 0, 'Restored process closes normally')
        text = '\n'.join(log.read_text(encoding='utf8') for log in logs)
        version = subprocess.check_output([str(args.executable.resolve()), '--version'], env=env, text=True).strip()
        check('OpenGL' in text and version.startswith('4.7.2.stable.official'), 'Official release runtime used actual OpenGL rendering')
        check(not re.search(r'(^ERROR:|SCRIPT ERROR|Parse Error)', text, re.M), 'No release runtime script/render errors')
        (output / 'report.json').write_text(json.dumps({'checks': checks, 'failures': 0,
            'scope': 'Actual release ELF, owned Xvfb, Mesa software OpenGL, XTest UI, native filesystem and process restart; not hardware/all-distro/online acceptance',
            'executable': str(args.executable.resolve()), 'fontconfig': 'isolated empty system-font directory'}, indent=2))
        print('LINUX RELEASE UI: %d checks, 0 failures' % checks, flush=True)
    except Exception:
        if x11:
            try:
                screenshot('failure')
            except Exception:
                pass
        raise
    finally:
        if process and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        if x11:
            x11.lib.XCloseDisplay(x11.display)
        server.terminate()
        server.wait(timeout=10)
        server_log.close()


if __name__ == '__main__':
    main()
