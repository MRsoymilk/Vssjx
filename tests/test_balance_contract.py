"""Contract provenance and mirror checks; no production state or catalog writes."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BalanceContract(unittest.TestCase):
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
