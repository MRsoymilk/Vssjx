"""Draw Unit-01-inspired pixel equipment on native frames; never change original art."""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'analysis/ai-generated/equipment/eva01'
OUTPUT = ROOT / 'client/assets/generated/equipment/eva01'
SLOTS = ['weapon', 'pendant', 'armor', 'wrist', 'belt', 'pants', 'boots', 'ring', 'necklace', 'hat']
LABELS = ['武器', '腰佩', '衣服', '手腕', '腰带', '裤子', '鞋子', '戒指', '项链', '帽子']
SUFFIXES = ['兵', '核心佩', '拘束甲', '护腕', '腰带', '战裤', '战靴', '指环', '项链', '独角盔']
SETS = [
    ('mzs', '初号·破阵', '高振动破障斧', 'ezs9'),
    ('wzs', '初号·镇岳', '高振动镇岳斧', 'ezs9'),
    ('mck', '初号·断界', '高振动短刃', 'eck9'),
    ('wck', '初号·疾刃', '高振动双刃', 'eck17'),
    ('mfs', '初号·共鸣', '力场共鸣杖', 'efs2'),
    ('wfs', '初号·觉醒', '力场觉醒杖', 'efs7'),
]
PALETTE = dict(black='#161823', dark='#30233f', shadow='#49316b', purple='#7850b4',
               light='#ad83df', green='#94eb45', lime='#d5ff7a', orange='#ed9048',
               white='#edf2db', steel='#83999e', red='#ae414b')
COLORS = {key: tuple(bytes.fromhex(value[1:])) + (255,) for key, value in PALETTE.items()}


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', 'utf-8')


def material(tile, body=False):
    """Keep native pixels/hand anchors, but replace skin/cloth with armored plates."""
    result = Image.new('RGBA', tile.size)
    bounds = tile.getbbox()
    if not bounds:
        return result
    left, top, right, bottom = bounds
    for y in range(top, bottom):
        for x in range(left, right):
            r, g, b, a = tile.getpixel((x, y))
            if not a:
                continue
            luma = (r * 3 + g * 6 + b) / 10
            color = 'black' if luma < 52 else 'shadow' if luma < 100 else 'purple' if luma < 175 else 'light'
            if body and y > top + (bottom - top) * .72:
                color = 'black' if luma < 110 else 'shadow'
            result.putpixel((x, y), COLORS[color])
    return result


def armor(tile, layer):
    image = material(tile, body=True)
    bounds = tile.getbbox()
    if not bounds:
        return image
    x, y, r, b = bounds
    w, h = r - x, b - y
    detail = Image.new('RGBA', tile.size)
    draw = ImageDraw.Draw(detail)
    # Consistent shoulder/cuff/leg seams, clipped to the exact native body mask.
    if layer == 'body':
        draw.line([(x, y+1), (x+w//3, y+1), (x+w//3, y+max(2, h//3))], fill=COLORS['green'], width=2)
        draw.line([(r-3, y+1), (r-3, y+max(2, h//3))], fill=COLORS['green'])
        draw.polygon([(x+w//2, y+2), (x+w//2+3, y+h//2), (x+w//2-1, y+h//2+1)], fill=COLORS['orange'])
        draw.line([(x+w//3, b-3), (x+2*w//3, b-3)], fill=COLORS['green'])
    elif layer == 'front':
        draw.line([(x+1, y+h//2), (r-2, y+h//2)], fill=COLORS['green'])
        draw.line([(x+1, y), (x+1, y+h//3)], fill=COLORS['light'])
    else:
        for fraction in (.25, .7):
            xx = x + int(w*fraction)
            draw.line([(xx, y+2), (xx, b-2)], fill=COLORS['purple'], width=2)
            draw.point((xx, y+h//2), fill=COLORS['green'])
        draw.line([(x+2, b-2), (r-2, b-2)], fill=COLORS['green'])
    detail.putalpha(Image.composite(detail.getchannel('A'), Image.new('L', tile.size), tile.getchannel('A')))
    image.alpha_composite(detail)
    return image


def helmet(tile, lower=False):
    image = material(tile)
    bounds = tile.getbbox()
    if not bounds:
        return image
    if lower:
        # Frame 1 is a lower hair/collar segment, NOT another head facing.
        # Preserve its complete alpha mask so every original ANI seam still joins.
        return armor(tile, 'back')
    left, top, right, bottom = bounds
    w, h = right-left, bottom-top
    result = Image.new('RGBA', tile.size)
    # Keep the native bottom seam as black/purple mechanical collar/cables.
    result.paste(image.crop((left, bottom-4, right, bottom)), (left, bottom-4))
    draw = ImageDraw.Draw(result)

    def points(values):
        return [(left+round(x*(w-1)), top+round(y*(h-1))) for x, y in values]

    def poly(values, fill, outline=None):
        draw.polygon(points(values), fill=COLORS[fill], outline=COLORS[outline] if outline else None)

    # Unit-01's single swept horn, purple shell, green temple and exposed jaw.
    poly([(.42, 0), (.60, .35), (.85, .39), (.98, .57), (.86, .85),
          (.62, .97), (.21, .88), (0, .68), (.14, .47), (.35, .34)], 'black')
    poly([(.44, .05), (.53, .35), (.36, .45), (.28, .40)], 'purple')
    draw.line(points([(.44, .09), (.47, .31)]), fill=COLORS['light'])
    poly([(.37, .38), (.67, .37), (.84, .48), (.75, .70), (.36, .83), (.12, .68), (.20, .47)], 'purple')
    poly([(.37, .40), (.60, .40), (.44, .51), (.23, .56), (.25, .46)], 'light')
    poly([(.63, .41), (.84, .44), (.92, .57), (.84, .74), (.69, .77), (.72, .55)], 'shadow')
    poly([(.74, .47), (.82, .48), (.86, .62), (.78, .67)], 'green')
    poly([(.21, .57), (.46, .53), (.60, .61), (.48, .77), (.30, .80), (.17, .68)], 'black')
    poly([(.20, .62), (.36, .59), (.30, .67)], 'white')
    poly([(.41, .60), (.53, .58), (.47, .66)], 'white')
    poly([(.27, .76), (.46, .73), (.49, .82), (.36, .90), (.25, .83)], 'steel')
    draw.line(points([(.30, .81), (.43, .79)]), fill=COLORS['black'])
    poly([(.53, .65), (.68, .58), (.67, .82), (.52, .88), (.43, .85)], 'purple')
    draw.line(points([(.58, .66), (.58, .81)]), fill=COLORS['light'])
    draw.point(points([(.34, .84)])[0], fill=COLORS['orange'])
    # Details must not widen the attachment seam after it has been copied.
    result.paste(image.crop((0, bottom-4, tile.width, tile.height)), (0, bottom-4))
    return result


def weapon(tile):
    image = material(tile)
    bounds = tile.getbbox()
    if not bounds:
        return image
    # Preserve every grip/end point and all native orientation transforms.
    left, top, right, bottom = bounds
    w, h = right-left, bottom-top
    for y in range(top, bottom):
        for x in range(left, right):
            if not tile.getpixel((x, y))[3]:
                continue
            r, g, b, _ = tile.getpixel((x, y))
            luma = (r+g+b)/3
            if luma > 180:
                image.putpixel((x, y), COLORS['white'])
            elif g > r*1.15 or (x-left > w*.55 and abs(y-(top+h*.5)) < max(1, h*.06)):
                image.putpixel((x, y), COLORS['green'])
            elif r > g*1.7 and r > b*1.2 and x-left < w*.16:
                image.putpixel((x, y), COLORS['orange'])
    return image


def icon(slot, main_head, main_weapon):
    image = Image.new('RGBA', (32, 32))
    d = ImageDraw.Draw(image)

    def poly(points, color='purple'):
        d.polygon(points, fill=COLORS[color], outline=COLORS['black'])

    if slot in ('hat', 'weapon'):
        source = main_head if slot == 'hat' else main_weapon
        source = source.crop(source.getbbox())
        if slot == 'weapon':
            source = source.rotate(35, resample=Image.Resampling.NEAREST, expand=True)
        source.thumbnail((28, 28), Image.Resampling.NEAREST)
        image.paste(source, ((32-source.width)//2, (32-source.height)//2), source)
    elif slot == 'armor':
        poly([(6, 3), (10, 3), (11, 9), (21, 9), (22, 3), (26, 3), (28, 16), (24, 18), (22, 28), (10, 28), (8, 18), (4, 16)])
        d.rectangle((6, 5, 9, 11), fill=COLORS['green'])
        d.rectangle((23, 5, 25, 11), fill=COLORS['green'])
        poly([(10, 13), (16, 16), (22, 13), (20, 22), (12, 22)], 'black')
        poly([(13, 10), (19, 10), (16, 16)], 'orange')
        d.line((11, 25, 21, 25), fill=COLORS['green'], width=2)
    elif slot in ('wrist', 'boots'):
        for x in (4, 18):
            if slot == 'boots':
                poly([(x+2, 4), (x+9, 4), (x+8, 20), (x+11, 23), (x+11, 27), (x, 27), (x, 22)])
                d.rectangle((x+3, 6, x+6, 16), fill=COLORS['light'])
                d.line((x+1, 22, x+8, 22), fill=COLORS['green'], width=2)
            else:
                poly([(x+1, 7), (x+10, 7), (x+9, 23), (x+2, 26), (x, 20)])
                d.line((x+3, 10, x+3, 20), fill=COLORS['green'], width=2)
                d.line((x+7, 10, x+7, 18), fill=COLORS['light'])
    elif slot == 'pants':
        poly([(7, 4), (25, 4), (26, 27), (18, 28), (16, 16), (14, 28), (6, 27)], 'black')
        for x in (9, 20):
            d.rectangle((x, 8, x+3, 24), fill=COLORS['purple'])
            d.rectangle((x, 17, x+3, 19), fill=COLORS['green'])
        d.line((9, 5, 23, 5), fill=COLORS['green'])
    elif slot == 'belt':
        poly([(3, 11), (27, 9), (29, 19), (5, 22)], 'black')
        d.line((5, 13, 27, 12), fill=COLORS['purple'], width=2)
        poly([(12, 10), (20, 10), (21, 19), (12, 20)])
        d.rectangle((14, 12, 18, 16), fill=COLORS['green'])
        d.point((16, 17), fill=COLORS['orange'])
    elif slot == 'pendant':
        d.line([(10, 3), (16, 8), (22, 3)], fill=COLORS['steel'])
        poly([(16, 8), (24, 13), (24, 23), (16, 28), (8, 23), (8, 13)])
        poly([(16, 12), (21, 15), (21, 21), (16, 25), (11, 21), (11, 15)], 'green')
        d.rectangle((15, 16, 17, 21), fill=COLORS['black'])
    elif slot == 'ring':
        d.ellipse((5, 8, 26, 28), fill=COLORS['black'], outline=COLORS['light'], width=2)
        d.ellipse((10, 13, 21, 24), fill=(0, 0, 0, 0), outline=COLORS['purple'], width=2)
        poly([(16, 3), (23, 8), (16, 14), (9, 8)], 'green')
        d.line((14, 6, 16, 5), fill=COLORS['lime'])
    else:
        d.line([(5, 4), (7, 15), (16, 25), (25, 15), (27, 4)], fill=COLORS['steel'], width=2)
        poly([(16, 16), (22, 22), (16, 29), (10, 22)], 'purple')
        poly([(16, 19), (19, 22), (16, 26), (13, 22)], 'orange')
    return image


def equipment_items():
    items = []
    for index, (stem, name, weapon_name, _) in enumerate(SETS):
        for slot, label, suffix in zip(SLOTS, LABELS, SUFFIXES):
            items.append(dict(id=f'ai/eva01/{stem}/{slot}', name=weapon_name if slot == 'weapon' else f'{name}·{suffix}',
                slot=slot, category=label, price=140 if slot == 'weapon' else 70,
                attack=14 if slot == 'weapon' else 0, defense=0 if slot == 'weapon' else 3,
                visual=40+index if slot == 'weapon' else 24+index if slot == 'armor' else 0,
                head_visual=22+index if slot == 'hat' else 0, level=1, job=index//2, gender=index%2,
                icon=f'res://assets/generated/equipment/eva01/{stem}/icons/{slot}.png',
                restore_hp=0, restore_mp=0, sections=['hot', 'rare'], set_id=f'eva01/{stem}', set_name=name,
                art_source='AI脚本像素绘制·EVA初号机同人参考',
                rules_basis='用户指定初号机主题；十槽属性及价格为重建玩法，无额外套装技能，不属于原包恢复',
                appearance_basis='紫黑拘束装甲、荧绿条带、独角全覆面盔；基于原生帧和握持点重绘。武器、衣服、头部独立换装，其余七槽仅影响属性。'))
    return items


def build():
    native = json.loads((ROOT / 'client/assets/data/hero-parts.json').read_text('utf-8'))
    sets, parts, report, inputs = [], {}, [], {}
    for index, (stem, name, weapon_name, weapon_source) in enumerate(SETS):
        recipe = native['recipes'][stem]
        sources = [stem+'t2', recipe['sources'][1], recipe['sources'][3], recipe['sources'][4], weapon_source]
        mapping, primary = {}, {}
        for order, source in enumerate(sources):
            spec = native['parts'][source]
            source_path = ROOT / 'client' / spec['texture'].removeprefix('res://')
            inputs[str(source_path.relative_to(ROOT))] = hashlib.sha256(source_path.read_bytes()).hexdigest()
            original = Image.open(source_path).convert('RGBA')
            image = Image.new('RGBA', original.size)
            for frame, (x, y, w, h) in enumerate(spec['frames']):
                tile = original.crop((x, y, x+w, y+h))
                if order == 0:
                    painted = helmet(tile, lower=frame > 0)
                elif order == 4:
                    painted = weapon(tile)
                else:
                    painted = armor(tile, ['body', 'front', 'back'][order-1])
                image.paste(painted, (x, y))
                if frame == 0:
                    primary[order] = painted
            path = OUTPUT / stem / 'parts' / (source+'.png')
            path.parent.mkdir(parents=True, exist_ok=True)
            image.save(path)
            part_id = f'eva01/{stem}/{source}'
            mapping[source] = part_id
            parts[part_id] = dict(texture='res://'+str(path.relative_to(ROOT/'client')), frames=spec['frames'])
            report.append(dict(path=parts[part_id]['texture'], sha256=hashlib.sha256(path.read_bytes()).hexdigest(), native_frames=spec['frames']))
        for slot in SLOTS:
            path = OUTPUT / stem / 'icons' / (slot+'.png')
            path.parent.mkdir(parents=True, exist_ok=True)
            icon(slot, primary[0], primary[4]).save(path)
            report.append(dict(path='res://'+str(path.relative_to(ROOT/'client')), sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
        sets.append(dict(id=f'eva01/{stem}', name=name, stem=stem, job=index//2, gender=index%2,
            weapon_code=40+index, clothing_code=24+index, head_code=22+index,
            head=mapping[sources[0]], body=[mapping[s] for s in sources[1:4]], weapon=mapping[weapon_source], weapon_name=weapon_name))
    write_json(ROOT/'client/assets/data/eva01-equipment.json', dict(format_version=1,
        source='AI脚本像素绘制；用户指定EVA初号机同人主题；原生人物分层适配，非官方授权素材', sets=sets, parts=parts))
    write_json(SOURCE/'runtime-import-report.json', report)
    write_json(SOURCE/'generation-record.json', dict(reference='用户文字指定：《新世纪福音战士》EVA初号机',
        method='Pillow确定性像素绘制；未使用外部图片生成服务，未复制官方标志或插画',
        features=['紫黑拘束装甲', '荧绿条带', '独角全覆面头盔', '白眼与金属下颌', '橙色核心点缀'],
        palette=PALETTE, generator='tools/build_eva01_equipment.py',
        generator_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), native_inputs=inputs,
        limitations='只改变三项现有外观编码；其余七槽提供属性，不增加AT力场或暴走技能。参考作品与原包素材权利分别核验。'))
    print('Generated EVA Unit-01 family: 6 sets, 30 native atlases, 60 transparent icons')


def migration():
    catalog = json.loads((ROOT/'client/assets/data/shop-v2.json').read_text('utf-8'))
    assert sum(item['id'].startswith('ai/eva01/') for item in catalog['items']) == 60
    quoted = lambda values: ','.join("'"+value.replace("'", "''")+"'" for value in values)
    lines = ['-- Add EVA Unit-01-inspired equipment; retain every previous inventory row.',
        'ALTER TABLE inventory_items DROP CONSTRAINT inventory_items_definition_id_check;',
        'ALTER TABLE inventory_items DROP CONSTRAINT inventory_items_check;',
        'ALTER TABLE inventory_items DROP CONSTRAINT equipment_quantity_one;',
        'DROP INDEX one_equipped_per_slot;', 'ALTER TABLE inventory_items DROP COLUMN equipment_slot;',
        'ALTER TABLE inventory_items ADD CONSTRAINT inventory_items_definition_id_check CHECK(definition_id IN ('+quoted([i['id'] for i in catalog['items']])+'));',
        'ALTER TABLE inventory_items ADD COLUMN equipment_slot TEXT GENERATED ALWAYS AS (CASE']
    for slot in SLOTS:
        lines.append(' WHEN definition_id IN ('+quoted([i['id'] for i in catalog['items'] if i['slot']==slot])+") THEN '"+slot+"'")
    lines += [' ELSE NULL END) STORED;',
        'ALTER TABLE inventory_items ADD CONSTRAINT inventory_items_check CHECK(NOT equipped OR (equipment_slot IS NOT NULL AND quantity=1));',
        'ALTER TABLE inventory_items ADD CONSTRAINT equipment_quantity_one CHECK(equipment_slot IS NULL OR quantity=1);',
        'CREATE UNIQUE INDEX one_equipped_per_slot ON inventory_items(character_id,equipment_slot) WHERE equipped;']
    (ROOT/'server/migrations/0023_eva01_equipment.sql').write_text('\n'.join(lines)+'\n', 'utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--migration', action='store_true', help='Generate the new migration after rebuilding the catalog')
    args = parser.parse_args()
    migration() if args.migration else build()
