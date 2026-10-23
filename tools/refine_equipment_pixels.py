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

from PIL import Image

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
                color = EVA.get(pixel, pixel)
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
    native_parts = json.loads((ROOT/'client/assets/data/hero-parts.json').read_text('utf8'))['parts']
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
            pending[key] = refine_tile(image, family, stem, 'icon')
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
