"""Export bounded static Thumb evidence for Online v48 map recovery.

Requires Capstone (`python -m pip install capstone`). Never executes native code.
All addresses are original file offsets, not process virtual addresses.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
NATIVE_SHA256 = 'e08f93bebe133b700f2305bfbedd994b05cc8d04a5a854262af9ced956afbc03'
RANGES = [
    ('scene_read', 0x137c8, 0x138b4, '编号字符串、名称、行列数、两层字节、图块表、两个字节、交互记录'),
    ('terrain_draw', 0x14670, 0x146c6, '单元0不绘制，正索引指向图块表；16像素网格'),
    ('tile_load', 0x15618, 0x1569c, '图块表编号减1后生成tile%d资源名'),
    ('world_routes_draw', 0x21090, 0x210d8, '原始行列顺序转换为x/y后绘制线段'),
    ('world_nodes_draw', 0x21244, 0x212e8, '记录+2为x、+1为y、+3为节点图标类别'),
    ('world_levels', 0x2193c, 0x2196e, '记录+4与+5显示为等级区间'),
    ('map_id_lookup', 0x221e8, 0x22210, '以记录首字节匹配原包地图编号'),
    ('cache_write', 0x25430, 0x25470, '写入缓存；有校验值时先写4字节再写原始流'),
    ('cache_read', 0x27274, 0x27300, '缓存校验匹配后跳过4字节头'),
    ('stream_readers', 0x277a4, 0x27980, '字节、大端短整数、UTF16字符串及数字字符串读取'),
    ('world_read', 0x2b25c, 0x2b2bc, '三字节头、名称数组、六字节记录、四字节路线记录'),
    ('tile_palette_read', 0x2fb50, 0x2fb6e, '字节数量，随后读取大端短整数数组'),
]


def export(root=ROOT):
    from capstone import Cs, CS_ARCH_ARM, CS_MODE_THUMB
    native = (root / 'analysis/unpacked/ssjx/gameonline.ext').read_bytes()
    if hashlib.sha256(native).hexdigest() != NATIVE_SHA256:
        raise ValueError('Unsupported native source: evidence only applies to the audited Online v48')
    decoder = Cs(CS_ARCH_ARM, CS_MODE_THUMB)
    decoder.skipdata = True
    lines = ['; Online v48 gameonline.ext; STATIC evidence, no native execution',
             f'; SHA256 {NATIVE_SHA256}',
             '; Addresses = file offsets. Comments are analysis, not recovered source code.',
             '; Bounded excerpts can include literal pools: do not treat data as executable instructions.']
    functions = []
    for name, start, end, meaning in RANGES:
        chunk = native[start:end]
        functions.append({'name': name, 'start': hex(start), 'end_exclusive': hex(end),
                          'byte_sha256': hashlib.sha256(chunk).hexdigest(), 'interpretation': meaning})
        lines.extend(['', f'; {name} [{start:#x}, {end:#x}) — {meaning}'])
        for insn in decoder.disasm(chunk, start):
            lines.append(f'{insn.address:08x} {insn.bytes.hex():<12} {insn.mnemonic:<9} {insn.op_str}')
    output = root / 'analysis/recovery/maps'
    output.mkdir(parents=True, exist_ok=True)
    (output / 'native_evidence.asm').write_text('\n'.join(lines) + '\n', encoding='utf-8', newline='\n')
    (output / 'native_evidence.json').write_text(json.dumps({
        'source': 'analysis/unpacked/ssjx/gameonline.ext', 'native_sha256': NATIVE_SHA256,
        'mode': 'ARM Thumb, static disassembly', 'address_unit': 'original file offset',
        'functions': functions,
        'scene_schema_status': '静态推导，尚无真实.map样本；合成测试只验证解析器自洽性',
    }, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    return functions


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--capstone-path', type=Path, help='Optional local dependency directory; not saved to output')
    args = parser.parse_args()
    if args.capstone_path:
        sys.path.insert(0, str(args.capstone_path))
    print(f'Exported {len(export())} static evidence excerpts')
