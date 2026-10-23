"""Build the six 誓约礼装 native outfits and their ten-slot shop definitions."""
import argparse
import hashlib
import io
import json
from pathlib import Path

from PIL import Image
import vow_native_style as style

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'analysis/ai-generated/equipment/vow'
OUTPUT=ROOT/'client/assets/generated/equipment/vow'
SLOTS=['weapon','pendant','armor','wrist','belt','pants','boots','ring','necklace','hat']
LABELS=['武器','腰佩','衣服','手腕','腰带','裤子','鞋子','戒指','项链','帽子']
SUFFIXES=['兵','花结佩','礼装','丝袖','束腰','礼裤','礼鞋','誓戒','珠链','花饰']
SETS=[
    ('mzs','誓约·夜玫','夜玫誓约大剑','ezs9'),
    ('wzs','誓约·白蔷','白蔷誓约大剑','ezs9'),
    ('mck','誓约·银蔷','银蔷花藤双爪','eck9'),
    ('wck','誓约·绯绡','绯绡花藤双爪','eck9'),
    ('mfs','誓约·星兰','星兰花誓法杖','efs7'),
    ('wfs','誓约·月藤','月藤花誓法杖','efs7'),
]


def equipment_items():
    result=[]
    for index,(stem,name,weapon,_) in enumerate(SETS):
        for slot,label,suffix in zip(SLOTS,LABELS,SUFFIXES):
            item_name=weapon if slot=='weapon' else name+'·'+suffix
            if slot=='armor':item_name=name+('婚纱' if stem=='wzs' else '礼裙' if stem.startswith('w') else '西装')
            if slot=='hat' and stem=='wzs':item_name=name+'·短头纱'
            result.append(dict(id=f'ai/vow/{stem}/{slot}',name=item_name,slot=slot,category=label,
                price=140 if slot=='weapon' else 70,attack=14 if slot=='weapon' else 0,
                defense=0 if slot=='weapon' else 3,visual=47+index if slot=='weapon' else 30+index if slot=='armor' else 0,
                head_visual=28+index if slot=='hat' else 0,level=1,job=index//2,gender=index%2,
                icon=f'res://assets/generated/equipment/vow/{stem}/icons/{slot}.png',restore_hp=0,restore_mp=0,
                sections=['hot','rare'],set_id='vow/'+stem,set_name=name,art_source='像素绘制·原生动作适配·誓约礼装',
                rules_basis='用户确认婚纱西装主题；采用现有新增系列同档价格和属性，十槽无额外套装技能。',
                appearance_basis='男士西装翻领、衬衣与胸花；女士分层礼裙、头纱或花冠；力士大剑、侠客双爪、隐者花环水晶法杖配丝绸。头部、衣服、武器独立换装，其余七槽提供属性。'))
    return result


def encoded(value):return (json.dumps(value,ensure_ascii=False,indent=2)+'\n').encode()


def build(stems=None,check=False):
    native=json.loads((ROOT/'client/assets/data/hero-parts.json').read_text('utf8'))
    pending={};sets=[];parts={};inputs={};report=[]
    def save_image(path,image,frames=None):
        buffer=io.BytesIO();image.save(buffer,format='PNG');data=buffer.getvalue()
        pending[path]=data
        entry=dict(path='res://'+path.relative_to(ROOT/'client').as_posix(),sha256=hashlib.sha256(data).hexdigest())
        if frames is not None:entry['native_frames']=frames
        report.append(entry)
        return entry['path']
    for index,(stem,name,weapon_name,weapon_source) in enumerate(SETS):
        if stems and stem not in stems:continue
        sources=[stem+'t'+str(style.HEADS[stem])]+[stem+str(style.BODY[stem])+s for s in ['','q','x']]+[weapon_source]
        reference_spec=native['parts'][sources[1]]
        x,y,w,h=reference_spec['frames'][0]
        reference=Image.open(ROOT/'client'/reference_spec['texture'][6:]).convert('RGBA').crop((x,y,x+w,y+h))
        for order,source in enumerate(sources):
            spec=native['parts'][source];path=ROOT/'client'/spec['texture'][6:]
            inputs[path.relative_to(ROOT).as_posix()]=hashlib.sha256(path.read_bytes()).hexdigest()
            original=Image.open(path).convert('RGBA');image=Image.new('RGBA',original.size)
            for frame,(x,y,w,h) in enumerate(spec['frames']):
                tile=original.crop((x,y,x+w,y+h))
                if order==0:painted=style.headwear(tile,stem,frame)
                elif order==4:painted=style.weapon(tile.size,frame,stem)
                else:painted=style.clothing(tile,stem,['','q','x'][order-1],frame,reference)
                image.paste(painted,(x,y))
            texture=save_image(OUTPUT/stem/'parts'/(source+'.png'),image,spec['frames'])
            parts[f'vow/{stem}/{source}']=dict(texture=texture,frames=spec['frames'])
        for slot in SLOTS:save_image(OUTPUT/stem/'icons'/(slot+'.png'),style.icon(stem,slot))
        sets.append(dict(id='vow/'+stem,name=name,stem=stem,job=index//2,gender=index%2,
            weapon_code=47+index,clothing_code=30+index,head_code=28+index,
            head=f'vow/{stem}/{sources[0]}',body=[f'vow/{stem}/{s}' for s in sources[1:4]],
            weapon=f'vow/{stem}/{weapon_source}',weapon_name=weapon_name))
    pending[ROOT/'client/assets/data/vow-equipment.json']=encoded(dict(format_version=1,
        source='用户确认誓约礼装；原生网格手绘西装礼裙、花饰大剑双爪法杖',sets=sets,parts=parts))
    pending[SOURCE/'runtime-import-report.json']=encoded(report)
    pending[SOURCE/'generation-record.json']=encoded(dict(method='Pillow原生像素网格绘制；沿用原始图层关节与握持坐标，不缩放整身参考图',
        generator='tools/build_vow_equipment.py',generator_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        style_module='tools/vow_native_style.py',style_sha256=hashlib.sha256(Path(style.__file__).read_bytes()).hexdigest(),
        native_inputs=inputs,palette={k:['#'+bytes(c[:3]).hex() for c in v] for k,v in style.CLOTH.items()},
        codes=dict(weapon=[47,52],clothing=[30,35],head=[28,33]),
        features=['男士翻领西装、衬衣、领结、胸花','女士收腰礼裙、分层开衩裙摆、头纱或花冠',
                  '玫瑰护手宽刃大剑、白色缎带','每手三刃花藤爪、粉白丝带','花环水晶杖首、垂落丝绸'] ))
    for path,data in pending.items():
        if check:
            assert path.read_bytes()==data,'Not reproducible: '+str(path)
        else:
            path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
    print(f'VOW: {len(sets)} sets, {len(report)} textures '+('byte-identical' if check else 'generated'))


def migration():
    catalog=json.loads((ROOT/'client/assets/data/shop-v2.json').read_text('utf8'))['items']
    assert sum(i['id'].startswith('ai/vow/') for i in catalog)==60
    quoted=lambda values:','.join("'"+v.replace("'","''")+"'" for v in values)
    lines=['-- Add six ceremonial outfits; preserve existing instances and supply gourd constraints.',
        'ALTER TABLE inventory_items DROP CONSTRAINT inventory_items_definition_id_check;',
        'ALTER TABLE inventory_items DROP CONSTRAINT inventory_items_check;',
        'ALTER TABLE inventory_items DROP CONSTRAINT equipment_quantity_one;',
        'DROP INDEX one_equipped_per_slot;',
        'ALTER TABLE inventory_items DROP COLUMN equipment_slot;',
        'ALTER TABLE inventory_items ADD CONSTRAINT inventory_items_definition_id_check CHECK(definition_id IN ('+quoted(i['id'] for i in catalog)+'));',
        'ALTER TABLE inventory_items ADD COLUMN equipment_slot TEXT GENERATED ALWAYS AS (CASE']
    for slot in SLOTS:
        lines.append(' WHEN definition_id IN ('+quoted(i['id'] for i in catalog if i['slot']==slot)+") THEN '"+slot+"'")
    lines+=[' ELSE NULL END) STORED;',
        'ALTER TABLE inventory_items ADD CONSTRAINT inventory_items_check CHECK(NOT equipped OR (equipment_slot IS NOT NULL AND quantity=1));',
        'ALTER TABLE inventory_items ADD CONSTRAINT equipment_quantity_one CHECK(equipment_slot IS NULL OR quantity=1);',
        'CREATE UNIQUE INDEX one_equipped_per_slot ON inventory_items(character_id,equipment_slot) WHERE equipped;']
    (ROOT/'server/migrations/0038_vow_equipment.sql').write_text('\n'.join(lines)+'\n','utf8')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    parser.add_argument('--stems',nargs='+',choices=[s[0] for s in SETS])
    parser.add_argument('--migration',action='store_true')
    args=parser.parse_args()
    migration() if args.migration else build(args.stems,args.check)
