"""Build six black/silver native-layer outfits and independent ten-slot icons."""
import argparse
import hashlib
import io
import json
from pathlib import Path

from PIL import Image
import xuanfeng_native_style as style

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'analysis/ai-generated/equipment/xuanfeng'
OUTPUT=ROOT/'client/assets/generated/equipment/xuanfeng'
SLOTS=['weapon','pendant','armor','wrist','belt','pants','boots','ring','necklace','hat']
LABELS=['武器','腰佩','衣服','手腕','腰带','裤子','鞋子','戒指','项链','帽子']
SUFFIXES=['兵','玄晶佩','行装','护腕','束带','护腿','短靴','佩环','银链','开面盔']
SETS=[('mzs','玄锋·破阵','玄锋阔刃'),('wzs','玄锋·斩月','玄锋钩刃'),
      ('mck','玄锋·逐影','玄锋双刃'),('wck','玄锋·流萤','玄锋反握刃'),
      ('mfs','玄锋·观星','玄晶灵杖'),('wfs','玄锋·照夜','照夜晶杖')]


def encoded(value):return (json.dumps(value,ensure_ascii=False,indent=2)+'\n').encode()


def equipment_items():
    result=[]
    for index,(stem,name,weapon) in enumerate(SETS):
        for slot,label,suffix in zip(SLOTS,LABELS,SUFFIXES):
            result.append(dict(id=f'ai/xuanfeng/{stem}/{slot}',name=weapon if slot=='weapon' else name+'·'+suffix,
                slot=slot,category=label,price=140 if slot=='weapon' else 70,
                attack=14 if slot=='weapon' else 0,defense=0 if slot=='weapon' else 3,
                visual=53+index if slot=='weapon' else 36+index if slot=='armor' else 0,
                head_visual=34+index if slot=='hat' else 0,level=1,job=index//2,gender=index%2,
                icon=f'res://assets/generated/equipment/xuanfeng/{stem}/icons/{slot}.png',restore_hp=0,restore_mp=0,
                sections=['hot','rare'],set_id='xuanfeng/'+stem,set_name=name,
                art_source='像素绘制·原生分层适配·玄锋行装',
                rules_basis='用户确认六角色成品外观；沿用现有新增系列同档售价与属性，十槽无额外套装技能。',
                appearance_basis='开面或半覆面硬盔、黑银衣装、暗红饰边；保留人脸、原生关节与握持。武器、衣服、头部独立换装，其余七槽只有图标与属性。'))
    return result


def build(check=False):
    native=json.loads((ROOT/'client/assets/data/hero-parts.json').read_text('utf8'))
    pending={};parts={};sets=[];report=[];inputs={}
    def load(path):
        absolute=ROOT/'client'/path.removeprefix('res://')
        inputs[absolute.relative_to(ROOT).as_posix()]=hashlib.sha256(absolute.read_bytes()).hexdigest()
        return Image.open(absolute).convert('RGBA')
    def save_image(path,image,frames=None):
        data=io.BytesIO();image.save(data,format='PNG');pending[path]=data.getvalue()
        item=dict(path='res://'+path.relative_to(ROOT/'client').as_posix(),sha256=hashlib.sha256(data.getvalue()).hexdigest())
        if frames is not None:item['native_frames']=frames
        report.append(item);return item['path']
    for index,(stem,name,weapon_name) in enumerate(SETS):
        recipe=native['recipes'][stem];sources=[recipe['sources'][i] for i in [0,1,3,4,2]]
        info_path=ROOT/f'client/assets/data/actors/hero/{stem}.json'
        info=json.loads(info_path.read_text('utf8'));inputs[info_path.relative_to(ROOT).as_posix()]=hashlib.sha256(info_path.read_bytes()).hexdigest()
        reference_path=SOURCE/'reference'/f'{stem}.png'
        reference=Image.open(reference_path).convert('RGBA')
        if reference.size!=(80,80):raise ValueError('Native-size master required: '+stem)
        inputs[reference_path.relative_to(ROOT).as_posix()]=hashlib.sha256(reference_path.read_bytes()).hexdigest()
        samples=style.project_master(native,stem,info,reference,load)
        spec=native['parts'][sources[1]];x,y,w,h=spec['frames'][0]
        base=load(spec['texture']).crop((x,y,x+w,y+h))
        painted=style.apply_projection(style.shade(base,stem),samples.get((sources[1],0),{}))
        primary={}
        for order,source in enumerate(sources):
            spec=native['parts'][source];original=load(spec['texture']);image=Image.new('RGBA',original.size)
            for frame,(x,y,w,h) in enumerate(spec['frames']):
                tile=original.crop((x,y,x+w,y+h));values=samples.get((source,frame),{})
                if order==0:result=style.headwear(tile,stem,frame,values)
                elif order==4:result=style.weapon(tile,stem,frame)
                else:result=style.clothing(tile,stem,['','q','x'][order-1],frame,base,painted,values)
                image.paste(result,(x,y))
                if frame==0:primary[order]=result
            texture=save_image(OUTPUT/stem/'parts'/(source+'.png'),image,spec['frames'])
            parts[f'xuanfeng/{stem}/{source}']=dict(texture=texture,frames=spec['frames'])
        for slot in SLOTS:save_image(OUTPUT/stem/'icons'/(slot+'.png'),style.icon(stem,slot,primary[0],primary[4]))
        sets.append(dict(id='xuanfeng/'+stem,name=name,stem=stem,job=index//2,gender=index%2,
            weapon_code=53+index,clothing_code=36+index,head_code=34+index,
            head=f'xuanfeng/{stem}/{sources[0]}',body=[f'xuanfeng/{stem}/{s}' for s in sources[1:4]],
            weapon=f'xuanfeng/{stem}/{sources[4]}',weapon_name=weapon_name))
    inputs['client/assets/data/hero-parts.json']=hashlib.sha256((ROOT/'client/assets/data/hero-parts.json').read_bytes()).hexdigest()
    pending[ROOT/'client/assets/data/xuanfeng-equipment.json']=encoded(dict(format_version=1,source='用户确认的像素母版；原生分层、关节与动作适配',sets=sets,parts=parts))
    pending[SOURCE/'runtime-import-report.json']=encoded(report)
    pending[SOURCE/'generation-record.json']=encoded(dict(method='Pillow像素部件生产；按可见原生部件回投成品母版，复用完整原生动作；不是整张立绘缩放',
        generator='tools/build_xuanfeng_equipment.py',generator_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        style_module='tools/xuanfeng_native_style.py',style_sha256=hashlib.sha256(Path(style.__file__).read_bytes()).hexdigest(),
        native_inputs=inputs,palette=style.COLORS,codes=dict(weapon=[53,58],clothing=[36,41],head=[34,39]),
        limitations='成品母版用于登记服装与头盔设计；动画由原生部件制作。只有武器、衣服、头部三项独立改变外观。'))
    for path,data in pending.items():
        if check:
            if not path.exists() or path.read_bytes()!=data:raise AssertionError('Not reproducible: '+str(path))
        else:path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
    print('XUANFENG: 6 sets, 30 part atlases, 60 icons '+('byte-identical' if check else 'generated'))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true')
    build(parser.parse_args().check)
