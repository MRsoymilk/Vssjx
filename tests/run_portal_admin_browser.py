"""Create disposable metrics/APK data and preview the real private management UI."""
from datetime import datetime, timezone
from io import BytesIO
import os
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory
import threading

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from portal_stats.apks import ApkManager
from portal_stats.server import StatsServer
from portal_stats.store import Store
from test_portal_apks import apk
from test_portal_stats import event


def main():
    output = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / 'work/portal-admin-captures'
    output.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(prefix='vssjx-private-admin-', dir='/tmp/opencode' if Path('/tmp/opencode').is_dir() else None) as temporary:
        base = Path(temporary)
        database = base / 'stats.sqlite3'
        store = Store(database)
        now = datetime.now(timezone.utc)
        store.ingest([event(1, moment=now), event(2, moment=now), event(3, 'game', moment=now),
                      event(4, 'web_click', 302, moment=now), event(5, 'android_click', 302, moment=now),
                      event(6, 'apk', 200, 1000, moment=now), event(7, 'apk', 206, 100, moment=now)])
        store.status('idle')
        store.close()
        manager = ApkManager(base / 'private-apks', base / 'public-apks')
        old = apk(b'old')
        record = manager.upload(BytesIO(old), len(old), '旧版.apk')['file']
        manager.publish(record['id'])
        other = apk(b'old untrusted filename')
        manager.upload(BytesIO(other), len(other), '<img src=x onerror=alert(1)>.apk')
        uploaded = base / 'new-preview.apk'
        uploaded.write_bytes(apk(b'new version'))
        server = StatsServer('127.0.0.1', 0, database, manager)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            subprocess.run(['node', str(ROOT / 'tests/portal_admin_browser.cjs'),
                            f'http://127.0.0.1:{server.server_port}', str(uploaded), str(output)],
                           check=True, env=os.environ.copy(), timeout=120)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)


if __name__ == '__main__':
    main()
