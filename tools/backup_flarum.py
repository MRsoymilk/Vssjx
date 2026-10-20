"""Back up only the independent forum using SQLite's online snapshot API."""
import argparse
from datetime import datetime, timezone
import fcntl
import os
from pathlib import Path
import subprocess


def backup(directory, container='vssjx-forum-forum-1'):
    directory = Path(directory).resolve()
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (directory / '.backup.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
        output = directory / ('forum-' + stamp + '.tar.gz')
        temporary = output.with_suffix('.gz.part')
        snapshot = '.backup-' + stamp + '.sqlite'
        script = ('$source=new SQLite3("/data/forum.sqlite",SQLITE3_OPEN_READONLY);'
                  '$source->busyTimeout(5000);'
                  f'$target=new SQLite3("/data/{snapshot}");'
                  'if(!$source->backup($target)){exit(1);}'
                  '$target->close();$source->close();')
        subprocess.run(['docker', 'exec', '-u', 'www-data', container, 'php', '-r', script], check=True, timeout=60)
        try:
            descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, 'wb') as stream:
                subprocess.run(['docker', 'exec', '-u', 'www-data', container, 'tar', '-czf', '-', '-C', '/data',
                                'config.php', 'assets', snapshot], stdout=stream, check=True, timeout=120)
                stream.flush()
                os.fsync(stream.fileno())
            temporary.rename(output)
        finally:
            subprocess.run(['docker', 'exec', '-u', 'www-data', container, 'rm', '-f', '/data/' + snapshot], check=True, timeout=10)
        return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--container', default='vssjx-forum-forum-1')
    args = parser.parse_args()
    print(backup(args.directory, args.container))
