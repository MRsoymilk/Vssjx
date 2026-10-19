"""Static navigation checks: no browser storage, credentials or game boot."""
from html.parser import HTMLParser
import importlib.util
from io import BytesIO
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('prepare_portal', ROOT / 'tools/prepare_portal.py')
PORTAL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PORTAL)


class Page(HTMLParser):
    def __init__(self, text):
        super().__init__()
        self.elements = []
        self.feed(text)

    def handle_starttag(self, tag, attrs):
        self.elements.append((tag, dict(attrs)))


class PortalPageTests(unittest.TestCase):
    def setUp(self):
        self.html = (ROOT / 'deploy/portal/index.html').read_text('utf-8')
        self.page = Page(self.html)

    def test_only_explicit_game_and_existing_download_links(self):
        links = [attrs['href'] for tag, attrs in self.page.elements if tag == 'a']
        self.assertIn('/webgame/', links)
        self.assertIn('/downloads/vssjx-arm64.apk', links)
        self.assertIn('#game', links)
        self.assertNotIn('#download', links)
        self.assertNotIn('/flarum/', links)
        self.assertTrue(any(tag == 'button' and 'disabled' in attrs
                            and attrs.get('aria-describedby') == 'forum-status'
                            for tag, attrs in self.page.elements))

    def test_platforms_share_one_game_entry_without_web_first_navigation(self):
        game = self.html.split('<article class="destination-card game-card"', 1)[1].split('</article>', 1)[0]
        self.assertIn('id="game"', game)
        self.assertIn('href="/webgame/"', game)
        self.assertIn('href="/downloads/vssjx-arm64.apk"', game)
        hero = self.html.split('<section class="hero"', 1)[1].split('</section>', 1)[0]
        self.assertIn('href="#game"', hero)
        self.assertNotIn('href="/webgame/"', hero)
        self.assertNotIn('download-panel', self.html)

    def test_no_script_form_engine_or_automatic_game_fetch(self):
        self.assertFalse({'script', 'iframe', 'form', 'object', 'embed'} &
                         {tag for tag, _ in self.page.elements})
        for tag, attrs in self.page.elements:
            self.assertFalse(any(name.startswith('on') for name in attrs))
            if tag in ('img', 'link'):
                value = attrs.get('src', attrs.get('href', ''))
                self.assertTrue(value.startswith('/navigation/'), value)
                self.assertNotIn(attrs.get('rel'), ('preload', 'prefetch', 'prerender'))
        for forbidden in ('localStorage', 'indexedDB', '.wasm', '.pck', 'fetch('):
            self.assertNotIn(forbidden, self.html)

    def test_internal_anchors_and_external_links_are_accessible(self):
        ids = [attrs['id'] for _, attrs in self.page.elements if 'id' in attrs]
        self.assertEqual(len(ids), len(set(ids)))
        for tag, attrs in self.page.elements:
            if tag != 'a':
                continue
            href = attrs['href']
            if href.startswith('#'):
                self.assertIn(href[1:], ids)
            if attrs.get('target') == '_blank':
                self.assertTrue({'noopener', 'noreferrer'} <= set(attrs.get('rel', '').split()))
        self.assertIn(('html', {'lang': 'zh-CN'}), self.page.elements)
        self.assertEqual(sum(tag == 'h1' for tag, _ in self.page.elements), 1)

    def test_prepare_is_small_reproducible_and_never_touches_game_export(self):
        original = (ROOT / 'client/assets/ui/app_icon.png').read_bytes()
        with TemporaryDirectory() as temporary:
            a = PORTAL.prepare(Path(temporary) / 'a')
            b = PORTAL.prepare(Path(temporary) / 'b')
            self.assertEqual({p.name for p in a.iterdir()}, {'index.html', 'portal.css', 'app-icon.webp'})
            for path in a.iterdir():
                self.assertEqual(path.read_bytes(), (b / path.name).read_bytes())
            image = (a / 'app-icon.webp').read_bytes()
            self.assertLess(len(image), 80000)
            self.assertEqual(Image.open(BytesIO(image)).size, (256, 256))
            self.assertLess(sum(p.stat().st_size for p in a.iterdir()), 120000)
        self.assertEqual(original, (ROOT / 'client/assets/ui/app_icon.png').read_bytes())

    def test_prepare_refuses_to_overwrite_any_existing_output(self):
        with TemporaryDirectory() as temporary:
            folder = PORTAL.prepare(Path(temporary) / 'portal')
            before = {p.name: p.read_bytes() for p in folder.iterdir()}
            with self.assertRaises(ValueError):
                PORTAL.prepare(folder)
            self.assertEqual(before, {p.name: p.read_bytes() for p in folder.iterdir()})


if __name__ == '__main__':
    unittest.main()
