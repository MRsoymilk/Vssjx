"""Export verified Online world-map names and quest evidence for the browser.

The source must be the existing ssjx.mrp (App ID 403084). Map names, guide
fragments and task UI strings are never promoted to playable scenes or quests.
"""
import argparse
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NATIVE_SHA256 = 'e08f93bebe133b700f2305bfbedd994b05cc8d04a5a854262af9ced956afbc03'


def verify_native(data):
    if hashlib.sha256(data).hexdigest() != NATIVE_SHA256:
        raise ValueError('Native map evidence applies only to the audited v48 gameonline.ext')


def recover_overview(maps):
    """Fields verified against the v48 Thumb reader and renderer, not filename guesses."""
    kinds = {0: '野外', 1: '城市', 2: '门派'}
    nodes = []
    for record in maps['records']:
        raw = bytes.fromhex(record['raw_record_hex'])
        if raw[3] not in kinds or raw[4] > raw[5]:
            raise ValueError('Invalid original map category or level range')
        visible = raw[1] != 255 and raw[2] != 255
        if (raw[1] == 255) != (raw[2] == 255):
            raise ValueError('Mixed visible/hidden map coordinates')
        record.update(original_map_id=raw[0], world_row=None if not visible else raw[1],
                      world_column=None if not visible else raw[2],
                      world_position=None if not visible else [raw[2], raw[1]],
                      location_kind=raw[3], location_type=kinds[raw[3]],
                      level_min=raw[4], level_max=raw[5])
        if visible:
            nodes.append({key: record[key] for key in ('original_map_id', 'name', 'world_position',
                                                       'location_kind', 'location_type', 'level_min', 'level_max')})
    trailer = bytes.fromhex(maps['uninterpreted_trailer_hex'])
    if not trailer or len(trailer) != 1 + trailer[0] * 4:
        raise ValueError('Incomplete world-route records')
    positions = {tuple(node['world_position']): node['original_map_id'] for node in nodes}
    if len(positions) != len(nodes):
        raise ValueError('Ambiguous visible map positions')
    routes = []
    for index in range(trailer[0]):
        raw = trailer[1 + index * 4:5 + index * 4]
        start, end = [raw[1], raw[0]], [raw[3], raw[2]]
        routes.append({'index': index, 'source_offset': maps['uninterpreted_trailer_offset'] + 1 + index * 4,
                       'raw_hex': raw.hex(' '), 'from': start, 'to': end,
                       'from_map_id': positions.get(tuple(start)), 'to_map_id': positions.get(tuple(end))})
    return {'grid_width': maps['header_raw'][1], 'grid_height': maps['header_raw'][0],
            'nodes': nodes, 'routes': routes, 'visible_location_count': len(nodes),
            'route_count': len(routes), 'native_sha256': NATIVE_SHA256,
            'evidence': {'reader': 'gameonline.ext@0x2b25c', 'route_draw': 'gameonline.ext@0x21090',
                         'node_draw': 'gameonline.ext@0x21244', 'level_label': 'gameonline.ext@0x2193c',
                         'map_id_lookup': 'gameonline.ext@0x221e8'},
            'notes': ['这是世界总图，非单张场景地形。记录坐标顺序为行、列，显示位置已转换为x、y。',
                      '按原样保留未命名端点与零长度线段；总图连线不等同于完整通行或传送配置。']}


def parse_worldmap(data):
    if len(data) < 3:
        raise ValueError('Truncated world-map header')
    count, offset = data[2], 3
    records = []
    for index in range(count):
        start = offset
        if offset + 2 > len(data):
            raise ValueError('Truncated map-name length')
        length = int.from_bytes(data[offset:offset + 2], 'big')
        offset += 2
        if length == 0 or length % 2 or offset + length > len(data):
            raise ValueError('Invalid UTF-16BE map-name length')
        name = data[offset:offset + length].decode('utf-16-be')
        records.append({'name_index': index, 'directory_number': index + 1,
                        'name': name, 'name_offset': start, 'name_length_bytes': length})
        offset += length
    names_end = offset
    for record in records:
        raw = data[offset:offset + 6]
        if len(raw) != 6 or raw[0] != record['directory_number']:
            raise ValueError('Map directory record/order mismatch')
        record.update(raw_record_offset=offset, raw_record_hex=raw.hex(' '))
        offset += 6
    return {'source_member': 'worldmap.data', 'source_bytes': len(data),
            'source_sha256': hashlib.sha256(data).hexdigest(),
            'header_raw': list(data[:3]), 'name_table_end_offset': names_end,
            'record_count': len(records), 'distinct_name_count': len({r['name'] for r in records}),
            'records': records, 'uninterpreted_trailer_offset': offset,
            'uninterpreted_trailer_hex': data[offset:].hex(' '),
            'notes': '保留同名目录记录与原始字节。经v48原生代码核验后可补充地图编号、世界总图位置、类型与等级；单张场景布局仍需对应.map文件。'}


def parse_strings(data):
    groups, offset = [], 0
    while offset < len(data):
        count = data[offset]
        offset += 1
        group = []
        for _ in range(count):
            if offset + 2 > len(data):
                raise ValueError('Truncated string length')
            length = int.from_bytes(data[offset:offset + 2], 'big')
            offset += 2
            if length % 2 or offset + length > len(data):
                raise ValueError('Invalid UTF-16BE string length')
            group.append(data[offset:offset + length].decode('utf-16-be'))
            offset += length
        groups.append(group)
    return groups


def guide_fragments(data):
    """Conservative text candidates only; not an interpreter of guide commands."""
    fragments = []
    for offset in range(1, len(data) - 3):
        if data[offset] != 7:
            continue
        length = int.from_bytes(data[offset + 1:offset + 3], 'big')
        if length < 2 or length % 2 or offset + 3 + length > len(data):
            continue
        try:
            text = data[offset + 3:offset + 3 + length].decode('utf-16-be')
        except UnicodeDecodeError:
            continue
        if (any('\u4e00' <= ch <= '\u9fff' for ch in text)
                and all(ch.isprintable() or ch in '\n\r\t' for ch in text)):
            fragments.append({'byte_offset': offset, 'byte_length': length, 'text': text})
    return fragments


def build_catalog(root=ROOT):
    spec = importlib.util.spec_from_file_location('world_mrp_reader', root / 'analysis/unpack_mrp.py')
    reader = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(reader)
    package = (root / 'analysis/source/ssjx.mrp').read_bytes()
    header = reader.read_header(package)
    # The audited package's internal filename is literally "ssjx.mpr".
    if header['appid'] != 403084 or header['filename'] not in ('ssjx.mrp', 'ssjx.mpr'):
        raise ValueError('Expected verified ssjx.mrp / App ID 403084, not a similarly named game')
    members = reader.parse_directory(package, header)

    def member(name):
        matches = [entry for entry in members if entry['name'] == name]
        if len(matches) != 1:
            raise ValueError(f'Missing/ambiguous Online member: {name}')
        entry = matches[0]
        raw = package[entry['stored_offset']:entry['stored_offset'] + entry['stored_length']]
        data = gzip.decompress(raw) if raw.startswith(b'\x1f\x8b') else raw
        if data != (root / 'analysis/unpacked/ssjx' / name).read_bytes():
            raise ValueError(f'Original-package/unpacked member mismatch: {name}')
        return data

    def evidence(name, kind, title):
        data = member(name)
        result = {'source_member': name, 'kind': kind, 'title': title,
                  'source_bytes': len(data), 'source_sha256': hashlib.sha256(data).hexdigest(),
                  'complete_quest_definition': False}
        if name.endswith('.str'):
            result['text_groups'] = parse_strings(data)
        else:
            result['text_fragments'] = guide_fragments(data)
            result['raw_hex'] = data.hex(' ')
        return result

    quests = [evidence('mission.str', 'ui', '任务界面文案 · mission.str'),
              evidence('teach.str', 'guide', '游戏引导文案 · teach.str')]
    quests += [evidence(f'teach{i}', 'guide', f'游戏引导线索 · teach{i}') for i in range(1, 10)]
    maps = parse_worldmap(member('worldmap.data'))
    verify_native(member('gameonline.ext'))
    maps['world_overview'] = recover_overview(maps)
    return {'format_version': 1,
            'source_package': {'path': 'analysis/source/ssjx.mrp', 'filename': header['filename'],
                               'appid': header['appid'], 'version': header['version'],
                               'description': header['description'], 'sha256': hashlib.sha256(package).hexdigest()},
            'maps': maps,
            'quests': {'original_complete_quest_count': None, 'evidence': quests,
                       'notes': '文案与引导线索不计为任务定义；原版任务总数尚未恢复。'}}


def export_catalog(root=ROOT):
    catalog = build_catalog(root)
    text = json.dumps(catalog, ensure_ascii=False, indent=2) + '\n'
    for relative in ('analysis/catalogs/online_world.json', 'client/assets/data/original_world.json'):
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8', newline='\n')
    # The same three node-type images used by the original overview renderer.
    import shutil
    icons = root / 'client/assets/ui'
    icons.mkdir(parents=True, exist_ok=True)
    for index in range(3):
        source = root / f'analysis/decoded_png/ssjx/worldmap_frame{index:03d}.png'
        shutil.copyfile(source, icons / f'worldmap_node_{index}.png')
    return catalog


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    catalog = export_catalog()
    print(f"Online maps: {catalog['maps']['record_count']} records / {catalog['maps']['distinct_name_count']} distinct names; quest evidence: {len(catalog['quests']['evidence'])} groups; original quest count unknown")
