"""Read-only Online map audit: cache flow, archive inventory and embedded streams.

Does not execute ARM/MR code, contact a historical server, import invented maps,
or process the two unrelated games. Negative results only cover this schema and
the explicitly reported plain/gzip/zlib streams and limits.
"""
import argparse
from collections import Counter
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import struct
import sys
import zlib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import recover_original_maps as recovery

NATIVE_SHA256 = 'e08f93bebe133b700f2305bfbedd994b05cc8d04a5a854262af9ced956afbc03'
PACKAGES = ['analysis/source/ssjx.mrp'] + [f'analysis/source/ssjx/{name}.mrp' for name in ('effect', 'hero', 'item', 'map', 'monster')]
EXCLUDED = {'gssjxz', 'gssxmz', 'gssjxz.mrp', 'gssxmz.mrp'}
RANGES = [
    ('scene_payload_and_cache_write', 0x137c8, 0x138b4),
    ('cache_hit_or_missing_request', 0x13ab2, 0x13b14),
    ('map_response_selector', 0x17fd0, 0x17fea),
    ('map_response_branch', 0x180c6, 0x180ce),
    ('map_response_calls', 0x184f8, 0x18512),
    ('bind_message_stream', 0x18c4c, 0x18c5e),
    ('write_cache_stream', 0x25430, 0x2546c),
    ('cache_token_comparison', 0x27274, 0x272fa),
    ('stream_pointer_binding', 0x270a0, 0x270ac),
    ('copy_terrain_bytes', 0x277e8, 0x2780c),
    ('bundle_version_reader', 0x9904, 0x9998),
    ('allocate_zeroed_work_array', 0x2737c, 0x273a6),
]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def literal(data, address):
    instruction = int.from_bytes(data[address:address + 2], 'little')
    if instruction & 0xf800 != 0x4800:
        raise ValueError('Expected Thumb literal LDR')
    pool = ((address + 4) & ~3) + (instruction & 255) * 4
    return struct.unpack_from('<I', data, pool)[0]


def bl_target(data, address):
    first, second = struct.unpack_from('<HH', data, address)
    if first & 0xf800 != 0xf000 or second & 0xd000 != 0xd000:
        raise ValueError('Expected Thumb BL')
    sign = (first >> 10) & 1
    i1 = 1 ^ ((second >> 13) & 1) ^ sign
    i2 = 1 ^ ((second >> 11) & 1) ^ sign
    displacement = sign << 24 | i1 << 23 | i2 << 22 | (first & 1023) << 12 | (second & 2047) << 1
    if sign:
        displacement -= 1 << 25
    return address + 4 + displacement


def native_flow(data):
    if digest(data) != NATIVE_SHA256:
        raise ValueError('Cache evidence only applies to audited Online v48')
    namespace = literal(data, 0x137ee) + 0x137f0 + 4
    read_namespace = literal(data, 0x13ad6) + 0x13ad8 + 4
    filename = literal(data, 0x137cc) + 0x137d0 + 4
    table = literal(data, 0x994c) + 0x9950 + 4
    names = [data[table + i * 20:table + (i + 1) * 20].split(b'\0')[0].decode('ascii') for i in range(5)]
    if namespace != read_namespace or data[namespace:namespace + 4] != b'map\0' or data[filename:filename + 7] != b'%d.map\0':
        raise ValueError('Map cache strings do not match the static evidence')
    calls = {f'{at:#x}': f'{bl_target(data, at):#x}' for at in [0x137f2, 0x13ada, 0x13ae2, 0x13b0e, 0x18506, 0x1850c, 0x18c50, 0x1381c, 0x13824]}
    return {'address_basis': 'original file offsets; no native execution',
            'native_sha256': digest(data), 'cache_namespace': 'map', 'cache_filename': '%d.map',
            'cache_string_offsets': {'namespace': hex(namespace), 'filename': hex(filename)},
            'direct_calls': calls, 'layout_dispatch_selector': hex(literal(data, 0x17fe2)),
            'cache_missing_request_value': hex(literal(data, 0x13b0c)),
            'bundle_table_offset': hex(table), 'bundle_names': names,
            'ranges': [{'name': name, 'start': hex(start), 'end_exclusive': hex(end),
                        'sha256': digest(data[start:end])} for name, start, end in RANGES],
            'interpretations': [
                '0x17fe2/0x17fe6 -> 0x180ca -> 0x1850c -> 0x137c8: layout input dispatch case 0x02001001.',
                '0x13ada reads map/%d.map; 0x13ae2 parses a cache hit; miss at 0x13b0c passes 0x02000002 to 0x18a44.',
                '0x137f2 writes current stream to map/%d.map before parsing; terrain arrays are copied by 0x277e8.',
                'The four 0x2737c calls in the scene reader allocate zeroed work arrays, not four more serialized layers.',
                'The cache prefix is compared to an expected 32-bit value; no checksum algorithm or live protocol is proven.',
                'These input/cache branches are not a procedural map generator; live server responses have not been captured.']}


def parse_local_versions(data, names):
    """Observed local config format; native version reader stores records backwards."""
    rows, offset = [], 0
    for name in reversed(names):
        start = offset
        if offset + 2 > len(data):
            raise ValueError('Truncated local version record')
        size = int.from_bytes(data[offset:offset + 2], 'little')
        offset += 2
        if size < 2 or size % 2 or offset + size + 4 > len(data):
            raise ValueError('Invalid local version string')
        text = data[offset:offset + size].decode('utf-16-be')
        if not text.endswith('\0') or not text[:-1].isascii() or not text[:-1].isdecimal():
            raise ValueError('Unexpected local version value')
        offset += size
        length = int.from_bytes(data[offset:offset + 4], 'little')
        offset += 4
        rows.append({'offset': start, 'bundle': name, 'version_text': text[:-1], 'recorded_package_bytes': length})
    if offset != len(data):
        raise ValueError('Unparsed local version trailer')
    return rows


def embedded_candidates(data, expected):
    matches, identity_hits, numeric_hits = [], 0, 0
    for match in re.finditer(rb'\x00[\x02\x04\x06]\x00[0-9]', data):
        offset = match.start()
        reader = recovery.MapReader(data[offset:])
        try:
            identifier = reader.text()
            if not identifier.isascii() or not identifier.isdecimal():
                continue
            numeric_hits += 1
            map_id = int(identifier)
            if map_id not in expected or reader.text() != expected[map_id]:
                continue
            identity_hits += 1
            scene, consumed = recovery.parse_scene_prefix(data[offset:], expected)
        except (ValueError, UnicodeError):
            continue
        matches.append({'byte_offset': offset, 'payload_bytes': consumed,
                        'payload_sha256': digest(data[offset:offset + consumed]),
                        'remaining_stream_bytes': len(data) - offset - consumed,
                        'review_required': True, 'scene': scene})
    return matches, identity_hits, numeric_hits


class StreamScanner:
    def __init__(self, expected, maximum_stream=4 * 1024 * 1024, maximum_expanded=64 * 1024 * 1024,
                 maximum_depth=2, maximum_attempts=50000):
        self.expected, self.maximum_stream, self.maximum_expanded = expected, maximum_stream, maximum_expanded
        self.maximum_depth, self.maximum_attempts = maximum_depth, maximum_attempts
        self.seen, self.streams, self.candidates, self.limits = {}, [], [], []
        self.expanded = self.attempts = self.decode_errors = 0

    def scan(self, data, source, depth=0):
        sha = digest(data)
        row = {'source': source, 'bytes': len(data), 'sha256': sha, 'compression_depth': depth}
        self.streams.append(row)
        if sha in self.seen:
            row['duplicate_of'] = self.seen[sha]
            return
        self.seen[sha] = source
        candidates, identity_hits, numeric_hits = embedded_candidates(data, self.expected)
        row.update(numeric_prefix_hits=numeric_hits, identity_prefix_hits=identity_hits, candidates=len(candidates))
        self.candidates.extend({'source': source, 'stream_sha256': sha, **candidate} for candidate in candidates)
        # Lookahead is intentional: a false zlib header immediately before a
        # genuine gzip member must not consume and hide its magic bytes.
        for match in re.finditer(rb'(?=(\x1f\x8b\x08|[\x08\x18\x28\x38\x48\x58\x68\x78][\s\S]))', data):
            at = match.start()
            gzip = data[at:at + 3] == b'\x1f\x8b\x08'
            if not gzip and (int.from_bytes(data[at:at + 2], 'big') % 31 or data[at + 1] & 32):
                continue
            if depth >= self.maximum_depth:
                self.limits.append({'source': source, 'offset': at, 'reason': 'compression_depth'})
                continue
            if self.attempts >= self.maximum_attempts:
                self.limits.append({'source': source, 'offset': at, 'reason': 'compression_attempts'})
                break
            self.attempts += 1
            decoder = zlib.decompressobj(31 if gzip else 15)
            allowed = min(self.maximum_stream, max(0, self.maximum_expanded - self.expanded))
            try:
                output = decoder.decompress(data[at:], allowed + 1)
            except zlib.error:
                self.decode_errors += 1
                continue
            if len(output) > allowed:
                self.limits.append({'source': source, 'offset': at, 'reason': 'expanded_size'})
                continue
            if not decoder.eof:
                self.decode_errors += 1
                continue
            self.expanded += len(output)
            self.scan(output, f'{source}::{"gzip" if gzip else "zlib"}@{at:#x}', depth + 1)

    def report(self):
        return {'unique_streams': len(self.seen), 'streams': self.streams, 'candidates': self.candidates,
                'candidate_count': len(self.candidates), 'expanded_bytes': self.expanded,
                'compression_attempts': self.attempts, 'rejected_compression_headers': self.decode_errors,
                'limit_hits': self.limits, 'limits': {'maximum_stream_bytes': self.maximum_stream,
                    'maximum_expanded_bytes': self.maximum_expanded, 'maximum_depth': self.maximum_depth,
                    'maximum_attempts': self.maximum_attempts}}


def audit(root=ROOT, extra_roots=()):
    world = recovery.load_world_exporter(root).build_catalog(root)
    expected = {row['original_map_id']: row['name'] for row in world['maps']['records']}
    native = (root / 'analysis/unpacked/ssjx/gameonline.ext').read_bytes()
    flow = native_flow(native)
    spec = importlib.util.spec_from_file_location('map_source_mrp', root / 'analysis/unpack_mrp.py')
    mrp = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mrp)
    scanner, archives = StreamScanner(expected), []
    decoded_hashes, decoded_bytes = set(), 0
    for relative in PACKAGES:
        path = root / relative
        data = path.read_bytes()
        header = mrp.read_header(data)
        if header['appid'] != 403084:
            raise ValueError('Do not import a similarly named game')
        members = mrp.parse_directory(data, header)
        decoded = []
        for member in members:
            start, length = member['stored_offset'], member['stored_length']
            raw = data[start:start + length]
            if raw.startswith(b'\x1f\x8b'):
                decoder = zlib.decompressobj(31)
                payload = decoder.decompress(raw, scanner.maximum_stream + 1)
                if len(payload) > scanner.maximum_stream or not decoder.eof:
                    raise ValueError('Declared archive member exceeds safe decoding bounds')
            else:
                payload = raw
            decoded_bytes += len(payload)
            if len(payload) > scanner.maximum_stream or decoded_bytes > scanner.maximum_expanded:
                raise ValueError('Archive payload set exceeds safe decoding budget')
            decoded.append((member['name'], payload))
        archives.append({'path': relative, 'sha256': digest(data), 'appid': header['appid'],
                         'version': header['version'], 'bytes': len(data), 'members': len(members),
                         'member_types': dict(sorted(Counter(Path(name).suffix or '(no suffix)' for name, _ in decoded).items())),
                         'scene_named_members': [name for name, _ in decoded if name.lower().endswith('.map')],
                         'all_member_payloads_match_unpacked': all((root / 'analysis/unpacked/ssjx' / ('' if path.name == 'ssjx.mrp' else path.stem) / name).read_bytes() == payload for name, payload in decoded)})
        scanner.scan(data, relative)
        for name, payload in decoded:
            decoded_hashes.add(digest(payload))
            scanner.scan(payload, f'{relative}::{name}')
    version_path = root / 'analysis/source/ssjx/commonRecord/version'
    version = version_path.read_bytes()
    scanner.scan(version, version_path.relative_to(root).as_posix())
    versions = parse_local_versions(version, flow['bundle_names'])
    for row in versions:
        row['matches_local_package_size'] = (root / f'analysis/source/ssjx/{row["bundle"]}.mrp').stat().st_size == row['recorded_package_bytes']
    for folder in extra_roots:
        if any(part.lower() in EXCLUDED for part in folder.parts):
            continue
        if not folder.is_dir():
            raise ValueError('Extra scan root must be an existing directory')
        for path in sorted(folder.rglob('*')):
            if not path.is_file() or any(part.lower() in EXCLUDED for part in path.relative_to(folder).parts):
                continue
            if path.stat().st_size > 40 * 1024 * 1024:
                raise ValueError('Extra source exceeds scan file limit')
            data = path.read_bytes()
            if data.startswith(b'MRPG') and not data.startswith(b'MRPGCMAP'):
                if mrp.read_header(data)['appid'] != 403084:
                    continue
            scanner.scan(data, str(path))
    return {'format_version': 1, 'source_package': world['source_package'], 'native_flow': flow,
            'archives': archives, 'local_version_records': versions,
            'all_declared_payload_hashes_scanned': decoded_hashes <= scanner.seen.keys(),
            'world_directory_entries': len(expected), 'scene_scan': scanner.report(),
            'limitations': ['No ARM/MR code execution and no historical endpoint contact.',
                'Candidates require review; no terrain is promoted to client/game assets.',
                'Only the v48 identity/name/two-layer schema and plain/gzip/zlib streams were searched.',
                'Unknown envelopes, raw deflate, encryption, differently named scenes or missing external caches remain unverified.',
                'Four-byte cache token equality is not a verified payload checksum.',
                'No original NPC, quest, collision-bit or teleport semantics are invented.']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'analysis/recovery/maps/source_audit.json')
    parser.add_argument('--scan-root', action='append', type=Path, default=[])
    parser.add_argument('--capstone-path', type=Path, help='Optional local Capstone for readable evidence')
    args = parser.parse_args()
    report = audit(extra_roots=args.scan_root)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf8')
    if args.capstone_path:
        sys.path.insert(0, str(args.capstone_path))
        from capstone import Cs, CS_ARCH_ARM, CS_MODE_THUMB
        native = (ROOT / 'analysis/unpacked/ssjx/gameonline.ext').read_bytes()
        decoder = Cs(CS_ARCH_ARM, CS_MODE_THUMB)
        lines = [f'; STATIC Online map input/cache evidence; SHA256 {digest(native)}', '; Original file offsets. Not original source code.']
        for name, start, end in RANGES:
            lines.append(f'\n; {name} [{start:#x}, {end:#x})')
            lines.extend(f'{row.address:08x} {row.bytes.hex():<12} {row.mnemonic:<9} {row.op_str}' for row in decoder.disasm(native[start:end], start))
        args.output.with_suffix('.asm').write_text('\n'.join(lines) + '\n', encoding='utf8')
    print(json.dumps({'archives': len(report['archives']), 'declared_members': sum(row['members'] for row in report['archives']),
        'directory_maps': report['world_directory_entries'], 'unique_streams': report['scene_scan']['unique_streams'],
        'scene_candidates': report['scene_scan']['candidate_count'], 'limit_hits': len(report['scene_scan']['limit_hits'])}, indent=2))


if __name__ == '__main__':
    main()
