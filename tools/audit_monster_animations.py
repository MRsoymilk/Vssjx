"""Audit every original monster ANI without assigning unknown action semantics.

Run after import_monster_catalog.py and import_assets.py. Never execute ARM code.
The report is also consumed by the Godot data browser; raw archives stay intact.
"""
import hashlib
import json
from pathlib import Path
from PIL import Image

if __package__:
    from . import import_assets as art
else:
    import import_assets as art

REPORT = art.ROOT / 'client/assets/admin/monsters/animation_audit.json'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def audit(root=art.ROOT):
    root = Path(root)
    catalog = json.loads((root / 'client/assets/admin/monsters/catalog.json').read_text('utf-8'))
    source = root / 'analysis/unpacked/ssjx/monster'
    records, errors = [], []
    listed = {record['resource_id'] for record in catalog['monsters']}
    actual = {path.stem for path in source.glob('*.ani')}
    if listed != actual:
        errors.append('ANI coverage mismatch: ' + str(sorted(listed ^ actual)))
    if digest(root / 'analysis/source/ssjx/monster.mrp') != catalog['source_sha256']:
        errors.append('Original monster package checksum mismatch')
    images = {}
    verified_images = set()
    for record in catalog['monsters']:
        name = record['resource_id']
        path = source / (name + '.ani')
        entry_errors = []
        if digest(path) != record['source_sha256']:
            entry_errors.append('ANI checksum mismatch')
        animation = art.parse_ani(path)
        archived = json.loads((root / f'analysis/animations/monster/{name}.json').read_text('utf-8'))
        if json.loads(json.dumps(animation)) != archived:
            entry_errors.append('Archived ANI layers/sequences differ from source')
        for member in record['image_sources']:
            member_path = source / Path(member['source_member']).name
            if member_path not in verified_images:
                if digest(member_path) != member['source_sha256']:
                    entry_errors.append('Image member checksum mismatch: ' + member_path.name)
                verified_images.add(member_path)
        landmarks, effect_frames = {}, {}
        for index, layers in enumerate(animation['frames']):
            for layer in layers:
                image_key = (layer['source'], layer['frame'])
                if image_key not in images:
                    image_path = root / 'analysis/decoded_png/ssjx/monster' / (
                        f"{layer['source']}_frame{layer['frame']:03}.png")
                    with Image.open(image_path) as image:
                        images[image_key] = image.size
                if layer['source'] not in animation['sources'] or layer['transform'] not in range(8):
                    entry_errors.append(f'Invalid layer in frame {index}')
                if layer['source'].startswith('tx'):
                    effect_frames.setdefault(layer['source'], set()).add(index)
                if layer['source'] == animation['sources'][0] and layer['frame'] == 0:
                    width, height = images[image_key]
                    if layer['transform'] in (1, 3, 5, 7):
                        width = height
                    landmarks[index] = (layer['x'] + width // 2, layer['transform'])
        sequence_rows = []
        for index in range(len(animation['sequences'])):
            steps = art.resolve_source_steps(animation, index)
            for frame, duration in steps:
                if not 0 <= frame < len(animation['frames']) or not 0 <= duration <= 255:
                    entry_errors.append(f'Invalid sequence step in source_{index}')
            used = {frame for frame, _ in steps}
            tracked = [landmarks[frame] for frame in used if frame in landmarks]
            complete = bool(used) and len(tracked) == len(used)
            xs = [point[0] for point in tracked]
            sequence_rows.append({
                'sequence': index, 'steps': len(steps),
                'effect_sources': sorted(effect for effect, frames in effect_frames.items() if used & frames),
                'landmark_coverage': len(tracked), 'unique_frames': len(used),
                'landmark_complete': complete,
                'landmark_transforms': sorted({point[1] for point in tracked}),
                'landmark_x_span': max(xs) - min(xs) if complete else None,
            })
        info = record['animation']
        raw = art.bake('monster/' + name, animation, output_key=name, write_texture=False,
                       texture_prefix='res://assets/admin/monsters/')
        raw.pop('playback')
        if json.loads(json.dumps(raw)) != info:
            entry_errors.append('Archive metadata does not match original composites')
        texture = root / 'client' / info['texture'].removeprefix('res://')
        if digest(texture) != record['texture_sha256']:
            entry_errors.append('Archive atlas checksum mismatch')
        with Image.open(texture) as image:
            size = (info['width'] * info['columns'],
                    info['height'] * ((info['count'] + info['columns'] - 1) // info['columns']))
            if image.size != size:
                entry_errors.append('Archive atlas dimensions mismatch')
            image.verify()
        key = 'monster/' + name
        runtime = None
        if key in art.MONSTER_PLAYBACK:
            runtime = json.loads((root / f'client/assets/data/actors/{key}.json').read_text('utf-8'))
            attack = {frame for frame, _ in runtime['playback']['attack']}
            hurt = {frame for frame, _ in runtime['playback']['hurt']}
            if attack & hurt:
                entry_errors.append('Runtime attack and hurt share composites')
            derived = {row['frame']: row for row in runtime.get('derived_frames', [])}
            for mode in ('idle', 'walk'):
                for frame, _ in runtime['playback'][mode]:
                    row = derived.get(frame, {'source_frame': frame, 'excluded_sources': []})
                    if any(layer['source'].startswith('tx') and layer['source'] not in row['excluded_sources']
                           for layer in animation['frames'][row['source_frame']]):
                        entry_errors.append('Runtime loop contains combat effects: ' + mode)
        records.append({
            'resource_id': name, 'source_sha256': record['source_sha256'],
            'frame_count': len(animation['frames']), 'sequence_count': len(sequence_rows),
            'structural_errors': entry_errors,
            'impact_layer_frames': sorted(effect_frames.get('tx38', set())),
            'effect_sources': sorted(effect_frames), 'sequences': sequence_rows,
            'mixed_landmark_sequences': [row['sequence'] for row in sequence_rows
                                         if len(row['landmark_transforms']) > 1],
            'root_travel_sequences': [row['sequence'] for row in sequence_rows
                                     if row['landmark_x_span'] is not None and row['landmark_x_span'] > 4],
            'runtime_status': 'corrected' if runtime else 'archive_only',
            'hurt_policy': 'native_sequence_6' if runtime else 'unassigned',
        })
        errors.extend(name + ': ' + message for message in entry_errors)
    return {
        'format_version': 1, 'source_package': 'ssjx/monster.mrp',
        'source_sha256': catalog['source_sha256'],
        'playback_interpretation': 'native_reverse_tables',
        'scope': 'All ANI members; archive sequence semantics remain unassigned. '
                 'Layer effects, landmark transforms and travel are observations, not inferred actions.',
        'summary': {
            'animation_count': len(records), 'image_member_count': len(verified_images),
            'frame_count': sum(row['frame_count'] for row in records),
            'sequence_count': sum(row['sequence_count'] for row in records),
            'with_impact_layers': sum(bool(row['impact_layer_frames']) for row in records),
            'with_mixed_landmarks': sum(bool(row['mixed_landmark_sequences']) for row in records),
            'with_root_travel': sum(bool(row['root_travel_sequences']) for row in records),
            'runtime_corrected': sum(row['runtime_status'] == 'corrected' for row in records),
            'archive_only': sum(row['runtime_status'] == 'archive_only' for row in records),
            'error_count': len(errors),
        },
        'errors': errors, 'monsters': records,
    }


def main():
    report = audit()
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(json.dumps(report['summary']))
    if report['errors']:
        raise SystemExit('\n'.join(report['errors']))


if __name__ == '__main__':
    main()
