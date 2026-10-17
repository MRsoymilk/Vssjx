"""Archive the user-supplied parallel CSV tables as review-only analysis data."""
import argparse
import csv
import hashlib
import io
import json
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/'analysis/references/player-sheet'
ORIGINAL_FILENAME='蜀山剑侠怪物数据-工作表1.csv'


def build(data):
    rows=list(csv.reader(io.StringIO(data.decode('utf-8-sig'))))
    if len(rows)<2 or any(len(row)!=27 for row in rows):raise ValueError('Expected the supplied 27-column CSV layout')
    if rows[1][0:3]!=['地图','NPC','怪物名（一）'] or rows[1][10:14]!=['职业','技能名称','技能等级','技能描述']:
        raise ValueError('Unexpected source table headers')
    native=json.loads((ROOT/'analysis/catalogs/online_world.json').read_text('utf8'))['maps']['records']
    native_by_index={int(row['name_index']):row for row in native}
    maps=[];monsters=[];skills=[];items=[];materials=[];gems=[];equipment=[]
    def reference(row,columns):return {'source_row':row,'source_columns':columns,'verification':'user_provided_unverified'}
    for row_no,row in enumerate(rows[2:],3):
        match=re.fullmatch(r'\s*\[\s*(\d+)\]\s*(.+?)\s*',row[0])
        if row[0].strip() and match is None:raise ValueError(f'Unrecognized map label on row {row_no}')
        if match:
            index=int(match[1]);label=match[2]
            # Only the three explicit trailing level annotations are removed for comparison.
            name=re.sub(r'\(\d+-\d+级\)$','',label)
            original=native_by_index.get(index,{})
            same=name==original.get('name')
            maps.append(dict(reference(row_no,'A:F'),csv_index=index,name_raw=label,npc_raw=row[1] or None,
                monsters_raw=row[2:6],native_name_match=same,
                match_method=('exact' if label==name else 'removed_trailing_level_annotation') if same else None,
                native_name_index=original.get('name_index') if same else None,
                native_map_id=original.get('original_map_id') if same else None,
                native_name=original.get('name') if same else None))
            for column,raw in zip('CDEF',row[2:6]):
                if not raw.strip():continue
                level=re.fullmatch(r'(\d+)级(.+)',raw.strip())
                monsters.append(dict(reference(row_no,column),map_csv_index=index,map_name_raw=label,
                    label_raw=raw,reported_level=int(level[1]) if level else None,
                    name_after_level=level[2] if level else None,
                    original_monster_id=None,animation=None,combat_stats=None))
        if any(row[10:16]):
            skills.append(dict(reference(row_no,'K:P'),record_id=f'reference/skill/row-{row_no:03}',
                role_raw=row[10] or None,name=row[11] or None,level_column_raw=row[12] or None,
                level_column_meaning='unconfirmed',description_raw=row[13] or None,notes_raw=row[14:16],
                original_skill_id=None,mp_cost=None,max_rank=None,damage_formula=None,effect_animation=None))
        if row[6].strip():items.append(dict(reference(row_no,'G:J'),name=row[6],level_raw=row[7] or None,
            description_raw=row[8] or None,binding_raw=row[9] or None,original_item_id=None,icon=None))
    # Right-hand tables start on the second CSV row, beside the left-hand headers.
    legendary_role=None
    for row_no,row in enumerate(rows[1:],2):
        for column,label,value in [('Q','material',row[16]),('R','herb',row[17])]:
            if value.strip():materials.append(dict(reference(row_no,column),name=value,column_group=label,original_item_id=None))
        if row[20].strip():gems.append(dict(reference(row_no,'U:V'),name=row[20],attribute_raw=row[21] or None,
            numeric_attribute=None,original_item_id=None))
        if row[23].strip():equipment.append(dict(reference(row_no,'X:Y'),name=row[23],level_raw=row[24] or None,
            group='equipment',role_raw=None,original_item_id=None,icon=None))
        value=row[25].strip()
        if value.startswith('《') and value.endswith('》'):legendary_role=value[1:-1]
        elif value:equipment.append(dict(reference(row_no,'Z:AA'),name=row[25],level_raw=row[26] or None,
            group='legendary',role_raw=legendary_role,original_item_id=None,icon=None))
    counts={'map_records':len(maps),'map_name_matches':sum(m['native_name_match'] for m in maps),
        'npc_nonempty_cells':sum(m['npc_raw'] is not None for m in maps),'monster_cells':len(monsters),
        'skill_rows':len(skills),'named_skills':sum(s['name'] is not None for s in skills),
        'unnamed_skill_rows':sum(s['name'] is None for s in skills),'items':len(items),
        'materials':len(materials),'gems':len(gems),'equipment':len(equipment)}
    manifest={'version':1,'source':{'file':'source.csv','original_filename':ORIGINAL_FILENAME,
        'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data),'encoding':'utf-8-sig',
        'rows_including_headers':len(rows),'columns':27,'provided_by':'user',
        'original_author':None,'original_version':None,'original_server_payload':False},
        'scope':'analysis_only','counts':counts,
        'map_comparison_source':'analysis/catalogs/online_world.json',
        'map_comparison_scope':'只核对同序地图名称，不证明怪物、NPC或其他表字段正确；CSV序号不是原服地图ID',
        'gem_notes_raw':[{'source_row':i+1,'text':r[22]} for i,r in enumerate(rows) if r[22].strip()],
        'issues':['各分区是横向并排的独立表，技能、道具、材料、装备不能与同一行地图关联。',
            '技能等级列的5、15、25等值未确认是学习等级还是其他含义，不当作技能阶数。',
            '花间派按表保留；与当前重建角色的花涧命名差异待核对。',
            '8-、16-等宝石属性保留原文，不自动转换成已确认数值。',
            'xx、什么、有个等模糊文字保留，不补写成确定名称。',
            '原始技能ID、灵力消耗、完整公式、图标及动画映射尚缺；不直接生成正式游戏定义。']}
    return {'manifest':manifest,'maps':maps,'monsters':monsters,'skills':skills,'items':items,
        'materials':materials,'gems':gems,'equipment':equipment}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,default=DEST/'source.csv')
    args=parser.parse_args()
    data=args.source.read_bytes();tables=build(data)
    DEST.mkdir(parents=True,exist_ok=True)
    raw=DEST/'source.csv'
    if raw.exists() and raw.read_bytes()!=data:raise ValueError('Archived source differs; preserve it and create a new revision')
    if not raw.exists():raw.write_bytes(data)
    for name,value in tables.items():
        (DEST/(name+'.json')).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n','utf8')
    print(json.dumps(tables['manifest']['counts'],ensure_ascii=False))


if __name__=='__main__':main()
