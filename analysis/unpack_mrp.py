#!/usr/bin/env python3
"""Recursive, bounds-checked Mythroad/MRPG container unpacker.

It extracts original member payload bytes, transparently gunzips individual
members, and recursively unpacks embedded .mrp packages. It does not execute
any code and does not claim to reconstruct original source from .mr files.

Usage: python unpack_mrp.py INPUT.mrp OUTPUT_DIRECTORY
"""
import argparse
import gzip
import hashlib
import json
import re
import struct
from pathlib import Path

MAX_FILES = 1000
MAX_UNCOMPRESSED_SIZE = 40 * 1024 * 1024
MAX_DEPTH = 6


def uint32(buf: bytes, offset: int) -> int:
    return struct.unpack_from('<I', buf, offset)[0]


def sha256(blob: bytes) -> str:
    return hashlib.sha256(blob).hexdigest()


def gbk_field(blob: bytes) -> str:
    return blob.split(b'\0', 1)[0].decode('gb18030', errors='replace')


def safe_name(raw: bytes) -> str:
    name = gbk_field(raw)
    # No absolute paths, '..' components, or path separators from foreign archives.
    name = name.replace('\\', '_').replace('/', '_')
    name = ''.join(ch if ch.isprintable() and ch not in '<>:"|?*' else '_' for ch in name)
    if name in ('', '.', '..'):
        raise ValueError('Illegal member name')
    return name


def read_header(blob: bytes) -> dict:
    if len(blob) < 240 or blob[:4] != b'MRPG':
        raise ValueError('Invalid MRPG magic or short header')
    file_start = uint32(blob, 4)
    total = uint32(blob, 8)
    hdr_size = uint32(blob, 12)
    if total != len(blob):
        raise ValueError(f'MRPG declared length {total} differs from actual {len(blob)}')
    if not 240 <= hdr_size <= file_start + 8 <= len(blob):
        raise ValueError('Invalid header or directory bounds')
    return {
        'magic': 'MRPG',
        'package_length': total,
        'file_start_field': file_start,
        'directory_start': hdr_size,
        'directory_end': file_start + 8,
        'filename': gbk_field(blob[16:28]),
        'display_name': gbk_field(blob[28:52]),
        'authorization': gbk_field(blob[52:68]),
        'appid': uint32(blob, 68),
        'version': uint32(blob, 72),
        'flags': uint32(blob, 76),
        'builder_version': uint32(blob, 80),
        'stored_crc32': f'{uint32(blob, 84):08x}',
        'vendor': gbk_field(blob[88:128]),
        'description': gbk_field(blob[128:192]),
        'extra_header_ascii': blob[240:hdr_size].split(b'\x00', 1)[0].decode('ascii', errors='replace'),
        'sha256': sha256(blob),
    }


def parse_directory(blob: bytes, header: dict) -> list:
    entries = []
    cur, end = header['directory_start'], header['directory_end']
    while cur < end:
        if len(entries) >= MAX_FILES or cur + 4 > end:
            raise ValueError('Too many members or truncated filename length')
        name_len = uint32(blob, cur)
        cur += 4
        if name_len <= 1 or name_len > 256 or cur + name_len + 12 > end:
            raise ValueError(f'Unreasonable member name length {name_len} at {cur - 4}')
        raw_name = blob[cur:cur + name_len]
        cur += name_len
        file_pos, file_len, unknown = struct.unpack_from('<III', blob, cur)
        cur += 12
        if file_pos + file_len > len(blob):
            raise ValueError('File member exceeds archive bounds')
        entries.append({'name': safe_name(raw_name), 'stored_offset': file_pos,
                        'stored_length': file_len, 'unknown': unknown})
    if cur != end:
        raise ValueError('File directory alignment error')
    return entries


def unpack(blob: bytes, dest: Path, prefix: str, collector: list, depth: int) -> dict:
    if depth > MAX_DEPTH:
        raise ValueError('Maximum nested depth exceeded')
    header = read_header(blob)
    entries = parse_directory(blob, header)
    dest.mkdir(parents=True, exist_ok=True)
    (dest / 'header.json').write_text(json.dumps(header, indent=2, ensure_ascii=False), encoding='utf-8')
    seen = set()
    for ent in entries:
        name = ent['name']
        if name.casefold() in seen:
            raise ValueError(f'Duplicate filenames: {name}')
        seen.add(name.casefold())
        start, length = ent['stored_offset'], ent['stored_length']
        raw = blob[start:start+length]
        if raw.startswith(b'\x1f\x8b'):
            decompressed = gzip.decompress(raw)
            if len(decompressed) > MAX_UNCOMPRESSED_SIZE:
                raise ValueError('Decompressed member exceeds memory limit')
            data, compression = decompressed, 'gzip'
        else:
            data, compression = raw, 'none'
        p = dest / name
        p.write_bytes(data)
        ent.update({
            'path': f'{prefix}/{name}', 'compression': compression,
            'unpacked_length': len(data), 'sha256': sha256(data),
            'content_type': ('ARM code extension' if data.startswith(b'MRPGCMAP')
                             else 'MRPG archive' if data.startswith(b'MRPG')
                             else 'MR bytecode' if data.startswith(b'\x1bMRP')
                             else 'other')
        })
        collector.append(ent.copy())
        if data.startswith(b'MRPG') and not data.startswith(b'MRPGCMAP'):
            child_prefix = f'{prefix}/{name}__contents'
            try:
                child = unpack(data, dest / f'{name}__contents', child_prefix, collector, depth + 1)
                ent['child_count'] = len(child['members'])
            except Exception as exc:
                ent['child_parse_error'] = str(exc)
    (dest / 'directory.json').write_text(json.dumps(entries, indent=2, ensure_ascii=False), encoding='utf-8')
    return {'header': header, 'members': entries}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('input', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    package = args.input.read_bytes()
    collector = []
    root = unpack(package, out / 'unpacked', 'unpacked', collector, 0)
    manifest = {'source_path': args.input.name, 'root': root['header'],
                'total_members_all_levels': len(collector), 'files': collector}
    (out / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    print('Top-level header:', json.dumps(root['header'], ensure_ascii=False, indent=2))
    print('Top-level members:', len(root['members']))
    print('Total members including nested:', len(collector))
    for entry in collector:
        print(f"{entry['path']}  {entry['content_type']}  {entry['unpacked_length']:8d} bytes  {entry['compression']}")

if __name__ == '__main__':
    main()
