"""Reconstructed free-destination travel talisman using an existing original icon."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ITEM_ID = 'restored/shenxing_scroll'


def catalog_item():
    return dict(id=ITEM_ID, name='神行符', slot='consumable', category='特殊',
                price=30, attack=0, defense=0, visual=0, head_visual=0, level=1,
                job=-1, gender=-1, restore_hp=0, restore_mp=0, effect='teleport',
                icon='res://assets/items/original/ix6.png', sections=['hot', 'rare'],
                art_source='原包图标', rules_basis='按用户要求重建：30铜钱一张，自选已开放地图，成功传送消耗一张。',
                appearance_basis='复用原包ix6符纸图标，尚未确认其原版道具身份。')


if __name__ == '__main__':
    path = ROOT/'client/assets/data/shop-v2.json'
    catalog = json.loads(path.read_text('utf8'))
    catalog['items'] = [item for item in catalog['items'] if item['id'] != ITEM_ID] + [catalog_item()]
    path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2)+'\n', encoding='utf8')
    if '--migration' in sys.argv:
        quoted = ','.join("'"+item['id'].replace("'", "''")+"'" for item in catalog['items'])
        sql = ('-- Add the reconstructed travel talisman without changing existing ownership.\n'
               'ALTER TABLE inventory_items DROP CONSTRAINT inventory_items_definition_id_check;\n'
               'ALTER TABLE inventory_items ADD CONSTRAINT inventory_items_definition_id_check '
               'CHECK(definition_id IN ('+quoted+'));\n')
        migration=ROOT/'server/migrations/0032_travel_scroll.sql'
        if migration.exists() and migration.read_text('utf8')!=sql:
            raise RuntimeError('Existing migration differs; add a new migration instead of rewriting history')
        migration.write_text(sql, encoding='utf8')
