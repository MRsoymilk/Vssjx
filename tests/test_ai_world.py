"""Synthetic content invariants, distinct from claims about original map recovery."""
import collections
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
spec=importlib.util.spec_from_file_location("build_ai_world",ROOT/"tools/build_ai_world.py")
generator=importlib.util.module_from_spec(spec);spec.loader.exec_module(generator)

class AIWorldTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.raw=(ROOT/"shared/data/ai-world-v1.json").read_bytes()
        cls.data=json.loads(cls.raw)
        cls.maps={m["map_id"]:m for m in cls.data["maps"]}

    def test_reproducible_and_identical_modes(self):
        self.assertEqual(self.raw,(ROOT/"client/assets/data/ai-world-v1.json").read_bytes())
        self.assertEqual(self.data,generator.build())

    def test_complete_original_directory_and_provenance(self):
        rows=json.loads((ROOT/"analysis/catalogs/online_world.json").read_text(encoding="utf8"))["maps"]["records"]
        self.assertEqual(len(self.maps),214)
        self.assertEqual(sum(len(m["quests"]) for m in self.maps.values()),642)
        for row in rows:
            m=self.maps[f"ai_{row['original_map_id']:03}"]
            for field in ["name","level_min","level_max","world_position"]: self.assertEqual(m[field],row[field])
            self.assertEqual(m["source"],"AI生成")
            self.assertIn("非原版恢复",m["provenance"]["layout"])
        self.assertGreaterEqual(len({m["biome"] for m in self.maps.values()}),10)
        self.assertEqual(len({hashlib.sha256(json.dumps(m["tiles"]).encode()).hexdigest() for m in self.maps.values()}),214)

    def test_routes_collisions_and_reachable_residents(self):
        for m in self.maps.values():
            with self.subTest(map=m["map_id"]):
                self.assertEqual((m["width"],m["height"],m["cell_size"]),(32,32,16))
                self.assertEqual(len(m["tiles"]),1024);self.assertEqual(len(m["blocked"]),1024)
                self.assertTrue(all(0<=t<756 for t in m["tiles"]))
                seen={tuple(m["spawn"])}; queue=collections.deque(seen)
                while queue:
                    x,y=queue.popleft()
                    for nx,ny in [(x+1,y),(x-1,y),(x,y+1),(x,y-1)]:
                        if 0<=nx<32 and 0<=ny<32 and not m["blocked"][ny*32+nx] and (nx,ny) not in seen:
                            seen.add((nx,ny));queue.append((nx,ny))
                self.assertEqual(len(seen),m["blocked"].count(False))
                self.assertIn(tuple(m["portal"]["cell"]),seen)
                self.assertTrue(1<=len(m['exits'])<=2)
                expected=set(m['neighbors'])|({'qingyun_trail'} if m['original_map_id']!=21 else set())
                self.assertEqual({g['target_map'] for g in m['exits']},expected)
                self.assertEqual(len({tuple(g['cell']) for g in m['exits']}),len(m['exits']))
                self.assertTrue(all(m['spawn'] not in g.get('cells',[g['cell']]) for g in m['exits']))
                for gate in m['exits']:
                    self.assertIn(tuple(gate['cell']),seen)
                    self.assertNotEqual(gate['cell'],m['spawn'])
                    for point in gate.get('cells',[gate['cell']]):
                        self.assertIn(tuple(point),seen)
                        self.assertNotEqual(point,m['spawn'])
                for prop in m['scenery']:
                    x,y=(prop['x']-8)//16,(prop['y']-8)//16
                    for p in [m['spawn'],m['portal']['cell'],*[r['cell'] for r in m['residents']]]:
                        self.assertFalse(abs(x-p[0])<=3 and 0<=y-p[1]<=6,'Canopy obscures arrival/resident '+m['map_id'])
                for r in m["residents"]: self.assertIn(tuple(r["cell"]),seen)
                self.assertEqual(len({tuple(r["cell"]) for r in m["residents"]}),len(m['residents']))
                for v in m["neighbors"]:self.assertIn(v,self.maps);self.assertNotEqual(v,m["map_id"])

    def test_task_graph_and_bounded_stats(self):
        ids=set()
        for m in self.maps.values():
            residents={r["id"]:r for r in m["residents"]}
            previous=""
            for q in m["quests"]:
                self.assertNotIn(q["id"],ids);ids.add(q["id"])
                self.assertEqual(q["source"],"AI生成")
                self.assertEqual(q["prerequisite"],previous);previous=q["id"]
                self.assertIn(q["giver"],residents)
                self.assertTrue(1<=q["min_level"]<=60)
                for o in q["objectives"]:
                    self.assertIn(o["target"],residents)
                    self.assertEqual(residents[o["target"]]["kind"]=="npc",o["kind"]=="interact")
                    self.assertTrue(1<=o["count"]<=2)
            for r in residents.values():
                self.assertLessEqual(len(r["id"]),32)
                self.assertTrue(1<=r["level"]<=60)
                self.assertLessEqual(r["hp"],10000)

    def test_runtime_does_not_depend_on_excluded_admin_preview(self):
        panel=(ROOT/"client/scripts/ai_world_panel.gd").read_text(encoding="utf8")
        self.assertNotIn('res://scripts/admin/',panel)
        self.assertIn('res://scripts/ai_map_preview.gd',panel)

    def test_screenshot_identity_and_separate_proposals(self):
        flower=self.maps['ai_021']
        self.assertEqual({r['name'] for r in flower['residents'] if r['kind']=='npc'},{'火修罗','五毒天王','哈哈老祖','孔灵子'})
        strips={g['target_map']:g for g in flower['exits'] if 'cells' in g}
        self.assertEqual(set(strips),{'ai_022','ai_023'})
        self.assertLess(strips['ai_022']['cell'][0],strips['ai_023']['cell'][0])
        self.assertTrue(all(len(g['cells'])==3 for g in strips.values()))
        self.assertEqual(self.maps['ai_079']['name'],'火礁祭坛')
        for key in ['blood-altar','tiandiu-valley']:
            data=json.loads((ROOT/f'analysis/ai-generated/map-designs/{key}.json').read_text(encoding='utf8'))
            self.assertFalse(data['runtime_enabled'])
            self.assertIsNone(data['original_map_id'])
            self.assertNotIn(data['map_id'],self.maps)
            for field in ('exits','quests','residents'):self.assertFalse(data[field])
        refs=ROOT/'analysis/references/map-screenshots'
        for record in json.loads((refs/'manifest.json').read_text(encoding='utf8'))['records']:
            self.assertEqual(hashlib.sha256((refs/record['file']).read_bytes()).hexdigest(),record['sha256'])

    def test_complete_npc_evidence_and_social_density(self):
        from ai_world_npcs import sheet_people
        parsed,rejected=sheet_people({'npc_raw':'枯竹老人(帮会管理)-XX子(帮会商店)小霸王(副本传送)-'})
        self.assertEqual([p['name'] for p in parsed],['枯竹老人','小霸王'])
        self.assertEqual([p['name'] for p in rejected],['XX子'])
        rows=json.loads((ROOT/'analysis/references/player-sheet/maps.json').read_text(encoding='utf8'))
        for row in rows:
            if row.get('native_map_id') is None:continue
            expected,_=sheet_people(row)
            m=self.maps[f"ai_{row['native_map_id']:03}"]
            found={r['name'] for r in m['residents'] if r['kind']=='npc'}
            for p in expected:
                if not p['gathering']:self.assertIn(p['name'],found,m['name'])
        self.assertEqual({r['name'] for r in self.maps['ai_001']['residents'] if r['kind']=='npc'},{'蜀山仙灵','白眉道长','丹辰子'})
        self.assertTrue({'余英男','铁匠','车夫','镇长'}.issubset({r['name'] for r in self.maps['ai_013']['residents']}))
        self.assertGreaterEqual(sum(r['kind']=='npc' for r in self.maps['ai_213']['residents']),7)
        self.assertGreaterEqual(sum(r['kind']=='npc' for r in self.maps['ai_214']['residents']),5)
        for m in self.maps.values():
            self.assertLessEqual(len(m['residents']),32)
            for r in m['residents']:
                if r['kind']!='npc':continue
                self.assertTrue(r['dialogue'] and r['service_label'])
                self.assertIn(r['npc_reference']['source'],['AI生成','用户表格（待核对）'])
                self.assertNotIn('玩家ID',r['name'])
                self.assertNotIn(r['name'],{'当归','茯苓','精铁矿','珍金矿','珍铜矿'})

    def test_water_centers_use_native_water_not_diagonal_bank(self):
        from ai_world_layouts import Layout
        layout=Layout(dict(original_map_id=214,name='仙灵幻界'),'forest')
        m=layout.compose();centers=0
        for y in range(1,31):
            for x in range(1,31):
                if all(layout.g[yy][xx]=='water' for xx,yy in [(x,y),(x+1,y),(x-1,y),(x,y+1),(x,y-1)]):
                    centers+=1;self.assertEqual(m['tiles'][y*32+x],91)
        self.assertGreater(centers,30)

    def test_layouts_vary_in_structure_and_resident_placement(self):
        self.assertGreaterEqual(len({m["layout_archetype"] for m in self.maps.values()}),25)
        self.assertGreaterEqual(len({tuple(tuple(r["cell"]) for r in m["residents"]) for m in self.maps.values()}),190)
        self.assertGreaterEqual(len({tuple(m["spawn"]) for m in self.maps.values()}),20)
        for m in self.maps.values():
            self.assertTrue(m["landmarks"],m["map_id"])
            for p in m["scenery"]:
                self.assertTrue(m["blocked"][(p["y"]//16)*32+p["x"]//16],m["map_id"])
            if m["layout_archetype"] in ["hamlet","canal_town","market_town","monastery"]:
                self.assertGreaterEqual(sum(p["kind"] in ["house","inn","shrine"] for p in m["landmarks"]),3)

if __name__=="__main__":unittest.main()
