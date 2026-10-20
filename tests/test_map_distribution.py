"""Behavioral checks for screenshot-derived terrain and traversable safe districts."""
import collections
import itertools
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MapDistributionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.maps = json.loads((ROOT/'shared/data/ai-world-v1.json').read_text(encoding='utf8'))['maps']

    def test_service_routes_bypass_entire_monster_patrol_areas(self):
        for m in self.maps[1:]:
            with self.subTest(map=m['map_id']):
                monsters = [r for r in m['residents'] if r['kind']!='npc']
                patrols = {(x,y) for r in monsters for x in range(r['cell'][0]-2,r['cell'][0]+3)
                           for y in range(r['cell'][1]-2,r['cell'][1]+3)}
                seen = {tuple(m['spawn'])}; queue = collections.deque(seen)
                while queue:
                    x,y = queue.popleft()
                    for xx,yy in ((x+1,y),(x-1,y),(x,y+1),(x,y-1)):
                        if 0<xx<31 and 0<yy<31 and not m['blocked'][yy*32+xx] and (xx,yy) not in patrols and (xx,yy) not in seen:
                            seen.add((xx,yy)); queue.append((xx,yy))
                targets = [r['cell'] for r in m['residents'] if r['kind']=='npc']
                targets += [p for gate in m['exits'] for p in gate.get('cells',[gate['cell']])]
                for target in targets: self.assertIn(tuple(target),seen)
                self.assertTrue(m['population_layout']['service_routes_avoid_patrols'])

    def test_combat_clearings_have_arrival_and_service_buffers(self):
        distance = lambda a,b: abs(a[0]-b[0])+abs(a[1]-b[1])
        for m in self.maps[1:]:
            with self.subTest(map=m['map_id']):
                people = [r['cell'] for r in m['residents'] if r['kind']=='npc']
                monsters = [r['cell'] for r in m['residents'] if r['kind']!='npc']
                arrivals = [m['spawn'],m['portal']['cell']]
                arrivals += [p for gate in m['exits'] for p in gate.get('cells',[gate['cell']])]
                for seed in monsters:
                    self.assertGreaterEqual(min(distance(seed,p) for p in people),7)
                    self.assertGreaterEqual(min(distance(seed,p) for p in arrivals),9)
                for a,b in itertools.combinations(monsters,2): self.assertGreaterEqual(distance(a,b),5)

    def test_ground_and_architecture_match_identifiable_reference_scenes(self):
        by_id = {m['original_map_id']:m for m in self.maps}
        for num in (28,29,30,32):
            m = by_id[num]
            self.assertGreater(m['tiles'].count(394),500,'Yellow earth courts, including Kunlun')
            self.assertGreaterEqual(sum(p['kind'] in ('shrine','blue_house') for p in m['landmarks']),3)
            self.assertTrue({456,479}.isdisjoint(m['tiles']),'These service courts are not snow/ice')
        for num in (43,45,46):
            m = by_id[num]
            self.assertGreater(m['tiles'].count(325),500,'Desert ground uses native sand')
            self.assertTrue(any(p['art'] in ('map/m1','map/m6','map/m13') for p in m['scenery']))
        village = by_id[7]
        self.assertGreater(village['tiles'].count(91),50)
        self.assertLess(village['tiles'].count(149),30,'Village keeps open grass rather than a large tiled plaza')

    def test_references_exist_and_keep_uncertainty_explicit(self):
        profiled = [m for m in self.maps if m.get('screenshot_reference',{}).get('profile')]
        self.assertEqual(len(profiled),11)
        for m in profiled:
            ref = m['screenshot_reference']
            self.assertIn('非原版恢复',ref['scope'])
            for file in ref['files']: self.assertTrue((ROOT/ref['directory']/file).is_file())
        self.assertIn('未唯一确认地图',next(m for m in profiled if m['original_map_id']==43)['screenshot_reference']['evidence'])


if __name__=='__main__': unittest.main()
