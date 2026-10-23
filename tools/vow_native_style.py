"""Hand-authored ceremonial pixels in the recovered native joint/weapon grids.

Clothing uses the original limb poses; new lapels, bodices, split skirts and
floral weapons are drawn at native resolution, with binary transparency.
"""
from PIL import Image, ImageDraw


def rgba(value):
    return tuple(bytes.fromhex(value))+(255,)


def ramp(values):
    return [rgba(value) for value in values.split()]


GOLD = ramp('534348 8a694b b89963 e1c58d fce5b1 fff8de')
SILVER = ramp('3b4052 67748a 91a4b6 c6d1d7 e7eeed fffff3')
WHITE = ramp('706779 a59aab c7bfc9 e5dce2 f6eee9 fffcf2')
LEAF = ramp('263a36 46624c 7d9c70 c1d3a2')
FLOWERS = {
    'zs': ramp('602e43 a43f59 db687b f4a5a4 ffe2ce'),
    'ck': ramp('734458 a7627b d893a3 f4c0c1 ffe9de'),
    'fs': ramp('554166 8865a4 b398d0 dfccef fff0f5'),
}
CLOTH = {
    'mzs': ramp('242433 363440 4c4651 68616a 8c8186 b5a6a2'),
    'wzs': ramp('766873 a99b9e cbc1bb e7e0d3 f8f0dc fffcf0'),
    'mck': ramp('242735 373d49 525967 747b87 969eaa c4c7cb'),
    'wck': ramp('806474 ab8692 d3afb5 e8cbd0 f8e4df fff8ed'),
    'mfs': ramp('20283e 28334d 344461 4b607e 6c82a1 9aaac1'),
    'wfs': ramp('6f627f 9b8da9 c0b2cf dfcfe5 f0e5f2 fff8f6'),
}
# Exact recovered skin ramps, including their dark edges; the floor shadow is
# also excluded from cloth recoloring. Pale shirt pixels are not classified as skin.
SKIN = {
    'mzs': {(65,24,24),(246,145,139),(222,109,98)},
    'wzs': {(65,24,24),(180,93,90),(238,129,115),(255,194,180)},
    'mck': {(65,24,24),(148,76,82),(213,121,98),(246,157,131)},
    'wck': {(65,24,24),(164,97,98),(230,157,139),(255,210,197)},
    'mfs': {(65,24,24),(131,97,131),(197,137,131),(238,170,164)},
    'wfs': {(65,24,24),(156,109,148),(222,161,172),(255,214,222)},
}
FLOOR = (115,93,90)
HEADS = dict(mzs=7, wzs=5, mck=5, wck=1, mfs=2, wfs=2)
BODY = dict(mzs=4, wzs=4, mck=2, wck=2, mfs=4, wfs=5)


def flower(draw, x, y, role, small=False):
    p=FLOWERS[role]
    if small:
        draw.line([(x-1,y),(x+1,y)],fill=p[1])
        draw.line([(x,y-1),(x,y+1)],fill=p[2])
        draw.point((x,y),fill=p[4])
        return
    draw.polygon([(x-1,y-2),(x+1,y-2),(x+2,y-1),(x+2,y+1),
                  (x+1,y+2),(x-1,y+2),(x-2,y+1),(x-2,y-1)],fill=p[0])
    draw.line([(x-1,y-1),(x+1,y-1),(x+1,y+1),(x-1,y+1)],fill=p[2])
    draw.point((x-1,y-1),fill=p[4]);draw.point((x,y),fill=p[1])


def headwear(tile, stem, frame):
    if frame:return tile.copy()  # Native hair/neck attachment stays exact.
    image=tile.copy();d=ImageDraw.Draw(image);role=stem[1:]
    # Positions reviewed against each selected hairdo, above the face.
    centers=dict(mzs=(27,24),wzs=(28,23),mck=(28,24),wck=(28,23),mfs=(29,22),wfs=(24,21))
    x,y=centers[stem]
    if stem=='wzs':
        # Short veil sits behind the bun, keeping the lower attachment untouched.
        veil=Image.new('RGBA',tile.size);v=ImageDraw.Draw(veil)
        v.polygon([(x,y-4),(x+6,y-1),(39,37),(33,40),(30,34)],fill=WHITE[2])
        v.line([(x+3,y-2),(35,31),(37,37),(33,39)],fill=WHITE[5])
        v.line([(x+1,y),(33,32),(34,37)],fill=WHITE[3])
        for px,py in [(36,33),(38,36),(35,38),(34,29)]:v.point((px,py),fill=WHITE[5])
        veil.alpha_composite(tile);image=veil;d=ImageDraw.Draw(image)
    if stem in ('wck','wfs'):
        d.line([(x-6,y+1),(x-3,y-1),(x+3,y-1),(x+6,y+2)],fill=LEAF[1])
        flower(d,x-4,y,role,True);flower(d,x+4,y+1,role,True)
    d.line([(x-3,y+1),(x-2,y+3),(x+3,y+2)],fill=LEAF[2])
    flower(d,x,y,role,small=stem.startswith('m'))
    if stem.startswith('w'):
        d.line([(x+2,y+2),(x+4,y+5),(x+3,y+7)],fill=WHITE[4])
    # Protect all native face pixels and the last three seam rows.
    flesh=[(px,py) for py in range(tile.height) for px in range(tile.width)
           if tile.getpixel((px,py))[:3] in SKIN[stem] and tile.getpixel((px,py))[3]
           and tile.getpixel((px,py))[:3]!=(65,24,24)]
    if flesh:
        left=min(p[0] for p in flesh);top=min(p[1] for p in flesh)
        right=max(p[0] for p in flesh)+1;bottom=max(p[1] for p in flesh)+1
        image.paste(tile.crop((left,top,right,bottom)),(left,top))
    image.paste(tile.crop((0,tile.height-3,tile.width,tile.height)),(0,tile.height-3))
    return image


def shaded(tile,stem):
    image=tile.copy();p=CLOTH[stem]
    for y in range(tile.height):
        for x in range(tile.width):
            r,g,b,a=tile.getpixel((x,y))
            if not a or (r,g,b) in SKIN[stem] or (r,g,b)==FLOOR:continue
            light=(r*3+g*6+b)/10
            level=sum(light>=v for v in (43,75,116,161,211))
            if stem.startswith('m'):level=min(4,level)
            image.putpixel((x,y),p[level])
    return image


def shirt(stem):
    """Small authored torso overlays, registered to their original shoulder pose."""
    sizes=dict(mzs=(19,13),wzs=(13,11),mck=(21,19),wck=(15,12),mfs=(28,17),wfs=(22,14))
    image=Image.new('RGBA',sizes[stem]);d=ImageDraw.Draw(image)
    p=CLOTH[stem];metal=GOLD if stem[1:]=='zs' else SILVER
    if stem=='mzs':
        d.polygon([(4,3),(8,2),(11,5),(10,11),(3,11)],fill=p[1])
        d.polygon([(6,3),(9,3),(9,9),(7,10)],fill=WHITE[4])
        d.line([(4,3),(6,6),(5,7),(7,10)],fill=p[4])
        d.line([(10,3),(9,6),(11,7),(9,10)],fill=metal[2])
        d.polygon([(10,1),(13,1),(16,3),(16,6),(12,7),(11,4)],fill=p[2])
        d.line([(11,1),(14,2),(16,4)],fill=p[3])
        d.line([(7,4),(9,4)],fill=FLOWERS['zs'][1]);flower(d,12,4,'zs',True)
        d.point((8,8),fill=metal[4]);d.line([(3,11),(10,11)],fill=metal[2])
    elif stem=='mck':
        d.polygon([(12,3),(13,4),(14,6),(12,7),(11,5)],fill=p[2])
        d.line([(12,7),(14,6)],fill=WHITE[4])
        d.line([(3,5),(4,6)],fill=p[2],width=2)
        d.polygon([(7,1),(11,1),(10,6),(9,8)],fill=WHITE[4])
        d.line([(6,2),(8,5),(7,6),(9,8)],fill=p[4])
        d.line([(12,2),(10,4),(12,6),(10,8)],fill=metal[2])
        d.line([(8,2),(10,2)],fill=FLOWERS['ck'][1]);flower(d,12,4,'ck',True)
        d.point((9,7),fill=metal[4]);d.line([(6,9),(11,9)],fill=p[0])
    elif stem=='mfs':
        d.polygon([(5,4),(9,4),(8,7),(7,11),(5,12)],fill=WHITE[4])
        d.line([(4,5),(5,8),(4,9),(5,12)],fill=metal[3])
        d.line([(10,5),(8,8),(9,9),(6,12)],fill=p[4])
        d.line([(6,5),(8,5)],fill=FLOWERS['fs'][1]);flower(d,10,6,'fs',True)
        d.point((6,10),fill=metal[4]);d.line([(2,13),(8,13)],fill=metal[2])
    elif stem=='wzs':
        d.polygon([(4,5),(6,6),(8,5),(9,8),(3,8)],fill=p[4])
        d.line([(4,5),(6,6),(8,5)],fill=p[5])
        d.line([(4,7),(8,7)],fill=GOLD[2]);d.point((6,7),fill=GOLD[4])
    elif stem=='wck':
        d.polygon([(4,5),(7,5),(9,6),(8,8),(4,8)],fill=p[4])
        d.line([(4,5),(6,6),(8,5)],fill=WHITE[5])
        d.line([(4,8),(8,8)],fill=GOLD[3]);d.point((8,7),fill=FLOWERS['ck'][1])
    else:
        d.polygon([(5,7),(8,7),(9,9),(8,11),(5,10)],fill=p[4])
        d.line([(5,8),(8,9)],fill=SILVER[3]);d.point((7,9),fill=FLOWERS['fs'][1])
    return image


def torso_offset(tile, reference):
    # Native compound attack frames contain this exact upper-body patch, often
    # shifted by several pixels. Require a strong match rather than guessing.
    samples=[(x,y,reference.getpixel((x,y))) for y in range(min(reference.height,9))
             for x in range(reference.width) if reference.getpixel((x,y))[3]]
    best=(0,None)
    for dy in range(-2,tile.height-5):
        for dx in range(-5,tile.width-5):
            match=sum(0<=x+dx<tile.width and 0<=y+dy<tile.height and tile.getpixel((x+dx,y+dy))==p
                      for x,y,p in samples)
            if match>best[0]:best=(match,(dx,dy))
    return best[1] if best[0]>=len(samples)*.82 else None


def clothing(tile,stem,suffix,frame,reference):
    image=shaded(tile,stem);p=CLOTH[stem]
    if stem=='mck' and suffix=='q' and frame in (1,3):
        for y in range(tile.height):
            for x in range(4,tile.width):
                pixel=tile.getpixel((x,y))
                if pixel[3] and pixel[:3] in SKIN[stem] and pixel[:3]!=(65,24,24):
                    image.putpixel((x,y),WHITE[3] if x==4 else p[2])
    offset=torso_offset(tile,reference) if suffix!='x' else None
    if offset is not None:
        overlay=shirt(stem);clipped=Image.new('RGBA',tile.size)
        clipped.alpha_composite(overlay,offset)
        for y in range(tile.height):
            for x in range(tile.width):
                if not tile.getpixel((x,y))[3]:clipped.putpixel((x,y),(0,0,0,0))
        image.alpha_composite(clipped)
    # Hem folds follow each original leg pose, so every walking/attack variant
    # has a divided skirt or coat tails with its own native foot placement.
    lower=suffix=='x' or (suffix=='' and frame==(2 if stem=='wfs' else 1))
    full=suffix=='q' and tile.height>=17
    if lower or full:
        start=0 if lower else max(9,tile.height-11)
        bottom=tile.height-4
        if stem=='wck':
            # Replace the recovered bare upper thigh with the dress's front
            # panel. Keep the ankle/foot and the native split between legs.
            for y in range(start,bottom):
                for x in range(tile.width):
                    before=tile.getpixel((x,y))
                    if before[3] and before[:3] in SKIN[stem] and before[:3]!=(65,24,24):
                        image.putpixel((x,y),p[3] if x%4 else p[4])
        for y in range(start,bottom):
            garment=[x for x in range(tile.width) if tile.getpixel((x,y))[3]
                     and tile.getpixel((x,y))[:3] not in SKIN[stem] and tile.getpixel((x,y))[:3]!=FLOOR]
            if not garment:continue
            left,right=min(garment),max(garment)
            if stem.startswith('w'):
                # A short front panel leaves a leg slit; the rear tier is longer.
                for x in garment:
                    if y==bottom-1 or (y==bottom-3 and x>left+2):
                        image.putpixel((x,y),p[5] if (x+y)%3 else p[2])
                    elif x==right-2:image.putpixel((x,y),p[5])
            else:
                for x in garment:
                    if x==left+2 and y<bottom-1:image.putpixel((x,y),p[3])
                    if y==bottom-1 and x>right-3:image.putpixel((x,y),p[0])
    return image


class Pen:
    """Integer polygon pen in each native weapon's measured grip coordinates."""
    def __init__(self,size,origin=(0,0),axis=(1,0)):
        self.image=Image.new('RGBA',size);self.draw=ImageDraw.Draw(self.image)
        self.origin=origin;self.axis=axis
    def at(self,p):
        x,y=p;a,b=self.axis;ox,oy=self.origin
        return (round(ox+a*x-b*y),round(oy+b*x+a*y))
    def poly(self,points,fill,outline=None):
        self.draw.polygon([self.at(p) for p in points],fill=fill,outline=outline)
    def line(self,points,fill,width=1):
        self.draw.line([self.at(p) for p in points],fill=fill,width=width)
    def bloom(self,x,y,role,small=False):flower(self.draw,*self.at((x,y)),role,small)


def sword(size,frame,stem):
    # Canonical pommel (7,19), grip (18,19), guard (32,19); second
    # native pose is the same shaft tilted 30 degrees, not a resized sheet.
    pen=Pen(size,(0,0)) if frame==0 else Pen(size,(-6,22),(.8660254,-.5))
    pen.poly([(6,17),(10,15),(13,19),(10,23),(6,21)],GOLD[2],GOLD[0])
    pen.line([(11,19),(33,19)],GOLD[0],5)
    pen.line([(12,18),(31,18)],CLOTH['mzs'][3],2)
    for x in range(14,29,4):pen.line([(x,18),(x+1,20)],GOLD[2])
    pen.poly([(32,13),(59,12),(72,19),(59,26),(32,25)],SILVER[1],SILVER[0])
    pen.poly([(34,14),(59,13),(69,19),(34,19)],SILVER[4])
    pen.poly([(34,20),(69,19),(58,25),(34,24)],SILVER[2])
    pen.line([(36,19),(64,19)],WHITE[5]);pen.line([(38,16),(56,16)],GOLD[3])
    pen.poly([(28,10),(32,9),(35,13),(35,25),(32,29),(28,28),(31,22),(31,16)],GOLD[2],GOLD[0])
    pen.line([(30,11),(33,12),(33,26),(30,27)],GOLD[4])
    pen.line([(31,23),(26,27),(20,25),(17,30),(11,31)],WHITE[1],3)
    pen.line([(31,23),(26,26),(20,25),(17,29),(11,30)],WHITE[4])
    pen.line([(33,24),(36,29),(32,33),(25,32)],WHITE[3],2)
    pen.line([(29,16),(27,13),(30,12)],LEAF[2],2)
    pen.bloom(32,18,'zs');pen.bloom(30,23,'zs',True)
    return pen.image


def claws(size,frame,stem):
    pen=Pen(size) if frame==0 else Pen(size,(-5,25),(.7071068,-.7071068))
    pen.poly([(25,3),(35,3),(38,6),(35,10),(25,10),(23,6)],SILVER[1],SILVER[0])
    pen.line([(28,4),(35,4),(36,6)],GOLD[3])
    # Three separated hooked blades, in both native orientations. The native
    # recipe places this part on each hand, giving an actual pair of claws.
    for y in (1,6,11):
        pen.poly([(27,y),(22,y-1),(12,y),(8,y+2),(16,y+1),(24,y+2)],SILVER[2],SILVER[0])
        pen.line([(11,y+1),(17,y),(24,y)],SILVER[5])
    pen.line([(29,4),(32,7),(28,9),(26,7),(29,4)],LEAF[1])
    pen.line([(31,9),(28,12),(21,12),(18,10)],WHITE[3],2)
    pen.bloom(29,6,'ck');pen.bloom(34,8,'ck',True)
    return pen.image


def staff(size,frame,stem):
    image=Image.new('RGBA',size);d=ImageDraw.Draw(image)
    center=(10,10) if frame==0 else (11,10)
    end=(36,37) if frame==0 else (46,26)
    x,y=center
    d.line([center,end],fill=SILVER[0],width=4)
    d.line([(x+1,y),(end[0]+1,end[1])],fill=GOLD[2],width=2)
    d.line([(x+2,y),(end[0]+1,end[1]-1)],fill=SILVER[4])
    d.ellipse((x-8,y-8,x+8,y+8),fill=SILVER[0])
    d.ellipse((x-7,y-7,x+7,y+7),fill=LEAF[1])
    d.ellipse((x-5,y-5,x+5,y+5),fill=(0,0,0,0))
    d.arc((x-7,y-7,x+7,y+7),180,330,fill=GOLD[3],width=1)
    d.polygon([(x,y-5),(x+3,y),(x,y+5),(x-3,y)],fill=FLOWERS['fs'][1])
    d.line([(x,y-4),(x-2,y),(x,y+3)],fill=FLOWERS['fs'][3])
    d.point((x,y-3),fill=WHITE[5])
    for dx,dy in [(-5,-5),(5,-4),(-5,5),(5,5)]:flower(d,x+dx,y+dy,'fs',True)
    flower(d,x,y-7,'fs')
    d.line([(x-3,y+7),(x-1,y+13),(x-4,y+17),(x-3,y+21)],fill=WHITE[1],width=3)
    d.line([(x-3,y+7),(x,y+13),(x-3,y+17),(x-2,y+21)],fill=WHITE[4])
    d.line([(x+5,y+6),(x+10,y+10),(x+8,y+16)],fill=FLOWERS['fs'][2],width=2)
    return image


def weapon(size,frame,stem):
    return {'zs':sword,'ck':claws,'fs':staff}[stem[1:]](size,frame,stem)


def icon(stem,slot):
    """Ten native-size item silhouettes with matching tailoring and florals."""
    image=Image.new('RGBA',(32,32));d=ImageDraw.Draw(image)
    role=stem[1:];female=stem.startswith('w');p=CLOTH[stem]
    metal=GOLD if role=='zs' else SILVER;ink=p[0]
    def shape(points,fill):d.polygon(points,fill=fill,outline=ink)
    def line(points,fill,width=1):d.line(points,fill=fill,width=width)
    def bloom(x,y,small=False):flower(d,x,y,role,small)
    if slot=='weapon':
        if role=='zs':
            shape([(5,24),(20,4),(26,2),(26,8),(9,27)],SILVER[3])
            line([(9,23),(23,6)],SILVER[5]);line([(7,21),(12,26)],metal[3],3)
            line([(3,29),(8,24)],ink,3);line([(4,29),(8,25)],metal[2])
            line([(10,25),(17,25),(18,29)],WHITE[4],2);bloom(10,23)
        elif role=='ck':
            for x,y in [(3,4),(13,15)]:
                shape([(x+9,y+2),(x+14,y+4),(x+13,y+9),(x+7,y+8)],SILVER[2])
                for offset in (0,4,8):
                    line([(x+offset,y),(x+offset-1,y+6),(x+7,y+9)],ink,3)
                    line([(x+offset,y),(x+offset,y+6),(x+7,y+8)],SILVER[5])
                bloom(x+10,y+6);line([(x+11,y+9),(x+9,y+12)],WHITE[4])
        else:
            line([(7,28),(22,8)],ink,4);line([(7,28),(22,8)],metal[3],2)
            d.ellipse((14,2,29,17),outline=LEAF[1],width=2)
            shape([(22,5),(25,10),(21,14),(19,9)],FLOWERS[role][2])
            line([(22,6),(21,10),(22,12)],WHITE[5]);bloom(17,5);bloom(27,12,True)
            line([(18,16),(14,20),(17,23),(15,26)],WHITE[4],2)
    elif slot=='armor':
        if female:
            shape([(11,4),(15,6),(20,4),(22,9),(19,14),(23,21),(28,29),(4,29),(9,20),(12,14),(9,9)],p[3])
            line([(11,5),(15,8),(20,5)],WHITE[5]);line([(12,14),(19,14)],metal[3],2)
            shape([(13,16),(16,17),(12,27),(7,27)],p[4])
            line([(20,19),(24,27),(16,27)],p[5]);line([(9,22),(18,24),(24,22)],p[1])
            line([(6,28),(25,28)],WHITE[5]);bloom(19,13,True)
        else:
            shape([(10,4),(14,6),(18,6),(22,4),(27,9),(29,21),(24,22),(22,13),(23,28),(18,29),(16,23),(14,29),(8,28),(10,13),(7,22),(3,21),(5,9)],p[1])
            shape([(12,5),(20,5),(17,18),(15,18)],WHITE[4])
            line([(10,6),(13,11),(11,12),(15,19)],p[4])
            line([(22,6),(19,11),(21,12),(17,19)],metal[2])
            line([(14,7),(18,7)],FLOWERS[role][1],2);bloom(22,11,True)
            line([(15,21),(18,21)],metal[2]);d.point((17,18),fill=metal[5])
            line([(4,20),(7,20)],WHITE[4]);line([(25,20),(28,20)],WHITE[4])
    elif slot=='hat':
        if female:
            if role=='zs':
                shape([(9,7),(22,7),(28,28),(23,27),(19,29),(12,27),(5,29)],WHITE[2])
                line([(10,10),(8,25),(13,24),(16,27),(22,25),(25,26)],WHITE[5])
            line([(6,16),(10,10),(16,8),(23,11),(27,17)],LEAF[1],2)
            for x,y in [(10,11),(16,9),(23,12)]:bloom(x,y)
            line([(24,14),(27,21),(24,25)],WHITE[4],2)
        else:
            shape([(6,16),(11,10),(17,8),(23,12),(27,17),(22,23),(12,23)],p[1])
            line([(7,17),(13,19),(22,18),(25,16)],metal[3],2);bloom(20,14)
            line([(21,17),(24,22)],WHITE[4])
    elif slot=='wrist':
        for x,y in [(4,6),(18,13)]:
            shape([(x,y),(x+8,y-2),(x+10,y+9),(x+2,y+12)],p[3])
            line([(x+2,y+2),(x+8,y)],WHITE[5],2);line([(x+3,y+9),(x+9,y+7)],metal[3])
            bloom(x+5,y+5,True)
    elif slot=='belt':
        shape([(3,11),(10,9),(23,9),(29,12),(27,19),(20,21),(10,20),(4,18)],p[2])
        line([(5,12),(11,11),(24,11),(27,13)],metal[4]);line([(6,17),(13,19),(24,18)],WHITE[4])
        shape([(14,20),(18,20),(15,29),(11,27)],p[4]);bloom(17,15)
    elif slot=='pants':
        shape([(8,4),(23,4),(24,14),(27,27),(18,29),(16,16),(14,28),(5,27),(7,14)],p[2])
        line([(10,8),(9,18),(8,25)],p[4]);line([(21,8),(22,19),(24,26)],p[4])
        line([(9,6),(22,6)],metal[2]);bloom(21,8,True)
    elif slot=='boots':
        for x,y in [(4,5),(18,10)]:
            shape([(x+2,y),(x+9,y),(x+8,y+10),(x+11,y+13),(x+10,y+16),(x-2,y+16),(x-2,y+12),(x+2,y+9)],p[1] if not female else p[3])
            line([(x+3,y+2),(x+7,y+2)],metal[3]);line([(x,y+13),(x+7,y+13)],p[5])
            bloom(x+5,y+5,True)
    elif slot=='ring':
        d.ellipse((6,9,25,28),outline=metal[0],width=4)
        d.ellipse((7,10,24,27),outline=metal[3],width=2)
        d.arc((7,10,24,27),80,230,fill=metal[5],width=2)
        shape([(16,3),(22,5),(25,9),(20,15),(13,13),(11,8)],metal[2])
        bloom(18,9);d.point((22,7),fill=WHITE[5])
    elif slot=='pendant':
        line([(13,3),(16,7),(19,3)],metal[3],2)
        shape([(16,8),(24,16),(16,25),(8,16)],metal[2])
        shape([(16,10),(21,16),(16,22),(11,16)],WHITE[4]);bloom(16,15)
        line([(14,24),(12,29)],WHITE[4],2);line([(18,24),(20,29)],FLOWERS[role][2],2)
    elif slot=='necklace':
        line([(5,5),(4,11),(8,20),(16,25),(24,20),(28,11),(27,5)],metal[1],2)
        for x,y in [(5,8),(5,13),(8,18),(12,21),(20,21),(24,18),(27,13),(27,8)]:
            d.rectangle((x-1,y-1,x+1,y+1),fill=WHITE[4]);d.point((x-1,y-1),fill=WHITE[5])
        bloom(16,24);line([(16,27),(16,29)],metal[3])
    else:raise ValueError(slot)
    return image
