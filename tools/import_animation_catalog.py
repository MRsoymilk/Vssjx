"""Bake complete original animation packages for the read-only browser.

Run after analysis/decode_assets.py. Original sequence numbers are retained;
Filenames are resource identifiers, not recovered gameplay names or rules.
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


def export_catalog(group, destination=None):
    plural, label, unknown = {
        'monster': ('monsters', '怪物动画', {'original_monster_id': None, 'level': None, 'stats': None}),
        'effect': ('effects', '特效动画', {'original_effect_id': None, 'skill_mapping': None}),
    }[group]
    source = ROOT / 'analysis/unpacked/ssjx' / group
    directory = json.loads((source / 'directory.json').read_text('utf-8'))
    members = {row['name']: row for row in directory}
    destination = Path(destination) if destination is not None else ROOT / 'client/assets/admin' / plural
    destination.mkdir(parents=True, exist_ok=True)
    records, covered = [], set()

    def verify(name):
        path = safe_file(source, name)
        member = members[name]
        if hashlib.sha256(path.read_bytes()).hexdigest() != member['sha256']:
            raise ValueError(group + ' member checksum mismatch: ' + name)
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
        info = bake(group + '/' + path.stem, animation, output_key=path.stem,
                    texture_dir=destination, texture_prefix=f'res://assets/admin/{plural}/')
        # Browser plays source_N only; inferred idle/walk/attack are not evidence.
        info.pop('playback')
        records.append({
            'id': f'original/{group}/' + path.stem, 'resource_id': path.stem,
            'display_name': label + ' · ' + path.stem,
            'original_name': None, **unknown,
            'source_member': member['path'], 'source_sha256': member['sha256'],
            'image_sources': images, 'animation': info,
            'texture_sha256': hashlib.sha256((destination / (path.stem + '.png')).read_bytes()).hexdigest(),
        })
    expected_images = {name for name in members if name.endswith('.imgs')}
    if covered != expected_images:
        raise ValueError(group + ' image coverage mismatch: ' + str(expected_images ^ covered))
    catalog = {
        'format_version': 1, 'source_package': f'ssjx/{group}.mrp',
        'source_sha256': hashlib.sha256((ROOT / f'analysis/source/ssjx/{group}.mrp').read_bytes()).hexdigest(),
        'animation_count': len(records), 'image_member_count': len(covered), plural: records,
    }
    (destination / 'catalog.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n',
                                             encoding='utf-8', newline='\n')
    return catalog

