"""Import reviewed transparent NPCs as small, foot-anchored static game actors.

Only deterministic atlas preparation (alpha bounds, crop, nearest resize, padding).
Original ImageGen PNGs and screenshot evidence are never changed.
"""
import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
JOBS = ROOT / 'analysis/recovery/ssjx-pic/npc-cutouts/jobs.json'
HEIGHTS = {'budai-xianren': 40, 'crane-daren': 60, 'brown-mask-full': 60,
           'jiang-xier': 50, 'zhi-xian': 52}


def actor_key(asset_id):
    return 'npc/ssjx_' + asset_id.replace('-', '_')


def build_assets(write_textures=True):
    result = {}
    for job in json.loads(JOBS.read_text('utf8'))['jobs']:
        path = ROOT / job['output']
        with Image.open(path) as source:
            if source.mode != 'RGBA':
                raise ValueError('NPC must have real alpha: ' + job['id'])
            bounds = source.getchannel('A').point(lambda a: 255 if a >= 16 else 0).getbbox()
            if bounds is None:
                raise ValueError('Empty NPC: ' + job['id'])
            crop = source.crop(bounds)
        h = HEIGHTS.get(job['id'], 56)
        w = max(1, round(crop.width * h / crop.height))
        frame = Image.new('RGBA', (w + 4, h + 4))
        frame.paste(crop.resize((w, h), Image.Resampling.NEAREST), (2, 2))
        key = actor_key(job['id'])
        filename = key.replace('/', '_') + '.png'
        if write_textures:
            target = ROOT / 'client/assets/actors' / filename
            target.parent.mkdir(parents=True, exist_ok=True)
            frame.save(target, optimize=True)
        result[key] = dict(texture='res://assets/actors/' + filename,
            width=frame.width, height=frame.height, columns=1, count=1,
            origin=[-frame.width // 2, -h - 2], anchor_x=0,
            sequences=[[[0, 1]]], playback={mode: [[0, 1]] for mode in ('idle', 'walk', 'attack')},
            provenance=dict(source='ssjx_pic截图 + AI辅助抠图/补全', source_asset=job['output'],
                source_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                asset_id=job['id'], repair_type=job['repair_type'], alpha_bounds=list(bounds),
                preparation='alpha>=16 bounds; nearest-neighbor resize; 2px padding; feet at y=0',
                original_animation_recovered=False))
    return result


def main():
    assets = build_assets()
    path = ROOT / 'client/assets/data/actors.json'
    index = json.loads(path.read_text('utf8'))
    for key, info in assets.items():
        shard = ROOT / 'client/assets/data/actors' / (key + '.json')
        shard.parent.mkdir(parents=True, exist_ok=True)
        shard.write_text(json.dumps(info, ensure_ascii=False, indent=2) + '\n', encoding='utf8', newline='\n')
        index['actors'][key] = 'res://assets/data/actors/' + key + '.json'
    index['actors'] = dict(sorted(index['actors'].items()))
    path.write_text(json.dumps(index, ensure_ascii=False, indent=2) + '\n', encoding='utf8', newline='\n')
    print('Imported 20 static NPC actors; visible heights 40-60px, feet at ground origin.')


if __name__ == '__main__':
    main()
