#!/usr/bin/env python3
"""Decode .img/.imgs custom RGB565 + indexed palette images and .str UTF-16BE text.
Static-only: never executes MR bytecode or ARM code. Inspects files already unpacked.
"""
from pathlib import Path
from collections import Counter
from PIL import Image
import numpy as np
import json

ROOT=Path(__file__).resolve().parent
INPUT=ROOT/'unpacked'
OUTPUT=ROOT/'decoded_png'
TEXT=ROOT/'decoded_text'
DECODER_VERSION=2


def normalize_storage(image, typ):
    # Type 3 is type-2 indexed RLE stored a quarter-turn clockwise. Restore
    # display orientation before applying ANI transforms or layer offsets.
    return image.transpose(Image.Transpose.ROTATE_90) if typ == 3 else image


def rgb565_to_rgba(words, alpha=None):
    # The images store big-endian RGB565 palette entries / raw pixels.
    w=np.asarray(words,dtype=np.uint16)
    red=((w>>11)&31).astype(np.uint16)*255//31
    green=((w>>5)&63).astype(np.uint16)*255//63
    blue=(w&31).astype(np.uint16)*255//31
    if alpha is None:
        aa=np.full(w.shape,255,dtype=np.uint8)
    else:aa=np.asarray(alpha,dtype=np.uint8)
    return np.stack((red.astype(np.uint8),green.astype(np.uint8),blue.astype(np.uint8),aa),axis=-1)


def image_palette(idx,colors,width,height):
    colors=np.asarray(colors,dtype=np.uint16)
    if np.max(idx,initial=0)>=len(colors):raise ValueError('palette index out of bounds')
    table=rgb565_to_rgba(colors, (np.arange(len(colors))!=0).astype(np.uint8)*255)
    # For indexed graphics, palette 0 is the transparent pixel.
    rgba=table[np.asarray(idx,dtype=np.uint8)]
    return Image.fromarray(rgba.reshape(height,width,4),'RGBA')


def read_palette(data):
    if len(data)%2:raise ValueError('bad palette length')
    return np.frombuffer(data,dtype='>u2')


def expand_rle(data,w,h,pc):
    if not data: return np.zeros((w*h,),dtype=np.uint8)
    if len(data)%2:raise ValueError('odd-length indexed RLE')
    vals=np.frombuffer(data,dtype=np.uint8)
    idx=vals[::2]
    counts=vals[1::2]
    if idx.max(initial=0)>=pc:raise ValueError('RLE palette index out of range')
    if int(counts.sum())!=w*h:raise ValueError(f'RLE pixel count {counts.sum()} != {w*h}')
    return np.repeat(idx,counts)


def decode_img(blob):
    typ,w,h=blob[:3]
    if w*h==0:raise ValueError('zero dimensions')
    if typ==0:
        if len(blob)!=4+2*w*h:raise ValueError('raw image length mismatch')
        pixels=np.frombuffer(blob[4:],dtype='>u2')
        return Image.fromarray(rgb565_to_rgba(pixels).reshape(h,w,4),'RGBA')
    if typ==1:
        pixels=blob[3:3+w*h]
        count=blob[3+w*h]
        palbytes=blob[4+w*h:]
        if len(palbytes)==count*2+1 and palbytes[:1]==b'\x00':
            palbytes=palbytes[1:]  # optional zero alignment pad in some original assets
        palette=read_palette(palbytes)
        if len(palette)!=count:raise ValueError('raw indexed palette length mismatch')
        return image_palette(np.frombuffer(pixels,dtype=np.uint8),palette,w,h)
    if typ in (2,3):
        sz=int.from_bytes(blob[3:7],'big')
        if 7+sz>=len(blob):raise ValueError('RLE payload outside file')
        data=blob[7:7+sz];count=blob[7+sz]
        palette=read_palette(blob[8+sz:])
        if len(palette)!=count:raise ValueError('RLE palette length mismatch')
        pixels=expand_rle(data,w,h,count)
        return normalize_storage(image_palette(pixels,palette,w,h),typ)
    raise ValueError(f'unsupported image type {typ}')


def decode_imgs(blob):
    if blob[0]!=1:raise ValueError('unexpected spriteset type')
    count=blob[1]
    palette=read_palette(blob[2:2+count*2]);pos=2+2*count
    frames=blob[pos];pos+=1
    out=[]
    for j in range(frames):
        if pos+3>len(blob):raise ValueError('truncated frame')
        typ,w,h=blob[pos:pos+3];pos+=3
        if w*h==0:raise ValueError('zero frame dimensions')
        if typ==1:
            ln=w*h;data=blob[pos:pos+ln];pos+=ln
            if len(data)!=ln:raise ValueError('short indexed frame')
            pixels=np.frombuffer(data,dtype=np.uint8)
        elif typ in (2,3):
            if pos+4>len(blob):raise ValueError('short frame length')
            ln=int.from_bytes(blob[pos:pos+4],'big');pos+=4
            data=blob[pos:pos+ln];pos+=ln
            if len(data)!=ln:raise ValueError('short RLE frame')
            pixels=expand_rle(data,w,h,count)
        else:raise ValueError(f'unsupported frame type {typ}')
        out.append(normalize_storage(image_palette(pixels,palette,w,h),typ))
    if pos!=len(blob):raise ValueError(f'trailing bytes {len(blob)-pos}')
    return out


def decode_str(blob):
    groups=[];pos=0
    while pos<len(blob):
        count=blob[pos];pos+=1;strings=[]
        for i in range(count):
            if pos+2>len(blob):raise ValueError('short string length')
            size=int.from_bytes(blob[pos:pos+2],'big');pos+=2
            if pos+size>len(blob):raise ValueError('string outside file')
            strings.append(blob[pos:pos+size].decode('utf-16-be'))
            pos+=size
        groups.append(strings)
    return groups


def main():
    OUTPUT.mkdir(exist_ok=True);TEXT.mkdir(exist_ok=True)
    stats=Counter();errors=[];asset_meta=[]
    for f in sorted(INPUT.rglob('*')):
        if not f.is_file():continue
        rel=f.relative_to(INPUT); ext=f.suffix.lower();blob=f.read_bytes()
        if ext not in ('.img','.imgs','.str'):continue
        try:
            if ext=='.str':
                groups=decode_str(blob)
                out=TEXT/rel.with_suffix('.txt');out.parent.mkdir(exist_ok=True,parents=True)
                out.write_text('\n\n'.join('\n'.join(f'{i+1:03d}. {s}' for i,s in enumerate(group)) for group in groups),'utf-8')
                stats['text_files']+=1
                stats['text_items']+=sum(len(g) for g in groups)
            else:
                images=[decode_img(blob)] if ext=='.img' else decode_imgs(blob)
                for i,img in enumerate(images):
                    dest=OUTPUT/rel.parent/((f.stem+'.png') if ext=='.img' else (f.stem+f'_frame{i:03d}.png'))
                    dest.parent.mkdir(parents=True,exist_ok=True)
                    img.save(dest,optimize=True)
                    asset_meta.append({'file':str(rel),'frame':i,'png':str(dest.relative_to(ROOT)),'width':img.width,'height':img.height,'source_sha256':None})
                stats['image_files']+=1;stats['png_frames']+=len(images)
        except Exception as e:
            errors.append({'file':str(rel),'error':str(e)})
            stats['failed_files']+=1
    (ROOT/'image_manifest.json').write_text(json.dumps({'decoder_version':DECODER_VERSION,'orientation_normalized':True,'stats':dict(stats),'errors':errors,'images':asset_meta},ensure_ascii=False,indent=2),'utf-8')
    print('stats',dict(stats),'errors',len(errors))
    for v in errors[:20]:print(v)

if __name__=='__main__': main()
