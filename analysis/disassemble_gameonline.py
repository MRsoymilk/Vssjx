#!/usr/bin/env python3
"""Conservative static ARM function-candidate analysis for MRPGCMAP, not execution."""
import sys,re,json,collections
from pathlib import Path
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'.python_deps'))
from capstone import Cs,CS_ARCH_ARM,CS_MODE_ARM,CS_MODE_LITTLE_ENDIAN
blob=(ROOT/'unpacked/ssjx/gameonline.ext').read_bytes()
assert blob.startswith(b'MRPGCMAP')
md=Cs(CS_ARCH_ARM,CS_MODE_ARM+CS_MODE_LITTLE_ENDIAN)
md.detail=False
md.skipdata=True
# MRPGCMAP prefix is 8 bytes; disassembly is provisional without loader metadata.
start=8
inst=list(md.disasm(blob[start:len(blob)//4*4],start))
by_addr={i.address:i for i in inst}
bl={}
for i in inst:
    if i.mnemonic in ('bl','blx') and i.op_str.startswith('#'):
        try:
            t=int(i.op_str[1:],0)
            if start<=t<len(blob) and t%4==0: bl.setdefault(t,[]).append(i.address)
        except ValueError:pass
prologues={i.address for i in inst if i.mnemonic in ('push','stmdb') and ('lr' in i.op_str)}
candidates=sorted(set(bl)|prologues)
def lines(addr,maxins=180):
    out=[]
    for k in range(maxins):
        i=by_addr.get(addr+k*4)
        if not i:break
        out.append(f'{i.address:08x}: {i.mnemonic:8s} {i.op_str}')
        if k>0 and ((i.mnemonic == 'bx' and i.op_str == 'lr') or (i.mnemonic in ('pop','ldmia') and 'pc' in i.op_str)):break
    return out
out=ROOT/'disasm'
out.mkdir(exist_ok=True)
scores={a:len(bl.get(a,()))*3+(5 if a in prologues else 0) for a in candidates}
ranked=sorted(candidates,key=lambda a:(-scores[a],a))
with (out/'gameonline_arm_candidates.asm').open('w') as f:
    f.write('; MRPGCMAP raw ARM scan. Candidate functions, not validated boundaries.\n')
    for a in ranked[:500]:
        f.write(f'\n; candidate 0x{a:x} callers={len(bl.get(a,()))} prologue={a in prologues}\n')
        f.write('\n'.join(lines(a))+'\n')
names=[]
for m in re.finditer(rb'[\x20-\x7e]{5,}',blob):
    s=m.group().decode('ascii','replace')
    if re.search(r'login|download|socket|server|connect|send|recv|http|update|resource',s,re.I):names.append({'offset':m.start(),'string':s[:100]})
report={'format':'MRPGCMAP','bytes':len(blob),'scan_offset':start,'scan_items':len(inst),'decoded_instructions':sum(i.id != 0 for i in inst),'skipped_data_items':sum(i.id == 0 for i in inst),'candidate_count':len(candidates),'prologue_count':len(prologues),'bl_target_count':len(bl),'caveat':'Linear ARM disassembly includes data and may misidentify Thumb/code boundaries; function list is heuristic.','strings':names,'top_candidates':[{'offset':a,'callers':len(bl.get(a,())),'prologue':a in prologues} for a in ranked[:100]]}
(out/'gameonline_arm_candidates.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps({k:v for k,v in report.items() if k not in ('top_candidates','strings')},ensure_ascii=False))
print('strings',names[:20])
print('top',report['top_candidates'][:12])
print('outputs',out/'gameonline_arm_candidates.asm',out/'gameonline_arm_candidates.json')
