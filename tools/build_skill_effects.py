"""Authored, user-authorized semantic mapping of skills to inspected original ANI art."""
import hashlib
import json
from pathlib import Path
from import_assets import ROOT, DEST, bake, parse_ani, readable_json

# Each entry was chosen after visually inspecting native ANI composites.
# These are design decisions, never recovered original server effect IDs.
MAPPINGS = {
    'sheet_003': ('青色飞剑直落，表现指路剑击', [('t88','enemy')]),
    'sheet_004': ('多道月牙剑气，表现沧海明月', [('t87','enemy')]),
    'sheet_005': ('银白飞剑连续掠过，表现剑飞惊天', [('t85','enemy')]),
    'sheet_006': ('蓝色环形剑气与星光，表现套月', [('t94','enemy')]),
    'sheet_007': ('金色真气上升并亮起攻击增益符号', [('t21','hero'),('t10','hero')]),
    'sheet_008': ('大范围飞剑齐射，表现万剑归宗', [('t78','enemy')]),
    'sheet_010': ('青蓝雷电裂纹，表现雷霆重击', [('t92','enemy')]),
    'sheet_011': ('蓝色回转屏障，表现物理反伤', [('t93','hero')]),
    'sheet_012': ('晶体护罩，表现坚固防御', [('t30','hero')]),
    'sheet_013': ('八向血色斩痕，表现血战八方', [('t126','enemy')]),
    'sheet_014': ('带星光的护体圆环，反伤时触发', [('t12','hero')]),
    'sheet_015': ('星芒与青色旋风，表现斗转星移', [('t99','enemy')]),
    'sheet_017': ('拔地而起的岩柱，表现连天绝壁', [('t81','enemy')]),
    'sheet_018': ('星火坠落并燃起火柱', [('t47','enemy')]),
    'sheet_019': ('成片火球与烈焰，表现焚天疾火', [('t60','enemy')]),
    'sheet_021': ('盘旋升腾的劫火，表现劫焰燎原', [('t62','enemy')]),
    'sheet_025': ('蓝白月牙冲击，表现望月劈击', [('t35','enemy')]),
    'sheet_027': ('金色猛兽扑击，表现猛虎下山', [('t37','enemy')]),
    'sheet_033': ('紫色法印屏障，表现法术反伤', [('t1','hero')]),
    'sheet_034': ('防御提升符号，表现以逸待劳', [('t11','hero')]),
    'sheet_035': ('青色龙卷叠加雷电，表现狂风骤电', [('t119','enemy'),('t173','enemy')]),
    'sheet_036': ('青蓝法力环震，法术反伤时触发', [('t112','hero')]),
    'sheet_037': ('连续冰锥与碎冰，表现雪满天山', [('t75','enemy')]),
    'sheet_039': ('绿色生命上升光效，表现起死回生', [('t18','hero')]),
    'sheet_041': ('宽幅绿色回春光效，表现救死扶伤', [('t96','hero')]),
    'sheet_042': ('多列冰墙与冰锥，表现冰雪封天', [('t145','enemy')]),
    'sheet_045': ('多重岩柱震起，表现排山倒海', [('t140','enemy')]),
    'sheet_047': ('目标灵力被紫环束缚，施法者获得星光', [('t147','enemy'),('t09','hero')]),
    'sheet_051': ('紫色催眠环，表现醉生梦死', [('t16','enemy')]),
    'sheet_052': ('绿色毒泡与紫雾，表现混元入蛊', [('t25','enemy')]),
    'legacy_0': ('落石与地裂，表现破山诀', [('t32','enemy')]),
    'legacy_1': ('飞剑直击，表现御剑诀', [('t40','enemy')]),
    'legacy_2': ('绿色摄灵粒子与自身灵光，表现摄灵诀', [('t107','enemy'),('t01','hero')]),
}


def build():
    skills=json.loads((DEST/'data/skills-v1.json').read_text('utf8'))['items']
    assert set(MAPPINGS)=={s['id'] for s in skills}
    entries={r['resource_id']:r for r in json.loads((DEST/'admin/effects/catalog.json').read_text('utf8'))['effects']}
    bindings={}
    for skill in skills:
        reason,layers=MAPPINGS[skill['id']]
        bindings[skill['id']]={
            'name':skill['name'],'basis':'authored_semantic_mapping',
            'trigger':'cast_impact' if skill['active'] else ('magic_reflect' if skill['effect']=='reflect_magic' else 'physical_reflect'),
            'reason':reason,'layers':[]}
        for key,anchor in layers:
            original=entries[key]
            bindings[skill['id']]['layers'].append({'art':'effect/'+key,'anchor':anchor,'sequence':0,
                'canvas_offset':[0,-78] if key=='t16' else ([0,-60] if key=='t12' else [0,0]),
                'source_member':original['source_member'],'source_sha256':original['source_sha256']})
    return {'version':'skill-effects-v1','basis':'用户要求按技能含义人工设计；原版ANI素材，非已恢复的原服技能对应表',
        'original_binding_recovered':False,'bindings':bindings}


def export():
    catalog=build()
    keys=sorted({layer['art'] for binding in catalog['bindings'].values() for layer in binding['layers']})
    index_path=DEST/'data/actors.json';index=json.loads(index_path.read_text('utf8'))
    for key in keys:
        stem=key.split('/')[1];path=ROOT/'analysis/unpacked/ssjx/effect'/f'{stem}.ani'
        expected=next(layer['source_sha256'] for b in catalog['bindings'].values() for layer in b['layers'] if layer['art']==key)
        assert hashlib.sha256(path.read_bytes()).hexdigest()==expected
        info=bake(key,parse_ani(path))
        target=DEST/'data/actors'/f'{key}.json';target.parent.mkdir(parents=True,exist_ok=True)
        target.write_text(readable_json(info)+'\n','utf8',newline='\n')
        index['actors'][key]='res://assets/data/actors/'+key+'.json'
    index['actors']=dict(sorted(index['actors'].items()))
    index_path.write_text(json.dumps(index,ensure_ascii=False,indent=2)+'\n','utf8',newline='\n')
    (DEST/'data/skill-effects-v1.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n','utf8',newline='\n')
    text=['# 技能特效人工映射','','用户要求按技能含义进行映射。已逐项查看原包 159 份 ANI 特效，再选择下列组合；这是人工设计，**不声称恢复了原服对应表**。30 个具名技能和 3 个兼容技能均独立配置，不再按职业选择同一特效。','','| 技能 | 视觉含义 | 原包 ANI | 跟随对象 | 触发 |','|---|---|---|---|---|']
    for binding in catalog['bindings'].values():
        text.append('| '+ ' | '.join([binding['name'],binding['reason'],'、'.join(layer['art'].split('/')[1]+'.ani' for layer in binding['layers']),'、'.join('自身' if layer['anchor']=='hero' else '目标' for layer in binding['layers']),{'cast_impact':'施放命中帧','physical_reflect':'物理反伤','magic_reflect':'法术反伤'}[binding['trigger']]])+' |')
    text+=['','原包素材与 ANI 源文件 SHA256 保留在 `client/assets/data/skill-effects-v1.json`。每层保留原始序列、图像偏移和时序，不给素材套职业色，不改动画帧。`canvas_offset` 是人工配置的附着点补偿：t16 催眠环上移 78 像素、t12 护体环上移 60 像素，避免原动画的正 Y 坐标把状态画到脚下。其余层不加补偿。反伤心法按触发事件播放，当前怪物没有法术 AI，因此法反动画可在预览／测试中核对，实战需有法术伤害才触发。','',f'共使用 {len(keys)} 份原包动画。生成：`python tools/build_skill_effects.py`。完整资源重新导入时也保留这些运行时动画。']
    (ROOT/'analysis/recovery/skills/effect-mapping.md').write_text('\n'.join(text)+'\n','utf8',newline='\n')
    print(f'Exported {len(catalog["bindings"])} individual bindings / {len(keys)} original ANI resources.')


if __name__=='__main__':export()
