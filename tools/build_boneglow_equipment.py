"""Publish six approved boneglow sets without replacing recovered source art."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SLOTS = ['weapon', 'pendant', 'armor', 'wrist', 'belt', 'pants', 'boots', 'ring', 'necklace', 'hat']
LABELS = ['武器', '腰佩', '衣服', '手腕', '腰带', '裤子', '鞋子', '戒指', '项链', '帽子']
SUFFIXES = ['兵', '佩', '甲', '腕', '带', '裤', '靴', '戒', '链', '冠']
SETS = [
    ('01_male_lishi', 'mzs', '玄骸镇岳', 0, 0),
    ('02_female_lishi', 'wzs', '赤翎破军', 0, 1),
    ('03_male_xiake', 'mck', '紫冥斩魄', 1, 0),
    ('04_female_xiake', 'wck', '霜骨流萤', 1, 1),
    ('05_male_yinzhe', 'mfs', '幽篁摄灵', 2, 0),
    ('06_female_yinzhe', 'wfs', '苍灵月骨', 2, 1),
]


def equipment_items():
    result = []
    for index, (set_id, stem, name, job, gender) in enumerate(SETS):
        for slot, label, suffix in zip(SLOTS, LABELS, SUFFIXES):
            result.append(dict(id=f'ai/boneglow/{stem}/{slot}', name=f'{name}·{suffix}',
                slot=slot, category=label, price=120 if slot == 'weapon' else 65,
                attack=12 if slot == 'weapon' else 0, defense=3 if slot != 'weapon' else 0,
                visual=28+index if slot == 'weapon' else (12+index if slot == 'armor' else 0),
                head_visual=10+index if slot == 'hat' else 0, level=1, job=job, gender=gender,
                icon=f'res://assets/generated/equipment/boneglow/{stem}/icons/{slot}.png',
                restore_hp=0, restore_mp=0, sections=['hot', 'rare'], set_id=f'boneglow/{stem}',
                set_name=name, art_source='AI生成',
                rules_basis='骨甲幽光新设计；属性与价格为重建规则，不属于原包恢复',
                appearance_basis='经确认的骨甲幽光设计；AI重绘原生部件，沿用原始ANI图层、变换与动作锚点。武器、衣服、头部独立替换，其余槽位仅提供属性。'))
    return result


def publish_manifest():
    native = json.loads((ROOT/'client/assets/data/hero-parts.json').read_text('utf8'))
    templates = json.loads((ROOT/'analysis/ai-generated/equipment/boneglow/native-frame-templates.json').read_text('utf8'))
    sets, parts = [], {}
    for index, ((set_id, stem, name, job, gender), template) in enumerate(zip(SETS, templates)):
        assert template['stem'] == stem
        sources = list(dict.fromkeys(cell['source'] for cell in template['cells']))
        mapped = {}
        for source in sources:
            part_id = f'boneglow/{stem}/{source}'
            mapped[source] = part_id
            parts[part_id] = dict(texture=f'res://assets/generated/equipment/boneglow/{stem}/parts/{source}.png',
                                  frames=native['parts'][source]['frames'])
        sets.append(dict(id=f'boneglow/{stem}', name=name, stem=stem, job=job, gender=gender,
            weapon_code=28+index, clothing_code=12+index, head_code=10+index,
            head=mapped[sources[0]], body=[mapped[s] for s in sources[1:4]], weapon=mapped[sources[4]],
            design=f'{set_id}-equipment-review.png', source_template=set_id+'-parts-template.png'))
    target = ROOT/'client/assets/data/boneglow-equipment.json'
    target.write_text(json.dumps(dict(format_version=1, source='AI生成；原人物分层动画适配', sets=sets, parts=parts), ensure_ascii=False, indent=2)+'\n', 'utf8')


if __name__ == '__main__':
    publish_manifest()
    print('Published six set definitions and thirty part atlas mappings')
