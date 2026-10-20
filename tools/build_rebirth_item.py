"""Restore the original named respec pill using explicit reconstructed catalog rules."""
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
ITEM_ID = 'restored/rebirth_pill'


def catalog_item():
    return dict(
        id=ITEM_ID, name='重生再造丹', slot='consumable', category='药品',
        price=200, attack=0, defense=0, visual=0, head_visual=0, level=1,
        job=-1, gender=-1, restore_hp=0, restore_mp=0, effect='reset_attributes',
        icon='res://assets/items/original/ix64.png', sections=['hot', 'elixir'],
        art_source='原包图标',
        rules_basis='名称及重新分配属性点用途据原版tips0.txt第006条；售价200铜钱及消耗规则为重建玩法。',
        appearance_basis='复用原包ix64丹丸状图标作为重建映射，尚未确认此图标就是原版重生再造丹。'
    )


def migration():
    catalog = json.loads((ROOT/'client/assets/data/shop-v2.json').read_text('utf8'))
    assert sum(item['id'] == ITEM_ID for item in catalog['items']) == 1
    quoted = ','.join("'"+item['id'].replace("'", "''")+"'" for item in catalog['items'])
    sql = (
        '-- Add the original named respec consumable; keep existing slots and inventory.\n'
        'ALTER TABLE inventory_items DROP CONSTRAINT inventory_items_definition_id_check;\n'
        'ALTER TABLE inventory_items ADD CONSTRAINT inventory_items_definition_id_check '
        'CHECK(definition_id IN ('+quoted+'));\n'
    )
    # It is a consumable: the existing generated slot CASE correctly yields NULL.
    (ROOT/'server/migrations/0029_rebirth_pill.sql').write_text(sql, encoding='utf8', newline='\n')


if __name__ == '__main__' and '--migration' in sys.argv:
    migration()
