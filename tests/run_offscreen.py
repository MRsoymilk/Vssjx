"""Run Godot with real rendering on an isolated virtual X11 display.

Usage: python tests/run_offscreen.py --path client res://tests/motion_regression.tscn
Requires Xvfb and an OpenGL driver (Mesa software rendering works).
GODOT_BIN / XVFB_BIN can override the executable paths. No desktop is touched.
"""
import os
import shutil
import subprocess
import sys


def main():
    xvfb = os.environ.get('XVFB_BIN') or shutil.which('Xvfb')
    if not xvfb:
        raise SystemExit('Install Xvfb or set XVFB_BIN; --headless only tests logic')
    read_fd, write_fd = os.pipe()
    try:
        server = subprocess.Popen([xvfb, '-displayfd', str(write_fd), '-screen', '0',
                                   '640x960x24', '-nolisten', 'tcp', '-ac'],
                                  pass_fds=(write_fd,))
    except OSError:
        os.close(read_fd)
        raise
    finally:
        os.close(write_fd)
    try:
        # Xvfb writes a free display number only once it is ready to accept clients.
        with os.fdopen(read_fd) as ready:
            display = ready.readline().strip()
        if not display:
            raise SystemExit('Xvfb failed to start')
        env = dict(os.environ, DISPLAY=':' + display)
        return subprocess.call([os.environ.get('GODOT_BIN', 'godot'),
                                '--display-driver', 'x11', '--audio-driver', 'Dummy',
                                *sys.argv[1:]], env=env)
    finally:
        server.terminate()
        server.wait()


if __name__ == '__main__':
    sys.exit(main())
