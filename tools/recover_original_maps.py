"""Recover the original scene-file schema and scan available caches read-only.

Uses only static bytes from Online v48. It never executes the ARM extension,
connects to the old game service, or substitutes another game's terrain.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]


class MapReader:
    def __init__(self, data):
        self.data, self.offset = data, 0

    def take(self, count):
        if count < 0 or self.offset + count > len(self.data):
            raise ValueError('Truncated scene data')
        result = self.data[self.offset:self.offset + count]
        self.offset += count
        return result

    def u8(self):
        return self.take(1)[0]

    def i8(self):
        return struct.unpack('b', self.take(1))[0]

    def text(self):
        length = int.from_bytes(self.take(2), 'big', signed=True)
        if length < 0 or length % 2 or length > 4096:
            raise ValueError('Invalid scene string length')
        return self.take(length).decode('utf-16-be')


def parse_scene_prefix(payload, expected_maps):
    """Parse one candidate record and return its length, without claiming its trailer."""
    reader = MapReader(payload)
    map_id_text = reader.text()
    if not map_id_text.isascii() or not map_id_text.isdecimal():
        raise ValueError('Not a numeric original map identifier')
    map_id = int(map_id_text)
    name = reader.text()
    if map_id not in expected_maps or name != expected_maps[map_id]:
        raise ValueError('Scene identity/name does not match the verified Online directory')
    # Native reader sign-extends, then stores and reloads both as unsigned bytes.
    height, width = reader.u8(), reader.u8()
    if not height or not width:
        raise ValueError('Invalid original scene dimensions')
    terrain = list(reader.take(width * height))
    interaction = list(reader.take(width * height))
    palette_count = reader.u8()
    palette = [int.from_bytes(reader.take(2), 'big', signed=True) for _ in range(palette_count)]
    if not palette or any(tile < 1 or tile > 756 for tile in palette):
        raise ValueError('Scene tile palette is outside the audited original tileset')
    if any(index > palette_count or index > 127 for index in terrain):
        raise ValueError('Scene cell references invalid one-based tile palette')
    metadata = [reader.i8(), reader.i8()]
    portal_count = reader.i8()
    if portal_count < 0:
        raise ValueError('Invalid interaction record count')
    portals = []
    for _ in range(portal_count):
        first, second = reader.text(), reader.text()
        x, y = reader.i8(), reader.i8()
        if not (0 <= x < width and 0 <= y < height):
            raise ValueError('Interaction marker outside scene bounds')
        portals.append({'text_0': first, 'text_1': second, 'x': x, 'y': y,
                        'note': '两个字符串的业务含义待真实场景样本核验'})
    scene = {'original_map_id': map_id, 'name': name, 'width': width, 'height': height,
            'cell_size': 16, 'terrain_indices': terrain, 'tile_palette_one_based': palette,
            'tiles': [palette[index - 1] - 1 if index else -1 for index in terrain],
            'interaction_bytes': interaction, 'metadata_bytes': metadata,
            'interaction_records': portals,
            'notes': ['地形0表示不绘制；其余索引经过图块表映射到tile编号。',
                      '第二字节层用于通行/交互，尚不将非零值统一解释为阻挡。']}
    return scene, reader.offset


def parse_scene(payload, expected_maps):
    """Strict v48 standalone parser: an unexplained trailer is still rejected."""
    scene, consumed = parse_scene_prefix(payload, expected_maps)
    if consumed != len(payload):
        raise ValueError('Unparsed scene trailer; do not claim a complete layout')
    return scene


def find_scene(data, expected_maps):
    for prefix in (0, 4):
        payload = data[prefix:]
        if len(payload) < 12:
            continue
        length = int.from_bytes(payload[:2], 'big')
        if not 2 <= length <= 6 or length % 2:
            continue
        try:
            candidate = payload[2:2 + length].decode('utf-16-be')
            if not candidate.isascii() or not candidate.isdecimal():
                continue
            scene = parse_scene(payload, expected_maps)
        except (ValueError, UnicodeError):
            continue
        return {'cache_prefix_bytes': prefix, 'scene': scene}
    return None


def load_world_exporter(root=ROOT):
    spec = importlib.util.spec_from_file_location('map_world_exporter', root / 'tools/import_original_world.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def scan_tree(path, expected_maps):
    result = {'source_root': str(path), 'files_examined': 0, 'bytes_examined': 0,
              'mrpg_headers': 0, 'online_package_headers': 0, 'scene_candidates': []}
    # Explicitly rejected by the user: do not process either unrelated game.
    excluded = {'gssjxz', 'gssxmz', 'gssjxz.mrp', 'gssxmz.mrp'}
    for file in sorted(path.rglob('*')):
        if not file.is_file() or any(part.lower() in excluded for part in file.relative_to(path).parts):
            continue
        data = file.read_bytes()
        result['files_examined'] += 1
        result['bytes_examined'] += len(data)
        if data.startswith(b'MRPG') and not data.startswith(b'MRPGCMAP') and len(data) >= 240:
            result['mrpg_headers'] += 1
            if int.from_bytes(data[68:72], 'little') == 403084:
                result['online_package_headers'] += 1
        candidate = find_scene(data, expected_maps)
        if candidate:
            result['scene_candidates'].append({'relative_path': file.relative_to(path).as_posix(),
                                                'source_sha256': hashlib.sha256(data).hexdigest(),
                                                'review_required': True, **candidate})
    return result


def recover(scan_roots, root=ROOT):
    exporter = load_world_exporter(root)
    world = exporter.build_catalog(root)
    expected = {r['original_map_id']: r['name'] for r in world['maps']['records']}
    scans = [scan_tree(path, expected) for path in scan_roots]
    return {'format_version': 1, 'native_sha256': exporter.NATIVE_SHA256,
            'source_package': world['source_package'],
            'world_overview': {'visible_locations': world['maps']['world_overview']['visible_location_count'],
                               'route_segments': world['maps']['world_overview']['route_count']},
            'scene_schema_status': '原生代码静态推导；待真实.map样本核验',
            'scans': scans, 'scene_candidate_count': sum(len(s['scene_candidates']) for s in scans),
            'notes': ['候选需身份审核，不自动导入地形。被用户拒绝的两个同名游戏不参与扫描。',
                      '仅发现格式匹配不足以证明文件来自Online，需进一步核对包/缓存来源。',
                      '检查散落缓存与已有解包成员，统计其他MRPG包头但不解包导入其他游戏。',
                      '格式为静态推导且无真实样本；未知封装或格式变体可能无法匹配。4字节前缀不等于校验值已验证。']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scan-root', type=Path, action='append', default=[])
    args = parser.parse_args()
    roots = [ROOT / 'analysis/unpacked'] + [p.resolve() for p in args.scan_root]
    report = recover(roots)
    output = ROOT / 'analysis/recovery/maps'
    output.mkdir(parents=True, exist_ok=True)
    (output / 'recovery_report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(json.dumps({k: v for k, v in report.items() if k not in ('source_package', 'scans', 'notes')}, ensure_ascii=True, indent=2))
