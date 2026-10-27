"""Upgrade an isolated pre-Xuanfeng database without changing old inventory/state."""
import json
from pathlib import Path
from uuid import uuid4
from pg_fixture import PostgresFixture

ROOT=Path(__file__).resolve().parents[1]


def main():
    catalog=json.loads((ROOT/'client/assets/data/shop-v2.json').read_text('utf8'))['items']
    previous=[i for i in catalog if not i['id'].startswith('ai/xuanfeng/')]
    added=[i for i in catalog if i['id'].startswith('ai/xuanfeng/')]
    assert len(previous)==459 and len(added)==60
    checks=0
    def check(ok,message):
        nonlocal checks
        assert ok,message
        checks+=1
    with PostgresFixture() as db:
        for path in sorted((ROOT/'server/migrations').glob('*.sql')):
            if int(path.name[:4])<44:db.query(path.read_text('utf8'))
        account,character=str(uuid4()),str(uuid4())
        db.query(f"INSERT INTO accounts(id,username,password_hash) VALUES('{account}','xuanfeng_upgrade','fixture');")
        db.query(f"""INSERT INTO characters(id,account_id,display_name,name_key,name_rules_version,rules_version,
            job,gender,school,hp,mp,gourd_state,loot_state) VALUES('{character}','{account}',
            '旧装测试','旧装测试','nickname-v1','creation-v1',0,0,0,100,50,
            '{{"hp":250,"mp":100}}','{{"items":[],"pending":[],"fixture":"preserve-binding-state"}}');""")
        def insert(items):
            values=','.join(f"('{uuid4()}','{character}','{i['id']}',1,{str(i['id'].startswith('ai/boneglow/mzs/')).lower()})" for i in items)
            db.query('INSERT INTO inventory_items(id,character_id,definition_id,quantity,equipped) VALUES '+values+';')
        insert(previous)
        query="SELECT jsonb_agg(to_jsonb(i) ORDER BY definition_id)::text FROM inventory_items i"
        before=db.query(query);old_character=db.query('SELECT to_jsonb(c)::text FROM characters c')
        db.query((ROOT/'server/migrations/0044_xuanfeng_equipment.sql').read_text('utf8'))
        check(db.query(query)==before,'all 459 prior rows, UUIDs, slots, quantities and equipped state survive')
        check(db.query('SELECT to_jsonb(c)::text FROM characters c')==old_character,'binding/instance/gourd and other character state survive')
        insert(added)
        rows=dict(line.split('|') for line in db.query("SELECT definition_id,coalesce(equipment_slot,'') FROM inventory_items").splitlines())
        for item in catalog:
            expected=item['slot'] if item['slot'] in ['weapon','pendant','armor','wrist','belt','pants','boots','ring','necklace','hat'] else ''
            check(rows[item['id']]==expected,'generated slot '+item['id'])
        def rejected(sql,condition):
            nonlocal checks
            db.query('DO $$ BEGIN '+sql+"; RAISE EXCEPTION 'unexpected acceptance'; EXCEPTION WHEN "+condition+' THEN NULL; END $$;')
            checks+=1
        rejected("UPDATE inventory_items SET equipped=true WHERE definition_id='ai/xuanfeng/mzs/armor'",'unique_violation')
        rejected("UPDATE inventory_items SET quantity=2 WHERE definition_id='ai/xuanfeng/mzs/weapon'",'check_violation')
        for gourd in ['hp','mp']:
            rejected(f"UPDATE inventory_items SET quantity=2 WHERE definition_id='supply/{gourd}_gourd'",'check_violation')
            rejected(f"UPDATE inventory_items SET equipped=true WHERE definition_id='supply/{gourd}_gourd'",'check_violation')
        rejected("UPDATE inventory_items SET definition_id='ai/xuanfeng/fake/weapon' WHERE definition_id='ai/xuanfeng/mzs/weapon'",'check_violation')
        db.query("UPDATE inventory_items SET equipped=false WHERE equipment_slot='armor'; UPDATE inventory_items SET equipped=true WHERE definition_id='ai/xuanfeng/mzs/armor';")
        check(db.query("SELECT definition_id FROM inventory_items WHERE equipment_slot='armor' AND equipped")=='ai/xuanfeng/mzs/armor','new armor replaces old armor without losing inventory')
    print(f'XUANFENG MIGRATION: {checks} checks, 0 failures')


if __name__=='__main__':main()
