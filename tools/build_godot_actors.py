"""Compile recovered actor evidence into editable Godot scenes and resources.

This is an explicit import/migration tool, not a game runtime JSON adapter.
Existing PNGs are referenced unchanged. Never deletes or overwrites unrelated files.
Use --check to compare import evidence without changing anything. Existing native
edits are never overwritten unless --force explicitly requests a fresh conversion.
"""
import argparse
import hashlib
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
    if key.startswith('hero/') and '_w' not in key:
        stem=key.split('/')[1]
        scene=scene.replace('load_steps=4','load_steps=6').replace(
            '\n[node name=',
            '\n[ext_resource type="Script" path="res://scripts/hero_actor.gd" id="HeroScript"]\n'
            f'[ext_resource type="Resource" path="res://assets/appearance_resources/outfits/{stem}.tres" id="Outfit"]\n\n[node name=')
        scene+='script = ExtResource("HeroScript")\nbase_frames = ExtResource("2")\noutfit = ExtResource("Outfit")\nactor_stem = '+value(stem)+'\n'
    return {f'{prefix}.tres': definition, f'{prefix}_frames.tres': '\n'.join(frames), f'{SCENE}/{key}.tscn': scene}


def hero_base(key):
    if key.startswith(('hero/','creation/')):
        return 'hero/'+key.split('/')[1].split('_')[0]
    return key


def build_files(client=CLIENT):
    index = json.loads((client/'assets/data/actors.json').read_text())['actors']
    output = {}
    for key, path in sorted(index.items()):
        info = json.loads((client/path.removeprefix('res://')).read_text())
        files=actor_files(key, info)
        if hero_base(key)!=key:
            files.pop(f'{SCENE}/{key}.tscn')
            files.pop(f'{RESOURCE}/{key}_frames.tres')
        output.update(files)
    output[f'{RESOURCE}/catalog.tres'] = '\n'.join([
        '[gd_resource type="Resource" script_class="NativeActorCatalog" load_steps=2 format=3]', '',
        '[ext_resource type="Script" path="res://scripts/resources/actor_catalog.gd" id="1"]', '',
        '[resource]', 'script = ExtResource("1")',
        'definitions = '+value({key: f'res://{RESOURCE}/{key}.tres' for key in sorted(index)}),
        'scenes = '+value({key: f'res://{SCENE}/{hero_base(key)}.tscn' for key in sorted(index)}), ''])
    output.update(appearance_files(client))
    return output


def appearance_files(client=CLIENT):
    source=json.loads((client/'assets/data/hero-parts.json').read_text())
    parts=dict(source['parts'])
    families={}
    for family in ['boneglow','gravebloom','eva01','legendary']:
        data=json.loads((client/f'assets/data/{family}-equipment.json').read_text())
        parts.update(data['parts'])
        families[family]=data
    prefix='assets/appearance_resources'
    output={}
    def resource(cls,script,fields):
        return '\n'.join([f'[gd_resource type="Resource" script_class="{cls}" load_steps=2 format=3]', '',
            f'[ext_resource type="Script" path="res://scripts/resources/{script}.gd" id="1"]', '',
            '[resource]', 'script = ExtResource("1")', *fields, ''])
    for key,part in sorted(parts.items()):
        if not re.fullmatch(r'[A-Za-z0-9_/]+',key) or '..' in key:raise ValueError('Invalid part key: '+key)
        regions=', '.join('Rect2i('+', '.join(str(v) for v in r)+')' for r in part['frames'])
        output[f'{prefix}/parts/{key}.tres']=resource('NativeAppearancePart','appearance_part',[
            'source_id = '+value(key),'texture_path = '+value(part['texture']), 'regions = Array[Rect2i](['+regions+'])'])
    for stem,recipe in sorted(source['recipes'].items()):
        output[f'{prefix}/recipes/{stem}.tres']=resource('NativeAppearanceRecipe','appearance_recipe',[
            key+' = '+value(recipe[key]) for key in ['sources','frames','sequences','opaque_tail_hex']])
    for key,data in families.items():
        output[f'{prefix}/families/{key}.tres']=resource('NativeEquipmentFamily','equipment_family',[
            'sets = '+value(data['sets']), 'weapons = '+value(data.get('weapons',[])), 'parts = '+value(sorted(data['parts']))])
    equipment={}
    def register(stem,slot,code,ids):
        if not all(source_id in parts for source_id in ids):return
        key=f'{stem}/{slot}/{code}'
        row={'stem':stem,'slot':slot,'code':code,'parts':[{'id':name,'spec':parts[name]} for name in ids]}
        if key in equipment and equipment[key]!=row:raise ValueError('Conflicting visual code: '+key)
        equipment[key]=row
    for stem,recipe in source['recipes'].items():
        register(stem,'weapon',0,[])
        for code in range(1,28):register(stem,'weapon',code,['e'+stem[1:]+str(code)])
        for code in range(12):
            body=code-2 if code>=3 else code+(2 if stem.endswith('fs') else 1)
            ids=[recipe['sources'][i] for i in [1,3,4]] if code==0 else [stem+str(body)+suffix for suffix in ['', 'q', 'x']]
            register(stem,'clothing',code,ids)
        for code in range(10):register(stem,'head',code,[recipe['sources'][0] if code==0 else stem+'t'+str(code)])
    for data in families.values():
        for row in data['sets']+data.get('weapons',[]):
            register(row['stem'],'weapon',row['weapon_code'],[row['weapon']])
            if 'clothing_code' in row:register(row['stem'],'clothing',row['clothing_code'],row['body'])
            if 'head_code' in row:register(row['stem'],'head',row['head_code'],[row['head']])
    for key,row in sorted(equipment.items()):
        ids=[p['id'] for p in row['parts']]
        output[f'{prefix}/equipment/{key}.tres']='\n'.join([
            f'[gd_resource type="Resource" script_class="NativeHeroEquipment" load_steps={len(ids)+3} format=3]', '',
            '[ext_resource type="Script" path="res://scripts/resources/hero_equipment.gd" id="1"]',
            '[ext_resource type="Script" path="res://scripts/resources/appearance_part.gd" id="PartType"]',
            *[f'[ext_resource type="Resource" path="res://{prefix}/parts/{name}.tres" id="Part_{i}"]' for i,name in enumerate(ids)], '',
            '[resource]', 'script = ExtResource("1")', 'stem = '+value(row['stem']), 'slot = '+value(row['slot']),
            'visual_code = '+str(row['code']), 'parts = Array[ExtResource("PartType")](['+', '.join(f'ExtResource("Part_{i}")' for i in range(len(ids)))+'])', ''])
    for stem,recipe in source['recipes'].items():
        rows=[equipment[f'{stem}/weapon/1'],equipment[f'{stem}/clothing/0'],equipment[f'{stem}/head/0']]
        signature=hashlib.sha256(json.dumps({'stem':stem,'recipe':recipe,'equipment':rows},ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
        output[f'{prefix}/outfits/{stem}.tres']='\n'.join([
            '[gd_resource type="Resource" script_class="NativeHeroOutfit" load_steps=6 format=3]', '',
            '[ext_resource type="Script" path="res://scripts/resources/hero_outfit.gd" id="1"]',
            f'[ext_resource type="Resource" path="res://{prefix}/recipes/{stem}.tres" id="Recipe"]',
            *[f'[ext_resource type="Resource" path="res://{prefix}/equipment/{stem}/{slot}/{code}.tres" id="{slot}"]' for slot,code in [('weapon',1),('clothing',0),('head',0)]], '',
            '[resource]', 'script = ExtResource("1")', 'stem = '+value(stem), 'recipe = ExtResource("Recipe")',
            'weapon = ExtResource("weapon")', 'clothing = ExtResource("clothing")', 'head = ExtResource("head")', 'baked_signature = '+value(signature), ''])
        if stem.endswith('zs'):
            output[f'{prefix}/outfits/creation_{stem}.tres']=output[f'{prefix}/outfits/{stem}.tres'].replace(f'equipment/{stem}/weapon/1.tres',f'equipment/{stem}/weapon/2.tres').replace('baked_signature = '+value(signature),'baked_signature = ""')
    output[f'{prefix}/catalog.tres']=resource('NativeAppearanceCatalog','appearance_catalog',[
        'parts = '+value({key:f'res://{prefix}/parts/{key}.tres' for key in sorted(parts)}),
        'recipes = '+value({key:f'res://{prefix}/recipes/{key}.tres' for key in sorted(source['recipes'])}),
        'equipment = '+value({key:f'res://{prefix}/equipment/{key}.tres' for key in sorted(equipment)}),
        'defaults = '+value({key:f'res://{prefix}/outfits/{key}.tres' for key in sorted(source['recipes'])}),
        'creation = '+value({key:f'res://{prefix}/outfits/{"creation_" if key.endswith("zs") else ""}{key}.tres' for key in sorted(source['recipes'])})])
    # Seed existing pixel edits once; subsequent imports never overwrite user work.
    if not (client/f'{prefix}/overrides.tres').exists():
        edits=json.loads((client/'assets/data/appearance-edits.json').read_text())
        output[f'{prefix}/overrides.tres']=resource('NativeAppearanceOverrides','appearance_overrides',[
            'format_version = 1', 'parts = '+value(edits['parts'])])
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--force', action='store_true', help='Explicitly replace differing native resources from recovered JSON evidence; never replaces pixel-editor overrides.')
    args = parser.parse_args()
    output = build_files()
    stale = [name for name,text in output.items() if not (CLIENT/name).is_file() or (CLIENT/name).read_bytes()!=text.encode('utf-8')]
    existing = [name for name in stale if (CLIENT/name).exists()]
    if existing and not args.check and not args.force:
        raise SystemExit('Native resources differ; preserve Inspector edits. Use --force only for an intentional reimport:\n'+'\n'.join(existing))
    for name, text in output.items():
        path = CLIENT/name
        if path.is_file() and path.read_bytes() == text.encode('utf-8'):
            continue
        if not args.check:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding='utf-8', newline='\n')
    if args.check and stale:
        raise SystemExit('Stale native actor resources:\n'+'\n'.join(stale))
    print(f'Godot actors: {len(output)} resources/scenes; {len(stale)} '+('stale' if args.check else 'written'))


if __name__ == '__main__':
    main()
