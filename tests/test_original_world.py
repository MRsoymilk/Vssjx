"""Verified Online provenance and honest map/quest recovery boundaries."""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('original_world_exporter', ROOT / 'tools/import_original_world.py')
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)


class OriginalWorldTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = json.loads((ROOT / 'client/assets/data/original_world.json').read_text('utf-8'))
        cls.world = (ROOT / 'analysis/unpacked/ssjx/worldmap.data').read_bytes()

    def test_same_verified_online_source_in_analysis_and_client(self):
        self.assertEqual((ROOT / 'analysis/catalogs/online_world.json').read_bytes(),
                         (ROOT / 'client/assets/data/original_world.json').read_bytes())
        package = (ROOT / 'analysis/source/ssjx.mrp').read_bytes()
        self.assertEqual(self.catalog['source_package']['appid'], 403084)
        self.assertEqual(hashlib.sha256(package).hexdigest(), self.catalog['source_package']['sha256'])
        self.assertEqual(exporter.build_catalog(), self.catalog)

    def test_generated_world_index_has_stable_cross_platform_bytes(self):
        for relative in ('analysis/catalogs/online_world.json', 'client/assets/data/original_world.json'):
            self.assertNotIn(b'\r', (ROOT / relative).read_bytes())

    def test_map_names_and_duplicate_records_are_preserved(self):
        maps = self.catalog['maps']
        self.assertEqual(maps['record_count'], 214)
        self.assertEqual(maps['distinct_name_count'], 157)
        self.assertEqual(len(maps['records']), 214)
        self.assertEqual(maps['records'][0]['name'], '灵空台')
        self.assertEqual(maps['records'][-1]['name'], '仙灵幻界')
        self.assertGreater(sum(r['name'] == '莫言山' for r in maps['records']), 1)
        for record in maps['records']:
            self.assertNotIn('tiles', record)
            self.assertNotIn('npc', record)
            self.assertNotIn('server_map_id', record)

    def test_map_records_round_trip_every_original_byte(self):
        maps = self.catalog['maps']
        rebuilt = bytearray(maps['header_raw'])
        for record in maps['records']:
            self.assertEqual(len(rebuilt), record['name_offset'])
            name = record['name'].encode('utf-16-be')
            rebuilt.extend(len(name).to_bytes(2, 'big'))
            rebuilt.extend(name)
        self.assertEqual(len(rebuilt), maps['name_table_end_offset'])
        for record in maps['records']:
            self.assertEqual(len(rebuilt), record['raw_record_offset'])
            rebuilt.extend(bytes.fromhex(record['raw_record_hex']))
        self.assertEqual(len(rebuilt), maps['uninterpreted_trailer_offset'])
        rebuilt.extend(bytes.fromhex(maps['uninterpreted_trailer_hex']))
        self.assertEqual(bytes(rebuilt), self.world)
        self.assertEqual(hashlib.sha256(rebuilt).hexdigest(), maps['source_sha256'])

    def test_quest_evidence_is_not_fabricated_quest_definitions(self):
        quests = self.catalog['quests']
        self.assertIsNone(quests['original_complete_quest_count'])
        self.assertEqual(len(quests['evidence']), 11)
        for evidence in quests['evidence']:
            self.assertFalse(evidence['complete_quest_definition'])
            source = (ROOT / 'analysis/unpacked/ssjx' / evidence['source_member']).read_bytes()
            self.assertEqual(hashlib.sha256(source).hexdigest(), evidence['source_sha256'])
            for fragment in evidence.get('text_fragments', []):
                offset = fragment['byte_offset']
                self.assertEqual(source[offset], 7)
                length = int.from_bytes(source[offset + 1:offset + 3], 'big')
                self.assertEqual(source[offset + 3:offset + 3 + length].decode('utf-16-be'), fragment['text'])
        ui = quests['evidence'][0]['text_groups']
        self.assertEqual(sum(map(len, ui)), 14)
        self.assertIn('任务目标', ui[0])
        self.assertIn('xsrw05', quests['evidence'][1]['text_groups'][0])

    def test_world_overview_fields_follow_native_row_column_order(self):
        maps = self.catalog['maps']
        overview = maps['world_overview']
        self.assertEqual((overview['grid_width'], overview['grid_height']), (22, 25))
        self.assertEqual((len(overview['nodes']), len(overview['routes'])), (79, 78))
        self.assertEqual(sum(r['world_position'] is None for r in maps['records']), 135)
        self.assertEqual(len({tuple(n['world_position']) for n in overview['nodes']}), 79)
        self.assertEqual(sum(n['location_kind'] == 1 for n in overview['nodes']), 4)
        self.assertEqual(sum(n['location_kind'] == 2 for n in overview['nodes']), 3)
        self.assertEqual(maps['records'][0]['world_position'], [6, 21])
        self.assertEqual(maps['records'][3]['world_position'], [4, 9])
        for record in maps['records']:
            raw = bytes.fromhex(record['raw_record_hex'])
            self.assertEqual(record['original_map_id'], raw[0])
            self.assertEqual(record['world_position'], None if raw[1] == 255 else [raw[2], raw[1]])
            self.assertEqual([record['location_kind'], record['level_min'], record['level_max']], list(raw[3:]))
        for index, route in enumerate(overview['routes']):
            raw = self.world[route['source_offset']:route['source_offset'] + 4]
            self.assertEqual(raw.hex(' '), route['raw_hex'])
            self.assertEqual(route['index'], index)
            self.assertEqual(route['from'], [raw[1], raw[0]])
            self.assertEqual(route['to'], [raw[3], raw[2]])
        self.assertEqual(overview['routes'][74]['from'], [22, 12])
        self.assertIsNone(overview['routes'][74]['from_map_id'])
        self.assertEqual(overview['routes'][77]['from'], overview['routes'][77]['to'])
        self.assertEqual(sum(r['from_map_id'] is not None and r['to_map_id'] is not None
                             for r in overview['routes']), 76)

    def test_native_evidence_and_original_icons_are_reproducible(self):
        native = (ROOT / 'analysis/unpacked/ssjx/gameonline.ext').read_bytes()
        exporter.verify_native(native)
        with self.assertRaises(ValueError):
            exporter.verify_native(native[:-1])
        evidence = json.loads((ROOT / 'analysis/recovery/maps/native_evidence.json').read_text('utf-8'))
        self.assertEqual(evidence['native_sha256'], hashlib.sha256(native).hexdigest())
        for function in evidence['functions']:
            chunk = native[int(function['start'], 16):int(function['end_exclusive'], 16)]
            self.assertEqual(hashlib.sha256(chunk).hexdigest(), function['byte_sha256'])
        for index in range(3):
            self.assertEqual((ROOT / f'client/assets/ui/worldmap_node_{index}.png').read_bytes(),
                             (ROOT / f'analysis/decoded_png/ssjx/worldmap_frame{index:03d}.png').read_bytes())

    def test_truncated_or_invalid_map_data_is_rejected(self):
        bad_length = bytearray(self.world)
        bad_length[3:5] = b'\0\x03'
        bad_record = bytearray(self.world)
        bad_record[1995] = 0
        for data in (b'', self.world[:1990], self.world[:3270], bytes(bad_length), bytes(bad_record)):
            with self.subTest(length=len(data)):
                with self.assertRaises((ValueError, UnicodeError)):
                    exporter.parse_worldmap(data)
        with self.assertRaises(ValueError):
            exporter.parse_strings(b'\x01\x00\x03\x00A\x00')

    def test_rejected_memory_card_game_ids_cannot_be_imported(self):
        with tempfile.TemporaryDirectory(prefix='ssjx-world-identity-') as temporary:
            root = Path(temporary)
            (root / 'analysis/source').mkdir(parents=True)
            shutil.copyfile(ROOT / 'analysis/unpack_mrp.py', root / 'analysis/unpack_mrp.py')
            original = (ROOT / 'analysis/source/ssjx.mrp').read_bytes()
            for appid in (315024, 330007):
                package = bytearray(original)
                package[68:72] = appid.to_bytes(4, 'little')
                (root / 'analysis/source/ssjx.mrp').write_bytes(package)
                with self.assertRaisesRegex(ValueError, '403084'):
                    exporter.build_catalog(root)


if __name__ == '__main__':
    unittest.main()
