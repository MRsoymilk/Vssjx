"""Fit approved pixel masters to native joints; never scale a whole actor into frames."""
from collections import Counter, defaultdict
from PIL import Image, ImageDraw

COLORS = dict(ink='#28212e', shadow='#373643', cloth='#515262', fold='#727586',
              steel='#9caab2', silver='#cbd6d3', ivory='#f1eee1',
              garnet='#753847', red='#aa5260', gem='#dd8790',
              leather='#4e3938', leather_light='#826354')
C = {k: tuple(bytes.fromhex(v[1:]))+(255,) for k,v in COLORS.items()}
HELMET = {(43,46,59),(59,66,81),(86,98,115),(125,139,155),
          (163,176,183),(210,219,214),(142,70,87),(180,90,103)}
SKIN = {
    'mzs': {(65,24,24),(246,145,139),(222,109,98)},
    'wzs': {(65,24,24),(180,93,90),(238,129,115),(255,194,180)},
    'mck': {(65,24,24),(148,76,82),(213,121,98),(246,157,131)},
    'wck': {(65,24,24),(164,97,98),(230,157,139),(255,210,197)},
    'mfs': {(65,24,24),(131,97,131),(197,137,131),(238,170,164)},
    'wfs': {(65,24,24),(156,109,148),(222,161,172),(255,214,222)},
}
HAIR = {
    'mzs': {(238,242,213):'#dedcca',(189,186,172):'#b2b1a6',(255,255,246):'#f1ecdc',(82,80,82):'#55525a'},
    'wzs': {(123,105,123):'#715e73',(98,72,98):'#493b50',(164,133,156):'#938197',(49,36,65):'#302635'},
    'mck': {(139,190,189):'#91abb0',(123,161,172):'#748e99',(115,129,148):'#596d80',(98,105,139):'#4c5972',(74,72,106):'#373b50',(49,40,57):'#2e2b3b'},
    'wck': {(205,186,213):'#b9a5ba',(180,137,189):'#8f7a92',(148,105,156):'#6a536d',(98,68,106):'#48384d',(74,44,82):'#362b3d'},
    'mfs': {(156,206,255):'#91aabd',(131,157,197):'#6d8197',(123,125,172):'#535d7b',(90,85,139):'#414861',(65,60,98):'#2d3048'},
    'wfs': {(106,93,123):'#655864',(82,64,90):'#51444f',(57,44,65):'#382d38',(90,85,139):'#635d75'},
}
HEAD_BOXES = dict(mzs=(25,24,54,46), wzs=(26,22,58,49), mck=(22,20,62,49),
                  wck=(20,20,60,49), mfs=(27,24,59,59), wfs=(26,24,56,59))
FACE_BOXES = dict(mzs=(12,30,23,35), wzs=(12,29,23,34), mck=(11,29,24,33),
                  wck=(10,30,23,34), mfs=(13,32,23,37), wfs=(14,29,24,36))


def transformed(image, code):
    operations = {1:Image.Transpose.ROTATE_270, 2:Image.Transpose.ROTATE_180,
                  3:Image.Transpose.ROTATE_90, 4:Image.Transpose.FLIP_LEFT_RIGHT,
                  6:Image.Transpose.FLIP_TOP_BOTTOM}
    if code in (5,7):
        return image.transpose(Image.Transpose.FLIP_LEFT_RIGHT).transpose(
            Image.Transpose.ROTATE_270 if code==5 else Image.Transpose.ROTATE_90)
    return image.transpose(operations[code]) if code else image.copy()


def layers_at_idle(native, stem, info, load):
    layers = native['recipes'][stem]['frames'][info['playback']['idle'][0][0]]
    head = next(l for l in layers if l['source']==native['recipes'][stem]['sources'][0] and l['frame']==0)
    center = head['x']+native['parts'][head['source']]['frames'][0][2]//2
    result=[]
    for layer in layers:
        spec=native['parts'][layer['source']];x,y,w,h=spec['frames'][layer['frame']]
        tile=load(spec['texture']).crop((x,y,x+w,y+h))
        coordinates=Image.new('I',tile.size)
        coordinates.putdata(range(tile.width*tile.height))
        result.append((layer,transformed(tile,layer['transform']),
                       transformed(coordinates,layer['transform']),40-center+layer['x'],68+layer['y']))
    return result


def project_master(native,stem,info,reference,load):
    """Project only visible pixels back to their actual part/frame coordinates."""
    layers=layers_at_idle(native,stem,info,load)
    owner={};samples=defaultdict(lambda:defaultdict(Counter))
    for index,(_,tile,coords,ox,oy) in enumerate(layers):
        for y in range(tile.height):
            for x in range(tile.width):
                if tile.getpixel((x,y))[3]:owner[(x+ox,y+oy)]=(index,coords.getpixel((x,y)))
    for (x,y),(index,pixel) in owner.items():
        if not (0<=x<80 and 0<=y<80):continue
        layer=layers[index][0]
        samples[(layer['source'],layer['frame'])][pixel][reference.getpixel((x,y))]+=1
    head_source=native['recipes'][stem]['sources'][0]
    index=next(i for i,v in enumerate(layers) if v[0]['source']==head_source and v[0]['frame']==0)
    layer,tile,coords,ox,oy=layers[index]
    x0,y0,x1,y1=HEAD_BOXES[stem]
    # New helmet silhouettes may occupy formerly transparent hair pixels, but
    # must never steal a hand, weapon or body pixel from a different layer.
    for y in range(tile.height):
        for x in range(tile.width):
            xx,yy=x+ox,y+oy
            if not (x0<=xx<x1 and y0<=yy<y1):continue
            if (xx,yy) in owner and owner[(xx,yy)][0]!=index:continue
            samples[(head_source,0)][coords.getpixel((x,y))][reference.getpixel((xx,yy))]+=1
    return {key:{pixel:counts.most_common(1)[0][0] for pixel,counts in row.items()} for key,row in samples.items()}


def shade(tile,stem,lower=False):
    image=tile.copy();ramp=[C[k] for k in ['ink','shadow','cloth','fold','steel','silver']]
    for y in range(tile.height):
        for x in range(tile.width):
            p=tile.getpixel((x,y));r,g,b,a=p
            if not a:continue
            if p[:3]==(115,93,90):continue  # Ground shadow is not a boot.
            if p[:3] in SKIN[stem] and not lower:continue
            light=(r*3+g*6+b)/10
            level=sum(light>=v for v in [55,100,155,210,242])
            if lower and y>=tile.height-3:
                color=C['ink'] if light<70 else C['leather'] if light<160 else C['leather_light']
            else:color=ramp[min(level,4)]
            image.putpixel((x,y),color)
    return image


def apply_projection(image,pixels):
    image=image.copy()
    for offset,color in pixels.items():image.putpixel((offset%image.width,offset//image.width),color)
    return image


def torso_offset(tile,reference):
    samples=[(x,y,reference.getpixel((x,y))) for y in range(min(8,reference.height))
             for x in range(reference.width) if reference.getpixel((x,y))[3]]
    best=(0,None)
    for dy in range(-2,tile.height-4):
        for dx in range(-5,tile.width-4):
            match=sum(0<=x+dx<tile.width and 0<=y+dy<tile.height and tile.getpixel((x+dx,y+dy))==p for x,y,p in samples)
            if match>best[0]:best=(match,(dx,dy))
    return best[1] if samples and best[0]>=len(samples)*.82 else None


def clothing(tile,stem,suffix,frame,base,painted,samples):
    lower=suffix=='x' or (suffix=='' and frame==1)
    image=shade(tile,stem,lower)
    if suffix=='q':
        at=torso_offset(tile,base)
        if at is not None:
            for y in range(painted.height):
                for x in range(painted.width):
                    xx,yy=x+at[0],y+at[1]
                    if 0<=xx<tile.width and 0<=yy<tile.height and tile.getpixel((xx,yy))[3] and painted.getpixel((x,y))[3]:
                        image.putpixel((xx,yy),painted.getpixel((x,y)))
    image=apply_projection(image,samples)
    # Native arm/leg boundaries and foot contacts cannot grow into rectangles.
    image.putalpha(tile.getchannel('A'))
    return image


def headwear(tile,stem,frame,samples):
    image=tile.copy()
    for y in range(tile.height):
        for x in range(tile.width):
            p=tile.getpixel((x,y))
            if p[3] and p[:3] in HAIR[stem]:image.putpixel((x,y),tuple(bytes.fromhex(HAIR[stem][p[:3]][1:]))+(255,))
    image=apply_projection(image,samples)
    if frame==0:
        # Independent face core: do not let a metal rim erase eyes or cheeks.
        box=FACE_BOXES[stem]
        for y in range(box[1],box[3]):
            for x in range(box[0],box[2]):
                p=tile.getpixel((x,y))
                if p[3] and p[:3] in SKIN[stem]:image.putpixel((x,y),p)
        image.paste(tile.crop((0,tile.height-2,tile.width,tile.height)),(0,tile.height-2))
    else:image.putalpha(tile.getchannel('A'))
    return image


def grid(rows,palette):
    image=Image.new('RGBA',(max(map(len,rows)),len(rows)))
    for y,row in enumerate(rows):
        for x,key in enumerate(row):
            if key!='.':image.putpixel((x,y),palette[key])
    return image


def weapon(tile,stem,frame):
    if stem[1:]!='fs':
        image=tile.copy()
        for y in range(tile.height):
            for x in range(tile.width):
                r,g,b,a=tile.getpixel((x,y))
                if not a:continue
                light=(r+g+b)/3
                color=C['ivory'] if min(r,g,b)>240 else C['silver'] if min(r,g,b)>205 else C['steel'] if min(r,g,b)>165 else C['leather_light'] if r>g*1.2 else C['shadow']
                image.putpixel((x,y),color)
        return image
    image=Image.new('RGBA',tile.size);d=ImageDraw.Draw(image)
    female=stem.startswith('w')
    if female:
        rows=['....kk','..khmmhk','.khmsmhk','khmsksmhk','ksbrtrbsk','ksbtttbsk','ksbtvtbsk','ksbtttbsk','.ksbrrbsk','..ksbbsk','...kbbsk','....kssk','.....kk']
        at=(5,5) if frame==0 else (12,6)
        start=(12,15) if frame==0 else (20,14)
    else:
        rows=['.....kk','...kmmmmk','..kmhmmmbk','.kmhrrrmbsk','kmhrrttrbbsk','kmhrtvtrbbsk','kmmrtttrbbsk','ksmmrrrmbbsk','.ksmmrmmmbsk','..ksmmmmmbsk','...ksbbbssk','....ksbbsk','.....kbbsk','......kbsk','.......ksk','........kk']
        at=(7,6) if frame==0 else (7,3)
        start=(15,20) if frame==0 else (18,15)
    grip=(27,28) if frame==0 else (34,21)
    end=(32,32) if frame==0 else (39,24)
    d.line([start,end],fill=C['ink'],width=4)
    d.line([start,end],fill=C['leather'],width=2)
    d.line([(start[0]+1,start[1]),(end[0]+1,end[1])],fill=C['leather_light'])
    d.rectangle((grip[0]-1,grip[1]-1,grip[0]+1,grip[1]+1),fill=C['leather'])
    palette=dict(k=C['ink'],s=C['shadow'],b=C['cloth'],m=C['steel'],h=C['silver'],r=C['garnet'],t=C['red'],v=C['gem'])
    image.alpha_composite(grid(rows,palette),at)
    return image


def fit_icon(image):
    result=Image.new('RGBA',(32,32));box=image.getbbox()
    if box:
        image=image.crop(box);image.thumbnail((28,28),Image.Resampling.NEAREST)
        result.alpha_composite(image,((32-image.width)//2,(32-image.height)//2))
    return result


def icon(stem,slot,head,main_weapon):
    if slot=='weapon':return fit_icon(main_weapon.rotate(25,Image.Resampling.NEAREST,expand=True))
    if slot=='hat':
        shell=Image.new('RGBA',head.size)
        for y in range(head.height):
            for x in range(head.width):
                p=head.getpixel((x,y))
                if p[3] and p[:3] in HELMET:shell.putpixel((x,y),p)
        return fit_icon(shell)
    image=Image.new('RGBA',(32,32));d=ImageDraw.Draw(image);role=stem[1:];female=stem.startswith('w')
    def shape(points,color):d.polygon(points,fill=C[color],outline=C['ink'])
    def line(points,color,width=1):d.line(points,fill=C[color],width=width)
    if slot=='armor':
        bottom=29 if role=='fs' else 27 if role=='ck' else 24
        shape([(9,4),(13,6),(19,6),(23,4),(28,10),(29,21),(25,22),(22,13),(24,bottom),(18,bottom),(16,22),(14,bottom),(7,bottom),(10,13),(7,22),(3,21),(4,10)],'cloth')
        line([(10,5),(13,11),(11,13),(16,19)],'silver')
        line([(22,5),(19,11),(21,13),(17,19)],'steel')
        line([(11,21),(21,21)],'garnet',2)
        line([(9,bottom-3),(13,bottom-1)],'fold');line([(21,bottom-3),(19,bottom-1)],'fold')
        if female:line([(12,15),(14,18),(19,18),(21,15)],'fold')
        if role=='zs':shape([(5,7),(10,5),(13,10),(8,13),(4,11)],'steel')
    elif slot=='wrist':
        for x,y in [(5,5),(18,13)]:
            shape([(x,y+2),(x+7,y),(x+9,y+11),(x+2,y+13)],'cloth')
            line([(x+1,y+3),(x+7,y+1)],'silver');line([(x+2,y+9),(x+7,y+8)],'red')
    elif slot=='belt':
        shape([(3,11),(10,9),(24,10),(29,13),(27,20),(20,22),(9,20),(3,18)],'cloth')
        line([(5,12),(12,11),(26,13)],'steel');shape([(13,12),(20,12),(21,18),(14,19)],'steel')
        d.rectangle((15,13,18,17),fill=C['garnet']);line([(21,21),(20,29)],'red',2)
    elif slot=='pants':
        shape([(8,4),(23,4),(24,16),(27,28),(18,29),(16,18),(14,29),(5,28),(7,16)],'cloth')
        line([(9,6),(22,6)],'steel');line([(11,10),(10,19),(8,26)],'fold');line([(20,10),(21,20),(23,27)],'fold')
    elif slot=='boots':
        for x,y in [(4,4),(18,10)]:
            shape([(x+2,y),(x+9,y),(x+8,y+10),(x+11,y+14),(x+10,y+16),(x-2,y+16),(x-2,y+12),(x+2,y+9)],'leather')
            line([(x+3,y+2),(x+7,y+2)],'steel');line([(x,y+13),(x+6,y+13)],'leather_light');line([(x+4,y+5),(x+7,y+5)],'garnet')
    elif slot=='ring':
        d.ellipse((7,10,25,28),outline=C['ink'],width=4);d.ellipse((8,11,24,27),outline=C['steel'],width=2)
        shape([(14,3),(21,5),(24,10),(19,16),(12,13),(10,8)],'silver');shape([(16,5),(21,9),(18,13),(13,10)],'garnet');d.point((17,7),fill=C['gem'])
    elif slot=='pendant':
        line([(12,3),(16,8),(20,3)],'steel',2);shape([(16,8),(24,16),(16,25),(8,16)],'steel')
        shape([(16,11),(20,16),(16,21),(12,16)],'garnet');line([(14,24),(12,29)],'red',2);line([(18,24),(20,29)],'shadow',2)
    elif slot=='necklace':
        line([(5,5),(4,12),(8,21),(16,26),(24,21),(28,12),(27,5)],'steel',2)
        shape([(16,19),(21,24),(16,29),(11,24)],'silver');shape([(16,21),(19,24),(16,27),(13,24)],'garnet')
    else:raise ValueError(slot)
    return image
