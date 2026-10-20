"""Prepare a script-free navigation page; never rebuild or edit a game export."""
import argparse
from io import BytesIO
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def enable_forum(text):
    # Apply equally to the current template or an inspected deployed HTML file;
    # no game/APK hrefs, scripts, styles or assets are otherwise changed.
    replacements = {
        '<a href="#community">论坛<span class="nav-note">筹备中</span></a>': '<a href="/flarum/">论坛</a>',
        '<button class="button button-secondary" type="button" disabled aria-describedby="forum-status">论坛筹备中</button>': '<a class="button button-secondary" href="/flarum/">进入论坛</a>',
        '剑侠茶馆 <span class="status-label">筹备中</span>': '剑侠茶馆',
        '论坛将在完成部署与验证后开放。': '前往论坛，与同道一起交流。',
        '<p class="muted-link" id="forum-status">尚未开放，不影响游戏游玩</p>': '<a class="button button-secondary" href="/flarum/">前往剑侠茶馆 <span aria-hidden="true">↗</span></a>',
    }
    for before, after in replacements.items():
        if text.count(before) != 1:
            raise ValueError('Unexpected portal forum marker; inspect before enabling')
        text = text.replace(before, after, 1)
    return text


def prepare(output, forum=False):
    output = Path(output).resolve()
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise ValueError('Use an empty or new navigation directory; existing files are never overwritten')
    sources = ROOT / 'deploy/portal'
    files = {name: (sources / name).read_bytes() for name in ('index.html', 'portal.css')}
    if forum:
        files['index.html'] = enable_forum(files['index.html'].decode('utf-8')).encode('utf-8')
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
    parser.add_argument('--forum', action='store_true', help='Enable forum links only after the service is verified')
    args = parser.parse_args()
    print('Navigation files: ' + str(prepare(args.output, forum=args.forum)))


if __name__ == '__main__':
    main()
