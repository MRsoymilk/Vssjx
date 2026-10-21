"""Deterministic Godot-native import; no game runtime JSON adapter or texture edits."""
import importlib.util
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('godot_actor_import',ROOT/'tools/build_godot_actors.py')
builder=importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class NativeActorResources(unittest.TestCase):
    def test_checked_in_resources_match_reviewed_source(self):
        for name,text in builder.build_files().items():
            with self.subTest(resource=name):
                self.assertEqual((ROOT/'client'/name).read_bytes(),text.encode('utf8'))

    def test_catalog_does_not_eagerly_reference_textures_or_scenes(self):
        text=builder.build_files()['assets/actor_resources/catalog.tres']
        self.assertEqual(text.count('[ext_resource'),1)
        self.assertNotIn('Texture2D',text)
        self.assertNotIn('PackedScene',text)

    def test_native_scenes_have_real_sprite_frames_not_json_payloads(self):
        files=builder.build_files()
        for name,text in files.items():
            if name.endswith('.tscn'):
                self.assertIn('type="SpriteFrames"',text)
                self.assertIn('instance=ExtResource("1")',text)
            elif name.endswith('_frames.tres'):
                self.assertIn('type="AtlasTexture"',text)
                self.assertIn('"name": &"idle"',text)
            self.assertNotIn('JSON.parse',text)

    def test_invalid_actor_paths_are_rejected(self):
        with self.assertRaises(ValueError):builder.actor_files('../escape',{})

    def test_visual_runtime_has_no_legacy_json_loader(self):
        for name in ['art','hero_appearance','generated_equipment','appearance_resources','appearance_edits','boneglow_equipment']:
            text=(ROOT/f'client/scripts/{name}.gd').read_text()
            self.assertNotIn('JSON.parse',text,name)
            self.assertNotIn('hero-parts.json',text,name)
            self.assertNotIn('actors.json',text,name)

    def test_every_export_preset_excludes_legacy_visual_json(self):
        import configparser
        config=configparser.ConfigParser()
        config.read(ROOT/'client/export_presets.cfg')
        for name in config.sections():
            if name.endswith('.options'):continue
            excluded=config[name]['exclude_filter']
            for path in ['assets/data/actors.json','assets/data/actors/*','assets/data/hero-parts.json','assets/data/*-equipment.json','assets/data/appearance-edits.json']:
                self.assertIn(path,excluded,name)

    def test_reimport_preserves_native_pixel_editor_overrides(self):
        import tempfile
        import shutil
        with tempfile.TemporaryDirectory(prefix='native-appearance-',dir='/tmp/opencode') as scratch:
            client=Path(scratch)
            (client/'assets/data').mkdir(parents=True)
            for name in ['hero-parts.json','appearance-edits.json',*[family+'-equipment.json' for family in ['boneglow','gravebloom','eva01','legendary']]]:
                shutil.copyfile(ROOT/'client/assets/data'/name,client/'assets/data'/name)
            target=client/'assets/appearance_resources/overrides.tres'
            target.parent.mkdir(parents=True)
            target.write_text('user-owned-native-overrides')
            self.assertNotIn('assets/appearance_resources/overrides.tres',builder.appearance_files(client))
            self.assertEqual(target.read_text(),'user-owned-native-overrides')


if __name__=='__main__':unittest.main()
