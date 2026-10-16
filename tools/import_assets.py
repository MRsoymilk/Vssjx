"""Build Godot art from the statically decoded MRP images. Never run MR/ARM code.

Requires Python 3, Pillow and NumPy. Run from any working directory.
"""
from pathlib import Path
import argparse
import importlib.util
import json
import struct
import copy
import re
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ANALYSIS = ROOT / 'analysis'
DEST = ROOT / 'client' / 'assets'
TRANSFORMS = {
    # ANI rotates clockwise; reflection is applied before rotation. This
    # differs from restoring the clockwise type-3 image storage in decoder.
    # In mck idle/walk, flag 1 must put the sword hilt against the hand.
    1: Image.Transpose.ROTATE_270, 2: Image.Transpose.ROTATE_180,
    3: Image.Transpose.ROTATE_90, 4: Image.Transpose.FLIP_LEFT_RIGHT,
    5: Image.Transpose.TRANSVERSE, 6: Image.Transpose.FLIP_TOP_BOTTOM,
    7: Image.Transpose.TRANSPOSE,
}
SELECTED = ['hero/mck', 'hero/mzs', 'hero/mfs', 'hero/wck', 'hero/wzs', 'hero/wfs',
            'monster/langw', 'monster/xt1', 'monster/hs1', 'monster/nt1',
            'map/m1', 'map/m2', 'map/m3', 'map/m4', 'map/m5', 'map/m6',
            'map/m7', 'map/m9', 'map/m10', 'main/biaoti',
            'effect/flash', 'effect/t1', 'effect/t20', 'effect/t36', 'effect/t44', 'effect/t47', 'effect/t71']


def parse_ani(path):
    blob = path.read_bytes()
    pos = 1
    names = []
    for _ in range(blob[0]):
        length = int.from_bytes(blob[pos:pos + 2], 'big')
        pos += 2
        names.append(blob[pos:pos + length].decode('utf-16-be'))
        pos += length
    size = blob[pos]
    pos += 1
    offsets = list(blob[pos:pos + size])
    pos += size
    assert size == len(names) and offsets == sorted(offsets)
    frames = []
    size = blob[pos]
    pos += 1
    for _ in range(size):
        layers = []
        count = blob[pos]
        pos += 1
        for _ in range(count):
            index, x, y, transform = struct.unpack_from('>BhhB', blob, pos)
            pos += 6
            source = max(i for i, offset in enumerate(offsets) if offset <= index)
            layers.append({'source': names[source], 'frame': index - offsets[source],
                           'x': x, 'y': y, 'transform': transform})
        frames.append(layers)
    sequence_count = blob[pos]
    pos += 1
    sequences = []
    for _ in range(sequence_count):
        length = blob[pos]
        pos += 1
        assert length % 2 == 0
        steps = list(zip(blob[pos:pos + length:2], blob[pos + 1:pos + length:2]))
        assert all(index < len(frames) for index, _ in steps)
        sequences.append(steps)
        pos += length
    # Unknown event/hit-box metadata is retained, not interpreted as gameplay.
    return {'sources': names, 'frames': frames, 'sequences': sequences,
            'opaque_tail_hex': blob[pos:].hex()}


def bake(key, animation, output_key=None, write_texture=True, texture_dir=None,
         texture_prefix='res://assets/actors/'):
    folder, name = key.split('/')
    source_dir = ANALYSIS / 'decoded_png/ssjx' / ('' if folder == 'main' else folder)
    frames = []
    bounds = [0, 0, 1, 1]
    for layers in animation['frames']:
        images = []
        head_center = None
        for layer in layers:
            img = Image.open(source_dir / f"{layer['source']}_frame{layer['frame']:03}.png").convert('RGBA') if layer['source'] != 'biaoti' else Image.open(source_dir / 'biaoti.png').convert('RGBA')
            transform = layer['transform']
            if transform:
                img = img.transpose(TRANSFORMS[transform])
            x, y = layer['x'], layer['y']
            if folder == 'hero' and layer['source'] == animation['sources'][0] and layer['frame'] == 0:
                head_center = x + img.width // 2
            images.append((img, x, y))
        # ANI frames may carry the old client's lunge/root motion. The Godot
        # world owns movement, so keep each hero's head above its actor anchor.
        # Source offsets remain intact in analysis/animations/<group>/<name>.json.
        if head_center is not None:
            images = [(img, x - head_center, y) for img, x, y in images]
        for img, x, y in images:
            bounds = [min(bounds[0], x), min(bounds[1], y),
                      max(bounds[2], x + img.width), max(bounds[3], y + img.height)]
        frames.append(images)
    left, top, right, bottom = bounds
    width, height = right - left, bottom - top
    columns = min(8, len(frames))
    filename = (output_key or key).replace('/', '_') + '.png'
    if write_texture:
        atlas = Image.new('RGBA', (width * columns, height * ((len(frames) + columns - 1) // columns)))
        for i, layers in enumerate(frames):
            for img, x, y in layers:
                atlas.alpha_composite(img, ((i % columns) * width + x - left,
                                            (i // columns) * height + y - top))
        atlas.save((Path(texture_dir) if texture_dir is not None else DEST / 'actors') / filename, optimize=True)
    sequences = animation['sequences']
    playback = {}
    if folder == 'hero':
        # The final twelve composites contain two complete six-frame gaits:
        # mirrored first, native facing second. Source sequence 1 mixes both
        # directions and standing poses; it is not a safe walk loop.
        native_walk = list(range(len(animation['frames']) - 6, len(animation['frames'])))
        for index in native_walk:
            layers = animation['frames'][index]
            head = next(layer for layer in layers if layer['source'] == animation['sources'][0] and layer['frame'] == 0)
            assert head['transform'] == 0 and any(layer['source'].endswith('x') for layer in layers), key
        standing = [index for index, layers in enumerate(animation['frames'])
                    if index < native_walk[0]
                    and any(layer['source'] == animation['sources'][0] and layer['frame'] == 0 and layer['transform'] == 0 for layer in layers)
                    and not any(layer['source'].endswith('x') or layer['source'].startswith('tx') for layer in layers)]
        # The last two native standing composites form a breathing pair.
        # A single still frame gives the state an idle name but no animation.
        # Composite IDs run opposite to the forward contact/swing cycle.
        # In native left-facing art the planted foot must travel right relative
        # to the body. Ascending IDs instead drag the planted foot left, making
        # the actor backpedal. Reverse whole composites, keeping body bob, feet
        # and weapons together; mirroring then also gives a forward right gait.
        playback = {'idle': [[index, 4] for index in standing[-2:]],
                    'walk': [[index, 1] for index in reversed(native_walk)], 'attack': sequences[-1]}
        if key in ('hero/mfs', 'hero/wfs') and not (output_key or '').startswith('creation/'):
            # The last sequence faces right. Battle heroes stand on the right
            # and must keep the native left-facing staff motion instead.
            playback['attack'] = sequences[4]
            playback['cast'] = sequences[6]  # Original floating-staff flourish.
    elif key == 'monster/langw':
        playback = {'idle': sequences[3], 'walk': sequences[0],
                    'attack': sequences[2]}
    return {'texture': texture_prefix + filename, 'width': width,
            'height': height, 'columns': columns, 'origin': [left, top],
            'anchor_x': 0, 'playback': playback,
            'count': len(frames), 'sequences': animation['sequences']}


def read_animations():
    parsed, errors = {}, []
    for path in sorted((ANALYSIS / 'unpacked/ssjx').rglob('*.ani')):
        rel = path.relative_to(ANALYSIS / 'unpacked/ssjx').with_suffix('').as_posix()
        key = rel if '/' in rel else 'main/' + rel
        try:
            parsed[key] = parse_ani(path)
        except (IndexError, AssertionError, ValueError, struct.error) as error:
            errors.append({'file': rel, 'error': repr(error)})
    return parsed, errors


def build_actor_catalog(parsed, write_textures=True):
    baked = {key: bake(key, parsed[key], write_texture=write_textures) for key in SELECTED if key in parsed}
    for stem in ['mzs', 'wzs', 'mck', 'wck', 'mfs', 'wfs']:
        key, preview_key = 'hero/' + stem, 'creation/' + stem
        preview = copy.deepcopy(parsed[key])
        if stem in ['mzs', 'wzs']:
            preview['sources'] = ['ezs2' if name == 'ezs1' else name for name in preview['sources']]
            for layers in preview['frames']:
                for layer in layers:
                    if layer['source'] == 'ezs1': layer['source'] = 'ezs2'
        baked[preview_key] = bake(key, preview, preview_key, write_texture=write_textures)
    return baked


def readable_json(value, level=0):
    """Keep primitive arrays / leaf records on one line, nested structure indented."""
    scalar = lambda item: not isinstance(item, (dict, list, tuple))
    if isinstance(value, dict) and value and not all(scalar(item) for item in value.values()):
        return '{\n' + ',\n'.join('  ' * (level + 1) + json.dumps(key, ensure_ascii=False) + ': ' + readable_json(item, level + 1) for key, item in value.items()) + '\n' + '  ' * level + '}'
    if isinstance(value, (list, tuple)) and value and not all(scalar(item) for item in value):
        return '[\n' + ',\n'.join('  ' * (level + 1) + readable_json(item, level + 1) for item in value) + '\n' + '  ' * level + ']'
    return json.dumps(value, ensure_ascii=False)


def write_metadata(baked, parsed, data_dir=None, analysis_dir=None):
    data_dir = Path(data_dir) if data_dir is not None else DEST / 'data'
    analysis_dir = Path(analysis_dir) if analysis_dir is not None else ANALYSIS / 'animations'
    for key in set(baked) | set(parsed):
        if not re.fullmatch(r'[A-Za-z0-9_]+/[A-Za-z0-9_]+', key):
            raise ValueError('Invalid animation key: ' + key)
    # Publish manifests last; never delete unrelated data or hand-authored files.
    index = {}
    for key in sorted(baked):
        path = data_dir / 'actors' / (key + '.json')
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(readable_json(baked[key]) + '\n', 'utf-8', newline='\n')
        index[key] = 'res://assets/data/actors/' + key + '.json'
    data_dir.mkdir(parents=True, exist_ok=True)
    (data_dir / 'actors.json').write_text(json.dumps({'format_version': 2, 'actors': index}, ensure_ascii=False, indent=2) + '\n', 'utf-8', newline='\n')
    original_index = {}
    for key in sorted(parsed):
        path = analysis_dir / (key + '.json')
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(readable_json(parsed[key]) + '\n', 'utf-8', newline='\n')
        original_index[key] = key + '.json'
    analysis_dir.mkdir(parents=True, exist_ok=True)
    (analysis_dir / 'index.json').write_text(json.dumps({'format_version': 1, 'animations': original_index}, ensure_ascii=False, indent=2) + '\n', 'utf-8', newline='\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--metadata-only', action='store_true', help='Regenerate split JSON metadata without rewriting any textures/UI assets; requires decoded source PNGs.')
    args = parser.parse_args()
    if args.metadata_only:
        parsed, errors = read_animations()
        if errors: raise RuntimeError(f'Animation parse errors: {errors}')
        baked = build_actor_catalog(parsed, write_textures=False)
        write_metadata(baked, parsed)
        print(f'Metadata only: {len(baked)} actor shards; {len(parsed)} original ANI shards; textures unchanged')
        return
    manifest_path = ANALYSIS / 'image_manifest.json'
    spec = importlib.util.spec_from_file_location('decoder', ANALYSIS / 'decode_assets.py')
    decoder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(decoder)
    if not manifest_path.exists() or json.loads(manifest_path.read_text('utf-8')).get('decoder_version', 1) < 2:
        decoder.main()
    for name in ['actors', 'tiles', 'ui', 'data']:
        (DEST / name).mkdir(parents=True, exist_ok=True)
    atlas = Image.new('RGBA', (16 * 32, 16 * 24))
    tiles = sorted((ANALYSIS / 'decoded_png/ssjx/map').glob('tile*.png'), key=lambda p: int(p.stem[4:]))
    for path in tiles:
        index = int(path.stem[4:])
        im = Image.open(path).convert('RGBA')
        assert im.size == (16, 16)
        atlas.alpha_composite(im, ((index % 32) * 16, (index // 32) * 16))
    atlas.save(DEST / 'tiles' / 'original_tiles.png')
    # The decoder has already restored type-3 storage orientation.
    Image.open(ANALYSIS / 'decoded_png/ssjx/biaoti.png').save(DEST / 'ui' / 'title.png')
    cover = Image.new('RGB', (320, 480))
    for i in range(10):
        # The cover is a full-screen image, not a keyed sprite. Palette index
        # zero retains its original RGB565 background color here.
        part = Image.open(ANALYSIS / f'decoded_png/ssjx/fm{i + 1}.png').convert('RGB')
        assert part.size == (160, 96)
        cover.paste(part, ((i % 2) * 160, (i // 2) * 96))
    cover.save(DEST / 'ui' / 'original_cover.png')
    cover_text = [value for group in decoder.decode_str((ANALYSIS / 'unpacked/ssjx/cover.str').read_bytes()) for value in group]
    (DEST / 'data' / 'cover.json').write_text(json.dumps({'menu': cover_text[:9], 'help': cover_text[9], 'about': cover_text[10], 'quit': cover_text[11]}, ensure_ascii=False, indent=2), 'utf-8')
    for i in range(4):
        Image.open(ANALYSIS / f'decoded_png/ssjx/select_frame{i:03}.png').save(DEST / 'ui' / f'select_{i}.png')
    parsed, errors = read_animations()
    baked = build_actor_catalog(parsed)
    choices = []
    stems = ['mzs', 'wzs', 'mck', 'wck', 'mfs', 'wfs']
    head_stems = ['mzst1', 'wzst1', 'mckt1', 'wckt1', 'mfst2', 'wfst2']
    login_text = [value for group in decoder.decode_str((ANALYSIS / 'unpacked/ssjx/login.str').read_bytes()) for value in group]
    for i, (stem, head_stem) in enumerate(zip(stems, head_stems)):
        key = 'hero/' + stem
        preview_key = 'creation/' + stem
        head = Image.open(ANALYSIS / f'decoded_png/ssjx/hero/{head_stem}_frame000.png').convert('RGBA')
        # Original 32px portrait slots show the face; long hair is clipped at
        # the slot edge rather than squashing the whole head into the slot.
        bbox = head.getbbox()
        portrait = head.crop((bbox[0], bbox[1], bbox[0] + 30, bbox[1] + 30))
        portrait.save(DEST / 'ui' / f'create_portrait_{i}.png')
        choices.append({'job': i // 2, 'gender': i % 2, 'art': key,
                        'preview': preview_key, 'portrait': f'res://assets/ui/create_portrait_{i}.png',
                        'quote': login_text[3 + i]})
    (DEST / 'data' / 'creation.json').write_text(json.dumps({'choices': choices, 'descriptions': login_text[:3]}, ensure_ascii=False, indent=2), 'utf-8')
    creation_skin = {
        'create_scroll': 'bigscroll_frame000.png', 'create_scroll_marks': 'bigscroll_frame001.png',
        'create_header_end': 'bt1_frame000.png',
        'create_slot_male': 'sceneui_frame000.png', 'create_slot_female': 'sceneui_frame001.png',
        'create_cursor': 'neverpic_frame023.png', 'create_arrow': 'neverpic_frame025.png',
        'create_edit': 'neverpic_frame028.png',
    }
    for name, source_name in creation_skin.items():
        Image.open(ANALYSIS / 'decoded_png/ssjx' / source_name).save(DEST / 'ui' / (name + '.png'))
    for i in range(3):
        Image.open(ANALYSIS / f'decoded_png/ssjx/career_frame{i:03}.png').save(DEST / 'ui' / f'create_career_{i}.png')
    for name, source_name in {'attribute_coin': 'neverpic_frame014.png',
                              'attribute_ingot': 'neverpic_frame015.png',
                              'attribute_guild': 'neverpic_frame016.png',
                              'attribute_essence': 'neverpic_frame033.png',
                              'attribute_spiral': 'bt3_frame000.png'}.items():
        Image.open(ANALYSIS / 'decoded_png/ssjx' / source_name).save(DEST / 'ui' / (name + '.png'))
    for color, index in [('white', 3), ('green', 5)]:
        for frame in range(11):
            Image.open(ANALYSIS / f'decoded_png/ssjx/shuzi{index:02}_frame{frame:03}.png').save(DEST / 'ui' / f'digit_{color}_{frame:02}.png')
    for i in [5, 6, 7, 8, 9, 18, 25]:
        Image.open(ANALYSIS / f'decoded_png/ssjx/sceneui_frame{i:03}.png').save(DEST / 'ui' / f'scene_icon_{i}.png')
    Image.open(ANALYSIS / 'decoded_png/ssjx/neverpic_frame024.png').save(DEST / 'ui' / 'scene_target.png')
    for name, source_name in {'bag_sword': 'item/iw28.png', 'bag_potion': 'item/ix28.png',
                              'bag_corner': 'neverpic_frame019.png', 'scene_reward': 'sceneui_frame011.png'}.items():
        Image.open(ANALYSIS / 'decoded_png/ssjx' / source_name).save(DEST / 'ui' / (name + '.png'))
    write_metadata(baked, parsed)
    (DEST / 'data' / 'import_report.json').write_text(json.dumps({'decoded_png': 3300, 'tiles': len(tiles), 'parsed_animations': len(parsed), 'baked': list(baked), 'errors': errors}, ensure_ascii=False, indent=2), 'utf-8')
    # Copy a small set of original inventory/UI graphics; no redraws.
    for source in ['ssjx/item/yao1_frame000.png', 'ssjx/item/yao2_frame000.png']:
        path = ANALYSIS / 'decoded_png' / source
        if path.exists():
            Image.open(path).save(DEST / 'ui' / path.name)
    print(f'Tiles: {len(tiles)}; ANI parsed: {len(parsed)}; baked: {len(baked)}; unsupported: {len(errors)}')
    if errors:
        print(errors[:5])


if __name__ == '__main__':
    main()
