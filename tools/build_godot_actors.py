"""Compile recovered actor evidence into editable Godot scenes and resources.

This is an explicit import/migration tool, not a game runtime JSON adapter.
Existing PNGs are referenced unchanged. Never deletes or overwrites unrelated files.
Use --check to detect stale generated resources without changing anything.
"""
import argparse
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / 'client'
RESOURCE = 'assets/actor_resources'
SCENE = 'scenes/actors/catalog'


def value(data):
    return json.dumps(data, ensure_ascii=False, separators=(',', ': '))


def animations(info):
    count = info.get('native_battle', {}).get('source_frame_count', info['count'])
    sequences = [[[count-1-int(frame), max(1, duration)] for frame, duration in steps]
                 for steps in info['sequences']]
    result = {f'source_{i}': (10.0, True, steps) for i, steps in enumerate(sequences)}
    for mode in ['idle', 'walk', 'attack', 'cast', 'hurt']:
        if mode in ['cast', 'hurt'] and mode not in info.get('playback', {}):
            continue
        index = max(0, len(sequences)-(6 if mode == 'attack' else 1))
        steps = info.get('playback', {}).get(mode, sequences[index]) or [[0, 1]]
        result[mode] = (6.0 if mode == 'idle' else 8.0 if mode == 'cast' else 10.0,
                        mode in ['idle', 'walk'], [[int(f), max(1, d)] for f, d in steps])
    return result


def actor_files(key, info):
    if not re.fullmatch(r'[A-Za-z0-9_]+/[A-Za-z0-9_]+', key):
        raise ValueError('Invalid actor key: '+key)
    prefix = f'{RESOURCE}/{key}'
    fields = {'texture', 'width', 'height', 'columns', 'count', 'origin', 'anchor_x', 'sequences', 'playback', 'native_battle'}
    definition = '\n'.join([
        '[gd_resource type="Resource" script_class="NativeActorDefinition" load_steps=2 format=3]', '',
        '[ext_resource type="Script" path="res://scripts/resources/actor_definition.gd" id="1"]', '',
        '[resource]', 'script = ExtResource("1")',
        'texture_path = '+value(info['texture']),
        f'frame_size = Vector2i({info["width"]}, {info["height"]})',
        f'columns = {info["columns"]}', f'frame_count = {info["count"]}',
        f'origin = Vector2i({info["origin"][0]}, {info["origin"][1]})',
        f'anchor_x = {info.get("anchor_x", 0)}',
        'sequences = '+value(info['sequences']), 'playback = '+value(info.get('playback', {})),
        'native_battle = '+value(info.get('native_battle', {})),
        'extra = '+value({k: v for k, v in info.items() if k not in fields}), ''])
    frames = [f'[gd_resource type="SpriteFrames" load_steps={info["count"]+2} format=3]', '',
              f'[ext_resource type="Texture2D" path={value(info["texture"])} id="1"]', '']
    for i in range(info['count']):
        frames += [f'[sub_resource type="AtlasTexture" id="Frame_{i}"]', 'atlas = ExtResource("1")', 'filter_clip = true']
        if 'frame_regions' in info:
            x, y, w, h, mx, my = info['frame_regions'][i]
            frames += [f'region = Rect2({x}, {y}, {w}, {h})',
                       f'margin = Rect2({mx}, {my}, {info["width"]-w}, {info["height"]-h})']
        else:
            frames += [f'region = Rect2({i % info["columns"] * info["width"]}, {i // info["columns"] * info["height"]}, {info["width"]}, {info["height"]})']
        frames += ['']
    entries = []
    for name, (speed, loop, steps) in animations(info).items():
        steps_text = ', '.join('{"duration": '+str(float(d))+', "texture": SubResource("Frame_'+str(f)+'")}' for f, d in steps)
        entries.append('{"frames": ['+steps_text+'], "loop": '+value(loop)+', "name": &'+value(name)+', "speed": '+str(speed)+'}')
    frames += ['[resource]', 'animations = [\n'+',\n'.join(entries)+'\n]', '']
    scene = '\n'.join([
        '[gd_scene load_steps=4 format=3]', '',
        '[ext_resource type="PackedScene" path="res://scenes/actors/native_actor.tscn" id="1"]',
        f'[ext_resource type="SpriteFrames" path="res://{prefix}_frames.tres" id="2"]',
        f'[ext_resource type="Resource" path="res://{prefix}.tres" id="3"]', '',
        f'[node name="{key.split("/")[1]}" instance=ExtResource("1")]',
        'sprite_frames = ExtResource("2")', 'animation = &"idle"', 'autoplay = "idle"',
        f'offset = Vector2({info["origin"][0]-info.get("anchor_x", 0)}, {info["origin"][1]})',
        'definition = ExtResource("3")', 'art_key = '+value(key), ''])
    return {f'{prefix}.tres': definition, f'{prefix}_frames.tres': '\n'.join(frames), f'{SCENE}/{key}.tscn': scene}


def build_files(client=CLIENT):
    index = json.loads((client/'assets/data/actors.json').read_text())['actors']
    output = {}
    for key, path in sorted(index.items()):
        info = json.loads((client/path.removeprefix('res://')).read_text())
        output.update(actor_files(key, info))
    output[f'{RESOURCE}/catalog.tres'] = '\n'.join([
        '[gd_resource type="Resource" script_class="NativeActorCatalog" load_steps=2 format=3]', '',
        '[ext_resource type="Script" path="res://scripts/resources/actor_catalog.gd" id="1"]', '',
        '[resource]', 'script = ExtResource("1")',
        'definitions = '+value({key: f'res://{RESOURCE}/{key}.tres' for key in sorted(index)}),
        'scenes = '+value({key: f'res://{SCENE}/{key}.tscn' for key in sorted(index)}), ''])
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    output = build_files()
    stale = []
    for name, text in output.items():
        path = CLIENT/name
        if path.is_file() and path.read_bytes() == text.encode('utf-8'):
            continue
        stale.append(name)
        if not args.check:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding='utf-8', newline='\n')
    if args.check and stale:
        raise SystemExit('Stale native actor resources:\n'+'\n'.join(stale))
    print(f'Godot actors: {len(output)} resources/scenes; {len(stale)} '+('stale' if args.check else 'written'))


if __name__ == '__main__':
    main()
