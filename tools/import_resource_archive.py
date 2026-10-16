"""Index every original member, including unsupported, missing and broken data.

Static decoders only: never execute MR bytecode or native extensions. Raw files
remain in analysis/; browser-only previews are excluded from game exports.
"""
from collections import Counter
import hashlib
import importlib.util
import json
from pathlib import Path

from PIL import Image

if __package__:
    from .import_assets import ROOT, bake, parse_ani
    from .import_item_catalog import safe_file
    from .audit_original_map_sources import native_flow, parse_local_versions
else:
    from import_assets import ROOT, bake, parse_ani
    from import_item_catalog import safe_file
    from audit_original_map_sources import native_flow, parse_local_versions


def export_catalog(destination=None, root=ROOT):
    root = Path(root)
    destination = Path(destination) if destination is not None else root / 'client/assets/admin/archive'
    destination.mkdir(parents=True, exist_ok=True)
    spec = importlib.util.spec_from_file_location('archive_decoder', ROOT / 'analysis/decode_assets.py')
    decoder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(decoder)
    reusable = {}
    for group in ('monsters', 'effects'):
        path = root / f'client/assets/admin/{group}/catalog.json'
        if path.exists():
            for row in json.loads(path.read_text('utf-8'))[group]:
                reusable[row['source_member']] = row['animation']
    world_path = root / 'client/assets/data/original_world.json'
    world = json.loads(world_path.read_text('utf-8')) if world_path.exists() else {}
    evidence = {row['source_member']: row for row in world.get('quests', {}).get('evidence', [])}
    records, packages, seen = [], [], set()

    def record(raw, path, member=None, package=None):
        key = member['path'] if member is not None else path.relative_to(root / 'analysis/source').as_posix()
        if key in seen:
            raise ValueError('Duplicate archive entry: ' + key)
        seen.add(key)
        row = {
            'id': 'archive/' + key, 'resource_path': key,
            'source_file': path.relative_to(root).as_posix(),
            'source_package': package, 'member': member,
            'size': len(raw) if raw is not None else None,
            'sha256': hashlib.sha256(raw).hexdigest() if raw is not None else None,
            'status': '未解析', 'reason': '尚无此格式的完整解码器；保留原始条目，不执行其中代码',
            'hex_prefix': raw[:128].hex() if raw is not None else '',
            'parsed': {}, 'preview': {'kind': 'unavailable'},
        }
        # Register first, so failures can never silently remove directory entries.
        records.append(row)
        if raw is None:
            row.update(status='解析失败', reason='目录条目存在，但原始文件缺失')
            return
        if member and (row['sha256'] != member['sha256'] or len(raw) != member['unpacked_length']):
            row.update(status='解析失败', reason='原始文件大小或SHA256与目录不一致')
            return
        try:
            suffix = path.suffix.lower()
            if suffix in ('.img', '.imgs'):
                images = [decoder.decode_img(raw)] if suffix == '.img' else decoder.decode_imgs(raw)
                if not images:
                    raise ValueError('Empty image set')
                width, height = max(im.width for im in images), max(im.height for im in images)
                columns = min(8, len(images))
                atlas = Image.new('RGBA', (columns * width, ((len(images) + columns - 1) // columns) * height))
                for index, image in enumerate(images):
                    atlas.paste(image, ((index % columns) * width, (index // columns) * height))
                filename = 'image_' + hashlib.sha256(key.encode()).hexdigest()[:24] + '.png'
                atlas.save(destination / filename, optimize=True)
                row['preview'] = {'kind': 'image_frames', 'animation': {
                    'texture': 'res://assets/admin/archive/' + filename, 'width': width, 'height': height,
                    'columns': columns, 'count': len(images), 'origin': [0, 0],
                    'sequences': [[[index, 1]] for index in range(len(images))],
                }}
                row['parsed'] = {'frame_count': len(images), 'frame_sizes': [list(im.size) for im in images]}
                row.update(status='已解析', reason='完整图片解码；frame_N为图片帧编号，不推断动画时序')
            elif suffix == '.ani':
                animation = parse_ani(path)
                row['parsed'] = animation
                row.update(status='部分解析' if animation['opaque_tail_hex'] else '已解析',
                           reason='帧、图层与序列已解析；尾部事件/碰撞元数据语义未知' if animation['opaque_tail_hex'] else '帧、图层与原始序列已解析；动作业务语义未推断')
                if not animation['frames'] or not any(animation['sequences']):
                    row.update(status='部分解析', reason='ANI结构已解析，但原始条目没有可播放的帧或序列；保留空条目')
                    return
                if key in reusable:
                    info = reusable[key]
                else:
                    group = path.parent.name if path.parent.name != 'ssjx' else 'main'
                    info = bake(group + '/' + path.stem, animation,
                                output_key='animation_' + group + '_' + path.stem,
                                texture_dir=destination, texture_prefix='res://assets/admin/archive/')
                    info.pop('playback')
                row['preview'] = {'kind': 'original_animation', 'animation': info}
            elif suffix == '.str':
                row['parsed'] = {'text_groups': decoder.decode_str(raw)}
                row.update(status='已解析', reason='完整解码长度前缀UTF-16BE文本；不执行文本')
            elif key == 'ssjx.mrp/worldmap.data' and world.get('maps', {}).get('source_sha256') == row['sha256']:
                row['parsed'] = world['maps']
                row.update(status='部分解析', reason='地图目录及世界总图已恢复；不代表单张场景地形已恢复')
            elif path.name in evidence:
                row['parsed'] = evidence[path.name]
                row.update(status='部分解析', reason='已提取原包引导文本线索；完整业务结构未恢复')
            elif key == 'ssjx.mrp/gameonline.ext':
                row['parsed'] = {'static_analysis': ['analysis/disasm/gameonline_mixed_report.md',
                                                   'analysis/disasm/gameonline_resource_findings.json'],
                                 'verified_native_flow': native_flow(raw)}
                row.update(status='部分解析', reason='已有ARM/Thumb静态反汇编与资源线索；完整原生业务逻辑未恢复，不执行原代码')
            elif key == 'ssjx/commonRecord/version':
                flow = native_flow((root / 'analysis/unpacked/ssjx/gameonline.ext').read_bytes())
                row['parsed'] = {'local_version_records': parse_local_versions(raw, flow['bundle_names'])}
                row.update(status='已解析', reason='本地资源包版本表已解析；不是地图地形或游戏业务定义')
        except Exception as error:
            row.update(status='解析失败', reason=f'{type(error).__name__}: {error}')
            row['preview'] = {'kind': 'unavailable'}

    unpacked = root / 'analysis/unpacked/ssjx'
    for directory in sorted(unpacked.rglob('directory.json')):
        members = json.loads(directory.read_text('utf-8'))
        package = 'ssjx.mrp' if directory.parent == unpacked else 'ssjx/' + directory.parent.name + '.mrp'
        package_file = root / 'analysis/source' / package
        packages.append({'path': package, 'member_count': len(members),
                         'sha256': hashlib.sha256(package_file.read_bytes()).hexdigest() if package_file.exists() else None})
        for member in sorted(members, key=lambda row: row['name']):
            try:
                path = safe_file(directory.parent, member['name'])
                raw = path.read_bytes()
            except ValueError:
                # Do not follow unsafe names, even when cataloguing a missing entry.
                path = directory.parent / Path(member['name'].replace('\\', '/')).name
                raw = None
            record(raw, path, member, package)
    # Sidecars such as commonRecord/version have no MRP directory entry, but are
    # original input files too. Do not lose them because their format is unknown.
    for path in sorted((root / 'analysis/source').rglob('*')):
        if path.is_file() and path.suffix.lower() != '.mrp':
            record(path.read_bytes(), path)
    counts = dict(sorted(Counter(row['status'] for row in records).items()))
    catalog = {'format_version': 1, 'record_count': len(records), 'packages': packages, 'status_counts': counts, 'records': records}
    (destination / 'catalog.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    return catalog


if __name__ == '__main__':
    catalog = export_catalog()
    print(f"Archived {catalog['record_count']} original entries: {catalog['status_counts']}")
