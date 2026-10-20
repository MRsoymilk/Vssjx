"""Adapt the Unit-01 reference to original armor, faces and native animation frames."""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image
from eva01_native_style import PALETTE, COLORS, tint, headwear, weapon, icon, ICON_SOURCES

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'analysis/ai-generated/equipment/eva01'
OUTPUT = ROOT / 'client/assets/generated/equipment/eva01'
SLOTS = ['weapon', 'pendant', 'armor', 'wrist', 'belt', 'pants', 'boots', 'ring', 'necklace', 'hat']
LABELS = ['武器', '腰佩', '衣服', '手腕', '腰带', '裤子', '鞋子', '戒指', '项链', '帽子']
SUFFIXES = ['兵', '核心佩', '拘束甲', '护腕', '腰带', '战裤', '战靴', '指环', '项链', '碧玉冠']
SETS = [
    ('mzs', '初号·破阵', '高振动破障斧', 'ezs9'),
    ('wzs', '初号·镇岳', '高振动镇岳斧', 'ezs9'),
    ('mck', '初号·断界', '高振动短刃', 'eck9'),
    ('wck', '初号·疾刃', '高振动双刃', 'eck17'),
    ('mfs', '初号·共鸣', '力场共鸣杖', 'efs2'),
    ('wfs', '初号·觉醒', '力场觉醒杖', 'efs7'),
]

def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', 'utf-8', newline='\n')


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
                art_source='AI参考设计·原生装备适配·初号机主题',
                rules_basis='用户指定初号机主题；十槽属性及价格为重建玩法，无额外套装技能，不属于原包恢复',
                appearance_basis='原版七阶甲衣、原生人脸与发型、碧玉冠饰；紫甲和玉绿镶边依据AI参考设计适配。保留原始部件轮廓、肤色、动作及握持；武器、衣服、头部独立换装，其余七槽仅影响属性。'))
    return items


def build():
    native = json.loads((ROOT / 'client/assets/data/hero-parts.json').read_text('utf-8'))
    sets, parts, report, inputs = [], {}, [], {}
    old_manifest_path=ROOT/'client/assets/data/eva01-equipment.json'
    old_parts=json.loads(old_manifest_path.read_text('utf8'))['parts'] if old_manifest_path.exists() else {}
    for number in ICON_SOURCES.values():
        path=ROOT/f'client/assets/items/original/if{number}.png'
        inputs[path.relative_to(ROOT).as_posix()]=hashlib.sha256(path.read_bytes()).hexdigest()
    for index, (stem, name, weapon_name, weapon_source) in enumerate(SETS):
        sources = [stem+'t2', stem+'7', stem+'7q', stem+'7x', weapon_source]
        mapping, primary = {}, {}
        for order, source in enumerate(sources):
            spec = native['parts'][source]
            source_path = ROOT / 'client' / spec['texture'].removeprefix('res://')
            inputs[source_path.relative_to(ROOT).as_posix()] = hashlib.sha256(source_path.read_bytes()).hexdigest()
            original = Image.open(source_path).convert('RGBA')
            image = Image.new('RGBA', original.size)
            for frame, (x, y, w, h) in enumerate(spec['frames']):
                tile = original.crop((x, y, x+w, y+h))
                if order == 0:
                    painted = headwear(tile, stem, lower=frame > 0)
                elif order == 4:
                    painted = weapon(tile)
                else:
                    painted = tint(tile, stem[1:])
                image.paste(painted, (x, y))
                if frame == 0:
                    primary[order] = painted
            path = OUTPUT / stem / 'parts' / (source+'.png')
            path.parent.mkdir(parents=True, exist_ok=True)
            image.save(path)
            part_id = f'eva01/{stem}/{source}'
            mapping[source] = part_id
            parts[part_id] = dict(texture='res://'+path.relative_to(ROOT/'client').as_posix(), frames=spec['frames'])
            report.append(dict(path=parts[part_id]['texture'], sha256=hashlib.sha256(path.read_bytes()).hexdigest(), native_frames=spec['frames']))
        for slot in SLOTS:
            path = OUTPUT / stem / 'icons' / (slot+'.png')
            path.parent.mkdir(parents=True, exist_ok=True)
            icon(ROOT, slot, primary[4]).save(path)
            report.append(dict(path='res://'+path.relative_to(ROOT/'client').as_posix(), sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
        sets.append(dict(id=f'eva01/{stem}', name=name, stem=stem, job=index//2, gender=index%2,
            weapon_code=40+index, clothing_code=24+index, head_code=22+index,
            head=mapping[sources[0]], body=[mapping[s] for s in sources[1:4]], weapon=mapping[weapon_source], weapon_name=weapon_name))
    # Remove only obsolete atlases previously owned by this family.
    referenced={entry['texture'] for entry in parts.values()}
    for entry in old_parts.values():
        if entry['texture'].replace('\\','/') not in referenced:
            stale=(ROOT/'client'/entry['texture'].removeprefix('res://')).resolve()
            assert stale.is_relative_to(OUTPUT.resolve())
            stale.unlink(missing_ok=True)
    write_json(ROOT/'client/assets/data/eva01-equipment.json', dict(format_version=1,
        source='AI参考设计；原版七阶甲衣和原生人物分层适配；初号机同人配色', sets=sets, parts=parts))
    write_json(SOURCE/'runtime-import-report.json', report)
    write_json(SOURCE/'generation-record.json', dict(reference='用户要求参考原版装备美化初号机皮肤；refinement-v2/design-reference.png',
        method='内置image_gen生成设计参考；按原版部件材质分区适配，不将AI整身图缩放为帧；原始轮廓、肤色及图层坐标保持',
        features=['原版七阶甲衣结构', '紫黑分层甲片与褶皱', '适量玉绿镶边', '保留原生脸型与发型', '贴合发丝的碧玉冠饰'],
        palette=PALETTE, generator='tools/build_eva01_equipment.py',
        generator_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        style_module='tools/eva01_native_style.py', style_sha256=hashlib.sha256((ROOT/'tools/eva01_native_style.py').read_bytes()).hexdigest(), native_inputs=inputs,
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
