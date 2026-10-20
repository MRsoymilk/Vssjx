"""Create a forum-enabled candidate from the inspected live Nginx config."""
import argparse
from pathlib import Path
import re
import textwrap

ROOT = Path(__file__).resolve().parents[1]


def configure(source, output):
    source, output = Path(source), Path(output)
    text = source.read_text('utf-8')
    pattern = r'(?m)^([ \t]*)location = /flarum \{ return 404; \}\r?\n[ \t]*location \^~ /flarum/ \{ return 404; \}'
    matches = list(re.finditer(pattern, text))
    if len(matches) != 1:
        raise ValueError('Expected exactly one inspected reserved forum block; merge manually')
    match = matches[0]
    snippet = (ROOT / 'deploy/flarum/public.locations.conf').read_text('utf-8').rstrip()
    candidate = text[:match.start()] + textwrap.indent(snippet, match[1]) + text[match.end():]
    with output.open('x', encoding='utf-8', newline='\n') as target:
        target.write(candidate)
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    print(configure(args.source, args.output))
