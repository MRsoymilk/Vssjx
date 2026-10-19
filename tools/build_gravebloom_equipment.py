"""Publish native parts and ten-slot items for the user's necromancer reference."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'analysis/ai-generated/equipment/gravebloom'
SLOTS = ['weapon','pendant','armor','wrist','belt','pants','boots','ring','necklace','hat']
LABELS = ['武器','腰佩','衣服','手腕','腰带','裤子','鞋子','戒指','项链','帽子']
SUFFIXES = ['兵','佩','袍','腕','带','裤','靴','戒','链','冠']


def config():
    return json.loads((SOURCE/'set-definitions.json').read_text('utf8'))


def equipment_items():
    definition = config()
    items = []
    for index, (_,stem,name,*_) in enumerate(definition['sets']):
        for slot,label,suffix in zip(SLOTS,LABELS,SUFFIXES):
            items.append(dict(id=f'ai/gravebloom/{stem}/{slot}',
                name=definition['weapon_names'][index] if slot=='weapon' else f'{name}·{suffix}',
                slot=slot,category=label,price=140 if slot=='weapon' else 70,
                attack=14 if slot=='weapon' else 0,defense=3 if slot!='weapon' else 0,
                visual=34+index if slot=='weapon' else (18+index if slot=='armor' else 0),
                head_visual=16+index if slot=='hat' else 0,level=1,job=index//2,gender=index%2,
                icon=f'res://assets/generated/equipment/gravebloom/{stem}/icons/{slot}.png',
                restore_hp=0,restore_mp=0,sections=['hot','rare'],set_id=f'gravebloom/{stem}',
                set_name=name,art_source='AI生成',
                rules_basis='用户冥林巫师与夸张发型参考的新设计；价格、属性为重建玩法，不属于原包恢复',
                appearance_basis='原生战斧／重锤／长剑／爪刃／法器分层帧重绘，保留握持点、原ANI配方及脚底锚点。隐者分别采用骨面兜帽与金焰高发。武器、衣服、头部独立换装，其余七槽仅影响属性。'))
    return items


def publish_manifest():
    definition = config()
    native = json.loads((ROOT/'client/assets/data/hero-parts.json').read_text('utf8'))
    templates = json.loads((SOURCE/'native-frame-templates.json').read_text('utf8'))
    sets,parts = [],{}
    for index,(row,template) in enumerate(zip(definition['sets'],templates)):
        identifier,stem,name,*_ = row
        assert stem == template['stem']
        sources = list(dict.fromkeys(c['source'] for c in template['cells']))
        mapped = {s:f'gravebloom/{stem}/{s}' for s in sources}
        for source,part_id in mapped.items():
            parts[part_id]=dict(texture=f'res://assets/generated/equipment/gravebloom/{stem}/parts/{source}.png',
                frames=native['parts'][source]['frames'])
        sets.append(dict(id=f'gravebloom/{stem}',name=name,stem=stem,job=index//2,gender=index%2,
            weapon_code=34+index,clothing_code=18+index,head_code=16+index,
            head=mapped[sources[0]],body=[mapped[s] for s in sources[1:4]],weapon=mapped[sources[4]],
            weapon_name=definition['weapon_names'][index],source_template=identifier+'-parts-template.png'))
    (ROOT/'client/assets/data/gravebloom-equipment.json').write_text(json.dumps(dict(format_version=1,
        source='AI生成；用户巫师与发型参考；原生人物分层适配',sets=sets,parts=parts),ensure_ascii=False,indent=2)+'\n','utf8')


if __name__ == '__main__':
    publish_manifest()
    print('Published six gravebloom sets and thirty native part definitions')
