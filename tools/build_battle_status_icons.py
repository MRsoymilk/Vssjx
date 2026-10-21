"""Copy inspected original effect frames byte-for-byte for persistent status badges.
The status mapping is authored; it is not a recovered original protocol table.
"""
import hashlib
import json
from pathlib import Path
import shutil
ROOT = Path(__file__).resolve().parents[1]
MAPPING = {
    "bleed": ("流血", "tx37_frame000", "t03", "红色血痕"),
    "poison": ("中毒", "tx55_frame004", "t25", "绿色毒泡"),
    "sleep": ("睡眠", "tx48_frame002", "t15", "绿色Z字"),
    "silence": ("封印", "tx34_frame000", "t00", "红色嘴形"),
    "regen": ("回春", "tx7_frame001", "t18", "绿色回复十字"),
    "defense": ("护体", "tx15_frame001", "t11", "蓝色盾牌"),
    "crit": ("暴击提升", "tx41_frame000", "t14", "金色星芒"),
    "reflect_physical": ("物理反伤", "tx16_frame000", "t12", "蓝色护环"),
    "reflect_magic": ("法术反伤", "tx27_frame001", "t1", "紫色法印"),
}
def build():
    dest=ROOT/"client/assets/ui/battle_status";dest.mkdir(parents=True,exist_ok=True)
    rows={}
    for key,(name,frame,ani,description) in MAPPING.items():
        source=ROOT/"analysis/decoded_png/ssjx/effect"/(frame+".png")
        raw=source.read_bytes();shutil.copyfile(source,dest/(key+".png"))
        member=ROOT/"analysis/unpacked/ssjx/effect"/(frame.split("_frame")[0]+".imgs")
        rows[key]={"name":name,"texture":"res://assets/ui/battle_status/"+key+".png","source_frame":source.relative_to(ROOT).as_posix(),"source_member":"ssjx/effect.mrp/"+member.name,"source_sha256":hashlib.sha256(member.read_bytes()).hexdigest(),"decoded_sha256":hashlib.sha256(raw).hexdigest(),"reference_animation":ani,"visual":description}
    (dest/"catalog.json").write_text(json.dumps({"version":"battle-status-v1","original_binding_recovered":False,"basis":"原包图像逐字节复制；状态对应、位置与回合角标为本次语义适配","icons":rows},ensure_ascii=False,indent=2)+"\n",encoding="utf8")
if __name__=="__main__":build()
