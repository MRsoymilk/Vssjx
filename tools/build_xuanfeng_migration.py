"""Publish the next catalog-only migration without rewriting historical SQL."""
import argparse
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
TARGET=ROOT/'server/migrations/0044_xuanfeng_equipment.sql'


def sql():
    data=json.loads((ROOT/'client/assets/data/shop-v2.json').read_text('utf8'))
    items=data['items'];assert len(items)==519
    assert sum(i['id'].startswith('ai/xuanfeng/') for i in items)==60
    quote=lambda values:','.join("'"+v.replace("'","''")+"'" for v in values)
    lines=['-- Add six Xuanfeng outfits; preserve inventory rows, binding state and gourd constraints.',
        'ALTER TABLE inventory_items DROP CONSTRAINT inventory_items_definition_id_check;',
        'ALTER TABLE inventory_items DROP CONSTRAINT inventory_items_check;',
        'ALTER TABLE inventory_items DROP CONSTRAINT equipment_quantity_one;',
        'DROP INDEX one_equipped_per_slot;',
        'ALTER TABLE inventory_items DROP COLUMN equipment_slot;',
        'ALTER TABLE inventory_items ADD CONSTRAINT inventory_items_definition_id_check CHECK(definition_id IN ('+quote(i['id'] for i in items)+'));',
        'ALTER TABLE inventory_items ADD COLUMN equipment_slot TEXT GENERATED ALWAYS AS (CASE']
    for slot in data['slots']:
        lines.append(' WHEN definition_id IN ('+quote(i['id'] for i in items if i['slot']==slot)+") THEN '"+slot+"'")
    lines+=[' ELSE NULL END) STORED;',
        'ALTER TABLE inventory_items ADD CONSTRAINT inventory_items_check CHECK(NOT equipped OR (equipment_slot IS NOT NULL AND quantity=1));',
        'ALTER TABLE inventory_items ADD CONSTRAINT equipment_quantity_one CHECK(equipment_slot IS NULL OR quantity=1);',
        'CREATE UNIQUE INDEX one_equipped_per_slot ON inventory_items(character_id,equipment_slot) WHERE equipped;']
    return '\n'.join(lines)+'\n'


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true');args=parser.parse_args()
    text=sql()
    if args.check:assert TARGET.read_text('utf8')==text
    else:TARGET.write_text(text,'utf8')
    print('XUANFENG migration '+('matches' if args.check else 'generated'))
