"""Deterministic, explicitly synthetic expansion. Never overwrites recovered evidence."""
from __future__ import annotations
import hashlib
import json
import random
from pathlib import Path
from ai_world_layouts import build_layout
from ai_world_monsters import roster,stats,sheet_records,NAMES
from ai_world_npcs import roster as npc_roster

ROOT = Path(__file__).resolve().parents[1]
BIOMES = {
    "forest": ("山林", 13, 18, 269, "山路被妖气侵染，巡山人与采药人都不敢独行。", "灵叶", "山魈", "守山妖将"),
    "bloom": ("花谷", 14, 18, 123, "花木失了时序，谷中的清香里夹着陌生的瘴气。", "清露", "花瘴灵", "噬香妖灵"),
    "snow": ("雪岭", 456, 471, 454, "寒潮封住山口，护路符的灵光也逐日暗淡。", "冰魄", "雪魇", "寒岭妖王"),
    "lava": ("炎域", 544, 258, 718, "地脉涌出灼热妖息，旧日镇火的符印已经残破。", "火晶", "焰魇", "焚脉妖王"),
    "cave": ("洞窟", 258, 544, 219, "洞中回声不绝，探路人的灯火停在了深处。", "灵石", "洞魇", "噬灵妖将"),
    "town": ("村镇", 299, 392, 269, "驿路受阻，百姓盼着有人把平安的消息送出去。", "药材", "扰路山狼", "劫道妖首"),
    "temple": ("仙门", 258, 299, 269, "护山阵出现裂隙，值守弟子正四处寻找失散的符引。", "符引", "阵隙妖灵", "破阵魔将"),
    "ruins": ("遗迹", 258, 678, 219, "残碑上的剑痕重新发亮，封印下传来不安的震响。", "碑拓", "怨剑灵", "镇碑魔将"),
    "coast": ("水泽", 13, 18, 123, "水脉被浊气截断，渡口往来的舟人已经失了音讯。", "净水珠", "水魇", "锁水妖王"),
    "marsh": ("瘴泽", 14, 544, 123, "雾瘴沿着浅水蔓延，只有旧石标还能辨认归途。", "避瘴草", "瘴魇", "吞雾妖王"),
}

def biome(row):
    n = row["name"]
    if "魔界" in n: return "cave"
    if "地狱" in n: return "lava"
    if "礼堂" in n: return "town"
    if any(word in n for word in ["地宫","枉死","阴阳","浴血"]): return "ruins"
    for keys, value in [("雪冰寒昆仑", "snow"), ("火炎焰焚", "lava"), ("洞窟巢穴", "cave"), ("沼瘴毒", "marsh"), ("湖潭池海江河渡泉水", "coast"), ("花兰竹百", "bloom"), ("墓坟陵冢遗封", "ruins")]:
        if any(c in n for c in keys): return value
    if row["location_kind"] == 1 or any(c in n for c in "镇村城寨"): return "town"
    if row["location_kind"] == 2 or any(c in n for c in "寺祠宫殿观派"): return "temple"
    return "forest"

def line(a, b):
    x, y = a
    while x != b[0]:
        yield x, y
        x += 1 if b[0] > x else -1
    while y != b[1]:
        yield x, y
        y += 1 if b[1] > y else -1
    yield x, y

def generate(row, sheet):
    num = row["original_map_id"]
    key = f"ai_{num:03}"
    rng = random.Random(20261018 + num * 917)
    kind = biome(row)
    label, floor, road, obstacle, premise, item, mob, boss = BIOMES[kind]
    if any(word in row["name"] for word in ["擂台","帮会","备战","营地","战场","基地","进攻区","防守区","精华源","礼堂","群英会"]):
        premise="此处暂作蜀山演武幻境。来客需先核验阵符，再与巡阵影身切磋，最后通过守阵者的考验；演示规则为AI设计。"
        item,mob,boss="阵符","巡阵影身","演武守阵者"
    level = row["level_min"]
    monsters = roster(row,kind)
    people,excluded_people=npc_roster(row,kind,sheet)
    layout = build_layout(row, kind,[v['role'] for v in monsters[2:]],[p['role'] for p in people])
    sites = layout["sites"]
    guide,courier,surveyor=[p['name'] for p in people[:3]]
    short = row["name"][:7]
    def resident(suffix,name,kind_,art,cell,lv):
        return dict(id=f"{key}_{suffix}", name=name[:12], kind=kind_, art=art, cell=cell, level=lv,
                    hp=0 if kind_=="npc" else 45+lv*20,
                    attack=0 if kind_=="npc" else 8+lv*3,
                    defense=0 if kind_=="npc" else 1+lv,
                    gold=0 if kind_=="npc" else 4+lv*2,
                    xp=0 if kind_=="npc" else 6+lv*3)
    residents=[]
    for p in people:
        value=resident(p['role'],p['name'],'npc',p['art'],sites[p['role']],level)
        value.update(service_label=p['service_label'],dialogue=p['dialogue'],dialogue_source=p['dialogue_source'],
            appearance_status=p['appearance_status'],gathering=p.get('gathering',False),
            npc_reference={k:v for k,v in p.items() if k not in ('role','art','name','dialogue','service_label')})
        residents.append(value)
    for v in monsters:
        role=v['role'];lv=max(1,min(60,v['level']))
        value=resident(role,v['name'],'boss' if role=='boss' else 'wolf',v['art'],sites[role],lv)
        value.update(stats(v['art'],lv,role=='boss'));value['reference']=v['reference']
        residents.append(value)
    mob,boss=monsters[0]['name'],monsters[1]['name']
    # Three linked authored templates: reconnaissance -> relief -> sealing boss.
    quests = []
    titles = [f"{short}·访迹",f"{short}·护路",f"{short}·镇脉"]
    for phase in range(3):
        qid = f"{key}_q{phase+1}"
        quests.append(dict(id=qid,map_id=key,name=titles[phase],source="AI生成",
            giver=f"{key}_guide", prerequisite=f"{key}_q{phase}" if phase else "",
            min_level=max(1,level-4),
            description=[f"{premise}{guide}托你拜访{surveyor}，查验{item}，再将见闻交给{courier}。",
                f"{courier}确认了{row['name']}的险情。请清除两只{mob}，为送药与传讯的人留出道路。",
                f"散妖已退，{boss}仍盘踞在{row['name']}深处。击败妖首，再将安定的消息带回{guide}处。后续可由驿石前往邻近地区。" ][phase],
            objectives=[dict(kind="interact",target=f"{key}_survey",count=1,text=f"查验{item}"),dict(kind="interact",target=f"{key}_courier",count=1,text=f"向{courier}传讯")] if phase==0 else
                [dict(kind="kill",target=f"{key}_{'mob' if phase==1 else 'boss'}",count=2 if phase==1 else 1,text=f"击败{mob if phase==1 else boss}")],
            gold=(12+level*3)*(phase+1),xp=(18+level*4)*(phase+1)))
    return dict(map_id=key,version="ai-world-v1",name=row["name"],source="AI生成",original_map_id=num,
        provenance={"name":"原包 worldmap.data", "layout":"AI生成，非原版恢复", "npcs":"参考玩家整理表的称谓；位置、对白为AI生成", "monsters":"优先用户表格同图记录；外形映射、摆放和数值为AI推定，缺项按地域补足", "quests":"AI生成，非反编译原文"},
        world_position=row["world_position"],location_kind=row["location_kind"],level_min=level,level_max=row["level_max"],
        biome=kind,biome_name=label,description=premise,width=32,height=32,cell_size=16,spawn=layout["spawn"],
        tiles=layout["tiles"],blocked=layout["blocked"],scenery=layout["scenery"],residents=residents,quests=quests,
        layout_archetype=layout["layout_archetype"],layout_name=layout["layout_name"],landmarks=layout["landmarks"],terrain_reference=layout["terrain_reference"],
        npc_notes=excluded_people,
        portal={"id":"ai_waystone","cell":layout["portal_cell"],"name":"蜀山驿石 · AI生成"})

def build():
    original = json.loads((ROOT/"analysis/catalogs/online_world.json").read_text(encoding="utf-8"))
    sheets = json.loads((ROOT/"analysis/references/player-sheet/maps.json").read_text(encoding="utf-8"))
    if isinstance(sheets,dict): sheets = sheets.get("records", sheets.get("rows", []))
    by_id = {int(r["native_map_id"]):r for r in sheets if r.get("native_map_id") is not None}
    maps = [generate(row,by_id.get(row["original_map_id"],{})) for row in original["maps"]["records"]]
    maps.sort(key=lambda m:m["original_map_id"])
    for m in maps:
        # Nearest original overview nodes supply a navigable suggested route, not recovered exits.
        p=m["world_position"]
        def distance(v):
            q=v["world_position"]
            return abs(q[0]-p[0])+abs(q[1]-p[1]) if p and q else 100+abs(v["original_map_id"]-m["original_map_id"])
        others=sorted((v for v in maps if v!=m),key=lambda v:(distance(v),v["original_map_id"]))
        m["neighbors"]=[v["map_id"] for v in others[:3]]
        if m['original_map_id']==21:
            m['neighbors']=['ai_022','ai_023',next(v['map_id'] for v in others if v['map_id'] not in ('ai_022','ai_023'))]
        elif m['original_map_id'] in (22,23):
            m['neighbors']=['ai_021',*[v['map_id'] for v in others if v['map_id']!='ai_021'][:2]]
    by_id={m['map_id']:m for m in maps}
    for m in maps:
        # The nearest-three list is for the directory, not three obligatory
        # physical portals. A small scene needs a return and one regional exit.
        m['recommended_maps']=m['neighbors'][:]
        if m['original_map_id']==21:
            m['neighbors']=['ai_022','ai_023']
        elif m['original_map_id'] in (22,23):
            m['neighbors']=['ai_021']
        else:
            following=[v for v in m['neighbors'] if by_id[v]['original_map_id']>m['original_map_id']]
            m['neighbors']=[(following or m['neighbors'])[0]]
        occupied=[m['spawn'],*[r['cell'] for r in m['residents']]]
        m['exits']=[] if m['original_map_id']==21 else [dict(id='return_trail',cell=m['portal']['cell'],target_map='qingyun_trail',name='青云山道',source='AI生成连接')]
        occupied.append(m['portal']['cell'])
        for index,target in enumerate(m['neighbors']):
            other=by_id[target];p,q=m['world_position'],other['world_position']
            if p and q:
                dx,dy=q[0]-p[0],q[1]-p[1]
                want=[28 if dx>=0 else 3,16] if abs(dx)>=abs(dy) else [16,28 if dy>=0 else 3]
            else:want=[[28,16],[16,3],[16,28]][index]
            candidates=[]
            for y in range(2,30):
                for x in range(2,30):
                    if m['blocked'][y*32+x] or any(abs(x-v[0])+abs(y-v[1])<4 for v in occupied):continue
                    if any(abs(x-p['x']//16)<=3 and 0<=p['y']//16-y<=6 for p in m['scenery']):continue
                    # Prefer outer road ends. Never dot the central living area
                    # with extra blue tiles just to satisfy a fixed portal count.
                    separation=abs(x-m['portal']['cell'][0])+abs(y-m['portal']['cell'][1])
                    if separation<10:continue
                    edge=min(x,y,31-x,31-y)
                    road=m['tiles'][y*32+x] in (18,20,21,22,30,32,40,41,42,72,138,149)
                    score=edge*7+((x-want[0])**2+(y-want[1])**2)*.12+(0 if road else 8)
                    body_clear=not any(abs(x-r['cell'][0])<=(2 if r['kind']=='npc' else 4) and 0<=r['cell'][1]-y<=(4 if r['kind']=='npc' else 6) for r in m['residents'])
                    candidates.append(((not body_clear,edge>8,not road,score),[x,y]))
            point=min(candidates)[1];occupied.append(point)
            m['exits'].append(dict(id='exit_'+target,cell=point,target_map=target,name=other['name'],source='AI生成连接，方向参考总图坐标'))
        if m['original_map_id']==21:
            for gate in m['exits']:
                if gate['target_map'] in ('ai_022','ai_023'):
                    x=3 if gate['target_map']=='ai_022' else 29
                    gate.update(cell=[x,27],cells=[[x,y] for y in (26,27,28)],source='截图确认左右目标；坐标和碰撞为AI设计')
            m['screenshot_reference']={'files':['flower-sect-court.png','flower-sect-garden.png'],'directory':'analysis/references/map-screenshots','scope':'局部结构与NPC称谓确认；全图尺寸、NPC外形、碰撞和任务为AI设计','screenshot_exit_ids':{'秋兰竹亭':10022,'幻波池':10023},'native_exit_ids':{'秋兰竹亭':22,'幻波池':23}}
        elif m['original_map_id'] in (22,23):
            m['screenshot_reference']={'files':['bamboo-waterfront.png'],'directory':'analysis/references/map-screenshots','scope':'竹林与水岸的环境参考；未能从截图确认整张地图名称，按相邻地域推定适配'}
    return dict(version="ai-world-v1",label="AI生成·蜀山补全试验",layout_revision=4,npc_revision=1,monster_revision=1,portal_revision=3,seed=20261018,
                disclaimer="地名、等级与总览坐标参考原包；场景布局、NPC布置、任务剧情与奖励均为AI生成。不是恢复出的原版内容。",maps=maps)

def main():
    data=build()
    raw=json.dumps(data,ensure_ascii=False,separators=(",",":"))+"\n"
    for dest in ["shared/data/ai-world-v1.json","client/assets/data/ai-world-v1.json"]:
        (ROOT/dest).write_text(raw,encoding="utf-8",newline="\n")
    index=dict(version=data["version"],layout_revision=data["layout_revision"],source="AI生成",disclaimer=data["disclaimer"],
        catalog="shared/data/ai-world-v1.json",catalog_sha256=hashlib.sha256(raw.encode()).hexdigest(),
        map_count=len(data["maps"]),quest_count=sum(len(m["quests"]) for m in data["maps"]),
        layout_count=len({m['layout_archetype'] for m in data['maps']}),
        monster_count=sum(r['kind']!='npc' for m in data['maps'] for r in m['residents']),
        monster_art_count=len({r['art'] for m in data['maps'] for r in m['residents'] if r['kind']!='npc'}),
        npc_count=sum(r['kind']=='npc' for m in data['maps'] for r in m['residents']),
        maps=[dict(map_id=m["map_id"],original_map_id=m["original_map_id"],name=m["name"],biome=m["biome"],level_min=m["level_min"],level_max=m["level_max"],
                   layout_archetype=m['layout_archetype'],layout_name=m['layout_name'],spawn=m['spawn'],portal=m['portal']['cell'],
                   landmarks=m['landmarks'],exits=m['exits'],residents=[dict(id=r['id'],cell=r['cell']) for r in m['residents']],
                   npcs=[r["name"] for r in m["residents"] if r["kind"]=="npc"],quests=[q["id"] for q in m["quests"]]) for m in data["maps"]])
    index_path=ROOT/"analysis/ai-generated/world-v1-index.json"
    index_path.parent.mkdir(parents=True,exist_ok=True)
    index_path.write_text(json.dumps(index,ensure_ascii=False,indent=2)+"\n",encoding="utf-8",newline="\n")
    mappings=dict(source='用户提供表格 + AI外形映射',disclaimer='原表未提供原始怪物ID、属性和动画ID；外形按已查看的原包图像推定，非恢复原服对应表。',
        records=[dict(r,appearance='monster/'+NAMES[r['name_after_level'] or r['label_raw']],appearance_status='AI按外形推定') for r in sheet_records()],
        runtime_monsters=[dict(map_id=m['map_id'],map_name=m['name'],**r) for m in data['maps'] for r in m['residents'] if r['kind']!='npc'])
    (ROOT/'analysis/ai-generated/monster-mapping-v1.json').write_text(json.dumps(mappings,ensure_ascii=False,indent=2)+'\n',encoding='utf8',newline='\n')
    npc_audit=dict(source='玩家NPC表 + AI按地点用途补全',disclaimer='称谓有表格来源；坐标、对白与外形对应均为AI设计，商店等身份不等于原版服务规则已恢复。',
        records=[dict(map_id=m['map_id'],map_name=m['name'],**r) for m in data['maps'] for r in m['residents'] if r['kind']=='npc'],
        excluded=[dict(map_id=m['map_id'],**p) for m in data['maps'] for p in m['npc_notes']])
    (ROOT/'analysis/ai-generated/npc-mapping-v1.json').write_text(json.dumps(npc_audit,ensure_ascii=False,indent=2)+'\n',encoding='utf8',newline='\n')
    print(f"AI maps: {len(data['maps'])}; quests: {sum(len(m['quests']) for m in data['maps'])}; sha256: {hashlib.sha256(raw.encode()).hexdigest()}")

if __name__=="__main__": main()
