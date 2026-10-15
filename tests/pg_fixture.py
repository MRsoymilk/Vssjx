"""Owned, ephemeral PostgreSQL for integration checks; never uses a user's DB."""
import os
import secrets
import subprocess
import time


class PostgresFixture:
    def __init__(self):
        self.name = f'vssjx-auth-test-{os.getpid()}-{secrets.token_hex(4)}'
        self.password = secrets.token_hex(24)
        self.url = None
        self.created = False

    def __enter__(self):
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
        return subprocess.check_output(['docker', 'exec', '-i', self.name, 'psql', '-U', 'vssjx',
                                        '-d', 'vssjx_auth_test', '-At', '-v', 'ON_ERROR_STOP=1'],
                                       input=statement, text=True).strip()

    def __exit__(self, *_args):
        if not self.created:
            return
        subprocess.run(['docker', 'unpause', self.name], capture_output=True)
        subprocess.run(['docker', 'rm', '-f', self.name], capture_output=True)
        self.created = False
