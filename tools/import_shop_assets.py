"""Recompose confirmed ssjx hero parts; no textures from other games.

Prices/names/stats in shop-v1 are reconstruction rules, not recovered item IDs.
Weapon e{zs,ck,fs}N and body {m,w}{zs,ck,fs}N use the original ANI layer
positions, transforms, ordering, head stabilization and audited battle playback.
"""
import copy
import json
from pathlib import Path
from PIL import Image
from import_assets import ANALYSIS, DEST, bake, parse_ani, readable_json


def build(write_textures=True):
    index_path = DEST / 'data/actors.json'
    index = json.loads(index_path.read_text('utf-8'))
    total = 0
    for stem in ['mzs', 'wzs', 'mck', 'wck', 'mfs', 'wfs']:
        key = 'hero/' + stem
        original = parse_ani(ANALYSIS / 'unpacked/ssjx/hero' / (stem + '.ani'))
        original_info = json.loads((DEST / 'data/actors' / (key + '.json')).read_text('utf-8'))
        for weapon in range(4):
            for armor in range(3):
                if weapon == 1 and armor == 0:
                    continue
                animation = copy.deepcopy(original)
                replacements = {original['sources'][2]: 'e' + stem[1:] + str(weapon)}
                if armor:
                    body = stem + str(armor + (2 if stem.endswith('fs') else 1))
                    for slot, suffix in [(1, ''), (3, 'q'), (4, 'x')]:
                        replacements[original['sources'][slot]] = body + suffix
                for layers in animation['frames']:
                    layers[:] = [layer for layer in layers if weapon or layer['source'] != original['sources'][2]]
                    for layer in layers:
                        layer['source'] = replacements.get(layer['source'], layer['source'])
                variant = f'{key}_w{weapon}_c{armor}'
                info = bake(key, animation, variant, write_texture=write_textures)
                # Playback/root-motion comes from the unmodified original ANI.
                info['playback'] = original_info['playback']
                info['native_battle'] = original_info['native_battle']
                path = DEST / 'data/actors' / (variant + '.json')
                path.write_text(readable_json(info) + '\n', 'utf-8', newline='\n')
                index['actors'][variant] = 'res://assets/data/actors/' + variant + '.json'
                total += 1
    index_path.write_text(json.dumps(index, ensure_ascii=False, indent=2) + '\n', 'utf-8', newline='\n')
    if not write_textures: return
    for prefix in ['eck', 'ezs', 'efs', 'mck']:
        for number in [2, 3]:
            source = Image.open(ANALYSIS / f'decoded_png/ssjx/hero/{prefix}{number}_frame000.png').convert('RGBA')
            icon = Image.new('RGBA', (48, 48))
            source.thumbnail((44, 44), Image.Resampling.NEAREST)
            icon.alpha_composite(source, ((48-source.width)//2, (48-source.height)//2))
            icon.save(DEST / f'ui/shop_{prefix}{number}.png')
    print(f'{total} appearance variants generated from ssjx hero parts')


if __name__ == '__main__':
    build()
