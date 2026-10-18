"""Decode recovered Online v48 skill records. This does not invent a skill table.

Input is the skill-list section consumed by native 20e04/2fe50, NOT a complete
network packet. No captured original sections are currently available.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
NATIVE_SHA256 = 'e08f93bebe133b700f2305bfbedd994b05cc8d04a5a854262af9ced956afbc03'
RANGES = {
    'skill_record_decoder': (0x2fe50,0x2ffae),
    'skill_list_bootstrap': (0x2e50e,0x2e51e),
    'skill_update': (0x2e5f0,0x2e70c),
    'martial_inner_filter': (0xed38,0xed9e),
    'skill_list_draw': (0xeba0,0xed16),
    'upgrade_downgrade_request': (0xdf64,0xdfde),
    'battle_usable_filter': (0x2b30,0x2b76),
    'battle_skill_list_draw': (0x31a4,0x3202),
    'battle_description_strip': (0x3ff8,0x4030),
    'battle_skill_row': (0x4158,0x41a0),
    'battle_choice_panel': (0x41ac,0x422c),
    'parameter_decoder': (0x2fdb0,0x2fe28),
    'list_decoder': (0x20e04,0x20e48),
    'signed_byte_reader': (0x277b8,0x277ca),
    'byte_reader': (0x277d0,0x277e2),
    'signed_short_reader': (0x278c4,0x278d6),
    'utf16_reader': (0x278f0,0x27938),
}


class DecodeError(ValueError):
    pass


class Reader:
    def __init__(self, data):
        if len(data)>1024*1024: raise DecodeError('Skill section exceeds analysis size limit')
        self.data=bytes(data)
        self.offset=0

    def take(self,n):
        if n<0 or self.offset+n>len(self.data):raise DecodeError(f'Truncated data at {self.offset:#x}')
        result=self.data[self.offset:self.offset+n];self.offset+=n
        return result

    def byte(self):return self.take(1)[0]
    def short(self):return struct.unpack('>h',self.take(2))[0]

    def text(self):
        size=self.short()
        if size<0 or size>8192 or size%2:raise DecodeError('Invalid UTF-16 byte length')
        try:return self.take(size).decode('utf-16-be')
        except UnicodeError as e:raise DecodeError('Invalid UTF-16 text') from e

    def count(self):
        value=self.byte()
        if value>127:raise DecodeError('Native signed list count exceeds 127')
        return value


def parameter(reader):
    """Keep unconfirmed parameter semantics as offsets in the native 8-byte union."""
    tag=reader.byte()
    if tag>7:raise DecodeError(f'Unknown parameter tag {tag}')
    fields={}
    if tag in [1,3,5,6]:fields['0x01']=reader.byte()
    if tag==5:fields['0x02']=reader.byte()
    if tag in [3,4,6,7]:fields['0x04']=reader.short()
    if tag in [3,4,5,6,7]:fields['0x06']=reader.short()
    return {'tag':tag,'fields':fields}


def record(reader):
    start=reader.offset
    item={'id':reader.text(),'name':reader.text(),'description':reader.text(),'level':reader.byte()}
    item['deleted']=item['level']==255
    if not item['deleted']:
        item['max_level']=reader.byte()
        item['mp_cost']=reader.short()
        item['category_code']=reader.byte()
        item['category']={0:'武功',1:'心法'}.get(item['category_code'])
        item['battle_flag']=reader.byte()
        item['battle_usable']=item['battle_flag']==1
        blocks=[]
        for _ in range(reader.count()):
            tag=reader.byte();fields={}
            if tag in [0,3,6]:
                fields['0x23']=reader.byte()
                for key in (['0x24','0x26'] if tag==3 else ['0x24','0x26','0x28','0x2a']):fields[key]=reader.short()
                if tag==0:
                    fields['0x2c']=reader.byte();fields['0x2e']=reader.short()
            elif tag==1:
                fields['0x30']=reader.byte();fields['0x34']=reader.text()
                fields['0x38']=reader.byte();fields['0x3c']=reader.text();fields['0x40']=reader.text()
                fields['0x44']=reader.byte()
                fields['0x48']=[parameter(reader) for _ in range(reader.count())]
            else:raise DecodeError(f'Unsupported skill block tag {tag}')
            blocks.append({'tag':tag,'fields':fields})
        item['blocks']=blocks
        if item['battle_usable']:
            fields={'0x12':reader.byte(),'0x13':struct.unpack('b',reader.take(1))[0],
                '0x14':reader.byte(),'0x15':reader.byte(),'0x18':reader.text(),
                '0x1c':reader.byte(),'0x1e':reader.short(),'0x20':reader.short()}
            item['battle_fields']=fields
    item['wire_offset']=start
    item['wire_size']=reader.offset-start
    item['wire_sha256']=hashlib.sha256(reader.data[start:reader.offset]).hexdigest()
    return item


def decode(data, single=False):
    reader=Reader(data)
    result=[record(reader)] if single else [record(reader) for _ in range(reader.count())]
    if reader.offset!=len(data):raise DecodeError(f'Trailing bytes at {reader.offset:#x}; pass only the skill section')
    return result


def evidence():
    blob=(ROOT/'analysis/unpacked/ssjx/gameonline.ext').read_bytes()
    if hashlib.sha256(blob).hexdigest()!=NATIVE_SHA256:raise DecodeError('Native binary identity mismatch')
    return {'version':1,'source':'analysis/unpacked/ssjx/gameonline.ext','source_sha256':NATIVE_SHA256,
        'recovered_skill_definitions':0,'skills':[],
        'status':'客户端技能记录解析与界面流程已定位；尚无原服实际技能记录',
        'known_fields':{'0x00':'字符串 ID','0x04':'名称','0x08':'说明','0x0c':'灵力消耗（有符号16位）',
            '0x0e':'等于1时进入战斗技能列表','0x0f':'0武功／1心法','0x10':'当前等级；255表示移除','0x11':'最高等级'},
        'wire':'三个带有符号BE16字节长度的UTF-16BE字符串，随后是等级及类型化参数。字符串长度和二进制数据不能直接套用UTF-8。',
        'guide':{'source':'analysis/unpacked/ssjx/teach6','sha256':hashlib.sha256((ROOT/'analysis/unpacked/ssjx/teach6').read_bytes()).hexdigest(),
            'evidence':'原文区分战斗中选择的攻击性武功与提升人物属性的辅助心法；不含任何具体技能表。'},
        'limitations':['没有恢复原版技能ID、名称列表、各级数值或技能与特效的完整对应表。',
            '现有破山诀、御剑诀、摄灵诀为重建规则，不能计入恢复出的原版技能。',
            '未知参数只记录原结构偏移；不能据参数类型编号猜测流血、控制、吸血或伤害公式。',
            '解析器只接受明确切出的技能记录／列表段；不猜测整包边界，也不连接旧服务器。'],
        'ranges':[{'name':name,'start':hex(a),'end_exclusive':hex(b),'sha256':hashlib.sha256(blob[a:b]).hexdigest()} for name,(a,b) in RANGES.items()]}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',type=Path,help='Original skill-list section, never a whole packet')
    parser.add_argument('--single',action='store_true',help='Input is exactly one record, without list count')
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    value=evidence()
    if args.input:
        data=args.input.read_bytes()
        value.update(skills=decode(data,args.single),input_sha256=hashlib.sha256(data).hexdigest(),
            status='输入记录已解析；来源真实性、参数语义及玩法效果仍需审核')
        # Parsing arbitrary bytes cannot certify original provenance.
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n','utf8')
    print('Skill evidence written; verified original definitions:',value['recovered_skill_definitions'])


if __name__=='__main__':main()
