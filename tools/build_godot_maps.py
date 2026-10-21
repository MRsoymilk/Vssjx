"""Bake all playable maps into editable native Godot scenes (never runtime JSON painting).

Gameplay geometry remains the shared client/server contract. This tool does not
invent recovered layouts or change coordinates. Existing native edits need --force.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import struct
import sys
from functools import lru_cache

sys.path.insert(0, str(Path(__file__).resolve().parent))
from original_map_art import rebuild

ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / 'client'
SCENES = 'scenes/maps'
ASSETS = 'assets/map_resources'


def value(data):
    return json.dumps(data, ensure_ascii=False, separators=(',', ': '))


@lru_cache(maxsize=1)
def maps():
    result = [json.loads((ROOT / 'shared/data' / file).read_text())
              for file in ('qingyun-v1.json', 'ancient-ruins-v1.json')]
    for m,file in zip(result,('qingyun-population-v1.json','ruins-population-v1.json')):
        m['residents']=json.loads((ROOT/'shared/data'/file).read_text())
    result += json.loads((ROOT / 'shared/data/ai-world-v1.json').read_text())['maps']
    return result


def geometry_hash(m):
    return hashlib.sha256(json.dumps({k: m[k] for k in ('width', 'height', 'cell_size', 'blocked')},
                                    sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def tile_bytes(tiles, width, offset=(0,0)):
    # TileMapLayer format 0: LE u16 version, then x/y/source/atlas x/y/alternative.
    return struct.pack('<H', 0) + b''.join(struct.pack('<hhHHHH', i % width+offset[0], i // width+offset[1], 0, t % 32, t // 32, 0)
                                         for i, t in enumerate(tiles) if t is not None)


def tile_layer(name, tiles, width, parent='.', offset=(0,0)):
    encoded = base64.b64encode(tile_bytes(tiles, width, offset)).decode()
    return [f'[node name="{name}" type="TileMapLayer" parent="{parent}"]',
            'tile_set = ExtResource("Tiles")', f'tile_map_data = PackedByteArray("{encoded}")', '']


def tileset():
    return '\n'.join(['[gd_resource type="TileSet" load_steps=3 format=3]', '',
        '[ext_resource type="Texture2D" path="res://assets/tiles/original_tiles.png" id="1"]', '',
        '[sub_resource type="TileSetAtlasSource" id="Atlas"]', 'texture = ExtResource("1")',
        'texture_region_size = Vector2i(16, 16)',
        *[f'{i % 32}:{i // 32}/0 = 0' for i in range(756)], '', '[resource]',
        'tile_size = Vector2i(16, 16)', 'sources/0 = SubResource("Atlas")', ''])


@lru_cache(maxsize=216)
def presentation(map_id):
    return rebuild(next(m for m in maps() if m['map_id']==map_id))


def scene(m):
    art = presentation(m['map_id'])
    props = art['scenery']
    arts = sorted({p['art'] for p in props})
    lines = [f'[gd_scene load_steps={2 + len(arts)} format=3]', '',
             f'[ext_resource type="TileSet" path="res://{ASSETS}/original_tiles.tres" id="Tiles"]',
             *[f'[ext_resource type="PackedScene" path="res://scenes/actors/catalog/{art}.tscn" id="Prop{i}"]'
               for i, art in enumerate(arts)], '', '[node name="WorldMap" type="Node2D"]',
             'texture_filter = 1', 'metadata/map_id = ' + value(m['map_id']),
             'metadata/navigation_sha256 = ' + value(geometry_hash(m)),
             'metadata/presentation_revision = 2',
             'metadata/provenance = "原包素材；截图局部参考及重建设计，非原版完整布局恢复"', '']
    lines += tile_layer('Ground', art['ground'], m['width'])
    lines += ['[node name="Scenery" type="Node2D" parent="."]', 'y_sort_enabled = true', '']
    for i, p in enumerate(props):
        lines += [f'[node name="Prop{i}" parent="Scenery" instance=ExtResource("Prop{arts.index(p["art"])}")]',
                  f'position = Vector2({int(p["x"])}, {int(p["y"])})', '']
    for i, b in enumerate(art['buildings']):
        x,y=b['cell'];w,h=b['size']
        lines += tile_layer('Building'+str(i), b['tiles'], w, 'Scenery', (0,-h))
        lines += [f'position = Vector2({x*16}, {(y+h)*16})', 'y_sort_enabled = false',
                  'metadata/building_kind = '+value(b['kind']), '']
    return '\n'.join(lines)


def build_files():
    data = maps()
    result = {f'{ASSETS}/original_tiles.tres': tileset()}
    for m in data:
        assert len(m['tiles']) == m['width'] * m['height'] == len(m['blocked'])
        assert all(0 <= t < 756 for t in m['tiles'])
        result[f'{SCENES}/{m["map_id"]}.tscn'] = scene(m)
    result[f'{ASSETS}/catalog.tres'] = '\n'.join([
        '[gd_resource type="Resource" script_class="NativeMapCatalog" load_steps=2 format=3]', '',
        '[ext_resource type="Script" path="res://scripts/resources/map_catalog.gd" id="1"]', '',
        '[resource]', 'script = ExtResource("1")',
        'scenes = ' + value({m['map_id']: f'res://{SCENES}/{m["map_id"]}.tscn' for m in data}), ''])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--force', action='store_true', help='Explicitly replace edited native scenes')
    args = parser.parse_args()
    files = build_files()
    stale = [name for name, text in files.items()
             if not (CLIENT / name).exists() or (CLIENT / name).read_bytes() != text.encode()]
    if args.check:
        print(f'Native maps: {len(maps())}; {len(stale)} stale resources')
        raise SystemExit(bool(stale))
    conflicts = [name for name in stale if (CLIENT / name).exists()]
    if conflicts and not args.force:
        raise SystemExit('Preserving existing native edits; inspect before --force: ' + ', '.join(conflicts))
    for name in stale:
        path = CLIENT / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(files[name], encoding='utf8', newline='\n')
    print(f'Native maps: {len(maps())}; wrote {len(stale)} resources')


if __name__ == '__main__':
    main()
