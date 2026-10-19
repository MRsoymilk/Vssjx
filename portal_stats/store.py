"""Allowlisted Nginx event ingestion with atomic deduplication and daily totals."""
from datetime import date, datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3

LOCAL_TIME = timezone(timedelta(hours=8))
PREFIX = 'VSSJX_PORTAL_V1 '
ROUTES = {'portal', 'game', 'web_click', 'android_click', 'apk'}
METRICS = ('portal_views', 'web_clicks', 'game_views', 'android_clicks',
           'apk_requests', 'apk_full_requests', 'apk_range_requests',
           'apk_cached_requests', 'apk_failed_requests', 'apk_bytes')
MAX_LINE = 4096
TIMESTAMP_PREFIX = re.compile(r'^\d{4}-\d\d-\d\dT[0-9:.]+(?:Z|[+-]\d\d:\d\d) ')


def utc_now():
    return datetime.now(timezone.utc)


def iso(value):
    return value.astimezone(timezone.utc).isoformat(timespec='seconds')


def parse_event(line):
    """Return only schema-validated fields; never persist arbitrary log contents."""
    if isinstance(line, bytes):
        if len(line) > MAX_LINE:
            raise ValueError('EVENT_TOO_LONG')
        line = line.decode('utf-8', errors='strict')
    if len(line.encode('utf-8')) > MAX_LINE:
        raise ValueError('EVENT_TOO_LONG')
    line = TIMESTAMP_PREFIX.sub('', line, count=1)
    if not line.startswith(PREFIX):
        return None

    def unique_pairs(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('DUPLICATE_FIELD')
            result[key] = value
        return result

    event = json.loads(line[len(PREFIX):], object_pairs_hook=unique_pairs)
    if not isinstance(event, dict) or set(event) != {'id', 'at', 'route', 'status', 'bytes'}:
        raise ValueError('INVALID_FIELDS')
    if not isinstance(event['id'], str) or not re.fullmatch(r'[a-f0-9]{32}', event['id']):
        raise ValueError('INVALID_ID')
    if not isinstance(event['at'], str) or not re.fullmatch(r'[0-9]{1,12}\.[0-9]{3}', event['at']):
        raise ValueError('INVALID_TIME')
    if not isinstance(event['route'], str) or event['route'] not in ROUTES:
        raise ValueError('INVALID_ROUTE')
    if type(event['status']) is not int or not 100 <= event['status'] <= 599:
        raise ValueError('INVALID_STATUS')
    if type(event['bytes']) is not int or not 0 <= event['bytes'] <= 10**12:
        raise ValueError('INVALID_BYTES')
    seconds, millis = event['at'].split('.')
    moment = datetime.fromtimestamp(int(seconds), timezone.utc) + timedelta(milliseconds=int(millis))
    event['day'] = moment.astimezone(LOCAL_TIME).date().isoformat()
    event['timestamp'] = iso(moment)
    return event


def increments(event):
    values = dict.fromkeys(METRICS, 0)
    route, status = event['route'], event['status']
    if route in ('portal', 'game') and status in (200, 304):
        values['portal_views' if route == 'portal' else 'game_views'] = 1
    elif route in ('web_click', 'android_click') and status == 302:
        values['web_clicks' if route == 'web_click' else 'android_clicks'] = 1
    elif route == 'apk':
        if status in (200, 206):
            values['apk_requests'] = 1
            values['apk_full_requests' if status == 200 else 'apk_range_requests'] = 1
            values['apk_bytes'] = event['bytes']
        elif status == 304:
            values['apk_cached_requests'] = 1
        elif status >= 400:
            values['apk_failed_requests'] = 1
    return values


class Store:
    def __init__(self, path, now=utc_now):
        self.path = Path(path).resolve()
        self.now = now
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        try:
            descriptor = os.open(self.path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        except FileExistsError:
            pass
        else:
            os.close(descriptor)
        self.db = sqlite3.connect(self.path, timeout=5)
        self.db.execute('PRAGMA journal_mode=WAL')
        self.db.execute('PRAGMA busy_timeout=5000')
        fields = ', '.join(name + ' INTEGER NOT NULL DEFAULT 0' for name in METRICS)
        self.db.executescript(f'''
            CREATE TABLE IF NOT EXISTS daily(day TEXT PRIMARY KEY, {fields});
            CREATE TABLE IF NOT EXISTS seen(id TEXT PRIMARY KEY, day TEXT NOT NULL, digest TEXT NOT NULL);
            CREATE INDEX IF NOT EXISTS seen_day ON seen(day);
            CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        ''')
        self.prune()

    def close(self):
        self.db.close()

    def _meta(self, key, default=''):
        row = self.db.execute('SELECT value FROM meta WHERE key=?', (key,)).fetchone()
        return row[0] if row else default

    def _set(self, key, value):
        self.db.execute('INSERT INTO meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value', (key, str(value)))

    def status(self, state, error=''):
        if state not in ('idle', 'streaming', 'retrying', 'stopped') or error not in ('', 'DOCKER_UNAVAILABLE', 'DOCKER_EXIT', 'INPUT_ERROR'):
            raise ValueError('INVALID_COLLECTOR_STATUS')
        with self.db:
            self._set('collector_state', state)
            self._set('collector_error', error)
            self._set('heartbeat', iso(self.now()))

    def prune(self):
        # Retired dates are never re-imported even after their IDs are removed.
        cutoff = (self.now().astimezone(LOCAL_TIME).date() - timedelta(days=29)).isoformat()
        with self.db:
            cutoff = max(cutoff, self._meta('retired_before', cutoff))
            self.db.execute('DELETE FROM seen WHERE day < ?', (cutoff,))
            self._set('retired_before', cutoff)

    def ingest(self, lines):
        counts = dict.fromkeys(('applied', 'duplicate', 'conflict', 'invalid', 'ignored', 'retired'), 0)
        self.prune()
        with self.db:
            cutoff = self._meta('retired_before')
            for line in lines:
                try:
                    event = parse_event(line)
                except (ValueError, TypeError, OverflowError, OSError, RecursionError):
                    counts['invalid'] += 1
                    continue
                if event is None:
                    counts['ignored'] += 1
                    continue
                if event['day'] < cutoff:
                    counts['retired'] += 1
                    continue
                if event['day'] > self.now().astimezone(LOCAL_TIME).date().isoformat():
                    counts['invalid'] += 1
                    continue
                fingerprint = hashlib.sha256(json.dumps(event, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
                row = self.db.execute('SELECT digest FROM seen WHERE id=?', (event['id'],)).fetchone()
                if row:
                    counts['duplicate' if row[0] == fingerprint else 'conflict'] += 1
                    continue
                self.db.execute('INSERT INTO seen VALUES(?,?,?)', (event['id'], event['day'], fingerprint))
                values = increments(event)
                names = ','.join(METRICS)
                assignments = ','.join(f'{name}={name}+excluded.{name}' for name in METRICS)
                self.db.execute(f'INSERT INTO daily(day,{names}) VALUES({",".join("?" for _ in range(len(METRICS)+1))}) ON CONFLICT(day) DO UPDATE SET {assignments}',
                                (event['day'], *(values[name] for name in METRICS)))
                self._set('last_event', max(event['timestamp'], self._meta('last_event')))
                counts['applied'] += 1
            for key, value in counts.items():
                self._set('count_' + key, int(self._meta('count_' + key, '0')) + value)
            self._set('last_import', iso(self.now()))
        return counts


def read_summary(path, start, end):
    if not isinstance(start, date) or not isinstance(end, date) or end < start or (end-start).days >= 366:
        raise ValueError('INVALID_DATE_RANGE')
    from urllib.parse import quote
    connection = sqlite3.connect('file:' + quote(str(Path(path).resolve())) + '?mode=ro', uri=True, timeout=5)
    connection.row_factory = sqlite3.Row
    try:
        rows = {row['day']: dict(row) for row in connection.execute('SELECT * FROM daily WHERE day BETWEEN ? AND ? ORDER BY day', (start.isoformat(), end.isoformat()))}
        days = []
        current = start
        while current <= end:
            key = current.isoformat()
            days.append(rows.get(key, {'day': key, **dict.fromkeys(METRICS, 0)}))
            current += timedelta(days=1)
        totals = {name: sum(row[name] for row in days) for name in METRICS}
        status = dict(connection.execute('SELECT key,value FROM meta'))
        return {'timezone': 'UTC+08:00', 'start': start.isoformat(), 'end': end.isoformat(),
                'totals': totals, 'days': days, 'collector': status}
    finally:
        connection.close()
