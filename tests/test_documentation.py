"""Check the public documentation's local links without network access."""
from pathlib import Path
import re
import unittest
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
DOCUMENTS = [
    ROOT / 'README.md',
    ROOT / 'CONTRIBUTING.md',
    ROOT / 'server/README.md',
    *sorted((ROOT / 'docs').glob('*.md')),
    *sorted((ROOT / 'design').glob('*.md')),
    *sorted((ROOT / 'deploy').glob('*.md')),
]


def links(text):
    # Ignore code examples, whose sample URLs are not navigation links.
    text = re.sub(r'^```[^\n]*\n.*?^```[^\n]*$', '', text,
                  flags=re.MULTILINE | re.DOTALL)
    return (re.findall(r'\]\(([^\s)]+)(?:\s+[^)]*)?\)', text)
            + re.findall(r'(?:src|href)="([^"]+)"', text))


class DocumentationTests(unittest.TestCase):
    def test_local_links_and_images_exist(self):
        for source in DOCUMENTS:
            for link in links(source.read_text('utf-8')):
                url = urlsplit(link)
                if url.scheme or url.netloc or not url.path:
                    continue
                with self.subTest(source=source.relative_to(ROOT), link=link):
                    target = source.parent / unquote(url.path)
                    self.assertTrue(target.exists(), str(target))

    def test_fenced_code_blocks_are_closed(self):
        for source in DOCUMENTS:
            with self.subTest(source=source.relative_to(ROOT)):
                fences = re.findall(r'^```', source.read_text('utf-8'), re.MULTILINE)
                self.assertEqual(len(fences) % 2, 0)

    def test_homepage_reuses_existing_icon(self):
        text = (ROOT / 'README.md').read_text('utf-8')
        self.assertIn('src="client/assets/ui/app_icon.png"', text)
        self.assertIn('client/project.godot', text)
        self.assertIn('godot --path client', text)


if __name__ == '__main__':
    unittest.main()
