"""Disposable Rust operator HTTP + real browser + two Godot channel consumers.

Does not require a database; does not claim authenticated world WebSocket E2E.
"""
import argparse
import os
from pathlib import Path
import queue
import re
import subprocess
import threading

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--server-bin', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--render', action='store_true')
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    if args.server_bin is None:
        subprocess.run(['cargo', 'build', '--locked', '--manifest-path', str(ROOT / 'server/Cargo.toml')], check=True)
    binary = args.server_bin or ROOT / 'server/target/debug' / ('vssjx-server.exe' if os.name == 'nt' else 'vssjx-server')
    env = {key: value for key, value in os.environ.items() if not key.startswith('SSJX_')}
    env.update(SSJX_ENV_FILE='', SSJX_DATABASE_URL='', SSJX_BIND_ADDR='127.0.0.1:0', SSJX_MONITOR_BIND_ADDR='127.0.0.1:0', SSJX_LOG_DIR='', RUST_LOG='info')
    startup = None
    if os.name == 'nt':
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = subprocess.SW_HIDE
        edge = Path('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe')
        if edge.exists(): env.setdefault('PLAYWRIGHT_CHROMIUM_EXECUTABLE', str(edge))
    process = subprocess.Popen([str(binary)], env=env, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf-8', startupinfo=startup)
    endpoints = queue.Queue()
    lines = []

    def read():
        for line in process.stdout:
            lines.append(line)
            match = re.search(r'monitor_endpoint=(127\.0\.0\.1:\d+)', line)
            if match: endpoints.put('http://' + match[1])

    reader = threading.Thread(target=read, daemon=True)
    reader.start()
    try:
        monitor = endpoints.get(timeout=20)
        subprocess.run(['node', str(ROOT / 'tests/announcement_browser.cjs'), monitor, str(args.output)], env=env, check=True, timeout=45)
        env.update(SSJX_ANNOUNCEMENT_PACKET_PATH=str(args.output / 'announcement_packet.json'))
        command = [env.get('GODOT_BIN', 'godot')]
        if args.render:
            command += ['--position', '-2000,-2000', '--audio-driver', 'Dummy']
            env['SSJX_ANNOUNCEMENT_CAPTURE_PATH'] = str(args.output)
        else: command += ['--headless']
        run = subprocess.run(command + ['--path', str(ROOT / 'client'), 'res://tests/announcements_test.tscn'], env=env, capture_output=True, text=True, encoding='utf-8', startupinfo=startup, timeout=45)
        print(run.stdout, end='')
        print(run.stderr, end='')
        assert run.returncode == 0 and '0 failures' in run.stdout and not re.search(r'(^ERROR:|SCRIPT ERROR)', run.stderr, re.M)
        print('PASS: real operator HTTP publish/replace/remove -> exact server packet -> two independent Godot announcement channels')
    finally:
        process.terminate()
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
        reader.join(timeout=5)
        process.stdout.close()
        (args.output / 'announcement_server.log').write_text(''.join(lines), encoding='utf-8')


if __name__ == '__main__': main()
