"""Fit the Unit-01 design reference to recovered pixel silhouettes and anatomy.

The AI sheet is a style reference, never resized into an animation frame.
Source masks, exposed skin and every native joint/attachment are retained.
"""
from pathlib import Path
from PIL import Image

PALETTE = dict(black='#302336', dark='#44324f', shadow='#584267', purple='#775790',
               light='#ad8fc1', pearl='#d3bddc', green='#90c65a', lime='#d4eca0',
               jade_shadow='#4c713e', orange='#d8a254', white='#f0e7e1',
               steel='#b3a9be', red='#a75c70')
COLORS = {key: tuple(bytes.fromhex(value[1:])) + (255,) for key, value in PALETTE.items()}
SHADES = ['black', 'dark', 'shadow', 'purple', 'light', 'pearl']
ICON_SOURCES = dict(hat=29, armor=30, wrist=31, belt=32, pants=33,
                    boots=34, ring=36, necklace=37, pendant=38)
CRESTS = dict(mzs=(23,17), wzs=(24,19), mck=(23,17), wck=(17,17),
              mfs=(27,18), wfs=(25,18))


def skin(color):
    r,g,b,a=color
    # Recovered flesh colors, including highlights and the hand shadow ramp.
    return a and r>=180 and 95<=g<=225 and .46*r<=b<=.93*r and g>=b-14 and r>g*1.06


def ramp(luma):
    return COLORS[SHADES[sum(luma>=v for v in (48,78,113,161,211))]]


def tint(tile, role='body', preserve_skin=True):
    result=Image.new('RGBA',tile.size)
    for y in range(tile.height):
        for x in range(tile.width):
            pixel=tile.getpixel((x,y));r,g,b,a=pixel
            if not a:continue
            if preserve_skin and skin(pixel):
                color=pixel
            elif r>g*1.15 and g>b*1.25 and r>150:
                # Original clasps and piping: gold midtones, jade highlights.
                color=COLORS['orange'] if g<165 else COLORS['green'] if g<220 else COLORS['lime']
            elif g>r*1.08 and g>b*1.08:
                color=COLORS['jade_shadow'] if g<140 else COLORS['green'] if g<220 else COLORS['lime']
            elif role=='weapon' and r>g*1.6 and r>b*1.3 and r>140:
                color=COLORS['jade_shadow'] if r<195 else COLORS['green']
            elif role=='zs' and r>g*1.55 and r>b*1.35 and r>90:
                # Heavy armor's small native red belt/seam becomes jade.
                color=COLORS['jade_shadow'] if r<180 else COLORS['green']
            elif role=='fs' and r>g*1.6 and r>b*1.4 and r>110:
                color=COLORS['jade_shadow'] if r<180 else COLORS['green']
            else:
                color=ramp((r*3+g*6+b)/10)
            result.putpixel((x,y),color)
    return result


def headwear(tile, stem, lower=False):
    # Do not paint over a native face, neck, hair outline or lower-hair seam.
    image=tile.copy()
    if lower:return image
    cx,cy=CRESTS[stem]
    ornament=['  g  ',' gLg ',' oGo ','  g  ','  d  ']
    lookup={'g':'green','L':'lime','o':'orange','G':'jade_shadow','d':'dark'}
    for dy,row in enumerate(ornament):
        for dx,ch in enumerate(row):
            x,y=cx+dx-2,cy+dy
            if ch!=' ' and 0<=x<tile.width and 0<=y<tile.height:
                original=tile.getpixel((x,y))
                if original[3] and not skin(original):image.putpixel((x,y),COLORS[lookup[ch]])
    return image


def weapon(tile):
    image=tint(tile,'weapon',False)
    for y in range(tile.height):
        for x in range(tile.width):
            r,g,b,a=tile.getpixel((x,y))
            if a and min(r,g,b)>185:
                image.putpixel((x,y),COLORS['white'])
    return image


def icon(root:Path,slot,main_weapon):
    image=Image.new('RGBA',(32,32))
    if slot=='weapon':
        source=main_weapon.crop(main_weapon.getbbox()).rotate(35,Image.Resampling.NEAREST,expand=True)
    else:
        source=Image.open(root/f'client/assets/items/original/if{ICON_SOURCES[slot]}.png').convert('RGBA')
        source=tint(source,'icon',False)
        source=source.crop(source.getbbox())
    source.thumbnail((28,28),Image.Resampling.NEAREST)
    image.alpha_composite(source,((32-source.width)//2,(32-source.height)//2))
    return image
