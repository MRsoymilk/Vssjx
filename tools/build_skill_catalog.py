"""Publish named user-sheet skills with explicitly reconstructed gameplay rules."""
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]


def build_coverage():
    """UI-only gaps in the supplied sheet; never create playable unknown skills."""
    rows=json.loads((ROOT/'analysis/references/player-sheet/skills.json').read_text('utf8'))
    roles={}
    for row in rows:
        job=next(i for i,name in enumerate(['力士','侠客','隐者']) if row['role_raw'].endswith(name))
        school=next((i for i,name in enumerate(['峨眉','花间','昆仑']) if row['role_raw'].startswith(name)),-1)
        entry=roles.setdefault(f'{job}/{school}',{'source_role':row['role_raw'],'named_count':0,'missing_levels':[]})
        if row['name']: entry['named_count']+=1
        else: entry['missing_levels'].append(int(row['level_column_raw']))
    return {'source':'analysis/references/player-sheet/skills.json','roles':roles}


def build():
    source=json.loads((ROOT/'analysis/references/player-sheet/skills.json').read_text('utf8'))
    items=[]
    for row in source:
        if not row['name']:continue
        job=next(i for i,name in enumerate(['力士','侠客','隐者']) if row['role_raw'].endswith(name))
        school=next((i for i,name in enumerate(['峨眉','花间','昆仑']) if row['role_raw'].startswith(name)),-1)
        level=int(row['level_column_raw']);tier=max(0,(level-5)//10)
        description=' '.join([row['description_raw'] or '']+row['notes_raw']).strip()
        effect='damage';value=0;duration=0;chance=100
        if '自动反弹' in description:effect='reflect_magic' if '法术' in description else 'reflect_physical';value=20
        elif '反伤' in description:effect='reflect_magic' if '法术' in description else 'reflect_physical';value=60;duration=2
        elif '防御加成' in description:effect='defense';value=25;duration=2
        elif '暴击加成' in description:effect='crit';value=25;duration=2
        elif '回复生命' in description or '生命值回复' in description:effect='regen';value=15;duration=2
        elif '偷取敌方灵力' in description:effect='mana_steal';value=20
        elif '睡眠' in description:effect='sleep';duration=2;chance=35
        elif '中毒' in description:effect='poison';value=20;duration=2
        elif '流血' in description:effect='bleed';value=20;duration=1 if '一回合' in description else 2
        elif '沉默' in description:effect='silence';duration=2;chance=15
        passive='自动反弹' in description
        damaging=effect in ['damage','mana_steal','sleep','poison','bleed','silence']
        items.append(dict(id=f"sheet_{row['source_row']:03}",name=row['name'],job=job,school=school,
            unlock_level=level,category='心法' if passive else '武功',active=not passive,
            mp_cost=0 if passive else 9+tier*3,damage_percent=180+tier*10 if damaging else 0,
            effect=effect,value=value,duration=duration,chance=chance,legacy_heal=0,
            target='all_enemies' if '群体攻击' in description else ('all_allies' if '群体增益' in description else ('enemy' if damaging else 'self')),
            description=description,source_row=row['source_row'],source_role=row['role_raw'],source_level=row['level_column_raw'],
            original_skill_id=None,source='analysis/references/player-sheet/source.csv',
            rules_basis='名称、归属与效果文字来自用户资料；等级暂按角色解锁等级；消耗、公式、部分持续时间及武功/心法划分为重建规则'))
    for job,name in enumerate(['破山诀','御剑诀','摄灵诀']):
        items.append(dict(id=f'legacy_{job}',name=name,job=job,school=-1,unlock_level=1,category='武功',active=True,
            mp_cost=9,damage_percent=180,effect='damage',value=0,duration=0,chance=100,
            legacy_heal=16 if job==2 else 0,target='enemy',description='旧版入门技能，保留兼容。',
            source_row=None,original_skill_id=None,source='client/scripts/battle.gd',rules_basis='沿用旧版重建规则，并非原版技能'))
    assert len(items)==33
    return {'version':'skills-v1','named_reference_count':30,'unnamed_rows_excluded':18,
        'rules_basis':'表中具名技能及效果文字接入；未知消耗与战斗参数使用显式重建规则',
        'school_aliases':{'花间':'花涧'},'unlock_basis':'资料中的等级列暂按角色解锁等级使用；自动解锁，无技能阶数或技能点消耗',
        'group_target_basis':'当前遭遇战为单人单怪，群体技能作用于现有唯一目标，不虚构额外队友或敌人',
        'items':items}


if __name__=='__main__':
    path=ROOT/'client/assets/data/skills-v1.json'
    path.write_text(json.dumps(build(),ensure_ascii=False,indent=2)+'\n','utf8')
    (path.parent/'skill-reference-coverage.json').write_text(json.dumps(build_coverage(),ensure_ascii=False,indent=2)+'\n','utf8')
    print('Published 30 named skills and 3 legacy skills; 18 unnamed rows remain analysis-only.')
