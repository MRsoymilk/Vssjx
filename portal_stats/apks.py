"""Managed APK files only. Never overwrites the legacy game export/download."""
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import hashlib
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import sqlite3
import struct
import threading
import time
import unicodedata
from uuid import uuid4
import zipfile
import zlib

APK_NAME = 'vssjx-arm64.apk'


class ApkError(Exception):
    def __init__(self, code, status=400):
        super().__init__(code)
        self.code, self.status = code, status


def identifier(value):
    if not isinstance(value, str) or not re.fullmatch('[a-f0-9]{32}', value):
        raise ApkError('INVALID_APK_ID')
    return value


def validate_name(name):
    if (not isinstance(name, str) or not 1 <= len(name) <= 120
            or len(name.encode('utf-8')) > 240 or not name.lower().endswith('.apk')
            or any(unicodedata.category(char).startswith('C') or char in '/\\' for char in name)
            or name.startswith('.')):
        raise ApkError('INVALID_APK_NAME')
    return name


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(65536), b''):
            value.update(chunk)
    return value.hexdigest()


def sync_directory(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def validate_apk(path):
    # Structural checks, not signature verification or an Android safety verdict.
    try:
        # Reject huge/ZIP64 central directories before ZipFile allocates members.
        with path.open('rb') as source:
            size = path.stat().st_size
            source.seek(max(0, size - 65557))
            tail = source.read(65557)
        offset = tail.rfind(b'PK\x05\x06')
        if offset < 0 or len(tail) - offset < 22:
            raise ApkError('INVALID_APK_STRUCTURE')
        _, disk, directory_disk, disk_count, count, directory_size, directory_offset, comment = struct.unpack('<4s4H2LH', tail[offset:offset+22])
        if (disk or directory_disk or disk_count != count or not 1 <= count <= 10000
                or directory_size > 16 * 1024**2 or directory_offset + directory_size > size
                or offset + 22 + comment != len(tail)):
            raise ApkError('INVALID_APK_STRUCTURE')
        with zipfile.ZipFile(path) as archive:
            files = archive.infolist()
            if not 1 <= len(files) <= 10000:
                raise ApkError('INVALID_APK_STRUCTURE')
            names = set()
            total = 0
            for member in files:
                name = PurePosixPath(member.filename)
                if (member.filename in names or name.is_absolute() or '..' in name.parts
                        or '\\' in member.filename or member.flag_bits & 1
                        or member.file_size > 512 * 1024 * 1024):
                    raise ApkError('INVALID_APK_STRUCTURE')
                names.add(member.filename)
                total += member.file_size
            if total > 2 * 1024**3 or 'AndroidManifest.xml' not in names:
                raise ApkError('INVALID_APK_STRUCTURE')
            manifest = archive.getinfo('AndroidManifest.xml')
            if not 1 <= manifest.file_size <= 2 * 1024 * 1024:
                raise ApkError('INVALID_APK_STRUCTURE')
            # Read only the bounded manifest; never extract or execute packages.
            if not archive.read(manifest):
                raise ApkError('INVALID_APK_STRUCTURE')
    except (zipfile.BadZipFile, RuntimeError, NotImplementedError, EOFError, zlib.error):
        raise ApkError('INVALID_APK_STRUCTURE') from None


class ApkManager:
    def __init__(self, directory, public=None, max_upload=256 * 1024**2, quota=1024 * 1024**2):
        if not 1 <= max_upload <= 1024**3 or quota < max_upload:
            raise ValueError('INVALID_APK_LIMITS')
        self.root = Path(directory).resolve()
        self.public = Path(public).resolve() if public else None
        if self.public and (self.public == self.root or self.public in self.root.parents or self.root in self.public.parents):
            raise ValueError('APK_PUBLIC_AND_PRIVATE_MUST_BE_SEPARATE')
        self.max_upload, self.quota = max_upload, quota
        self.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.packages = self.root / 'packages'
        self.packages.mkdir(mode=0o700, exist_ok=True)
        self.database = self.root / 'registry.sqlite3'
        self.lock = threading.Lock()
        with self._database() as db:
            db.execute('CREATE TABLE IF NOT EXISTS apks(id TEXT PRIMARY KEY,name TEXT NOT NULL,bytes INTEGER NOT NULL,sha256 TEXT UNIQUE NOT NULL,uploaded TEXT NOT NULL,state TEXT NOT NULL DEFAULT "ready")')
        self.database.chmod(0o600)

    @contextmanager
    def _database(self):
        connection = sqlite3.connect(self.database, timeout=5)
        connection.row_factory = sqlite3.Row
        try:
            with connection:
                yield connection
        finally:
            connection.close()

    @contextmanager
    def _exclusive(self):
        if not self.lock.acquire(blocking=False):
            raise ApkError('APK_BUSY', 409)
        try:
            with (self.root / '.manager.lock').open('ab') as guard:
                try:
                    fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    raise ApkError('APK_BUSY', 409) from None
                try:
                    yield
                finally:
                    fcntl.flock(guard, fcntl.LOCK_UN)
        finally:
            self.lock.release()

    def _current(self, verify=False):
        if not self.public:
            return None
        pointer = self.public / 'current'
        if not pointer.exists() and not pointer.is_symlink():
            return None
        if not pointer.is_symlink():
            raise ApkError('UNMANAGED_CURRENT', 409)
        target = os.readlink(pointer)
        if not re.fullmatch(r'releases/[a-f0-9]{32}', target):
            raise ApkError('UNMANAGED_CURRENT', 409)
        key = target.split('/')[1]
        with self._database() as database:
            row = database.execute('SELECT * FROM apks WHERE id=?', (key,)).fetchone()
        release = self.public / 'releases' / key
        package = release / 'downloads' / APK_NAME
        if (not row or row['state'] != 'ready' or release.is_symlink()
                or (release / 'downloads').is_symlink() or package.is_symlink() or not package.is_file()):
            raise ApkError('UNMANAGED_CURRENT', 409)
        if verify:
            self._check_release(dict(row))
        return key

    def listing(self):
        with self._database() as db:
            rows = [dict(row) for row in db.execute('SELECT * FROM apks ORDER BY uploaded DESC,id')]
        try:
            current, warning = self._current(), ''
        except ApkError as error:
            current, warning = None, error.code
        for row in rows:
            row['current'] = row['id'] == current
        return {'files': rows, 'current': current, 'warning': warning,
                'publish_enabled': self.public is not None, 'max_upload': self.max_upload, 'quota': self.quota,
                'used_bytes': sum(path.stat().st_size for path in self.packages.iterdir() if path.is_file())}

    def upload(self, stream, length, name):
        validate_name(name)
        if type(length) is not int or not 0 < length <= self.max_upload:
            raise ApkError('APK_TOO_LARGE', 413)
        with self._exclusive():
            used = sum(path.stat().st_size for path in self.packages.iterdir() if path.is_file())
            if used + length > self.quota:
                raise ApkError('APK_QUOTA_EXCEEDED', 413)
            key = uuid4().hex
            temporary = self.packages / ('.upload-' + key + '.part')
            target = self.packages / (key + '.apk')
            remaining, checksum = length, hashlib.sha256()
            deadline = time.monotonic() + 600
            try:
                with temporary.open('xb') as output:
                    os.chmod(temporary, 0o600)
                    while remaining:
                        if time.monotonic() > deadline:
                            raise ApkError('APK_UPLOAD_TIMEOUT', 408)
                        chunk = stream.read(min(65536, remaining))
                        if not chunk:
                            raise ApkError('APK_UPLOAD_INCOMPLETE')
                        output.write(chunk)
                        checksum.update(chunk)
                        remaining -= len(chunk)
                    output.flush()
                    os.fsync(output.fileno())
                validate_apk(temporary)
                with self._database() as db:
                    existing = db.execute('SELECT * FROM apks WHERE sha256=?', (checksum.hexdigest(),)).fetchone()
                    if existing:
                        return {'file': dict(existing), 'duplicate': True}
                    temporary.rename(target)
                    sync_directory(self.packages)
                    try:
                        db.execute('INSERT INTO apks(id,name,bytes,sha256,uploaded) VALUES(?,?,?,?,?)',
                                   (key, name, length, checksum.hexdigest(), datetime.now(timezone.utc).isoformat()))
                        db.commit()
                    except BaseException:
                        target.unlink(missing_ok=True)
                        raise
                    return {'file': dict(db.execute('SELECT * FROM apks WHERE id=?', (key,)).fetchone()), 'duplicate': False}
            finally:
                temporary.unlink(missing_ok=True)

    def _record(self, key):
        identifier(key)
        with self._database() as db:
            row = db.execute('SELECT * FROM apks WHERE id=?', (key,)).fetchone()
        if not row:
            raise ApkError('APK_NOT_FOUND', 404)
        return dict(row)

    def _check_package(self, row):
        path = self.packages / (row['id'] + '.apk')
        if path.is_symlink() or not path.is_file() or path.stat().st_size != row['bytes'] or digest(path) != row['sha256']:
            raise ApkError('APK_FILE_CHANGED', 409)
        return path

    def publish(self, key):
        if not self.public:
            raise ApkError('APK_PUBLISH_DISABLED', 409)
        with self._exclusive():
            row = self._record(key)
            if row['state'] != 'ready':
                raise ApkError('APK_NOT_READY', 409)
            source = self._check_package(row)
            self._current(verify=True)  # Refuse unmanaged files/links before changing anything.
            new_public = not self.public.exists()
            self.public.mkdir(mode=0o755, parents=True, exist_ok=True)
            if new_public:
                self.public.chmod(0o755)
            # Never overwrite a legacy download directory accidentally selected by an operator.
            if (self.public / 'downloads').exists() or (self.public / APK_NAME).exists():
                raise ApkError('UNMANAGED_CURRENT', 409)
            releases = self.public / 'releases'
            if releases.is_symlink():
                raise ApkError('UNMANAGED_RELEASE', 409)
            releases.mkdir(mode=0o755, exist_ok=True)
            releases.chmod(0o755)
            release = releases / key
            if release.exists():
                self._check_release(row)
            else:
                stage = releases / ('.stage-' + uuid4().hex)
                stage.mkdir(mode=0o755)
                stage.chmod(0o755)
                download = stage / 'downloads'
                download.mkdir(mode=0o755)
                download.chmod(0o755)
                try:
                    shutil.copyfile(source, download / APK_NAME)
                    (download / APK_NAME).chmod(0o644)
                    with (download / APK_NAME).open('rb') as package:
                        os.fsync(package.fileno())
                    (download / 'SHA256SUMS.txt').write_text(row['sha256'] + '  ' + APK_NAME + '\n')
                    (download / 'SHA256SUMS.txt').chmod(0o644)
                    with (download / 'SHA256SUMS.txt').open('rb') as checksum_file:
                        os.fsync(checksum_file.fileno())
                    sync_directory(download)
                    sync_directory(stage)
                    stage.rename(release)
                    sync_directory(releases)
                except BaseException:
                    if stage.exists():
                        for filename in (APK_NAME, 'SHA256SUMS.txt'):
                            (download / filename).unlink(missing_ok=True)
                        download.rmdir()
                        stage.rmdir()
                    raise
            pointer = self.public / ('.current-' + uuid4().hex)
            try:
                pointer.symlink_to('releases/' + key)
                os.replace(pointer, self.public / 'current')
                sync_directory(self.public)
            finally:
                pointer.unlink(missing_ok=True)
            return {'current': key, 'sha256': row['sha256']}

    def _check_release(self, row, partial=False):
        release = self.public / 'releases' / row['id']
        download = release / 'downloads'
        if release.is_symlink() or download.is_symlink():
            raise ApkError('UNMANAGED_RELEASE', 409)
        children = {p.name for p in release.iterdir()}
        if children != {'downloads'} and not (partial and not children):
            raise ApkError('UNMANAGED_RELEASE', 409)
        if download.exists():
            names = {p.name for p in download.iterdir()}
            expected = {APK_NAME, 'SHA256SUMS.txt'}
            if names != expected and not (partial and names <= expected):
                raise ApkError('UNMANAGED_RELEASE', 409)
            for name in names:
                if (download / name).is_symlink() or not (download / name).is_file():
                    raise ApkError('UNMANAGED_RELEASE', 409)
            if APK_NAME in names and digest(download / APK_NAME) != row['sha256']:
                raise ApkError('UNMANAGED_RELEASE', 409)
            if 'SHA256SUMS.txt' in names and (download / 'SHA256SUMS.txt').read_text() != row['sha256'] + '  ' + APK_NAME + '\n':
                raise ApkError('UNMANAGED_RELEASE', 409)
        return release

    def delete(self, key):
        identifier(key)
        with self._exclusive():
            if self._current(verify=True) == key:
                raise ApkError('APK_IS_CURRENT', 409)
            try:
                row = self._record(key)
            except ApkError as error:
                if error.code == 'APK_NOT_FOUND':
                    return {'deleted': key}
                raise
            source = self.packages / (key + '.apk')
            if source.exists() or source.is_symlink():
                self._check_package(row)
            release = None
            if self.public and ((self.public / 'releases' / key).exists() or (self.public / 'releases' / key).is_symlink()):
                release = self._check_release(row, partial=row['state'] == 'deleting')
            with self._database() as db:
                db.execute('UPDATE apks SET state="deleting" WHERE id=?', (key,))
            if release:
                (release / 'downloads' / APK_NAME).unlink(missing_ok=True)
                (release / 'downloads/SHA256SUMS.txt').unlink(missing_ok=True)
                if (release / 'downloads').exists():
                    (release / 'downloads').rmdir()
                release.rmdir()
                sync_directory(release.parent)
            source.unlink(missing_ok=True)
            sync_directory(self.packages)
            with self._database() as db:
                db.execute('DELETE FROM apks WHERE id=?', (key,))
            return {'deleted': key}
