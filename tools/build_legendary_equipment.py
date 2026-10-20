"""Standalone approved weapons; no replacement of recovered original items."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ITEM_ID = 'ai/legendary/potian_axe'
VISUAL = 46


def equipment_items():
    return [dict(
        id=ITEM_ID, name='破天斧', slot='weapon', category='武器',
        price=250, attack=20, defense=0, visual=VISUAL, head_visual=0,
        level=1, reference_level=51, job=0, gender=-1,
        icon='res://assets/generated/equipment/legendary/potian-icon.png',
        restore_hp=0, restore_mp=0, sections=['hot', 'rare'],
        set_id='legendary/potian_axe', set_name='传世兵器', art_source='AI生成',
        rules_basis='用户确认破天斧图；参考表记载力士、51级。当前与重建商城一致不设等级门槛，售价250铜钱、攻击20为重建规则。',
        appearance_basis='使用用户确认的斧头图片，按原版力士握持点适配两帧；男女力士共用，可与原版及新增衣服、头饰混穿。'
    )]


def build():
    native = json.loads((ROOT/'client/assets/data/hero-parts.json').read_text('utf8'))
    part = dict(texture='res://assets/generated/equipment/legendary/potian-axe.png',
                frames=native['parts']['ezs9']['frames'])
    manifest = dict(format_version=1, source='用户确认AI还原图片；原版力士武器坐标适配',
                    sets=[], weapons=[
                        dict(id='legendary/potian_axe', name='破天斧', stem=stem,
                             job=0, gender=gender, weapon_code=VISUAL,
                             weapon='legendary/potian_axe')
                        for gender, stem in enumerate(['mzs', 'wzs'])
                    ], parts={'legendary/potian_axe': part})
    (ROOT/'client/assets/data/legendary-equipment.json').write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf8', newline='\n')


def migration():
    """New migration only: preserve old inventory IDs and slot uniqueness."""
    catalog = json.loads((ROOT/'client/assets/data/shop-v2.json').read_text('utf8'))
    assert sum(item['id'] == ITEM_ID for item in catalog['items']) == 1
    quoted = lambda values: ','.join("'"+value.replace("'", "''")+"'" for value in values)
    lines = [
        '-- Add approved Potian axe; retain all existing inventory and slot constraints.',
        'ALTER TABLE inventory_items DROP CONSTRAINT inventory_items_definition_id_check;',
        'ALTER TABLE inventory_items DROP CONSTRAINT inventory_items_check;',
        'ALTER TABLE inventory_items DROP CONSTRAINT equipment_quantity_one;',
        'DROP INDEX one_equipped_per_slot;',
        'ALTER TABLE inventory_items DROP COLUMN equipment_slot;',
        'ALTER TABLE inventory_items ADD CONSTRAINT inventory_items_definition_id_check CHECK(definition_id IN ('+quoted(i['id'] for i in catalog['items'])+'));',
        'ALTER TABLE inventory_items ADD COLUMN equipment_slot TEXT GENERATED ALWAYS AS (CASE'
    ]
    for slot in catalog['slots']:
        lines.append(' WHEN definition_id IN ('+quoted(i['id'] for i in catalog['items'] if i['slot']==slot)+") THEN '"+slot+"'")
    lines += [
        ' ELSE NULL END) STORED;',
        'ALTER TABLE inventory_items ADD CONSTRAINT inventory_items_check CHECK(NOT equipped OR (equipment_slot IS NOT NULL AND quantity=1));',
        'ALTER TABLE inventory_items ADD CONSTRAINT equipment_quantity_one CHECK(equipment_slot IS NULL OR quantity=1);',
        'CREATE UNIQUE INDEX one_equipped_per_slot ON inventory_items(character_id,equipment_slot) WHERE equipped;'
    ]
    (ROOT/'server/migrations/0027_potian_equipment.sql').write_text('\n'.join(lines)+'\n', encoding='utf8', newline='\n')


if __name__ == '__main__':
    migration() if '--migration' in sys.argv else build()
