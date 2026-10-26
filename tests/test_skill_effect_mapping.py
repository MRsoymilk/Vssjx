import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from build_skill_effects import build,all_layers,STAGES
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
            for layer in all_layers(binding):
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
        self.assertGreaterEqual(len(seen),77)

    def test_user_stages_use_exact_resource_order_and_boundaries(self):
        catalog=build()
        self.assertEqual(STAGES['sheet_010'],(172,173,174))
        self.assertEqual(STAGES['sheet_017'],(81,80,79))
        self.assertEqual(STAGES['sheet_013'],(46,179,180))
        for skill,resources in STAGES.items():
            stages=catalog['bindings'][skill]['stages']
            self.assertEqual([s['level'] for s in stages],[6,10,15])
            self.assertEqual([s['layers'][0]['art'] for s in stages],['effect/t'+str(n) for n in resources])

    def test_full_metadata_import_retains_mapped_effects(self):
        import import_assets
        # Real mapping and native hero structure; only atlas baking is replaced.
        parsed={key:{} for key in import_assets.SELECTED}
        for binding in build()['bindings'].values():
            for layer in all_layers(binding):parsed[layer['art']]={}
        for stem in ['mzs','wzs','mck','wck','mfs','wfs']:
            parsed['hero/'+stem]={'sources':[],'frames':[]}
        with patch.object(import_assets,'bake',side_effect=lambda *a,**k:{}):
            imported=build_actor_catalog(parsed,False)
        for binding in build()['bindings'].values():
            for layer in all_layers(binding):self.assertIn(layer['art'],imported)

    def test_representative_texture_exports_are_reproducible(self):
        with tempfile.TemporaryDirectory(prefix='skill-fx-') as folder:
            for stem in ['t18','t145','t25']:
                bake('effect/'+stem,parse_ani(ROOT/'analysis/unpacked/ssjx/effect'/f'{stem}.ani'),texture_dir=folder)
                self.assertEqual((Path(folder)/f'effect_{stem}.png').read_bytes(),(ROOT/'client/assets/actors'/f'effect_{stem}.png').read_bytes())


if __name__=='__main__':unittest.main()
