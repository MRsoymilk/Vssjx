"""Refine existing native pixels from immutable inputs, including editor overrides.

No resampling of animation parts: masks, frame rectangles and facial pixels stay
on their authored coordinates. Run --snapshot once for newly selected sets, then
rebuild from the saved inputs rather than repeatedly grading the output.
"""
import argparse
import colorsys
import hashlib
import io
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'analysis/ai-generated/equipment/pixel-refinement'
FAMILIES = ('boneglow', 'gravebloom', 'eva01')
OVERRIDES = ROOT / 'client/assets/appearance_resources/overrides.tres'


def colors(values):
    return [tuple(bytes.fromhex(value)) + (255,) for value in values.split()]


CLOTH = colors('191b28 303144 4b4b60 6b687a 96909c c5bdc5')
BONE = colors('302a2a 615240 998163 c8b38b ebdcb4 fff3d4')
GOLD = colors('302330 654636 9e7144 cd9c57 edc887 fff0bd')
STEEL = colors('202332 41495b 68788b 97abb7 c6d9dd eff9ef')
ACCENTS = {
    'mzs': colors('2b2030 623331 a55035 c67948 eca269 ffdda0'),
    'wzs': colors('291b28 582332 90293c c93e50 ef696e ffc2a7'),
    'mck': colors('241e33 49305c 754b8a a477b5 d3acd9 f3dcf3'),
    'wck': colors('172c3a 28536b 3c829e 63b5c9 a0e2e7 e4fff4'),
    'mfs': colors('172d2d 2d5047 47876a 73b995 aee5bf e8ffdc'),
    'wfs': colors('202d37 3b5761 5b8994 8ab9bd bce6df efffef'),
}
JADE = colors('182c29 2b503e 4b7950 79ac60 b2d78d e8f6c2')
FLAME = colors('392336 713136 ae542e e68d36 ffc864 fff0b1')
EVA = {
    '302336': '231e33', '44324f': '3b2e51', '584267': '5c4379',
    '775790': '8965a9', 'ad8fc1': 'bb97d5', 'd3bddc': 'e8d3ed',
    '90c65a': '8bbd79', 'd4eca0': 'd3edaa', '4c713e': '3f6850',
    'd8a254': 'd8ac6b', 'f0e7e1': 'fff3df', 'b3a9be': 'bdc5d5',
    'a75c70': 'b66c83',
}
EVA = {colors(key)[0]: colors(value)[0] for key, value in EVA.items()}
EVA_ROLES = {
    'ck': {'302336':'211f30', '44324f':'353046', '584267':'534663',
           '775790':'806493', 'ad8fc1':'b6a0c9', 'd3bddc':'e2d9ec',
           '90c65a':'76c0a0', 'd4eca0':'c7f1d1', '4c713e':'365c51',
           'd8a254':'b8c7c4'},
    'fs': {'302336':'282238', '44324f':'493657', '584267':'6d4f7d',
           '775790':'986cad', 'ad8fc1':'c79bd9', 'd3bddc':'efd8f1',
           '90c65a':'91cbb2', 'd4eca0':'d8f4ce', '4c713e':'416956',
           'd8a254':'dfba7f'},
}
EVA_ROLES = {role: {colors(key)[0]: colors(value)[0] for key, value in entries.items()}
             for role, entries in EVA_ROLES.items()}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', 'utf8')


def local(path):
    return ROOT / 'client' / path.removeprefix('res://')


def saved_overrides():
    return json.loads(OVERRIDES.read_text('utf8').split('parts = ', 1)[1])


def definitions():
    result = {}
    for family in FAMILIES:
        manifest = json.loads((ROOT/f'client/assets/data/{family}-equipment.json').read_text('utf8'))
        for row in manifest['sets']:
            result[row['id']] = (row, manifest['parts'])
    return result


def skin(pixel):
    r, g, b, a = pixel
    return a and r >= 180 and 95 <= g <= 225 and .46*r <= b <= .93*r and g >= b-14 and r > g*1.06


def luma(pixel):
    return (pixel[0]*3 + pixel[1]*6 + pixel[2])/10


def material(pixel, family, stem, head):
    r, g, b, _ = pixel
    h, s, v = colorsys.rgb_to_hsv(r/255, g/255, b/255)
    if family == 'gravebloom':
        if head and stem == 'wfs' and .025 < h < .19 and s > .5:
            return FLAME
        if .17 < h < .48 and s > .3:
            return JADE
    else:
        match = {'mzs': (h < .085 or h > .95) and r > g*1.4,
                 'wzs': (h < .065 or h > .90) and r > g*1.45,
                 'mck': .65 < h < .90, 'wck': .45 < h < .68,
                 'mfs': .23 < h < .49, 'wfs': .35 < h < .65}[stem]
        if match and s > .23:
            return ACCENTS[stem]
    if .065 < h < .19 and s > .28:
        return GOLD
    if v > .45 and s < .28:
        return BONE if r >= b else STEEL
    return CLOTH


def refine_tile(tile, family, stem, kind, native=None):
    result = tile.copy()
    bounds = tile.getchannel('A').getbbox()
    if bounds is None:
        return result
    face = None
    if kind == 'head':
        # Protect the whole face, including eyes/mouth between flesh pixels.
        flesh = [(x, y) for y in range(tile.height) for x in range(tile.width)
                 if skin(tile.getpixel((x, y)))]
        if flesh:
            face = (min(p[0] for p in flesh), min(p[1] for p in flesh),
                    max(p[0] for p in flesh)+1, max(p[1] for p in flesh)+1)
    for y in range(tile.height):
        for x in range(tile.width):
            pixel = tile.getpixel((x, y))
            if not pixel[3] or (kind != 'icon' and skin(pixel)):
                continue
            if kind == 'head':
                if y >= bounds[3]-3 or (face and face[0] <= x < face[2] and face[1] <= y < face[3]):
                    continue
                if native is not None and pixel == native.getpixel((x, y)):
                    continue
            if family == 'eva01':
                color = EVA_ROLES.get(stem[1:], {}).get(pixel, EVA.get(pixel, pixel))
            else:
                ramp = material(pixel, family, stem, kind == 'head')
                light = luma(pixel)
                level = sum(light >= threshold for threshold in (34, 65, 103, 146, 195))
                # One-pixel upper bevel inside an existing dark contour.
                if kind in ('body', 'weapon', 'icon') and y >= 2 and light > 65:
                    above = tile.getpixel((x, y-1))
                    if above[3] and luma(above) < 40 and not tile.getpixel((x, y-2))[3]:
                        level = min(5, level+1)
                graded = ramp[level]
                # Retain subtle authored shading; consolidate only within a material.
                color = tuple(round(pixel[i]*.22 + graded[i]*.78) for i in range(3)) + (pixel[3],)
            result.putpixel((x, y), color)
    return result


def refine_part(image, row, part, source, native_parts):
    family, stem = row['id'].split('/')
    kind = 'head' if source == row['head'] else 'weapon' if source == row['weapon'] else 'body'
    result = image.copy()
    native = None
    if family == 'eva01' and kind == 'head':
        native = Image.open(local(native_parts[source.rsplit('/', 1)[1]]['texture'])).convert('RGBA')
    for index, (x, y, w, h) in enumerate(part['frames']):
        if kind == 'head' and index > 0:
            continue  # The lower hair/neck attachment keeps its authored seam pixels.
        rect = (x, y, x+w, y+h)
        tile = refine_tile(image.crop(rect), family, stem, kind, None if native is None else native.crop(rect))
        result.paste(tile, (x, y))
    return result


def eva_icon(stem, slot):
    """Authored 32px silhouettes: plate, light leather and long ritual robes.

    Palette and jade motifs match the worn outfit. Draw directly on the icon
    grid so shoulders, clasps and gems remain readable at backpack scale.
    """
    image = Image.new('RGBA', (32, 32))
    draw = ImageDraw.Draw(image)
    role = stem[1:]; female = stem.startswith('w')
    def shade(key):
        pixel = colors(key)[0]
        return EVA_ROLES.get(role, {}).get(pixel, EVA.get(pixel, pixel))
    ink, dark, mid, light, pearl = [shade(key) for key in ('302336','44324f','775790','ad8fc1','d3bddc')]
    jade, green, gleam, gold = [shade(key) for key in ('4c713e','90c65a','d4eca0','d8a254')]
    def shape(points, fill):draw.polygon(points, fill=fill, outline=ink)
    def line(points, fill, width=1):draw.line(points, fill=fill, width=width)
    def gem(x, y, radius=3):
        shape([(x,y-radius-1),(x+radius,y),(x,y+radius+1),(x-radius,y)], gold)
        draw.polygon([(x,y-radius),(x+radius-1,y),(x,y+radius),(x-radius+1,y)],fill=jade)
        line([(x,y-radius+1),(x-radius+1,y),(x,y)],green)
        draw.point((x,y-radius+1),fill=gleam)

    if slot == 'armor':
        if role == 'zs':
            shape([(10,4),(14,7),(18,7),(22,4),(28,9),(26,16),(23,15),
                   (22 if female else 24,27),(18,29),(16,25),(14,29),(8 if female else 7,27),
                   (9,15),(5,16),(3,9)],dark)
            shape([(5,9),(10,5),(13,9),(11,14),(5,13)],mid)
            shape([(19,9),(22,5),(26,9),(25,13),(21,14)],mid)
            line([(5,9),(10,6),(12,9)],pearl);line([(21,8),(23,7),(26,10)],light)
            shape([(11,11),(16,13),(21,11),(20,19),(16,21),(12,19)],mid)
            line([(12,12),(15,14),(15,18)],light);line([(17,14),(20,12)],pearl)
            shape([(11,21),(15,21),(14,27),(9,26)],mid)
            shape([(17,21),(21,21),(23,26),(18,27)],mid)
            line([(10,25),(13,23)],green);line([(19,23),(21,25)],green)
        elif role == 'ck':
            shape([(11,4),(15,7),(20,4),(25,9),(23,14),(21,13),(21,19),
                   (25,28),(18,26),(16,22),(13,28),(6,28),(10,18),(10,13),(7,14),(6,9)],dark)
            shape([(10,7),(14,9),(14,18),(11,20),(8,11)],mid)
            shape([(17,8),(20,6),(23,10),(20,15),(19,19),(16,18)],mid)
            line([(10,7),(13,10),(13,17)],pearl);line([(19,7),(17,11),(17,17)],green)
            shape([(11,21),(15,21),(12,26),(8,26)],mid)
            line([(18,21),(21,25)],light)
            if female:line([(22,10),(24,11)],green)
        else:
            shape([(11,4),(15,6),(19,4),(23,8),(29,15),(24,18),(21,14),
                   (24,29),(8,29),(11,14),(7,18),(2,15),(8,8)],dark)
            shape([(9,8),(12,10),(9,14),(6,16),(4,14)],mid)
            shape([(20,9),(23,9),(27,14),(24,16),(21,12)],mid)
            shape([(13,9),(18,8),(20,19),(17,27),(10,27)],mid)
            line([(12,6),(16,10),(19,6)],gold)
            line([(13,10),(16,13),(18,11)],pearl)
            line([(12,21),(10,27),(15,27)],green)
            line([(20,20),(22,27)],light)
            line([(5,14),(7,16),(10,12)],green)
        line([(11,20),(21,20)],gold);gem(16,20,2)
    elif slot == 'hat':
        # Small jade hair ornaments, matching the visible crest rather than a helmet.
        if role == 'zs':
            shape([(5,17),(7,10),(11,14),(15,6),(20,14),(25,10),(26,17),(22,22),(9,22)],dark)
            line([(7,16),(11,18),(21,18),(25,15)],gold,2)
            line([(9,20),(22,20)],light);gem(16,14,4 if not female else 3)
            line([(8,12),(10,15)],green);line([(23,12),(22,15)],green)
        elif role == 'ck':
            shape([(7,21),(8,12),(13,16),(17,5),(20,7),(20,15),(25,10),(27,13),(23,21)],dark)
            line([(10,18),(16,8),(17,13),(22,10)],pearl)
            line([(9,22),(24,22)],gold);gem(16 if not female else 18,18,3)
            line([(11,23),(10,27)],jade);draw.point((10,26),fill=gleam)
        else:
            shape([(6,19),(9,11),(15,7),(21,10),(25,18),(21,22),(10,22)],dark)
            line([(8,17),(11,12),(16,10),(21,13),(23,18)],gold)
            gem(16,15,4)
            for x in (10,22):
                line([(x,22),(x,27)],gold);draw.rectangle((x-1,25,x+1,27),fill=green)
            if female:line([(7,20),(5,24)],light)
    elif slot == 'wrist':
        for x,y in ((4,6),(18,12)):
            shape([(x,y),(x+8,y-2),(x+10,y+3),(x+8,y+12),(x+3,y+14),(x-1,y+9)],dark)
            shape([(x+1,y+2),(x+7,y),(x+7,y+9),(x+3,y+11)],mid)
            line([(x+1,y+2),(x+6,y)],pearl)
            line([(x+1,y+5),(x+8,y+3)],green,2)
            line([(x+3,y+10),(x+6,y+9)],gold)
    elif slot == 'belt':
        shape([(3,10),(9,8),(23,8),(29,10),(27,19),(20,21),(11,20),(4,18)],dark)
        line([(5,11),(11,10),(22,10),(27,12)],light)
        line([(5,17),(12,18),(23,18),(27,16)],gold)
        shape([(12,19),(17,20),(15,29),(11,27)],mid)
        line([(13,22),(13,27)],green);gem(17,15,4)
    elif slot == 'pants':
        shape([(8,4),(24,4),(25,14),(27,27),(18,29),(16,17),(14,28),(5,27),(7,14)],dark)
        shape([(9,8),(14,8),(14,16),(11,26),(7,25)],mid)
        shape([(18,8),(22,8),(23,15),(25,26),(20,27)],mid)
        line([(9,10),(9,16),(8,24)],light);line([(21,10),(21,16),(23,24)],green)
        line([(9,6),(23,6)],gold);draw.point((16,6),fill=gleam)
    elif slot == 'boots':
        for x,y in ((4,4),(17,9)):
            shape([(x+2,y),(x+10,y),(x+9,y+11),(x+12,y+15),(x+10,y+18),(x-1,y+18),(x-2,y+14),(x+2,y+10)],dark)
            shape([(x+3,y+3),(x+8,y+3),(x+7,y+12),(x+1,y+14)],mid)
            line([(x+3,y+4),(x+3,y+10)],light)
            line([(x+2,y+2),(x+9,y+2)],green,2)
            line([(x,y+15),(x+8,y+15),(x+10,y+16)],gold)
            line([(x,y+17),(x+8,y+17)],pearl)
    elif slot == 'ring':
        draw.ellipse((5,8,26,29),fill=ink)
        draw.ellipse((6,9,25,28),fill=gold)
        draw.ellipse((9,12,22,25),fill=dark)
        draw.ellipse((11,13,21,24),fill=(0,0,0,0))
        draw.arc((6,9,25,28),75,210,fill=pearl,width=2)
        shape([(14,4),(23,4),(27,9),(23,15),(15,14),(11,9)],mid)
        gem(19,9,4);draw.point((7,17),fill=gleam)
    elif slot == 'pendant':
        line([(13,3),(16,6),(19,3)],gold,2)
        draw.ellipse((13,6,19,11),outline=light)
        shape([(16,10),(24,17),(16,25),(8,17)],mid)
        gem(16,17,5);line([(16,25),(16,29)],gold)
        line([(14,26),(13,29)],jade);line([(18,26),(19,29)],green)
    elif slot == 'necklace':
        line([(5,6),(4,12),(7,19),(12,23),(20,23),(25,19),(28,12),(27,6)],ink,3)
        line([(5,6),(5,12),(8,18),(13,22),(19,22),(24,18),(27,12),(27,6)],gold)
        for x,y in ((5,9),(6,14),(9,19),(23,19),(26,14),(27,9)):
            draw.rectangle((x-1,y-1,x+1,y+1),fill=mid)
            draw.point((x-1,y-1),fill=pearl)
        gem(16,23,4)
    else:
        raise ValueError(slot)
    return image


def snapshot(selected, all_sets):
    path = DATA/'baseline.json'
    data = json.loads(path.read_text('utf8')) if path.exists() else {'textures': {}, 'overrides': {}}
    overrides = saved_overrides()
    for set_id in selected:
        row, parts = all_sets[set_id]
        family, stem = set_id.split('/')
        paths = [local(parts[source]['texture']) for source in [row['head'], *row['body'], row['weapon']]]
        paths += sorted((ROOT/f'client/assets/generated/equipment/{family}/{stem}/icons').glob('*.png'))
        for source in paths:
            key = source.relative_to(ROOT).as_posix()
            if key in data['textures']:
                continue
            target = DATA/'inputs'/family/stem/source.parent.name/source.name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.read_bytes())
            data['textures'][key] = {'input': target.relative_to(ROOT).as_posix(), 'sha256': digest(target)}
        for source in [row['head'], *row['body'], row['weapon']]:
            if source in overrides and source not in data['overrides']:
                entry = overrides[source]
                data['overrides'][source] = dict(entry, sha256=digest(local(entry['texture'])))
    write_json(path, data)


def build(selected, all_sets, check=False):
    baseline = json.loads((DATA/'baseline.json').read_text('utf8'))
    report_path = DATA/'refinement.json'
    report = json.loads(report_path.read_text('utf8')) if report_path.exists() else {'sets': [], 'textures': {}, 'overrides': {}}
    native = json.loads((ROOT/'client/assets/data/hero-parts.json').read_text('utf8'))
    native_parts = native['parts']
    overrides = saved_overrides()
    override_text = OVERRIDES.read_text('utf8')
    family_reports = {}
    pending = {}
    for set_id in selected:
        row, parts = all_sets[set_id]
        family, stem = set_id.split('/')
        for source in [row['head'], *row['body'], row['weapon']]:
            key = local(parts[source]['texture']).relative_to(ROOT).as_posix()
            record = baseline['textures'][key]
            assert digest(ROOT/record['input']) == record['sha256'], 'Changed refinement input: '+key
            image = Image.open(ROOT/record['input']).convert('RGBA')
            pending[key] = refine_part(image, row, parts[source], source, native_parts)
            if source in baseline['overrides']:
                entry = baseline['overrides'][source]
                assert digest(local(entry['texture'])) == entry['sha256']
                previous = report['overrides'].get(source, entry)
                assert overrides.get(source) in [dict(texture=entry['texture'], offsets=entry['offsets']), dict(texture=previous['texture'], offsets=entry['offsets'])], 'Editor override changed: '+source
                image = Image.open(local(entry['texture'])).convert('RGBA')
                refined = refine_part(image, row, parts[source], source, native_parts)
                buffer = io.BytesIO(); refined.save(buffer, format='PNG')
                checksum = hashlib.sha256(buffer.getvalue()).hexdigest()
                path = 'res://assets/edited/equipment/'+hashlib.sha256(source.encode()).hexdigest()[:12]+'-'+checksum[:20]+'.png'
                pending[local(path).relative_to(ROOT).as_posix()] = refined
                override_text = override_text.replace(overrides[source]['texture'], path)
                report['overrides'][source] = dict(texture=path, offsets=entry['offsets'], sha256=checksum)
        for path in sorted((ROOT/f'client/assets/generated/equipment/{family}/{stem}/icons').glob('*.png')):
            key = path.relative_to(ROOT).as_posix(); record = baseline['textures'][key]
            assert digest(ROOT/record['input']) == record['sha256']
            image = Image.open(ROOT/record['input']).convert('RGBA')
            pending[key] = (eva_icon(stem, path.stem)
                            if family == 'eva01' and path.stem != 'weapon'
                            else refine_tile(image, family, stem, 'icon'))
        if set_id not in report['sets']:
            report['sets'].append(set_id)
        family_reports[family] = json.loads((ROOT/f'analysis/ai-generated/equipment/{family}/runtime-import-report.json').read_text('utf8'))
    # Validate the complete target set before writing any production texture.
    for key in pending:
        if key in baseline['textures']:
            assert digest(ROOT/key) in (baseline['textures'][key]['sha256'], report['textures'].get(key)), 'Unexpected production edit: '+key
    if check:
        for key, image in pending.items():
            buffer = io.BytesIO(); image.save(buffer, format='PNG')
            assert hashlib.sha256(buffer.getvalue()).hexdigest() == digest(ROOT/key), 'Non-reproducible pixels: '+key
        assert override_text == OVERRIDES.read_text('utf8'), 'Editor override is not applied'
        print(f'Reproducible refinement: {len(selected)} sets, {len(pending)} textures')
        return
    for key, image in pending.items():
        image.save(ROOT/key)
        if key in baseline['textures']:
            report['textures'][key] = digest(ROOT/key)
    if override_text != OVERRIDES.read_text('utf8'):
        OVERRIDES.write_text(override_text, 'utf8')
    for family, rows in family_reports.items():
        for record in rows:
            key = local(record['path']).relative_to(ROOT).as_posix()
            if key in report['textures']:
                record['sha256'] = report['textures'][key]
        write_json(ROOT/f'analysis/ai-generated/equipment/{family}/runtime-import-report.json', rows)
    report['generator'] = 'tools/refine_equipment_pixels.py'
    report['generator_sha256'] = digest(Path(__file__))
    write_json(report_path, report)
    print(f'Refined {len(selected)} sets; {len(pending)} textures, including active editor overrides')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sets', nargs='+', help='Family/stem IDs; defaults to every additional set')
    parser.add_argument('--snapshot', action='store_true', help='Capture immutable inputs for selected sets before refinement')
    parser.add_argument('--check', action='store_true', help='Rebuild in memory and verify byte-identical production pixels')
    args = parser.parse_args()
    all_sets = definitions()
    selected = args.sets or list(all_sets)
    if any(key not in all_sets for key in selected):
        parser.error('Unknown set ID')
    if args.snapshot and args.check:
        parser.error('--snapshot and --check cannot be combined')
    if args.snapshot:
        snapshot(selected, all_sets)
    build(selected, all_sets, args.check)
