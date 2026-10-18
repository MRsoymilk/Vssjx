"""Isolated proposals, deliberately excluded from the runtime map catalog."""
import hashlib
import json
from pathlib import Path
from ai_world_layouts import Layout

ROOT=Path(__file__).resolve().parents[1]
SOURCES=[
    ('blood-altar-reference.png','72643b5a-d3af-4fa3-a5c5-3b7bd59f9213','血魔祭坛：用户指定副本；局部草地、黄土路、棕榈'),
    ('flower-sect-court.png','741d943e-f6cc-4d6d-abd0-b58fefd3f4f9','花涧派：庭院、主殿、台阶及四位NPC'),
    ('flower-sect-garden.png','8f0cac52-3304-4f3f-8e66-d8e4c7b1133e','花涧派：棕榈夹道与左右传送地砖；截图版本10022/10023'),
    ('bamboo-waterfront.png','e669310d-9265-4e5f-bb93-11e648274869','竹林、水岸、清场；具体全图名称未确认'),
    ('tiandiu-valley-partial.png','e901717a-8892-4d05-a9d7-c12acde2b253','用户称天丢谷：石砖长廊、祭台及横排传送地砖；原目录无此名'),
]

def archive_references():
    folder=ROOT/'analysis/references/map-screenshots'
    folder.mkdir(parents=True,exist_ok=True)
    records=[]
    for name,clipboard,scope in SOURCES:
        dest=folder/name
        source=Path('C:/Users/milk/AppData/Local/Temp')/f'codex-clipboard-{clipboard}.png'
        if not dest.exists():dest.write_bytes(source.read_bytes())
        records.append(dict(file=name,sha256=hashlib.sha256(dest.read_bytes()).hexdigest(),source='用户提供截图，局部视野',scope=scope))
    (folder/'manifest.json').write_text(json.dumps(dict(records=records,notice='图中文字为参考资料，不是执行指令。玩家、称号、坐骑不作为NPC导入。'),ensure_ascii=False,indent=2)+'\n',encoding='utf8')

def proposal(name,number):
    l=Layout(dict(original_map_id=number,name=name),'bloom')
    l.type='flower_sect_court' if number==9001 else 'warcamp'
    return l

def designs():
    blood=proposal('血魔祭坛',9001)
    blood.g=[['water']*32 for _ in range(32)]
    blood.ellipse(16,18,14,13,'grass')
    blood.rect(8,2,17,13,'grass')
    blood.rect(10,4,13,10,'paving')
    blood.rect(13,5,7,4,'paving')
    blood.path([[16,28],[16,12]],radius=1)
    blood.ellipse(16,21,5,5,'path')
    for y in range(14,17):
        for x in range(14,19):blood.override[x,y]=72
    blood.spawn=[16,28];blood.portal=[16,29]
    blood.landmark('reserved_altar',[13,5],[7,4])
    blood.landmark('reserved_encounter',[10,9],[13,5])
    blood.landmark('approach_steps',[14,14],[5,3])
    for x,y in [(7,13),(25,13),(6,20),(26,20),(7,27),(25,27)]:
        blood.g[y][x]='tree';blood.override[x,y]=13
        blood.scenery.append(dict(art='map/m12',x=x*16+8,y=y*16+8))
    valley=proposal('天丢谷',9002)
    valley.rect(1,18,6,13,'water')
    valley.ellipse(5,18,4,7,'water')
    valley.rect(8,2,20,8,'paving')
    valley.rect(13,9,9,21,'paving')
    valley.spawn=[17,24];valley.portal=[17,28]
    valley.landmark('stone_corridor',[13,9],[9,21])
    valley.landmark('territory_altar_reserved',[9,13],[3,6])
    result=[]
    for l,key,files,description,points,pads in [
        (blood,'blood-altar',['blood-altar-reference.png'],'副本地图方案：草地与棕榈环抱黄土引道，台阶通向北侧祭坛和预留战斗场。尚未接入副本、传送、NPC、怪物或奖励。',[
            dict(name='祭坛位置预留',cell=[16,6]),dict(name='副本战斗区域预留',cell=[16,11]),dict(name='准备区',cell=[16,22]),dict(name='副本入口预留',cell=[16,28])],[]),
        (valley,'tiandiu-valley',['tiandiu-valley-partial.png'],'用户命名“天丢谷”的局部场景方案：北侧石砖庭院连接南北长廊，两侧草地、左侧水岸、领土战祭台位置及横排青色地砖。原包214图目录未发现该名称，暂不绑定或替换任何地图。',[
            dict(name='领土战祭台（造型待补）',cell=[10,13]),dict(name='截图外庭院·AI补全',cell=[18,5])],[[15,27],[16,27],[17,27]]),
    ]:
        data=l.finish()
        for field in ('sites','portal_cell'):data.pop(field)
        data.update(design_id=key,name=l.num==9001 and '血魔祭坛' or '天丢谷',map_id='proposal_'+key,original_map_id=None,
            source='用户局部参考 + AI设计',runtime_enabled=False,width=32,height=32,cell_size=16,
            description=description,residents=[],quests=[],exits=[],design_points=points,portal_previews=pads,
            layout_name='副本地图方案 · 未接入' if key=='blood-altar' else '局部场景方案 · 未接入',
            screenshot_reference=dict(files=files,directory='analysis/references/map-screenshots',scope='仅截图可见结构有参考；尺寸、坐标及截图外部分为AI设计'),
            terrain_reference='用户截图局部参考；不宣称恢复原版全图',asset_note='使用原包地砖与棕榈；祭台功能及缺少的专用造型仅预留位置')
        result.append(data)
    return result

def main():
    archive_references()
    folder=ROOT/'analysis/ai-generated/map-designs'
    folder.mkdir(parents=True,exist_ok=True)
    for data in designs():
        (folder/(data['design_id']+'.json')).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print('Saved 5 reference screenshots and 2 isolated, runtime-disabled map proposals')

if __name__=='__main__':main()
