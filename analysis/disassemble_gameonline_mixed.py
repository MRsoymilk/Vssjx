#!/usr/bin/env python3
"""Bounded, static ARM/Thumb CFG analysis. Never executes the input or uses the network.

Addresses are file-relative; the runtime load base is NOT assumed to be zero.
Only relative address materialization is propagated. General memory reads remain
symbolic because SDK globals and RW data are patched by the loader. Indirect
branches/jump tables that cannot be proved are recorded, not guessed.
"""
from __future__ import annotations
import argparse
import collections
import csv
import hashlib
import json
import re
import struct
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / '.python_deps'))
try:
    import capstone as cs
    from capstone.arm import *
except ImportError as exc:
    raise SystemExit('Install capstone==5.0.6 into analysis/.python_deps first.') from exc

class Address(int):
    """A file-relative address derived from PC, not an arbitrary integer."""


Key = tuple[int, str]
Value = Any
CALLER_SAVED = (ARM_REG_R0, ARM_REG_R1, ARM_REG_R2, ARM_REG_R3, ARM_REG_R12, ARM_REG_LR)
ARGS = (ARM_REG_R0, ARM_REG_R1, ARM_REG_R2, ARM_REG_R3)
KEYWORDS = re.compile(r'login|download|socket|server|connect|send|recv|http|update|resource|version|\.mrp|\.data|\.str|\.bin|\.map|commonRecord', re.I)
URL = re.compile(rb'https?://[^\x00\s<>"\x80-\xff]{4,180}|(?:[a-zA-Z0-9-]+\.)+(?:com|cn|net|org)(?:/[^\x00\s\x80-\xff]*)?')
MAX_STEPS = 16000


def label(key: Key) -> str:
    return f'{key[1]}_{key[0]:08x}'


def show(value: Value) -> str:
    if value is None:
        return '?'
    if isinstance(value, int):
        return f'0x{value & 0xffffffff:08x}'
    if value[0] == 'sym':
        return value[1]
    if value[0] == 'mem':
        return f'mem[{show(value[1])}]'
    if value[0] == 'add':
        return f'({show(value[1])}{value[2]:+#x})'
    return '?'


def plus(value: Value, delta: int) -> Value:
    if value is None:
        return None
    if isinstance(value, int):
        result = (value + delta) & 0xffffffff
        return Address(result) if isinstance(value, Address) or isinstance(delta, Address) else result
    if not delta:
        return value
    if value[0] == 'add':
        return plus(value[1], value[2] + delta)
    if len(show(value)) > 160:
        return None
    return ('add', value, delta)


def meet(old: dict[int, Value], new: dict[int, Value]) -> dict[int, Value]:
    return {reg: val for reg, val in old.items() if reg in new and type(new[reg]) is type(val) and new[reg] == val}


class Analyzer:
    def __init__(self, blob: bytes, code_end: int | None = None):
        if not blob.startswith(b'MRPGCMAP'):
            raise ValueError('Input does not have the expected MRPGCMAP header.')
        if len(blob) > 16 * 1024 * 1024:
            raise ValueError('Input exceeds the 16 MiB static-analysis bound.')
        self.blob = blob
        self.end = min(code_end or len(blob), len(blob))
        self.engines = {mode: cs.Cs(cs.CS_ARCH_ARM, flag | cs.CS_MODE_LITTLE_ENDIAN) for mode, flag in [('arm', cs.CS_MODE_ARM), ('thumb', cs.CS_MODE_THUMB)]}
        for engine in self.engines.values():
            engine.detail = True
            engine.skipdata = False
        self.cache: dict[Key, Any] = {}
        self.functions: dict[Key, dict[str, Any]] = {}
        self.reasons: dict[Key, set[str]] = {}
        self.pending: collections.deque[Key] = collections.deque()
        self.literals: set[int] = set()
        self.string_cache: dict[int, str | None] = {}
        self.covered: set[Key] = set()
        self.limit_hits: list[str] = []

    def valid(self, key: Key) -> bool:
        address, mode = key
        return 8 <= address < self.end and address % (4 if mode == 'arm' else 2) == 0

    def decode(self, key: Key):
        if key not in self.cache:
            address, mode = key
            self.cache[key] = next(self.engines[mode].disasm(self.blob[address:address + 4], address, count=1), None) if self.valid(key) else None
        return self.cache[key]

    def prologue(self, key: Key) -> bool:
        ins = self.decode(key)
        return bool(ins and (ins.id == ARM_INS_PUSH or (ins.id == ARM_INS_STMDB and ins.operands and ins.operands[0].type == ARM_OP_REG and ins.operands[0].reg == ARM_REG_SP)) and any(op.type == ARM_OP_REG and op.reg == ARM_REG_LR for op in ins.operands))

    def add_function(self, key: Key, reason: str) -> None:
        if not self.valid(key) or self.decode(key) is None:
            return
        if key not in self.reasons:
            if len(self.reasons) >= 5000:
                self.limit_hits.append('function_limit')
                return
            self.reasons[key] = set()
            self.pending.append(key)
        self.reasons[key].add(reason)

    def string_at(self, address: int) -> str | None:
        if address in self.string_cache:
            return self.string_cache[address]
        result = None
        if 8 <= address < len(self.blob):
            stop = self.blob.find(b'\0', address, min(address + 201, len(self.blob)))
            if stop >= address + 4:
                data = self.blob[address:stop]
                if all(32 <= x < 127 for x in data) and any(chr(x).isalpha() for x in data):
                    result = data.decode('ascii')
        self.string_cache[address] = result
        return result

    def operand(self, op, state: dict[int, Value], ins, mode: str) -> Value:
        if op.type == ARM_OP_IMM:
            val = op.imm & 0xffffffff
        elif op.type == ARM_OP_REG:
            val = Address(ins.address + (8 if mode == 'arm' else 4)) if op.reg == ARM_REG_PC else state.get(op.reg)
        else:
            return None
        if op.shift.type:
            if not isinstance(val, int):
                return None
            shift = op.shift.value
            if op.shift.type == ARM_SFT_LSL:
                val = (val << shift) & 0xffffffff
            elif op.shift.type == ARM_SFT_LSR:
                val >>= shift
            elif op.shift.type == ARM_SFT_ASR:
                val = ((val if val < 0x80000000 else val - 0x100000000) >> shift) & 0xffffffff
            else:
                return None
        return val

    def memory_address(self, op, state, ins, mode) -> Value:
        mem = op.mem
        if mem.base == ARM_REG_PC:
            base = ins.address + (8 if mode == 'arm' else 4)
            if mode == 'thumb':
                base &= ~3
        else:
            base = state.get(mem.base)
        delta = mem.disp
        if mem.index:
            index = state.get(mem.index)
            if not isinstance(index, int):
                return None
            if op.shift.type == ARM_SFT_LSL:
                index <<= op.shift.value
            elif op.shift.type:
                return None
            delta += index * (mem.scale or 1)
        return plus(base, delta)

    def step(self, key: Key, state: dict[int, Value]):
        ins = self.decode(key)
        if ins is None:
            return dict(state), [], [], []
        mode = key[1]
        out = dict(state)
        try:
            _, writes = ins.regs_access()
        except cs.CsError:
            writes = []
        for reg in writes:
            out.pop(reg, None)
        ops = ins.operands
        values = []
        literals = []
        stores = []
        conditional = ins.cc not in (ARM_CC_AL, ARM_CC_INVALID)
        val = None
        dest = ops[0].reg if ops and ops[0].type == ARM_OP_REG else None
        if ins.id in (ARM_INS_MOV, ARM_INS_MOVW) and len(ops) >= 2:
            val = self.operand(ops[1], state, ins, mode)
        elif ins.id == ARM_INS_MOVT and len(ops) >= 2 and isinstance(state.get(dest), int):
            val = (state[dest] & 0xffff) | ((ops[1].imm & 0xffff) << 16)
        elif ins.id == ARM_INS_MVN and len(ops) >= 2:
            source = self.operand(ops[1], state, ins, mode)
            if isinstance(source, int):
                val = (~source) & 0xffffffff
        elif ins.id == ARM_INS_ADR and len(ops) >= 2:
            pc = ins.address + (8 if mode == 'arm' else 4)
            if mode == 'thumb':
                pc &= ~3
            val = Address((pc + ops[1].imm) & 0xffffffff)
        elif ins.id in (ARM_INS_ADD, ARM_INS_SUB) and len(ops) >= 2:
            left = state.get(dest) if len(ops) == 2 else self.operand(ops[1], state, ins, mode)
            right = self.operand(ops[-1], state, ins, mode)
            if isinstance(right, int):
                val = plus(left, right if ins.id == ARM_INS_ADD else -right)
            elif ins.id == ARM_INS_ADD and isinstance(left, int):
                val = plus(right, left)
        elif ins.id == ARM_INS_LDR and len(ops) >= 2 and ops[1].type == ARM_OP_MEM:
            address = self.memory_address(ops[1], state, ins, mode)
            if ops[1].mem.base == ARM_REG_PC and isinstance(address, int) and 0 <= address <= len(self.blob) - 4:
                val = struct.unpack_from('<I', self.blob, address)[0]
                literals.append(address)
            elif address is not None and len(show(address)) < 160:
                val = ('mem', address)
        elif ins.id in (ARM_INS_LSL, ARM_INS_LSR, ARM_INS_ASR, ARM_INS_AND, ARM_INS_ORR, ARM_INS_EOR, ARM_INS_BIC) and len(ops) >= 2:
            left = state.get(dest) if len(ops) == 2 else self.operand(ops[1], state, ins, mode)
            right = self.operand(ops[-1], state, ins, mode)
            if isinstance(left, int) and isinstance(right, int):
                if ins.id == ARM_INS_LSL: val = (left << (right & 255)) & 0xffffffff
                elif ins.id == ARM_INS_LSR: val = left >> (right & 255)
                elif ins.id == ARM_INS_ASR: val = ((left if left < 0x80000000 else left - 0x100000000) >> (right & 255)) & 0xffffffff
                elif ins.id == ARM_INS_AND: val = left & right
                elif ins.id == ARM_INS_ORR: val = left | right
                elif ins.id == ARM_INS_EOR: val = left ^ right
                elif ins.id == ARM_INS_BIC: val = left & (~right & 0xffffffff)
        if val is not None and dest is not None:
            if not conditional or state.get(dest) == val:
                out[dest] = val
                if isinstance(val, Address):
                    values.append(val)
        if ins.id in (ARM_INS_STR, ARM_INS_STRB, ARM_INS_STRH) and len(ops) >= 2 and ops[1].type == ARM_OP_MEM:
            stores.append((self.memory_address(ops[1], state, ins, mode), self.operand(ops[0], state, ins, mode)))
        return out, values, literals, stores

    @staticmethod
    def conditional(ins) -> bool:
        return ins.cc not in (ARM_CC_AL, ARM_CC_INVALID) or ins.id in (ARM_INS_CBZ, ARM_INS_CBNZ)

    def control(self, key: Key, state: dict[int, Value], after: dict[int, Value]):
        ins = self.decode(key)
        address, mode = key
        fall = (address + ins.size, mode)
        successors = []
        calls = []
        stops = []
        cond = self.conditional(ins)
        ops = ins.operands
        if ins.id in (ARM_INS_BL, ARM_INS_BLX):
            target = None
            expression = None
            resolution = 'immediate'
            if ops and ops[0].type == ARM_OP_IMM:
                target = (ops[0].imm & ~1, ('thumb' if mode == 'arm' else 'arm') if ins.id == ARM_INS_BLX else mode)
            elif ops and ops[0].type == ARM_OP_REG:
                value = state.get(ops[0].reg)
                expression = show(value)
                resolution = 'pc_relative_pointer' if isinstance(value, Address) else 'unresolved_indirect'
                if isinstance(value, Address):
                    target = (value & ~1, 'thumb' if value & 1 else 'arm')
            # Some ARMv4T toolchains use BL to a BX-register thunk.
            if target is not None:
                thunk = self.decode(target)
                if thunk and thunk.id == ARM_INS_BX and thunk.operands[0].type == ARM_OP_REG and thunk.operands[0].reg != ARM_REG_LR:
                    value = state.get(thunk.operands[0].reg)
                    expression = show(value)
                    resolution = 'register_thunk'
                    target = (value & ~1, 'thumb' if value & 1 else 'arm') if isinstance(value, Address) else None
            calls.append({'site': address, 'mode': mode, 'instruction': ins.mnemonic + ' ' + ins.op_str, 'target': label(target) if target and self.valid(target) else None, 'target_key': target, 'expression': expression, 'resolution': resolution, 'conditional': cond, 'arguments': [show(state.get(reg)) for reg in ARGS], 'argument_strings': [self.string_at(state[reg]) if isinstance(state.get(reg), Address) else None for reg in ARGS]})
            for reg in CALLER_SAVED:
                after.pop(reg, None)
            successors.append((fall, after))
        elif ins.id in (ARM_INS_B, ARM_INS_CBZ, ARM_INS_CBNZ):
            immediate = next((op.imm for op in reversed(ops) if op.type == ARM_OP_IMM), None)
            if immediate is not None:
                successors.append(((immediate & ~1, mode), after))
            else:
                stops.append('unresolved_branch')
            if cond:
                successors.append((fall, after))
        elif ins.id in (ARM_INS_BX, ARM_INS_BXJ):
            reg = ops[0].reg if ops and ops[0].type == ARM_OP_REG else None
            if reg == ARM_REG_LR:
                stops.append('return_bx_lr')
            else:
                value = self.operand(ops[0], state, ins, mode) if ops else None
                if isinstance(value, Address):
                    successors.append(((value & ~1, 'thumb' if value & 1 else 'arm'), after))
                else:
                    stops.append('unresolved_indirect_branch:' + show(value))
                    calls.append({'site': address, 'mode': mode, 'instruction': ins.mnemonic + ' ' + ins.op_str, 'target': None, 'target_key': None, 'expression': show(value), 'resolution': 'indirect_tail_branch_or_stack_return', 'conditional': cond, 'arguments': [show(state.get(r)) for r in ARGS], 'argument_strings': [self.string_at(state[r]) if isinstance(state.get(r), Address) else None for r in ARGS]})
            if cond:
                successors.append((fall, after))
        elif ins.id in (ARM_INS_POP, ARM_INS_LDM, ARM_INS_LDMDA, ARM_INS_LDMDB, ARM_INS_LDMIB) and any(op.type == ARM_OP_REG and op.reg == ARM_REG_PC for op in ops):
            stops.append('return_pop_pc')
            if cond:
                successors.append((fall, after))
        elif ins.id == ARM_INS_MOV and len(ops) >= 2 and ops[0].type == ARM_OP_REG and ops[0].reg == ARM_REG_PC and ops[1].type == ARM_OP_REG and ops[1].reg == ARM_REG_LR:
            stops.append('return_mov_pc_lr')
            if cond:
                successors.append((fall, after))
        elif ins.id in (ARM_INS_IT, ARM_INS_UDF, ARM_INS_SVC, ARM_INS_HVC, ARM_INS_SMC, ARM_INS_BKPT, ARM_INS_TBB, ARM_INS_TBH):
            stops.append('unsupported_control:' + ins.mnemonic)
        else:
            try:
                _, writes = ins.regs_access()
            except cs.CsError:
                writes = []
            if ARM_REG_PC in writes:
                stops.append('unresolved_pc_write:' + ins.mnemonic)
                if cond:
                    successors.append((fall, after))
            else:
                successors.append((fall, after))
        return successors, calls, stops

    def analyze_function(self, entry: Key):
        incoming: dict[Key, dict[int, Value]] = {entry: {ARM_REG_R9: ('sym', 'SB')}}
        queue: collections.deque[Key] = collections.deque([entry])
        visits = 0
        stopped: dict[Key, list[str]] = {}
        while queue:
            key = queue.popleft()
            visits += 1
            if visits > MAX_STEPS:
                self.limit_hits.append(label(entry))
                break
            if not self.valid(key):
                stopped[key] = ['outside_image']
                continue
            if key[0] in self.literals and key != entry:
                stopped[key] = ['literal_pool_boundary']
                continue
            ins = self.decode(key)
            if ins is None:
                stopped[key] = ['invalid_instruction']
                continue
            state = incoming[key]
            after, _, literals, _ = self.step(key, state)
            for address in literals:
                self.literals.update(range(address, address + 4))
            successors, _, stops = self.control(key, state, after)
            if stops:
                stopped[key] = stops
            for next_key, next_state in successors:
                if not self.valid(next_key):
                    stopped[key] = stopped.get(key, []) + ['outside_image_edge:' + label(next_key)]
                    continue
                if next_key not in incoming:
                    incoming[next_key] = dict(next_state)
                    queue.append(next_key)
                else:
                    merged = meet(incoming[next_key], next_state)
                    if merged != incoming[next_key]:
                        incoming[next_key] = merged
                        queue.append(next_key)
        instructions = []
        calls = []
        refs = []
        stores = []
        edges = []
        address_taken = []
        pc_addresses = []
        literal_reads = []
        for key, state in sorted(incoming.items()):
            ins = self.decode(key)
            if ins is None or key[0] in self.literals:
                continue
            instructions.append({'address': key[0], 'mode': key[1], 'size': ins.size, 'bytes': bytes(ins.bytes).hex(), 'mnemonic': ins.mnemonic, 'operands': ins.op_str})
            after, values, literals, write_values = self.step(key, state)
            successors, found_calls, _ = self.control(key, state, after)
            for next_key, _ in successors:
                edges.append((label(key), label(next_key)))
            for call in found_calls:
                target = call.pop('target_key')
                if target and self.valid(target):
                    self.add_function(target, f'call:{label(entry)}@{key[0]:x}')
                calls.append(call)
            for pool in literals:
                literal_reads.append({'site': key[0], 'mode': key[1], 'pool_offset': pool, 'u32': struct.unpack_from('<I', self.blob, pool)[0]})
            for value in values:
                pc_addresses.append({'site': key[0], 'mode': key[1], 'value': int(value)})
                text = self.string_at(value)
                if text:
                    refs.append({'site': key[0], 'mode': key[1], 'offset': value, 'text': text, 'interesting': bool(KEYWORDS.search(text)), 'basis': 'pc_derived_address_not_plain_integer'})
                pointer = (value & ~1, 'thumb' if value & 1 else 'arm')
                if value >= 8 and self.valid(pointer) and self.prologue(pointer):
                    address_taken.append({'site': key[0], 'pointer': label(pointer)})
                    self.add_function(pointer, f'address_taken:{label(entry)}@{key[0]:x}')
            for address, value in write_values:
                if address is not None or value is not None:
                    stores.append({'site': key[0], 'address': show(address), 'value': show(value)})
        self.covered.update((row['address'], row['mode']) for row in instructions)
        blocks = self.build_blocks(instructions, edges)
        return {'entry': entry[0], 'mode': entry[1], 'instructions': instructions, 'blocks': blocks, 'calls': calls, 'string_refs': refs, 'stores': stores, 'address_taken': address_taken, 'pc_addresses': pc_addresses, 'literal_reads': literal_reads, 'stops': [{'address': key[0], 'mode': key[1], 'reasons': reasons} for key, reasons in sorted(stopped.items())], 'instruction_count': len(instructions), 'worklist_steps': visits, 'limit_hit': bool(queue)}

    @staticmethod
    def build_blocks(instructions, edges):
        keys = {f"{row['mode']}_{row['address']:08x}": row for row in instructions}
        successors: dict[str, set[str]] = collections.defaultdict(set)
        predecessors: dict[str, set[str]] = collections.defaultdict(set)
        for a, b in edges:
            if a in keys and b in keys:
                successors[a].add(b)
                predecessors[b].add(a)
        leaders = set()
        for key, row in keys.items():
            prev = predecessors.get(key, set())
            if len(prev) != 1:
                leaders.add(key)
            else:
                previous = next(iter(prev))
                p = keys[previous]
                if len(successors[previous]) != 1 or p['mode'] != row['mode'] or p['address'] + p['size'] != row['address']:
                    leaders.add(key)
        result = []
        seen = set()
        for first in sorted(leaders) + sorted(keys):
            if first in seen:
                continue
            block = []
            current = first
            while current not in seen:
                seen.add(current)
                block.append(current)
                following = successors.get(current, set())
                if len(following) != 1:
                    break
                candidate = next(iter(following))
                if candidate in leaders:
                    break
                current = candidate
            result.append({'start': first, 'instructions': block, 'successors': sorted(successors.get(block[-1], set()))})
        return result

    def drain(self):
        while self.pending:
            key = self.pending.popleft()
            if key not in self.functions:
                self.functions[key] = self.analyze_function(key)

    def run(self, heuristic: bool = True):
        self.add_function((8, 'arm'), 'image_entry')
        self.drain()
        rooted = set(self.functions)
        if heuristic:
            candidates = []
            for address in range(8, self.end - 1, 2):
                if address in self.literals:
                    continue
                half = struct.unpack_from('<H', self.blob, address)[0]
                if half & 0xff00 == 0xb500 and half & 0xff:
                    key = (address, 'thumb')
                    if key not in self.covered and self.prologue(key):
                        candidates.append(key)
                if address % 4 == 0 and address + 4 <= self.end:
                    word = struct.unpack_from('<I', self.blob, address)[0]
                    if word & 0xffff0000 == 0xe92d0000 and word & (1 << 14):
                        key = (address, 'arm')
                        if key not in self.covered and self.prologue(key):
                            candidates.append(key)
            for key in candidates:
                if key not in self.covered and key not in self.reasons:
                    self.add_function(key, 'heuristic_prologue')
                    self.drain()
        for key, function in self.functions.items():
            function['reasons'] = sorted(self.reasons[key])
            function['confidence'] = 'entry_or_address_taken_graph' if key in rooted else 'heuristic_expansion'
        return self.report(rooted)

    def report(self, rooted):
        calls = [dict(call, function=label(key)) for key, function in sorted(self.functions.items()) for call in function['calls']]
        refs = [dict(ref, function=label(key)) for key, function in sorted(self.functions.items()) for ref in function['string_refs']]
        unique_instructions = {(row['address'], row['mode']): row for function in self.functions.values() for row in function['instructions']}
        byte_owners: dict[int, set[str]] = collections.defaultdict(set)
        for (address, mode), row in unique_instructions.items():
            for byte in range(address, address + row['size']):
                byte_owners[byte].add(mode)
        branch_sites = {(call['site'], call['mode']) for call in calls if call['resolution'] == 'indirect_tail_branch_or_stack_return'}
        distinct_calls = {(call['site'], call['mode']): call for call in calls if call['resolution'] != 'indirect_tail_branch_or_stack_return'}
        valid_targets = {call['target'] for call in distinct_calls.values() if call['target'] is not None}
        counts = {'functions': len(self.functions), 'root_graph_functions': len(rooted), 'heuristic_graph_functions': len(self.functions) - len(rooted), 'arm_functions': sum(key[1] == 'arm' for key in self.functions), 'thumb_functions': sum(key[1] == 'thumb' for key in self.functions), 'unique_instructions': len(unique_instructions), 'decoded_code_bytes': len(byte_owners), 'mode_conflict_bytes': sum(len(v) > 1 for v in byte_owners.values()), 'literal_bytes': len(self.literals), 'distinct_call_sites': len(distinct_calls), 'ambiguous_indirect_branch_sites': len(branch_sites), 'resolved_local_call_sites': sum(call['target'] is not None for call in distinct_calls.values()), 'unresolved_call_sites': sum(call['target'] is None for call in distinct_calls.values()), 'distinct_nonempty_call_targets': len(valid_targets), 'string_xrefs': len(refs), 'keyword_string_xrefs': sum(ref['interesting'] for ref in refs), 'limit_hits': len(self.limit_hits)}
        return {'schema_version': 2, 'method': 'static_recursive_arm_thumb_with_block_local_symbolic_values', 'input_sha256': hashlib.sha256(self.blob).hexdigest(), 'input_bytes': len(self.blob), 'capstone_version': cs.__version__, 'address_basis': 'file-relative, unknown runtime relocation base', 'code_end_bound': self.end, 'counts': counts, 'limitations': ['Function starts and ends remain candidates; indirect control flow and jump tables are not guessed.', 'Root graph includes address-taken prologues, not just executable paths from entry.', 'Heuristic expansion can decode data or choose the wrong mode; see conflicts and confidence.', 'General memory loads remain symbolic. No runtime load address or SDK layout is assumed.', 'IT blocks and unsupported PC writes terminate analysis explicitly.', 'No original binary is executed; no historical network endpoint is contacted.'], 'limit_hits': self.limit_hits, 'functions': {label(key): value for key, value in sorted(self.functions.items())}, 'calls': calls, 'string_xrefs': refs, 'endpoint_candidates': [{'offset': match.start(), 'text': match.group().decode('ascii'), 'confidence': 'string_only_not_verified_endpoint'} for match in URL.finditer(self.blob)]}


def export(report: dict[str, Any], output: Path):
    output.mkdir(parents=True, exist_ok=True)
    (output / 'gameonline_mixed.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    with (output / 'gameonline_functions.asm').open('w', encoding='utf-8') as stream:
        stream.write('; Static candidates, FILE OFFSETS; not a reconstructed original source file.\n')
        for name, function in report['functions'].items():
            stream.write(f"\n; FUNCTION {name} confidence={function['confidence']}\n; reasons={' | '.join(function['reasons'])}\n")
            calls = {call['site']: call for call in function['calls']}
            refs = {ref['site']: ref for ref in function['string_refs']}
            for row in function['instructions']:
                comment = ''
                if row['address'] in calls:
                    call = calls[row['address']]
                    comment += ' ; call=' + (call['target'] or call['expression'] or '?') + ' args=' + ','.join(call['arguments'])
                if row['address'] in refs:
                    comment += ' ; string=' + repr(refs[row['address']]['text'])
                stream.write(f"{row['address']:08x} {row['mode']:5s} {row['bytes']:8s} {row['mnemonic']:9s} {row['operands']}{comment}\n")
            for stop in function['stops']:
                stream.write(f"; STOP {stop['address']:08x} {' | '.join(stop['reasons'])}\n")
    with (output / 'gameonline_functions.tsv').open('w', encoding='utf-8', newline='') as stream:
        writer = csv.writer(stream, delimiter='\t')
        writer.writerow(['function', 'confidence', 'instructions', 'blocks', 'call_or_indirect_branch_sites', 'string_refs', 'stop_reasons'])
        for name, function in report['functions'].items():
            writer.writerow([name, function['confidence'], function['instruction_count'], len(function['blocks']), len(function['calls']), len(function['string_refs']), ';'.join(sorted({reason for stop in function['stops'] for reason in stop['reasons']}))])
    with (output / 'gameonline_calls.tsv').open('w', encoding='utf-8', newline='') as stream:
        writer = csv.writer(stream, delimiter='\t')
        writer.writerow(['function', 'site', 'mode', 'target', 'expression', 'resolution', 'arguments', 'argument_strings'])
        for call in report['calls']:
            writer.writerow([call['function'], f"0x{call['site']:x}", call['mode'], call['target'] or '', call['expression'] or '', call['resolution'], ','.join(call['arguments']), json.dumps(call['argument_strings'], ensure_ascii=False)])
    with (output / 'gameonline_strings.tsv').open('w', encoding='utf-8', newline='') as stream:
        writer = csv.writer(stream, delimiter='\t')
        writer.writerow(['function', 'site', 'mode', 'string_offset', 'interesting', 'text'])
        for ref in report['string_xrefs']:
            writer.writerow([ref['function'], f"0x{ref['site']:x}", ref['mode'], f"0x{ref['offset']:x}", ref['interesting'], ref['text']])
    summary = ['# gameonline.ext ARM/Thumb 静态控制流分析', '', '## 输入与限制', '', f"- SHA-256: `{report['input_sha256']}`", '- 地址均为文件偏移，不是运行时绝对地址。', '- 函数、语义和字符串用途需要人工复核；不把启发式候选计为完整恢复。', '- 未执行原始 ARM/Thumb 程序，未发送网络请求。', '', '## 统计', '']
    summary += [f'- {key}: {value}' for key, value in report['counts'].items()]
    summary += ['', '## 重点字符串引用', '', '| 函数 | 引用位置 | 字符串位置 | 内容 |', '|---|---|---|---|']
    for ref in report['string_xrefs']:
        if ref['interesting']:
            summary.append(f"| `{ref['function']}` | `0x{ref['site']:x}` | `0x{ref['offset']:x}` | {ref['text'].replace('|', '/')} |")
    summary += ['', '## 后续核验', '', '优先复核下载/登录字符串的引用函数、间接调用的表偏移和调用参数；只有匹配公开 SDK 和具体机器指令后才能给 API 命名。间接跳转、回调和资源请求协议仍需补全。', '']
    (output / 'gameonline_mixed_report.md').write_text('\n'.join(summary), encoding='utf-8')


def self_check():
    passed = []
    def check(condition, message):
        if not condition:
            raise AssertionError(message)
        passed.append(message)
    blob = bytearray(0x2cd70)
    blob[:8] = b'MRPGCMAP'
    blob[8:28] = bytes.fromhex('10402de90040a0e10400a0e152b300fa1080bde8')
    blob[0x2cd64:0x2cd68] = bytes.fromhex('10b510bd')
    analyzer = Analyzer(bytes(blob))
    report = analyzer.run(heuristic=False)
    check('thumb_0002cd64' in report['functions'], 'ARM BLX immediate switches to Thumb')
    check(report['counts']['distinct_nonempty_call_targets'] == 1, 'Nonempty target count is independent of prologue candidates')
    check(report['functions']['arm_00000008']['instruction_count'] == 5, 'Stop at POP PC, not at header/data')
    blob = bytearray(20)
    blob[:8] = b'MRPGCMAP'
    blob[8:12] = bytes.fromhex('1040bde8')
    blob[12:16] = bytes.fromhex('1eff2fe1')
    analyzer = Analyzer(bytes(blob))
    report = analyzer.run(heuristic=False)
    check(report['functions']['arm_00000008']['instruction_count'] == 2, 'POP LR alone is not a return')
    analyzer = Analyzer(bytes(blob))
    check(analyzer.decode((10, 'arm')) is None, 'Misaligned ARM address rejected')
    check(meet({1: 4, 2: 5}, {1: 4, 2: 6}) == {1: 4}, 'Join discards conflicting register constants')
    check(show(plus(('mem', 0x30000), 0x64)) == '(mem[0x00030000]+0x64)', 'SDK memory reads remain symbolic')
    check(isinstance(plus(Address(12), 8), Address), 'PC-derived addresses preserve their provenance')
    check(not isinstance(plus(12, 8), Address), 'Plain integer is not silently treated as a string/code pointer')
    check(meet({1: Address(12)}, {1: 12}) == {}, 'Join discards address/integer provenance conflict')
    print(json.dumps({'self_check': 'passed', 'checks': passed}, ensure_ascii=False))


def verify_results(input_path: Path, output: Path):
    self_check()
    report = json.loads((output / 'gameonline_mixed.json').read_text(encoding='utf-8'))
    resource = json.loads((output / 'gameonline_resource_findings.json').read_text(encoding='utf-8'))
    legacy = json.loads((output / 'gameonline_arm_candidates.json').read_text(encoding='utf-8'))
    digest = hashlib.sha256(input_path.read_bytes()).hexdigest()
    checks = []
    def check(condition, name):
        if not condition:
            raise AssertionError(name)
        checks.append(name)
    check(digest == report['input_sha256'] == resource['input_sha256'], 'input_and_report_hashes_match')
    functions = report['functions']
    counts = report['counts']
    check(len(functions) == counts['functions'], 'function_count_consistent')
    check(counts['arm_functions'] + counts['thumb_functions'] == counts['functions'], 'mode_counts_consistent')
    check(counts['root_graph_functions'] + counts['heuristic_graph_functions'] == counts['functions'], 'confidence_counts_consistent')
    sites = {(c['site'], c['mode']): c for c in report['calls'] if c['resolution'] != 'indirect_tail_branch_or_stack_return'}
    targets = {c['target'] for c in sites.values() if c['target'] is not None}
    check(len(sites) == counts['distinct_call_sites'], 'call_sites_deduplicated')
    check(len(targets) == counts['distinct_nonempty_call_targets'], 'nonempty_target_count_consistent')
    check(counts['resolved_local_call_sites'] + counts['unresolved_call_sites'] == len(sites), 'resolved_and_unresolved_partition')
    check(all(target in functions for target in targets), 'all_resolved_local_targets_present')
    instructions = {(row['address'], row['mode']): row for function in functions.values() for row in function['instructions']}
    check(len(instructions) == counts['unique_instructions'], 'unique_instruction_count_consistent')
    check(all(row['size'] == 4 if row['mode'] == 'arm' else row['size'] in (2, 4) for row in instructions.values()), 'instruction_widths_valid')
    check(all(row['address'] % (4 if row['mode'] == 'arm' else 2) == 0 for row in instructions.values()), 'instruction_alignment_valid')
    check(legacy['decoded_instructions'] + legacy['skipped_data_items'] == legacy['scan_items'], 'legacy_instruction_and_data_counts_separated')
    check(legacy['bl_target_count'] == sum(row['callers'] > 0 for row in legacy['top_candidates']), 'legacy_empty_targets_not_counted')
    manifest = []
    for name in ('gameonline_arm_candidates.asm', 'gameonline_arm_candidates.json', 'gameonline_mixed.json', 'gameonline_functions.asm', 'gameonline_functions.tsv', 'gameonline_calls.tsv', 'gameonline_strings.tsv', 'gameonline_mixed_report.md', 'gameonline_resource_findings.json', 'gameonline_resource_findings.md'):
        data = (output / name).read_bytes()
        check(bool(data), 'nonempty:' + name)
        manifest.append({'path': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
    result = {'status': 'passed', 'scope': 'synthetic_engine_checks_and_artifact_consistency_NOT_proof_of_all_function_semantics', 'synthetic_checks': 10, 'consistency_checks': checks, 'input_sha256': digest, 'counts': counts, 'resource_summary': resource['summary'], 'artifacts': manifest}
    (output / 'gameonline_verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'verification': result['status'], 'synthetic_checks': 10, 'consistency_checks': len(checks), 'input_sha256': digest, 'counts': counts, 'resource_summary': resource['summary']}, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, default=ROOT / 'unpacked/ssjx/gameonline.ext')
    parser.add_argument('--output', type=Path, default=ROOT / 'disasm')
    parser.add_argument('--code-end', type=lambda value: int(value, 0), default=None)
    parser.add_argument('--no-heuristic', action='store_true')
    parser.add_argument('--self-check', action='store_true')
    parser.add_argument('--verify-results', action='store_true')
    args = parser.parse_args()
    if args.verify_results:
        verify_results(args.input, args.output)
        return
    if args.self_check:
        self_check()
        return
    blob = args.input.read_bytes()
    before = hashlib.sha256(blob).hexdigest()
    report = Analyzer(blob, args.code_end).run(heuristic=not args.no_heuristic)
    if hashlib.sha256(args.input.read_bytes()).hexdigest() != before:
        raise RuntimeError('Input changed during analysis; refusing to publish a stale report.')
    export(report, args.output)
    print(json.dumps({'input_sha256': before, 'counts': report['counts'], 'keyword_xrefs': [ref for ref in report['string_xrefs'] if ref['interesting']][:24], 'endpoint_candidates': report['endpoint_candidates'], 'output': str(args.output)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
