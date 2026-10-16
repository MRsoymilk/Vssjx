"""Trace the original cache namespace and compare additional packages read-only.

Outputs evidence only. Additional same-name games/variants are never imported.
No native code execution, archive extraction to disk, or historical network calls.
"""
import argparse
import json
from pathlib import Path, PurePosixPath
import sys
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import audit_original_map_sources as audit

RANGES = [
    ('cache_root_initialization', 0x24b8c, 0x24bd2),
    ('cache_path_join', 0x26df8, 0x26e60),
    ('package_header_field_dispatch', 0x2ceac, 0x2ced4),
    ('package_internal_basename', 0x2ced4, 0x2cf34),
]


def cstring(data, at):
    end = data.index(b'\0', at)
    return data[at:end].decode('ascii')


def cache_path_evidence(native, package):
    if audit.digest(native) != audit.NATIVE_SHA256:
        raise ValueError('Path evidence applies only to the audited native v48 bytes')
    root_format_at = audit.literal(native, 0x24ba4) + 0x24ba8 + 4
    directory_format_at = audit.literal(native, 0x26e10) + 0x26e14 + 4
    file_format_at = audit.literal(native, 0x26e46) + 0x26e4c + 4
    # ADD PC at 0x2ceba dispatches the relative halfword table at 0x2cec0.
    case_one = 0x2cebe + int.from_bytes(native[0x2cec2:0x2cec4], 'little') * 2
    formats = [cstring(native, at) for at in (root_format_at, directory_format_at, file_format_at)]
    if formats != ['gwy/%s', '%s/%s', '%s/%s/%s'] or case_one != 0x2ced4:
        raise ValueError('Unexpected native cache root/header dispatch')
    internal_name = package[16:28].split(b'\0')[0].decode('gb18030')
    # Case 1 reads 12 header bytes at offset 0x10, then removes the LAST suffix.
    if '.' not in internal_name:
        raise ValueError('Native case 1 requires an internal filename extension')
    stem = internal_name.rsplit('.', 1)[0]
    if not stem or any(ch in stem for ch in '/\\:') or stem in ('.', '..'):
        raise ValueError('Unsafe internal package basename')
    root = formats[0] % stem
    return {'native_sha256': audit.digest(native), 'internal_filename': internal_name,
            'header_field_offset': 16, 'header_field_bytes': 12, 'header_selector': 1,
            'header_selector_target': hex(case_one), 'basename': stem,
            'root_relative_to_runtime_directory': root,
            'map_directory_relative_to_runtime_directory': root + '/map',
            'map_filename_pattern': root + '/map/<decimal map id>.map',
            'format_strings': [{'offset': hex(at), 'text': value} for at, value in
                               zip((root_format_at, directory_format_at, file_format_at), formats)],
            'calls': {hex(at): hex(audit.bl_target(native, at)) for at in (0x24b92, 0x24ba0, 0x24bcc)},
            'evidence': [{'name': name, 'start': hex(start), 'end_exclusive': hex(end),
                          'sha256': audit.digest(native[start:end])} for name, start, end in RANGES],
            'limitations': ['Normal package-header path only; special runtime virtual package names remain unverified.',
                            'This is relative to the original runtime working directory; the ZIP may have been rearranged.']}


def load_world_exporter(root=ROOT):
    return audit.recovery.load_world_exporter(root)  # importer verifies reference Online members


def read_package(data, reader, maximum_member=4 * 1024 * 1024):
    header = reader.read_header(data)
    entries = reader.parse_directory(data, header)
    decoded = {}
    total = 0
    for entry in entries:
        begin, size = entry['stored_offset'], entry['stored_length']
        payload = data[begin:begin + size]
        if payload.startswith(b'\x1f\x8b'):
            decoder = zlib.decompressobj(31)
            payload = decoder.decompress(payload, maximum_member + 1)
            if not decoder.eof or len(payload) > maximum_member:
                raise ValueError('Archive member exceeds decoding limit or is incomplete')
        total += len(payload)
        if len(payload) > maximum_member or total > 64 * 1024 * 1024:
            raise ValueError('Archive exceeds decoded size limit')
        if entry['name'] in decoded:
            raise ValueError('Duplicate archive member')
        decoded[entry['name']] = payload
    return header, decoded


def compare_package(data, reader, reference, expected, known_packages=None):
    header = reader.read_header(data)
    result = {key: header[key] for key in ('appid', 'version', 'filename', 'display_name', 'sha256')}
    result['review_required'] = True
    result['imported'] = False
    if header['appid'] != 403084:
        result['status'] = 'different_appid_not_scanned_or_imported'
        result['member_names_only'] = [row['name'] for row in reader.parse_directory(data, header)]
        return result
    matched_reference = (known_packages or {}).get(header['sha256'])
    if matched_reference:
        result['exact_reference_package'] = matched_reference
        if matched_reference != 'analysis/source/ssjx.mrp':
            result.update(status='exact_reference_resource_bundle', member_count=len(reader.parse_directory(data, header)))
            return result
    _, members = read_package(data, reader)
    result['status'] = 'exact_reference_main_package' if matched_reference else 'same_appid_variant_requires_review'
    result['member_count'] = len(members)
    result['matching_reference_members'] = sorted(name for name in members.keys() & reference.keys()
                                                   if members[name] == reference[name])
    result['different_reference_members'] = sorted(name for name in members.keys() & reference.keys()
                                                    if members[name] != reference[name])
    result['extra_members'] = sorted(members.keys() - reference.keys())
    result['missing_reference_members'] = sorted(reference.keys() - members.keys())
    result['native_matches_reference'] = members.get('gameonline.ext') == reference['gameonline.ext']
    result['world_directory_matches_reference'] = members.get('worldmap.data') == reference['worldmap.data']
    scanner = audit.StreamScanner(expected)
    for name, payload in sorted(members.items()):
        scanner.scan(payload, name)
    scan = scanner.report()
    result['scene_scan'] = {key: scan[key] for key in ('candidate_count', 'candidates', 'unique_streams', 'limit_hits')}
    return result


def inspect_folder(folder, relative_map_directory, scanner):
    if any(part.lower() in audit.EXCLUDED for part in folder.parts):
        return {'root': str(folder), 'excluded_by_user': True, 'files_examined': 0}
    if not folder.is_dir():
        raise ValueError('Cache root must be an existing directory')
    files = [path for path in sorted(folder.rglob('*')) if path.is_file()
             and not any(part.lower() in audit.EXCLUDED for part in path.relative_to(folder).parts)]
    wanted = relative_map_directory.lower() + '/'
    expected_cache = []
    other_map_count, shared_cache = 0, []
    selected_bytes = 0
    def read_selected(path):
        nonlocal selected_bytes
        size = path.stat().st_size
        selected_bytes += size
        if size > 40 * 1024 * 1024 or selected_bytes > 64 * 1024 * 1024:
            raise ValueError('Selected cache files exceed read limit')
        return path.read_bytes()
    for path in files:
        relative = path.relative_to(folder).as_posix()
        if relative.lower().startswith(wanted):
            data = read_selected(path)
            expected_cache.append({'path': relative, 'bytes': len(data), 'sha256': audit.digest(data)})
            scanner.scan(data, 'cache-root/' + relative)
        elif path.suffix.lower() == '.map':
            other_map_count += 1
        if relative.lower().startswith('cache/exr.'):
            data = read_selected(path)
            shared_cache.append({'path': relative, 'bytes': len(data), 'sha256': audit.digest(data)})
            scanner.scan(data, 'shared-runtime/' + relative)
    return {'root': str(folder), 'files_examined': len(files), 'expected_directory_present': any(
                path.is_dir() and path.relative_to(folder).as_posix().lower() == wanted.rstrip('/')
                for path in folder.rglob('*')),
            'expected_cache_files': expected_cache, 'other_map_files_not_promoted': other_map_count,
            'shared_runtime_cache_files': shared_cache,
            'shared_cache_identity': 'Shared SDK files are not proof of Online ownership.'}


def build_report(sources, cache_roots=(), root=ROOT):
    import importlib.util
    spec = importlib.util.spec_from_file_location('cache_path_mrp', root / 'analysis/unpack_mrp.py')
    reader = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(reader)
    reference_data = (root / 'analysis/source/ssjx.mrp').read_bytes()
    _, reference = read_package(reference_data, reader)
    flow = cache_path_evidence(reference['gameonline.ext'], reference_data)
    world = load_world_exporter(root).build_catalog(root)
    known_packages = {audit.digest((root / relative).read_bytes()): relative for relative in audit.PACKAGES}
    expected = {row['original_map_id']: row['name'] for row in world['maps']['records']}
    scanner = audit.StreamScanner(expected)
    folders = [inspect_folder(folder, flow['map_directory_relative_to_runtime_directory'], scanner)
               for folder in cache_roots]
    rows, seen = [], {}
    for path in sources:
        if any(part.lower() in audit.EXCLUDED for part in path.parts):
            rows.append({'source': str(path), 'excluded_by_user': True, 'imported': False})
            continue
        if path.stat().st_size > 40 * 1024 * 1024:
            raise ValueError('Additional archive exceeds file size limit')
        sha = audit.digest(path.read_bytes())
        row = {'source': str(path), 'sha256': sha, 'imported': False}
        rows.append(row)
        if sha in seen:
            row['duplicate_of'] = seen[sha]
            continue
        seen[sha] = str(path)
        if path.suffix.lower() == '.zip':
            with zipfile.ZipFile(path) as archive:
                if len(archive.infolist()) > 10000:
                    raise ValueError('Archive member count exceeds limit')
                entries = []
                expanded_bytes = 0
                def read_member(info):
                    nonlocal expanded_bytes
                    expanded_bytes += info.file_size
                    if expanded_bytes > 64 * 1024 * 1024:
                        raise ValueError('Selected ZIP payloads exceed cumulative read limit')
                    return archive.read(info)
                for info in archive.infolist():
                    normalized = info.filename.replace('\\', '/')
                    parts = PurePosixPath(normalized).parts
                    if any(part.lower() in audit.EXCLUDED for part in parts) or info.is_dir():
                        continue
                    if '..' in parts or PurePosixPath(normalized).is_absolute():
                        raise ValueError('Unsafe archive member name')
                    if info.file_size > 40 * 1024 * 1024:
                        raise ValueError('Archive member exceeds read limit')
                    is_mrp = normalized.lower().endswith('.mrp')
                    if is_mrp:
                        with archive.open(info) as stream:
                            prefix = stream.read(240)
                        if len(prefix) < 72 or prefix[:4] != b'MRPG' or prefix[:8] == b'MRPGCMAP':
                            continue
                        if int.from_bytes(prefix[68:72], 'little') == 403084:
                            data = read_member(info)
                            entries.append({'member': normalized, **compare_package(data, reader, reference, expected, known_packages)})
                    elif normalized.lower().endswith('.map') or '/cache/exr.' in '/' + normalized.lower():
                        scanner.scan(read_member(info), path.name + '::' + normalized)
                row.update(archive_members=len(archive.infolist()), online_packages=entries,
                           map_named_members=sum(not i.is_dir() and i.filename.lower().endswith('.map')
                                                 for i in archive.infolist()))
        else:
            row['package'] = compare_package(path.read_bytes(), reader, reference, expected, known_packages)
    scan = scanner.report()
    return {'format_version': 1, 'cache_path_evidence': flow, 'cache_roots': folders, 'additional_sources': rows,
            'cache_scene_scan': {key: scan[key] for key in ('candidate_count', 'candidates', 'unique_streams', 'limit_hits')},
            'notes': ['Additional variants remain evidence only and require review before any resource import.',
                      'Negative candidates cover only the known v48 schema and supported compression; missing data is not fabricated.']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, action='append', default=[])
    parser.add_argument('--cache-root', type=Path, action='append', default=[])
    parser.add_argument('--output', type=Path, default=ROOT / 'analysis/recovery/maps/cache_path_audit.json')
    parser.add_argument('--capstone-path', type=Path, help='Optional local dependency for static evidence excerpts')
    args = parser.parse_args()
    report = build_report(args.source, args.cache_root)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    if args.capstone_path:
        sys.path.insert(0, str(args.capstone_path))
        from capstone import Cs, CS_ARCH_ARM, CS_MODE_THUMB
        native = (ROOT / 'analysis/unpacked/ssjx/gameonline.ext').read_bytes()
        decoder = Cs(CS_ARCH_ARM, CS_MODE_THUMB)
        decoder.skipdata = True
        lines = [f'; STATIC cache namespace evidence; SHA256 {audit.digest(native)}',
                 '; File offsets; bounded excerpts can include literal/table data, not original source code.']
        for name, start, end in RANGES:
            lines.append(f'\n; {name} [{start:#x}, {end:#x})')
            lines.extend(f'{item.address:08x} {item.bytes.hex():<12} {item.mnemonic:<9} {item.op_str}'
                         for item in decoder.disasm(native[start:end], start))
        args.output.with_suffix('.asm').write_text('\n'.join(lines) + '\n', encoding='utf-8', newline='\n')
    print(json.dumps({'root': report['cache_path_evidence']['map_directory_relative_to_runtime_directory'],
                      'additional_sources': len(report['additional_sources']),
                      'cache_scene_candidates': report['cache_scene_scan']['candidate_count']}, indent=2))
