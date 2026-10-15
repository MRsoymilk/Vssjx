"""Owned, ephemeral PostgreSQL for integration checks; never uses a user's DB."""
import os
import secrets
import subprocess
import time
from pathlib import Path
import socket
import tempfile


class PostgresFixture:
    def __init__(self):
        self.name = f'vssjx-auth-test-{os.getpid()}-{secrets.token_hex(4)}'
        self.password = secrets.token_hex(24)
        self.url = None
        self.created = False
        self.portable = None
        self.process = None
        self.log = None

    def __enter__(self):
        if os.environ.get('SSJX_TEST_PG_BIN'):
            return self._start_portable()
        env = dict(os.environ, POSTGRES_PASSWORD=self.password)
        try:
            subprocess.run(['docker', 'run', '--pull=never', '--rm', '-d', '--name', self.name,
                            '--tmpfs', '/var/lib/postgresql/data:rw', '-e', 'POSTGRES_PASSWORD',
                            '-e', 'POSTGRES_USER=vssjx', '-e', 'POSTGRES_DB=vssjx_auth_test',
                            '-p', '127.0.0.1::5432', 'postgres:17-bookworm'],
                           env=env, check=True, capture_output=True, text=True)
            self.created = True
            deadline = time.monotonic() + 30
            while time.monotonic() < deadline:
                ready = subprocess.run(['docker', 'exec', self.name, 'pg_isready', '-h', '127.0.0.1',
                                        '-U', 'vssjx', '-d', 'vssjx_auth_test'], capture_output=True)
                if ready.returncode == 0:
                    break
                time.sleep(0.2)
            else:
                raise RuntimeError('Disposable PostgreSQL did not become ready')
            port = subprocess.check_output(['docker', 'port', self.name, '5432/tcp'], text=True).strip().rsplit(':', 1)[1]
            self.url = f'postgresql://vssjx:{self.password}@127.0.0.1:{port}/vssjx_auth_test'
            return self
        except BaseException:
            self.__exit__(None, None, None)
            raise

    def query(self, statement):
        if self.portable is not None:
            return subprocess.check_output([str(self.bin / 'psql'), '-h', '127.0.0.1', '-p', str(self.port),
                '-U', 'vssjx', '-d', 'vssjx_auth_test', '-At', '-v', 'ON_ERROR_STOP=1'],
                env=dict(os.environ, PGPASSWORD=self.password), input=statement, text=True, encoding='utf-8').strip()
        return subprocess.check_output(['docker', 'exec', '-i', self.name, 'psql', '-U', 'vssjx',
                                        '-d', 'vssjx_auth_test', '-At', '-v', 'ON_ERROR_STOP=1'],
                                       input=statement, text=True).strip()

    def __exit__(self, *_args):
        if self.portable is not None:
            try:
                if self.process is not None:
                    subprocess.run([str(self.bin / 'pg_ctl'), '-D', str(self.data), '-m', 'fast', '-w', 'stop'], capture_output=True, timeout=15)
                    if self.process.poll() is None: self.process.terminate()
                    self.process.wait(timeout=10)
            finally:
                if self.log is not None: self.log.close()
                # Only remove our owned temporary cluster, underneath its verified root.
                assert Path(self.portable.name).resolve().is_relative_to(self.test_root)
                self.portable.cleanup()
                self.portable = None
            return
        if not self.created:
            return
        subprocess.run(['docker', 'unpause', self.name], capture_output=True)
        subprocess.run(['docker', 'rm', '-f', self.name], capture_output=True)
        self.created = False

    def _start_portable(self):
        self.bin = Path(os.environ['SSJX_TEST_PG_BIN']).resolve()
        self.test_root = Path(os.environ.get('SSJX_TEST_PG_WORK_DIR', tempfile.gettempdir())).resolve()
        self.portable = tempfile.TemporaryDirectory(prefix='vssjx-pg-', dir=self.test_root)
        scratch = Path(self.portable.name)
        self.data = scratch / 'data'
        password_file = scratch / 'password'
        password_file.write_text(self.password, encoding='utf-8')
        startup = None
        if os.name == 'nt':
            startup = subprocess.STARTUPINFO()
            startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            startup.wShowWindow = subprocess.SW_HIDE
        env = dict(os.environ, PGPASSWORD=self.password)
        try:
            subprocess.run([str(self.bin / 'initdb'), '-D', str(self.data), '-U', 'vssjx', '--pwfile', str(password_file),
                '--auth=scram-sha-256', '--encoding=UTF8', '--locale=C'], env=env, check=True, capture_output=True, startupinfo=startup)
            password_file.unlink()
            with socket.socket() as reserved:
                reserved.bind(('127.0.0.1', 0)); self.port = reserved.getsockname()[1]
            self.log = (scratch / 'postgres.log').open('wb')
            self.process = subprocess.Popen([str(self.bin / 'postgres'), '-D', str(self.data), '-h', '127.0.0.1', '-p', str(self.port), '-c', 'fsync=off'],
                env=env, stdout=self.log, stderr=subprocess.STDOUT, startupinfo=startup)
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                ready = subprocess.run([str(self.bin / 'pg_isready'), '-h', '127.0.0.1', '-p', str(self.port), '-U', 'vssjx'], capture_output=True, startupinfo=startup)
                if ready.returncode == 0: break
                time.sleep(0.1)
            else: raise RuntimeError('Owned portable PostgreSQL did not become ready')
            subprocess.run([str(self.bin / 'createdb'), '-h', '127.0.0.1', '-p', str(self.port), '-U', 'vssjx', 'vssjx_auth_test'],
                env=env, check=True, capture_output=True, startupinfo=startup)
            self.url = f'postgresql://vssjx:{self.password}@127.0.0.1:{self.port}/vssjx_auth_test'
            return self
        except BaseException:
            self.__exit__(None, None, None)
            raise
