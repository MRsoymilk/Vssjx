"""Publish every ssjx item icon, with explicit reconstructed gameplay rules.

The original item catalog remains unmodified evidence. Slot classifications are
visual review of the nine equipment families; names/prices/stats are new rules.
Weapon-part links were reviewed side by side against original frame-zero art.
"""
import json
from pathlib import Path
from build_boneglow_equipment import equipment_items
from build_gravebloom_equipment import equipment_items as gravebloom_items
from build_eva01_equipment import equipment_items as eva01_items
from build_legendary_equipment import equipment_items as legendary_items

ROOT = Path(__file__).resolve().parents[1]
SLOTS = ['weapon','pendant','armor','wrist','belt','pants','boots','ring','necklace','hat']
LABELS = dict(zip(SLOTS,['武器','腰佩','衣服','手腕','腰带','裤子','鞋子','戒指','项链','帽子']))
# Each family is hat, armor, wrist, belt, pants, boots, ring, necklace, pendant.
FAMILIES = [
    [1,2,3,4,5,6,7,8,9], [10,11,12,13,14,16,17,18,19],
    [20,21,22,23,24,25,28,26,27], [29,30,31,32,33,34,36,37,38],
    [39,43,41,42,40,44,45,46,47], [48,49,50,51,52,53,54,55,56],
    [57,61,59,60,58,62,63,64,65], [66,67,68,69,70,71,72,73,74],
    [75,76,77,78,79,80,81,82,83],
]
FAMILY_SLOTS = ['hat','armor','wrist','belt','pants','boots','ring','necklace','pendant']
STYLES = ['朱霞','丹羽','玄青','紫霄','皓月','赤焰','流光','碧落','星河']
SUFFIX = dict(zip(FAMILY_SLOTS,['冠','衣','腕','带','裤','靴','戒','链','佩']))
WEAPONS = {
    0: {1:17,2:18,3:6,4:4,5:19,6:14,7:5,8:15,9:16,10:7,11:3,12:13,13:9,14:8,15:10,16:11,17:12,18:2},
    1: {19:17,20:16,21:5,22:6,23:18,24:19,25:7,26:20,27:21,28:1,29:9,30:8,31:12,32:14,33:13,34:10,35:11,36:3,37:2,38:4},
    2: {39:2,40:8,41:11,42:14,43:15,44:12,45:16,46:17,47:7,48:13,49:18,50:19,51:10,52:9,53:6,54:3,55:4,56:5},
}
WEAPON_NAMES = ['冰魄龙锤','紫焰龙锤','赤鳞龙锤','白骨锤','金骨锤','玄骨锤','日轮锤','骨纹轮锤','冰花锤','玄铁斧','赤珠锤','赤纹锤','双刃斧','金钺','骨刃斧','玄刃战斧','紫月战镰','木槌','赤爪刃','冰焰刃','焰牙刃','寒锋剑','苍星剑','赤星剑','流霞剑','碧纹剑','赤纹剑','青锋长剑','苍刃剑','赤锋剑','银锋剑','绯翼剑','紫翼剑','白刃剑','赤刃剑','苍月刀','弧锋刃','紫月刀','木纹杖','檀木杖','冰灵杖','碧灵杖','紫晶杖','朱纹杖','紫纹杖','青纹杖','金焰杖','玄星杖','赤星杖','绯星杖','金铃杖','白玉杖','日华杖','月华杖','灵骨杖','冰晶杖']
MEDICINES = {
    0:('青露药剂',30,0),1:('白玉药剂',45,0),2:('青瓷灵液',0,20),
    3:('赤玉药剂',60,0),4:('碧水灵液',0,30),5:('琥珀药剂',40,15),
    15:('小玉药瓶',30,0),16:('白瓷药瓶',60,0),17:('方口药瓶',0,25),18:('竹筒药液',45,20),
    19:('紫晶灵液',0,35),20:('四方灵液',0,45),21:('圆肚灵液',0,55),
    22:('赤玉葫芦',70,0),23:('铜口葫芦',100,25),24:('烧饼',20,0),25:('灵果',25,10),
    26:('莲蓬',0,20),27:('朱果',35,15),28:('回春药罐',45,0),70:('白玉药囊',75,0),71:('赤陶药罐',100,0),72:('青纹药罐',60,40),
}
# Material resource names confirmed by the user; keep recovered evidence intact.
MATERIAL_NAMES = {42: '当归', 43: '茯苓'}


def build():
    original = json.loads((ROOT/'client/assets/data/original_items.json').read_text('utf8'))
    legacy = json.loads((ROOT/'client/assets/data/shop-v1.json').read_text('utf8'))['items']
    for row in legacy:
        row.update(level=1, job=-1, category='药品' if row['slot']=='consumable' else LABELS[row['slot']],
                   sections=['hot','elixir'] if row['id']=='potion' else ['hot','rare'], restore_hp=45 if row['id']=='potion' else 0, restore_mp=0,
                   rules_basis='重建规则；兼容既有存档', head_visual=0)
    for row in legacy:
        row['name']={'weapon_2':'弧锋刃','weapon_3':'苍月刀','armor_2':'行云衣','armor_3':'青岚衣'}.get(row['id'],row['name'])
    slots={n:(slot,tier) for tier,family in enumerate(FAMILIES,1) for n,slot in zip(family,FAMILY_SLOTS)}
    weapon_parts={n:(job,part) for job,members in WEAPONS.items() for n,part in members.items()}
    items=[]
    for source in original['items']:
        key=source['resource_id'];prefix=key[:2];n=int(key[2:])
        row=dict(id=source['id'],name='',slot='material',price=12,attack=0,defense=0,visual=0,
                 head_visual=0,level=1,job=-1,icon=source['icon'],restore_hp=0,restore_mp=0,
                 source_member=source['source_member'],source_sha256=source['source_sha256'],
                 rules_basis='图形特征命名、分类、售价和属性为重建规则；并非原服务器物品表')
        if prefix=='iw':
            job,part=weapon_parts[n]
            row.update(name=WEAPON_NAMES[n-1],slot='weapon',category='武器',job=job,visual=part,
                       price=25+n*4,attack=5+(n-1)//3,sections=['hot','rare'],
                       appearance_basis=f'按原图形核对 {key} 与 e{["zs","ck","fs"][job]}{part}；物品属性仍为重建规则')
        elif prefix=='if':
            slot,tier=slots[n]
            row.update(name=STYLES[tier-1]+SUFFIX[slot],slot=slot,category=LABELS[slot],price=15+tier*12,
                       defense=1+(tier-1)//2,sections=['hot','rare'],
                       visual=tier+2 if slot=='armor' else 0,head_visual=tier if slot=='hat' else 0,
                       appearance_basis='衣服／头饰使用同序原包人物部件；此对应为可调整的重建映射')
        elif n in MEDICINES:
            name,hp,mp=MEDICINES[n]
            row.update(name=name,slot='consumable',category='药品',price=max(4,(hp+mp*2)//6),restore_hp=hp,restore_mp=mp,sections=['hot','elixir'])
        else:
            if n in [29,31,32,33,34,35,67]: category='宝石';name='灵石';row['price']=35
            elif n in [6,51,52,53,54,68]: category='配方';name='纹印卷轴';row['price']=24
            elif n in [7,8,9,10,11,12,13,14,62,63,73]: category='药材';name='灵草';row['price']=10
            elif n in [30,55,56,58,64,65,66,69]: category='特殊';name='奇珍';row['price']=30
            else: category='材料';name='炼制材料';row['price']=8
            row.update(name=MATERIAL_NAMES.get(n,f'{name}·{n:02}'),category=category,sections=['hot','rare' if category=='特殊' else 'craft'])
        items.append(row)
    assert len(items)==208 and len({r['id'] for r in items})==208
    assert {r['source_member'] for r in items}=={r['source_member'] for r in original['items']}
    return {'version':'shop-v2','provenance':'全量原包图标；显示名、分类和玩法数值为显式重建规则',
            'slots':SLOTS,'slot_labels':LABELS,'tabs':[['hot','热卖'],['rare','奇珍'],['craft','炼制'],['elixir','仙丹']],
            'items':items+legacy+equipment_items()+gravebloom_items()+eva01_items()+legendary_items()}


if __name__=='__main__':
    catalog=build()
    target=ROOT/'client/assets/data/shop-v2.json'
    target.write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n','utf8')
    print('Published',len(catalog['items']),'items, including all 208 original icons')
