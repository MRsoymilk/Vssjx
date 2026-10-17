import gzip
import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from export_web import prepare_static_assets


class WebStaticAssetsTests(unittest.TestCase):
    def create(self, folder, suffix=b''):
        folder.mkdir()
        for name in ['index.js', 'index.wasm', 'index.pck']:
            (folder / name).write_bytes((name.encode() * 1000) + suffix)
        config = {'executable': 'index', 'fileSizes': {'index.wasm': 10000, 'index.pck': 9000}}
        (folder / 'index.html').write_text('<script src="index.js"></script>\nconst config = ' + json.dumps(config) + ';\n')

    def test_actual_versioned_files_decode_exactly_and_html_pins_the_whole_bundle(self):
        with TemporaryDirectory() as temp:
            folder = Path(temp) / 'public'
            self.create(folder)
            assets = prepare_static_assets(folder)
            html = (folder / 'index.html').read_text()
            self.assertIn(assets['prefix'] + 'index.js', html)
            config = json.loads(html.split('const config = ')[1].split(';')[0])
            self.assertEqual(config['executable'], assets['prefix'] + 'index')
            self.assertEqual(config['mainPack'], assets['prefix'] + 'index.pck')
            self.assertEqual(set(config['fileSizes']), {assets['prefix'] + 'index.wasm', assets['prefix'] + 'index.pck'})
            for name in ['index.js', 'index.wasm', 'index.pck']:
                original = (folder / name).read_bytes()
                compressed = (folder / (name + '.gz')).read_bytes()
                self.assertEqual(gzip.decompress(compressed), original)
                self.assertEqual((folder / assets['prefix'] / name).read_bytes(), original)
                self.assertEqual((folder / assets['prefix'] / (name + '.gz')).read_bytes(), compressed)

    def test_resource_changes_get_new_urls_and_identical_builds_keep_the_same_urls(self):
        with TemporaryDirectory() as temp:
            versions = []
            for index, suffix in enumerate([b'', b'', b'changed']):
                folder = Path(temp) / str(index)
                self.create(folder, suffix)
                versions.append(prepare_static_assets(folder)['version'])
            self.assertEqual(versions[0], versions[1])
            self.assertNotEqual(versions[0], versions[2])
