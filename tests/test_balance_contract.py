"""Contract provenance and mirror checks; no production state or catalog writes."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BalanceContract(unittest.TestCase):
    def test_progression_catalog_mirror_and_finite_economy(self):
        source=(ROOT/'shared/data/progression-v1.json').read_bytes()
        self.assertEqual(source,(ROOT/'client/assets/data/progression-v1.json').read_bytes())
        data=json.loads(source)
        self.assertEqual(data['max_upgrade'],6)
        self.assertEqual(data['max_rerolls'],20)
        self.assertEqual(sum(data['normal_weights'].values()),100)
        self.assertEqual(sum(data['boss_weights'].values()),100)
    def test_build_catalog_mirror_and_six_styles(self):
        source=(ROOT/'shared/data/builds-v1.json').read_bytes()
        self.assertEqual(source,(ROOT/'client/assets/data/builds-v1.json').read_bytes())
        data=json.loads(source)
        self.assertEqual(len(data['items']),6)
        self.assertEqual(len({d['id'] for d in data['items']}),6)
        for job in range(3):self.assertEqual(sum(d['job']==job for d in data['items']),2)
        self.assertEqual(len(set(data['set_slots'])),4)
    def test_loot_mirror_and_slot_pools(self):
        source=(ROOT/'shared/data/loot-v1.json').read_bytes()
        self.assertEqual(source,(ROOT/'client/assets/data/loot-v1.json').read_bytes())
        rules=json.loads(source)
        self.assertEqual(set(rules['base']),set(rules['pools']))
        self.assertEqual(len(rules['pools']),10)
        for pool in rules['pools'].values():
            self.assertEqual(len(pool),len(set(pool)))
            self.assertGreaterEqual(len(pool),rules['quality_affixes']['yellow'])
            for kind in pool:
                low,high=rules['affixes'][kind]
                self.assertGreater(low,0)
                self.assertGreaterEqual(high,low)
    def test_skill_budget_mirror(self):
        self.assertEqual((ROOT/'shared/data/skill-balance-v1.json').read_bytes(),(ROOT/'client/assets/data/skill-balance-v1.json').read_bytes())
    def test_runtime_mirror(self):
        self.assertEqual((ROOT/'shared/data/balance-v1.json').read_bytes(),(ROOT/'client/assets/data/balance-v1.json').read_bytes())

    def test_vector_mirror(self):
        self.assertEqual((ROOT/'shared/data/balance-v1-vectors.json').read_bytes(),(ROOT/'client/tests/fixtures/balance-v1-vectors.json').read_bytes())

    def test_bounded_basis_point_contract(self):
        rules=json.loads((ROOT/'shared/data/balance-v1.json').read_text())
        self.assertEqual(rules['version'],'balance-v1')
        self.assertEqual(rules['basis'],10000)
        self.assertEqual(rules['max_level']*rules['points_per_level'],300)
        for key in ['hp_base','hp_growth','mp_base','physical_base','magic_base','defense_base']:
            self.assertEqual(len(rules[key]),3)
        self.assertLess(rules['armor_cap_bp'],rules['basis'])


if __name__=='__main__':unittest.main()
