"""Expose inspected ssjx originals used by the video-based scene compositions."""
import hashlib
import json
from pathlib import Path
from PIL import Image
from import_assets import ROOT, DEST, ANALYSIS, parse_ani, bake, readable_json

def build_assets(parsed=None,write_textures=True):
    result={}
    if write_textures:Image.open(ANALYSIS/'decoded_png/ssjx/neverpic_frame000.png').save(DEST/'ui/portal_tile.png',optimize=True)
    for name in ["m12","m13","m14"]:
        key="map/"+name
        ani=(parsed or {}).get(key) or parse_ani(ANALYSIS/"unpacked/ssjx/map"/(name+".ani"))
        result[key]=bake(key,ani,write_texture=write_textures)
    # m8 exists as a decoded original image, without its own ANI. Only its
    # placement anchor is authored; no new pixels are drawn.
    for name in ["m8","m11"]:
        source=ANALYSIS/"decoded_png/ssjx/map"/(name+"_frame000.png")
        image=Image.open(source).convert("RGBA");w,h=image.size
        if write_textures:image.save(DEST/"actors"/("map_"+name+".png"),optimize=True)
        result["map/"+name]=dict(texture="res://assets/actors/map_"+name+".png",width=w,height=h,columns=1,
            origin=[-w//2,-h+1],anchor_x=0,playback={},count=1,sequences=[[[0,1]]])
    return result

def main():
    assets=build_assets()
    index_path=DEST/"data/actors.json";index=json.loads(index_path.read_text(encoding="utf8"))
    for key,meta in assets.items():
        path=DEST/"data/actors"/(key+".json");path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text(readable_json(meta)+"\n",encoding="utf8",newline="\n")
        index["actors"][key]="res://assets/data/actors/"+key+".json"
    index["actors"]=dict(sorted(index["actors"].items()))
    index_path.write_text(json.dumps(index,ensure_ascii=False,indent=2)+"\n",encoding="utf8",newline="\n")
    print("Original map props and neverpic transfer tile:",list(assets))

if __name__=="__main__":main()
