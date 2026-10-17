import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from build_skill_effects import build
from import_assets import bake,parse_ani,build_actor_catalog
from unittest.mock import patch


class SkillEffectMappingTests(unittest.TestCase):
    def test_every_skill_has_an_explicit_individual_design(self):
        catalog=build()
        self.assertEqual(catalog,json.loads((ROOT/'client/assets/data/skill-effects-v1.json').read_text('utf8')))
        skills=json.loads((ROOT/'client/assets/data/skills-v1.json').read_text('utf8'))['items']
        self.assertEqual(len(catalog['bindings']),33)
        self.assertFalse(catalog['original_binding_recovered'])
        signatures=set()
        for skill in skills:
            binding=catalog['bindings'][skill['id']]
            self.assertEqual(binding['name'],skill['name'])
            self.assertEqual(binding['trigger']=='cast_impact',skill['active'])
            self.assertEqual(binding['basis'],'authored_semantic_mapping')
            signature=tuple((l['art'],l['anchor']) for l in binding['layers'])
            self.assertNotIn(signature,signatures);signatures.add(signature)

    def test_all_resources_keep_native_content_and_valid_sequences(self):
        seen=set()
        index=json.loads((ROOT/'client/assets/data/actors.json').read_text('utf8'))['actors']
        for binding in build()['bindings'].values():
            for layer in binding['layers']:
                self.assertIn(layer['anchor'],['hero','enemy'])
                key=layer['art'];stem=key.split('/')[1]
                source=ROOT/'analysis/unpacked/ssjx/effect'/f'{stem}.ani'
                self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(),layer['source_sha256'])
                info=json.loads((ROOT/'client'/index[key].removeprefix('res://')).read_text('utf8'))
                self.assertLess(layer['sequence'],len(info['sequences']))
                if key not in seen:
                    expected=bake(key,parse_ani(source),write_texture=False)
                    self.assertEqual(info,json.loads(json.dumps(expected)))
                    seen.add(key)
        self.assertEqual(len(seen),37)

    def test_full_metadata_import_retains_mapped_effects(self):
        import import_assets
        # Real mapping and native hero structure; only atlas baking is replaced.
        parsed={key:{} for key in import_assets.SELECTED}
        for binding in build()['bindings'].values():
            for layer in binding['layers']:parsed[layer['art']]={}
        for stem in ['mzs','wzs','mck','wck','mfs','wfs']:
            parsed['hero/'+stem]={'sources':[],'frames':[]}
        with patch.object(import_assets,'bake',side_effect=lambda *a,**k:{}):
            imported=build_actor_catalog(parsed,False)
        for binding in build()['bindings'].values():
            for layer in binding['layers']:self.assertIn(layer['art'],imported)

    def test_representative_texture_exports_are_reproducible(self):
        with tempfile.TemporaryDirectory(prefix='skill-fx-') as folder:
            for stem in ['t18','t145','t25']:
                bake('effect/'+stem,parse_ani(ROOT/'analysis/unpacked/ssjx/effect'/f'{stem}.ani'),texture_dir=folder)
                self.assertEqual((Path(folder)/f'effect_{stem}.png').read_bytes(),(ROOT/'client/assets/actors'/f'effect_{stem}.png').read_bytes())


if __name__=='__main__':unittest.main()
