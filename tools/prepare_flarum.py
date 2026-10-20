"""Prepare a dedicated forum image context from hash-pinned official downloads."""
import argparse
import hashlib
from pathlib import Path
import shutil
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
DOWNLOADS = {
    'flarum.tar.gz': (
        'https://github.com/flarum/installation-packages/raw/main/packages/v2.x/v2.0.2/flarum-v2.0.2-php8.3.tar.gz',
        '9f941e27bd8cafc7f81440574832a13eeef47486947a46cf4e5b307126a0d61a'),
    'composer.phar': (
        'https://getcomposer.org/download/2.10.3/composer.phar',
        '7a2d379d5b8ffdaa028580ef26494c36d2feef4b178d3dd1473a4dbc5e17c8d6'),
}


def prepare(output):
    output = Path(output).resolve()
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise ValueError('Use an empty/new forum context; existing files are not overwritten')
    output.mkdir(parents=True, exist_ok=True)
    for name, (url, expected) in DOWNLOADS.items():
        digest = hashlib.sha256()
        target = output / name
        with urlopen(url, timeout=90) as response, target.open('xb') as stream:
            while chunk := response.read(1024 * 1024):
                digest.update(chunk)
                stream.write(chunk)
        if digest.hexdigest() != expected:
            raise ValueError('Forum dependency checksum mismatch: ' + name)
    (output / 'composer.sha384').write_text(hashlib.sha384((output / 'composer.phar').read_bytes()).hexdigest())
    for name in ('Dockerfile', 'site.php', 'apache.conf', 'limits.conf', 'php.ini', 'initialize.sh'):
        shutil.copyfile(ROOT / 'deploy/flarum' / name, output / name)
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    print(prepare(parser.parse_args().output))
