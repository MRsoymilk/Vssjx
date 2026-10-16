"""Bake all monster ANI resources for the read-only browser, not gameplay rules.

Run after analysis/decode_assets.py. Original sequence numbers are retained;
filenames are resource identifiers, not recovered monster names or stats.
"""
import hashlib
import json
from pathlib import Path

if __package__:
    from .import_assets import ROOT, bake, parse_ani
    from .import_item_catalog import safe_file
else:
    from import_assets import ROOT, bake, parse_ani
    from import_item_catalog import safe_file


def export_catalog(destination=None):
    source = ROOT / 'analysis/unpacked/ssjx/monster'
    directory = json.loads((source / 'directory.json').read_text('utf-8'))
    members = {row['name']: row for row in directory}
    destination = Path(destination) if destination is not None else ROOT / 'client/assets/admin/monsters'
    destination.mkdir(parents=True, exist_ok=True)
    records, covered = [], set()

    def verify(name):
        path = safe_file(source, name)
        member = members[name]
        if hashlib.sha256(path.read_bytes()).hexdigest() != member['sha256']:
            raise ValueError('Monster member checksum mismatch: ' + name)
        return path, member

    for name in sorted(members):
        if not name.endswith('.ani'):
            continue
        path, member = verify(name)
        animation = parse_ani(path)
        images = []
        for stem in animation['sources']:
            _, image = verify(stem + '.imgs')
            covered.add(image['name'])
            images.append({'source_member': image['path'], 'source_sha256': image['sha256']})
        info = bake('monster/' + path.stem, animation, output_key=path.stem,
                    texture_dir=destination, texture_prefix='res://assets/admin/monsters/')
        # Browser plays source_N only; inferred idle/walk/attack are not evidence.
        info.pop('playback')
        records.append({
            'id': 'original/monster/' + path.stem, 'resource_id': path.stem,
            'display_name': '怪物动画 · ' + path.stem,
            'original_name': None, 'original_monster_id': None, 'level': None, 'stats': None,
            'source_member': member['path'], 'source_sha256': member['sha256'],
            'image_sources': images, 'animation': info,
            'texture_sha256': hashlib.sha256((destination / (path.stem + '.png')).read_bytes()).hexdigest(),
        })
    expected_images = {name for name in members if name.endswith('.imgs')}
    if covered != expected_images:
        raise ValueError('Monster image coverage mismatch: ' + str(expected_images ^ covered))
    catalog = {
        'format_version': 1, 'source_package': 'ssjx/monster.mrp',
        'source_sha256': hashlib.sha256((ROOT / 'analysis/source/ssjx/monster.mrp').read_bytes()).hexdigest(),
        'animation_count': len(records), 'image_member_count': len(covered), 'monsters': records,
    }
    (destination / 'catalog.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n',
                                             encoding='utf-8', newline='\n')
    return catalog


if __name__ == '__main__':
    catalog = export_catalog()
    print(f"Exported {catalog['animation_count']} monster animations / {catalog['image_member_count']} image members")
