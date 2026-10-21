"""Build a complete native-map contact index and comparable source-art pairs.

First render native_world_maps_test.tscn with SSJX_MAP_CAPTURE set. Captures are
actual Godot scenes. Before/after pairs deliberately omit residents in BOTH
panels to compare map artwork, not imply recovery of original full-map layouts.
"""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import build_godot_maps as builder

ROOT = builder.ROOT


def artwork(tiles, props):
    atlas=Image.open(ROOT/'client/assets/tiles/original_tiles.png').convert('RGBA')
    out=Image.new('RGBA',(512,512))
    for i,t in enumerate(tiles):
        out.paste(atlas.crop((t%32*16,t//32*16,t%32*16+16,t//32*16+16)),(i%32*16,i//32*16))
    for p in sorted(props,key=lambda p:p['y']):
        info=json.loads((ROOT/'client/assets/data/actors'/f'{p["art"]}.json').read_text())
        texture=Image.open(ROOT/'client'/info['texture'].removeprefix('res://')).convert('RGBA')
        w,h=info['width'],info['height']
        sprite=texture.crop((0,0,w,h))
        out.alpha_composite(sprite,(int(p['x']+info['origin'][0]),int(p['y']+info['origin'][1])))
    return out.convert('RGB')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--captures',type=Path,default=ROOT/'work/map-rebuild/native')
    parser.add_argument('--output',type=Path,default=ROOT/'work/map-rebuild/review')
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True)
    font=ImageFont.truetype(str(ROOT/'client/assets/fonts/NotoSansCJKsc-Regular.otf'),14)
    maps=builder.maps();records=[]
    for start in range(0,len(maps),36):
        page=Image.new('RGB',(1152,1296),'#18262c');draw=ImageDraw.Draw(page)
        for j,m in enumerate(maps[start:start+36]):
            path=args.captures/(m['map_id']+'.png')
            if not path.is_file():raise SystemExit('Missing actual Godot capture: '+str(path))
            tile=Image.open(path).convert('RGB').resize((192,192),Image.Resampling.NEAREST)
            x,y=j%6*192,j//6*216;page.paste(tile,(x,y))
            draw.text((x+3,y+194),m['map_id']+' '+m.get('name',{'qingyun_trail':'青云山道','ancient_ruins':'古剑遗迹'}.get(m['map_id'],'')),font=font,fill='#e9e7cb')
        page.save(args.output/f'all-maps-{start//36+1}.png')
    selected={'qingyun_trail','ancient_ruins','ai_001','ai_007','ai_013','ai_021','ai_022','ai_028','ai_033','ai_047','ai_010','ai_213'}
    for m in maps:
        art=builder.presentation(m['map_id'])
        records.append(dict(map_id=m['map_id'],navigation_sha256=builder.geometry_hash(m),
            changed_tile_count=sum(a!=b for a,b in zip(m['tiles'],art['composite'])),
            building_count=len(art['buildings']),original_scenery_count=len(m['scenery']),
            boundary_scenery_count=len(art['scenery'])-len(m['scenery'])))
        if m['map_id'] not in selected:continue
        pair=Image.new('RGB',(1040,546),'#18262c');draw=ImageDraw.Draw(pair)
        pair.paste(artwork(m['tiles'],m['scenery']),(0,34))
        pair.paste(artwork(art['composite'],art['scenery']),(528,34))
        draw.text((8,7),m['map_id']+' 旧重建地表（非原版地图）',font=font,fill='#e9e7cb')
        draw.text((536,7),'原生重建地表（两侧均隐藏居民）',font=font,fill='#e9e7cb')
        pair.save(args.output/(m['map_id']+'-comparison.png'))
    (args.output/'audit.json').write_text(json.dumps(dict(map_count=len(maps),
        provenance='原包素材及局部截图；全图重建，非原版布局恢复',maps=records),ensure_ascii=False,indent=2)+'\n')
    print(f'Reviewed {len(maps)} actual captures; 6 contact pages; {len(selected)} artwork comparisons')


if __name__=='__main__':main()
