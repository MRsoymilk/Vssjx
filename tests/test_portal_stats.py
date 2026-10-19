from datetime import date, datetime, timedelta, timezone
import importlib.util
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import threading
import time
from tempfile import TemporaryDirectory
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from portal_stats.collector import Lines, docker_stream
from portal_stats.store import LOCAL_TIME, METRICS, PREFIX, Store, parse_event, read_summary

NOW = datetime(2026, 10, 19, 10, tzinfo=timezone.utc)


def event(number=1, route='portal', status=200, size=100, moment=NOW):
    return PREFIX + json.dumps({'id': f'{number:032x}', 'at': f'{moment.timestamp():.3f}',
                                'route': route, 'status': status, 'bytes': size}) + '\n'


class StatsStoreTests(unittest.TestCase):
    def setUp(self):
        self.temporary = TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name) / 'stats.sqlite3'
        self.store = Store(self.path, now=lambda: NOW)
        self.addCleanup(lambda: self.store.close())

    def totals(self, start=date(2026, 10, 19), end=date(2026, 10, 19)):
        return read_summary(self.path, start, end)['totals']

    def test_whitelisted_metrics_do_not_claim_download_completion(self):
        result = self.store.ingest([
            event(1), event(2, 'game', 304), event(3, 'web_click', 302), event(4, 'android_click', 302),
            event(5, 'apk', 200, 1200), event(6, 'apk', 206, 100), event(7, 'apk', 206, 200),
            event(8, 'apk', 304, 0), event(9, 'apk', 499, 999), event(10, 'apk', 416, 500),
            event(11, 'portal', 404), event(12, 'web_click', 200),
        ])
        self.assertEqual(result['applied'], 12)
        self.assertEqual(self.totals(), dict(zip(METRICS, (1, 1, 1, 1, 3, 1, 2, 1, 2, 1500))))

    def test_replay_and_restart_do_not_double_count(self):
        self.store.ingest([event()])
        self.assertEqual(self.store.ingest([event()])['duplicate'], 1)
        self.store.close()
        self.store = Store(self.path, now=lambda: NOW)
        self.assertEqual(self.store.ingest([event()])['duplicate'], 1)
        self.assertEqual(self.totals()['portal_views'], 1)
        self.assertEqual(self.store.ingest([event(route='apk')])['conflict'], 1)
        self.assertEqual(self.totals()['apk_requests'], 0)

    def test_dedup_and_totals_share_one_transaction(self):
        self.store.db.execute("CREATE TRIGGER fail_daily BEFORE INSERT ON daily BEGIN SELECT RAISE(ABORT, 'fixture'); END")
        self.store.db.commit()
        with self.assertRaises(sqlite3.IntegrityError):
            self.store.ingest([event()])
        self.assertEqual(self.store.db.execute('SELECT count(*) FROM seen').fetchone()[0], 0)
        self.store.db.execute('DROP TRIGGER fail_daily')
        self.store.db.commit()
        self.assertEqual(self.store.ingest([event()])['applied'], 1)

    def test_daily_timezone_is_explicit_and_empty_dates_are_filled(self):
        before = datetime(2026, 10, 18, 15, 59, 59, 999000, tzinfo=timezone.utc)
        after = before + timedelta(milliseconds=1)
        self.store.ingest([event(1, moment=before), event(2, moment=after)])
        summary = read_summary(self.path, date(2026, 10, 17), date(2026, 10, 19))
        self.assertEqual(summary['timezone'], 'UTC+08:00')
        self.assertEqual([day['portal_views'] for day in summary['days']], [0, 1, 1])

    def test_retired_ids_can_be_removed_without_old_logs_counting_again(self):
        old = NOW - timedelta(days=29)
        self.store.ingest([event(moment=old)])
        self.store.now = lambda: NOW + timedelta(days=2)
        self.store.prune()
        self.assertEqual(self.store.db.execute('SELECT count(*) FROM seen').fetchone()[0], 0)
        self.assertEqual(self.store.ingest([event(moment=old)])['retired'], 1)
        self.assertEqual(self.totals(old.astimezone(LOCAL_TIME).date(), NOW.date())['portal_views'], 1)

    def test_invalid_fields_ids_numbers_and_raw_logs_are_not_persisted(self):
        invalid = [PREFIX + '{"id":', event().replace('"bytes": 100', '"bytes": true'),
                   event().replace('"route": "portal"', '"route": "api"'),
                   event().replace('"id": "00000000000000000000000000000001"', '"id": "secret"'),
                   event().replace('"bytes": 100', '"bytes": -1'),
                   event().replace('"bytes": 100', '"bytes": 1, "bytes": 2'),
                   PREFIX + json.dumps({'password': 'fixture-private-do-not-store'}),
                   b'\xff\xff', b'x' * 4097, event(moment=NOW + timedelta(days=2))]
        result = self.store.ingest(invalid + ['Nginx error: fixture-private-do-not-store'])
        self.assertEqual(result['invalid'], len(invalid))
        self.assertEqual(result['ignored'], 1)
        self.assertEqual(self.totals()['portal_views'], 0)
        self.store.db.execute('PRAGMA wal_checkpoint(TRUNCATE)')
        self.assertNotIn(b'fixture-private-do-not-store', self.path.read_bytes())
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)

    def test_docker_timestamp_and_chunk_boundaries_are_supported(self):
        line = ('2026-10-19T10:00:00.123456789Z ' + event()).encode()
        self.assertEqual(parse_event(line)['route'], 'portal')
        decoder = Lines()
        self.assertEqual(decoder.feed(line[:20]), [])
        self.assertEqual(decoder.feed(line[20:]), [line])
        oversized = b'x' * 8000 + b'\n'
        decoded = decoder.feed(oversized + line)
        self.assertEqual(len(decoded), 2)
        result = self.store.ingest(decoded)
        self.assertEqual((result['invalid'], result['applied']), (1, 1))

    def test_summary_is_read_only_and_date_ranges_are_bounded(self):
        self.store.ingest([event()])
        self.assertEqual(self.totals()['portal_views'], 1)
        with self.assertRaises(ValueError):
            read_summary(self.path, date(2020, 1, 1), date(2026, 1, 1))
        with self.assertRaises(ValueError):
            read_summary(self.path, NOW.date(), date(2020, 1, 1))
        with self.assertRaises(sqlite3.OperationalError):
            read_summary(self.path.parent / 'missing.sqlite3', NOW.date(), NOW.date())

    def test_stdin_cli_import_is_restart_safe(self):
        command = [sys.executable, '-m', 'portal_stats', 'collect', '--stdin', '--database', str(self.path)]
        # Use today's timestamp for the real CLI clock.
        line = event(moment=datetime.now(timezone.utc)).encode()
        for expected in ('applied', 'duplicate'):
            result = subprocess.run(command, input=line, capture_output=True, check=True, cwd=Path(__file__).resolve().parents[1])
            self.assertEqual(json.loads(result.stdout)[expected], 1)

    def test_docker_collector_reconnects_without_shell_or_duplicate_counts(self):
        script = self.path.parent / 'fixture-docker'
        line = event(moment=datetime.now(timezone.utc)).strip()
        script.write_text('#!' + sys.executable + '\nimport sys\nassert sys.argv[1] == "logs"\nprint(' + repr(line) + ', flush=True)\n')
        script.chmod(0o700)
        target = self.path.parent / 'collector.sqlite3'
        stopped = threading.Event()
        errors = []

        def collect():
            store = Store(target)
            try:
                docker_stream(store, 'owned-nginx-fixture', stopped, command=str(script))
            except BaseException as error:
                errors.append(error)
            finally:
                store.close()

        thread = threading.Thread(target=collect)
        thread.start()
        try:
            deadline = time.monotonic() + 8
            while True:
                try:
                    summary = read_summary(target, datetime.now(LOCAL_TIME).date(), datetime.now(LOCAL_TIME).date())
                    if int(summary['collector'].get('count_duplicate', '0')) >= 1:
                        break
                except sqlite3.OperationalError:
                    pass
                self.assertLess(time.monotonic(), deadline, 'Collector did not replay')
                time.sleep(0.05)
            self.assertEqual(summary['totals']['portal_views'], 1)
            self.assertEqual(errors, [])
        finally:
            stopped.set()
            thread.join(timeout=5)
        self.assertFalse(thread.is_alive())
        self.assertEqual(read_summary(target, datetime.now(LOCAL_TIME).date(), datetime.now(LOCAL_TIME).date())['collector']['collector_state'], 'stopped')
        with self.assertRaises(ValueError):
            docker_stream(self.store, 'name; touch unexpected', stopped, command=str(script))


if __name__ == '__main__':
    unittest.main()
