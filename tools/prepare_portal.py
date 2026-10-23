"""Prepare a script-free navigation page; never rebuild or edit a game export."""
import argparse
from io import BytesIO
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def prepare(output):
    output = Path(output).resolve()
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise ValueError('Use an empty or new navigation directory; existing files are never overwritten')
    sources = ROOT / 'deploy/portal'
    files = {name: (sources / name).read_bytes() for name in ('index.html', 'portal.css')}
    with Image.open(ROOT / 'client/assets/ui/app_icon.png') as original:
        icon = original.convert('RGB')
        icon.thumbnail((256, 256), Image.Resampling.LANCZOS)
        stream = BytesIO()
        icon.save(stream, format='WEBP', quality=85, method=6)
        files['app-icon.webp'] = stream.getvalue()
    output.mkdir(parents=True, exist_ok=True)
    for name, content in files.items():
        with (output / name).open('xb') as target:
            target.write(content)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    print('Navigation files: ' + str(prepare(args.output)))


if __name__ == '__main__':
    main()
