"""Export original ssjx ANI recipes and lossless part atlases for runtime dress-up."""
import json
from pathlib import Path
from PIL import Image
from import_assets import parse_ani

ROOT=Path(__file__).resolve().parents[1]


def build():
    source=ROOT/'analysis/decoded_png/ssjx/hero'
    output=ROOT/'client/assets/hero_parts';output.mkdir(exist_ok=True)
    groups={}
    for path in source.glob('*_frame*.png'):
        key,frame=path.stem.rsplit('_frame',1)
        groups.setdefault(key,[]).append((int(frame),path))
    parts={}
    for key,files in sorted(groups.items()):
        images=[(index,Image.open(path).convert('RGBA')) for index,path in sorted(files)]
        assert [i for i,_ in images]==list(range(len(images))),key
        width=max(im.width for _,im in images);height=max(im.height for _,im in images)
        atlas=Image.new('RGBA',(width*len(images),height));rects=[]
        for i,im in images:
            atlas.alpha_composite(im,(i*width,0));rects.append([i*width,0,im.width,im.height])
        atlas.save(output/(key+'.png'),optimize=True)
        parts[key]={'texture':'res://assets/hero_parts/'+key+'.png','frames':rects}
    recipes={stem:parse_ani(ROOT/f'analysis/unpacked/ssjx/hero/{stem}.ani') for stem in ['mzs','wzs','mck','wck','mfs','wfs']}
    target=ROOT/'client/assets/data/hero-parts.json'
    target.write_text(json.dumps({'version':1,'source_package':'ssjx/hero.mrp','parts':parts,'recipes':recipes},ensure_ascii=False,separators=(',',':'))+'\n','utf8')
    print(len(parts),'original part atlases;',sum(len(p['frames']) for p in parts.values()),'frames')


if __name__=='__main__':build()
