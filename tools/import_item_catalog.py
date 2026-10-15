"""Export every statically decoded item icon and its provenance for Godot.

No gameplay names/stats are inferred from filenames or pictures. Run after
analysis/decode_assets.py; this exporter does not change the gameplay database.
"""
from collections import Counter
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
GROUPS = {'iw': ('weapons', '武器图标'), 'if': ('equipment', '装备图标'),
          'ix': ('other', '其他物品图标')}


def safe_file(base, relative):
    relative = PurePosixPath(relative.replace('\\', '/'))
    if relative.is_absolute() or '..' in relative.parts or ':' in str(relative):
        raise ValueError(f'Unsafe relative resource: {relative}')
    path = base.joinpath(*relative.parts).resolve()
    if not path.is_relative_to(base.resolve()) or not path.is_file():
        raise ValueError(f'Missing/outside resource: {relative}')
    return path


def build_catalog(root=ROOT):
    analysis = root / 'analysis'
    images = json.loads((analysis / 'image_manifest.json').read_text('utf-8'))['images']
    directory = json.loads((analysis / 'unpacked/ssjx/item/directory.json').read_text('utf-8'))
    members = {member['name']: member for member in directory if member['name'].endswith(('.img', '.imgs'))}
    records, seen, covered = [], set(), set()
    for image in images:
        source = PurePosixPath(image['file'].replace('\\', '/'))
        if str(source.parent) != 'ssjx/item':
            continue
        member = members[source.name]
        original = safe_file(analysis / 'unpacked', str(source))
        decoded = safe_file(analysis, image['png'])
        raw_hash = hashlib.sha256(original.read_bytes()).hexdigest()
        if raw_hash != member['sha256']:
            raise ValueError(f'Unpacked member checksum mismatch: {source}')
        key = source.stem if source.suffix == '.img' else f"{source.stem}_frame{image['frame']:03d}"
        if key in seen:
            raise ValueError(f'Duplicate item resource: {key}')
        seen.add(key)
        covered.add(source.name)
        group, label = GROUPS.get(source.stem[:2], ('other', '其他物品图标'))
        records.append({
            'id': 'original/' + key, 'resource_id': key,
            'group': group, 'display_name': f'{label} · {key}',
            'classification_basis': '原始文件名前缀分类；不是原服务器物品类型表',
            'original_item_id': None, 'original_name': None,
            'level': None, 'stats': None, 'equipment_slot': None,
            'icon': f'res://assets/items/original/{key}.png',
            'width': image['width'], 'height': image['height'],
            'frame': image['frame'], 'source_package': 'ssjx/item.mrp',
            'source_member': str(source), 'archive_member': member['path'],
            'decoded_png': image['png'].replace('\\', '/'),
            'source_bytes': member['unpacked_length'],
            'source_sha256': raw_hash,
            'png_sha256': hashlib.sha256(decoded.read_bytes()).hexdigest(),
        })
    if covered != set(members):
        raise ValueError(f'Item members missing from decoded manifest: {set(members) - covered}')
    records.sort(key=lambda row: (row['resource_id'][:2], int(re.search(r'\d+', row['resource_id'])[0]), row['frame']))
    return {'format_version': 1, 'source_package': 'ssjx/item.mrp',
            'source_manifest': 'analysis/image_manifest.json',
            'counts': dict(sorted(Counter(row['group'] for row in records).items())),
            'items': records}


def export_catalog(root=ROOT, destination=None):
    catalog = build_catalog(root)
    destination = destination or root / 'client/assets'
    icons = destination / 'items/original'
    icons.mkdir(parents=True, exist_ok=True)
    for item in catalog['items']:
        source = safe_file(root / 'analysis', item['decoded_png'])
        shutil.copyfile(source, icons / (item['resource_id'] + '.png'))
    target = destination / 'data/original_items.json'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return catalog


if __name__ == '__main__':
    exported = export_catalog()
    print(f"Exported {len(exported['items'])} original item icons: {exported['counts']}")
