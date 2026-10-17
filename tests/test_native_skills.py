"""Synthetic protocol vectors; optional execution of the actual recovered Thumb reader.

Synthetic names are test fixtures, never published as recovered game definitions.
Set SSJX_NATIVE_DEPS to a directory containing unicorn to enable native execution.
"""
import hashlib
import os
from pathlib import Path
import struct
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
if os.environ.get('SSJX_NATIVE_DEPS'):sys.path.insert(0,os.environ['SSJX_NATIVE_DEPS'])
from native_skills import decode, DecodeError, evidence


def text(value):
    value=value.encode('utf-16-be')
    return struct.pack('>h',len(value))+value


def vector(deleted=False,active=True):
    header=text('fixture/skill-01')+text('协议测试技能')+text('合成测试数据，不是原版技能。')
    if deleted:return header+b'\xff'
    parameters=b'\x08'+b'\x00'+b'\x01\x02'+b'\x02'+b'\x03\x04\xff\xf6\x00\x14'+b'\x04\x00\x1e\xff\xd8'+b'\x05\x06\x07\x00\x32'+b'\x06\x08\x00\x3c\x00\x46'+b'\x07\x00\x50\x00\x5a'
    numeric=b'\x00\x09'+struct.pack('>hhhhBh',-10,20,-30,40,5,-60)
    visual=b'\x01\x03'+text('fixture/a')+b'\x04'+text('fixture/b')+text('fixture/c')+b'\x05'+parameters
    status=b'\x03\x06'+struct.pack('>hh',-7,8)
    other=b'\x06\x0a'+struct.pack('>hhhh',11,-12,13,-14)
    payload=header+bytes([2,9])+struct.pack('>h',17)+bytes([0,1 if active else 0,4])+numeric+visual+status+other
    if active:payload+=bytes([3,255,5,6])+text('fixture/target')+b'\x07'+struct.pack('>hh',-8,9)
    return payload


def native_record(data):
    from unicorn import Uc, UC_ARCH_ARM, UC_MODE_THUMB, UC_HOOK_CODE
    from unicorn.arm_const import UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_R9,UC_ARM_REG_LR,UC_ARM_REG_PC,UC_ARM_REG_SP
    blob=(ROOT/'analysis/unpacked/ssjx/gameonline.ext').read_bytes()
    cpu=Uc(UC_ARCH_ARM,UC_MODE_THUMB)
    base,sb,heap,wire,copy,stack,stop=0x100000,0x400000,0x500000,0x600000,0x700000,0x800000,0x900000
    cpu.mem_map(base,0x40000);cpu.mem_write(base,blob)
    for address,size in [(sb,0x10000),(heap,0x100000),(wire,0x100000),(copy,0x1000),(stack,0x10000),(stop,0x1000)]:cpu.mem_map(address,size)
    cpu.mem_write(wire,data)
    cpu.mem_write(sb+0x78c,struct.pack('<I',wire))
    cpu.mem_write(sb+0xd98,struct.pack('<I',copy|1))
    cpu.reg_write(UC_ARM_REG_R9,sb);cpu.reg_write(UC_ARM_REG_SP,stack+0x8000);cpu.reg_write(UC_ARM_REG_LR,stop|1)
    allocation=heap
    def hook(emulator,address,_size,_user):
        nonlocal allocation
        if address==base+0x2737c:
            size=emulator.reg_read(UC_ARM_REG_R0)
            if size>65536:raise AssertionError('Unexpected native allocation')
            pointer=allocation;allocation+=(size+7)&~7
            emulator.reg_write(UC_ARM_REG_R0,pointer)
            emulator.reg_write(UC_ARM_REG_PC,emulator.reg_read(UC_ARM_REG_LR))
        elif address==copy:
            dest=emulator.reg_read(UC_ARM_REG_R0);source=emulator.reg_read(UC_ARM_REG_R1);size=emulator.reg_read(UC_ARM_REG_R2)
            emulator.mem_write(dest,bytes(emulator.mem_read(source,size)))
            emulator.reg_write(UC_ARM_REG_PC,emulator.reg_read(UC_ARM_REG_LR))
    cpu.hook_add(UC_HOOK_CODE,hook)
    cpu.emu_start(base+0x2fe51,stop,count=200000)
    if cpu.reg_read(UC_ARM_REG_PC)!=stop:raise AssertionError('Native reader did not return')
    pointer=cpu.reg_read(UC_ARM_REG_R0)
    consumed=struct.unpack('<I',cpu.mem_read(sb+0x78c,4))[0]-wire
    def field(offset,format):return struct.unpack('<'+format,cpu.mem_read(pointer+offset,struct.calcsize(format)))[0]
    def string(offset):
        address=field(offset,'I');data=bytearray()
        for i in range(4096):
            pair=bytes(cpu.mem_read(address+i*2,2))
            if pair==b'\0\0':return data.decode('utf-16-be')
            data.extend(pair)
        raise AssertionError('Unterminated native string')
    return consumed,field,string,cpu


class NativeSkillsTests(unittest.TestCase):
    def test_evidence_identifies_server_provided_records_without_inventing_skills(self):
        report=evidence()
        self.assertEqual(report['skills'],[])
        self.assertEqual(report['recovered_skill_definitions'],0)
        self.assertEqual(report['source_sha256'],hashlib.sha256((ROOT/report['source']).read_bytes()).hexdigest())
        self.assertTrue(any(i['start']=='0x2fe50' for i in report['ranges']))

    def test_all_known_typed_blocks_and_parameters(self):
        data=vector();item=decode(data,True)[0]
        self.assertEqual((item['id'],item['name'],item['level'],item['max_level'],item['mp_cost']),('fixture/skill-01','协议测试技能',2,9,17))
        self.assertEqual(item['category'],'武功');self.assertTrue(item['battle_usable'])
        self.assertEqual([b['tag'] for b in item['blocks']],[0,1,3,6])
        self.assertEqual([p['tag'] for p in item['blocks'][1]['fields']['0x48']],list(range(8)))
        self.assertEqual(item['blocks'][0]['fields']['0x2e'],-60)
        self.assertEqual(item['battle_fields']['0x13'],-1)

    def test_list_and_removal_record(self):
        records=decode(b'\x02'+vector(active=False)+vector(deleted=True))
        self.assertEqual(len(records),2);self.assertFalse(records[0]['battle_usable'])
        self.assertTrue(records[1]['deleted']);self.assertNotIn('mp_cost',records[1])
        self.assertEqual(decode(b'\x00'),[])

    def test_truncation_never_publishes_partial_records(self):
        data=vector()
        for size in range(len(data)):
            with self.subTest(size=size),self.assertRaises(DecodeError):decode(data[:size],True)
        with self.assertRaises(DecodeError):decode(data+b'\0',True)

    def test_bad_lengths_counts_and_unknown_blocks(self):
        for data in [b'\xff\xff',b'\x00\x01a',b'\x80']:
            with self.assertRaises(DecodeError):decode(data,True if len(data)>1 else False)
        header=text('id')+text('name')+text('description')+b'\x01\x09\x00\x11\x00\x00\x01'
        with self.assertRaises(DecodeError):decode(header+b'\x02',True)

    @unittest.skipUnless(os.environ.get('SSJX_NATIVE_DEPS'),'Optional native ARM execution requires unicorn')
    def test_native_thumb_reader_matches_decoded_records(self):
        for data in [vector(),vector(active=False),vector(deleted=True)]:
            with self.subTest(bytes=len(data)):
                item=decode(data,True)[0];consumed,field,string,cpu=native_record(data)
                self.assertEqual(consumed,len(data))
                for offset,key in [(0,'id'),(4,'name'),(8,'description')]:self.assertEqual(string(offset),item[key])
                self.assertEqual(field(0x10,'B'),item['level'])
                if item['deleted']:continue
                self.assertEqual(field(0x11,'B'),item['max_level']);self.assertEqual(field(0xc,'h'),item['mp_cost'])
                self.assertEqual(field(0xf,'B'),item['category_code']);self.assertEqual(field(0xe,'B'),item['battle_flag'])
                self.assertEqual([field(i,'h') for i in [0x24,0x26,0x28,0x2a]],[11,-12,13,-14])
                self.assertEqual(string(0x34),'fixture/a');self.assertEqual(string(0x40),'fixture/c')
                parameters=item['blocks'][1]['fields']['0x48']
                native_list=field(0x48,'I')
                self.assertEqual(bytes(cpu.mem_read(native_list+4,1))[0],len(parameters))
                array=struct.unpack('<I',cpu.mem_read(native_list,4))[0]
                for index,parameter in enumerate(parameters):
                    node=struct.unpack('<I',cpu.mem_read(array+index*4,4))[0]
                    self.assertEqual(bytes(cpu.mem_read(node,1))[0],parameter['tag'])
                    for offset,value in parameter['fields'].items():
                        kind='B' if offset in ['0x01','0x02'] else 'h'
                        self.assertEqual(struct.unpack('<'+kind,cpu.mem_read(node+int(offset,16),struct.calcsize(kind)))[0],value)
                if item['battle_usable']:
                    self.assertEqual(string(0x18),item['battle_fields']['0x18'])
                    self.assertEqual(field(0x13,'b'),-1)


if __name__=='__main__':unittest.main()
