"""Lossless split, deterministic regeneration and runtime/archive boundaries."""
import hashlib
import base64
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zlib

from test_actor_import import ROOT, runtime_actors, original_animations


def canonical(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


class ActorCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expected = json.loads((ROOT.parent / 'tests/fixtures/actor_catalog_v1.json').read_text())
        cls.actors = runtime_actors()
        cls.source = original_animations()
        spec = importlib.util.spec_from_file_location('actor_importer', ROOT.parent / 'tools/import_assets.py')
        cls.importer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.importer)

    def test_every_runtime_record_is_semantically_identical(self):
        self.assertEqual(len(self.actors), self.expected['runtime_records'])
        self.assertEqual(canonical(self.actors), self.expected['runtime_canonical_sha256'])

    def test_benchmark_fixture_is_the_exact_legacy_catalog_size_and_content(self):
        path = ROOT.parent / 'tests/fixtures/actors_v1.json.zlib.b64'
        raw = zlib.decompress(base64.b64decode(path.read_text()))
        self.assertEqual(len(raw), self.expected['legacy_runtime_bytes'])
        self.assertEqual(canonical(json.loads(raw)), self.expected['runtime_canonical_sha256'])

    def test_every_original_layer_sequence_and_opaque_tail_is_preserved(self):
        self.assertEqual(len(self.source), self.expected['original_records'])
        self.assertEqual(canonical(self.source), self.expected['original_canonical_sha256'])
        parsed, errors = self.importer.read_animations()
        self.assertEqual(errors, [])
        self.assertEqual(canonical(parsed), self.expected['original_canonical_sha256'])

    def test_atlas_bytes_are_unchanged(self):
        digest = hashlib.sha256()
        for texture in sorted({info['texture'] for info in self.actors.values()}):
            digest.update(texture.encode() + b'\0' + (ROOT / texture.removeprefix('res://')).read_bytes())
        self.assertEqual(digest.hexdigest(), self.expected['texture_set_sha256'])

    def test_runtime_index_is_small_and_references_one_shard_per_actor(self):
        path = ROOT / 'assets/data/actors.json'
        index = json.loads(path.read_text())
        self.assertEqual(index['format_version'], 2)
        self.assertLess(path.stat().st_size, 4096)
        indexed = set()
        for key, resource in index['actors'].items():
            self.assertEqual(resource, 'res://assets/data/actors/' + key + '.json')
            shard = ROOT / resource.removeprefix('res://')
            self.assertTrue(shard.is_file())
            self.assertLessEqual(len(shard.read_text().splitlines()), 250)
            indexed.add(shard)
        self.assertEqual(indexed, set((ROOT / 'assets/data/actors').rglob('*.json')))

    def test_analysis_data_is_outside_the_godot_project(self):
        self.assertFalse((ROOT / 'assets/data/original_animations.json').exists())
        self.assertFalse((ROOT / 'assets/data/animations').exists())
        self.assertTrue((ROOT.parent / 'analysis/animations/index.json').is_file())

    def test_metadata_rebuild_matches_existing_art_without_rewriting_textures(self):
        parsed, errors = self.importer.read_animations()
        self.assertEqual(errors, [])
        rebuilt = self.importer.build_actor_catalog(parsed, write_textures=False)
        self.assertEqual(canonical(rebuilt), self.expected['runtime_canonical_sha256'])

    def test_export_is_deterministic_and_does_not_delete_unrelated_files(self):
        with tempfile.TemporaryDirectory(prefix='vssjx-actor-data-', dir='/tmp/opencode') as folder:
            folder = Path(folder)
            data, source = folder / 'data', folder / 'analysis'
            self.importer.write_metadata(self.actors, self.source, data, source)
            before = {str(path.relative_to(folder)): path.read_bytes() for path in folder.rglob('*.json')}
            sentinel = data / 'hand-authored.txt'
            sentinel.write_text('preserve')
            self.importer.write_metadata(self.actors, self.source, data, source)
            after = {str(path.relative_to(folder)): path.read_bytes() for path in folder.rglob('*.json')}
            self.assertEqual(before, after)
            self.assertEqual(sentinel.read_text(), 'preserve')
            self.assertEqual((data / 'actors.json').read_bytes(), (ROOT / 'assets/data/actors.json').read_bytes())
            for key in self.actors:
                self.assertEqual((data / 'actors' / (key + '.json')).read_bytes(), (ROOT / 'assets/data/actors' / (key + '.json')).read_bytes())
            for key in self.source:
                self.assertEqual((source / (key + '.json')).read_bytes(), (ROOT.parent / 'analysis/animations' / (key + '.json')).read_bytes())

    def test_export_refuses_path_traversal_before_writing(self):
        with tempfile.TemporaryDirectory(prefix='vssjx-actor-path-', dir='/tmp/opencode') as folder:
            with self.assertRaises(ValueError):
                self.importer.write_metadata({'../escape': {}}, {}, Path(folder) / 'data', Path(folder) / 'analysis')
            self.assertEqual(list(Path(folder).iterdir()), [])


if __name__ == '__main__': unittest.main()
