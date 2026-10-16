#!/usr/bin/env python3
"""Cross-reference static reports with a pinned public SDK layout and local resources.
No native game code is run. No network connections are made.
"""
from __future__ import annotations
import collections
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'disasm'
NETWORK = {'mr_initNetwork', 'mr_closeNetwork', 'mr_getHostByName', 'mr_socket', 'mr_connect', 'mr_closeSocket', 'mr_recv', 'mr_recvfrom', 'mr_send', 'mr_sendto'}
FILE_APIS = {'mr_open', 'mr_close', 'mr_info', 'mr_write', 'mr_read', 'mr_seek', 'mr_getLen', 'mr_remove', 'mr_rename'}


def main():
    report = json.loads((OUT / 'gameonline_mixed.json').read_text(encoding='utf-8'))
    reference = json.loads((ROOT / 'mrp_sdk_reference.json').read_text(encoding='utf-8'))
    blob = (ROOT / 'unpacked/ssjx/gameonline.ext').read_bytes()
    if hashlib.sha256(blob).hexdigest() != report['input_sha256']:
        raise RuntimeError('The input and the mixed-analysis report do not match.')
    fields = reference['fields']
    if reference['pointer_bytes'] != 4 or fields[25] != '_mr_c_function_new' or fields[85] != 'mr_connect':
        raise ValueError('Unexpected SDK layout reference.')

    def table_api(expression):
        if expression == 'mem[mem[0x00000000]]':
            return fields[0]
        match = re.fullmatch(r'mem\[\(mem\[0x00000000\]\+0x([0-9a-f]+)\)\]', expression or '')
        if match:
            offset = int(match[1], 16)
            if offset % 4 == 0 and offset // 4 < len(fields):
                return fields[offset // 4]
        return None

    # Cached SDK pointers are evidence from static assignments, not immutable globals.
    assignments = collections.defaultdict(list)
    for function, data in report['functions'].items():
        for store in data['stores']:
            api = table_api(store['value'])
            if api and store['address'] != '?':
                assignments['mem[' + store['address'] + ']'].append({'api': api, 'function': function, 'site': store['site'], 'confidence': data['confidence']})
    aliases = {expr: rows for expr, rows in assignments.items() if len({row['api'] for row in rows}) == 1}
    matches = []
    for call in report['calls']:
        api = table_api(call['expression'])
        evidence = 'direct_header_table_offset' if api else None
        alias = aliases.get(call['expression'])
        if not api and alias:
            api = alias[0]['api']
            evidence = 'cached_global_assignment_candidate'
        if api:
            matches.append(dict(call, sdk_api=api, sdk_evidence=evidence, sdk_slot=fields.index(api) * 4))
    callers = collections.defaultdict(list)
    for call in report['calls']:
        if call['target']:
            callers[call['target']].append(call)
    network_matches = [row for row in matches if row['sdk_api'] in NETWORK]
    network_functions = sorted({row['function'] for row in network_matches})
    upstream = []
    for function in network_functions:
        for call in callers.get(function, []):
            upstream.append({'network_function': function, 'caller_function': call['function'], 'site': call['site'], 'arguments': call['arguments'], 'argument_strings': call['argument_strings']})

    raw_strings = []
    for encoding, pattern in [('utf-16le', rb'(?:[\x20-\x7e]\x00){4,}'), ('utf-16be', rb'(?:\x00[\x20-\x7e]){4,}')]:
        for match in re.finditer(pattern, blob):
            text = match.group().decode(encoding)
            if re.search(r'\.mrp|\.map|http|\.(com|cn|net)\b|(?:\d{1,3}\.){3}\d{1,3}', text, re.I):
                raw_strings.append({'offset': match.start(), 'encoding': encoding, 'text': text[:250], 'confidence': 'encoded_string_candidate'})
    filename_patterns = [row for row in report['string_xrefs'] if re.search(r'\.map|\.mrp|worldmap|version', row['text'], re.I)]
    package_tables = []
    function = report['functions'].get('thumb_00009904', {})
    for materialized in function.get('pc_addresses', []):
        if materialized['site'] != 0x9950:
            continue
        start = materialized['value']
        if start + 100 > len(blob):
            continue
        for encoding in ('utf-16le', 'utf-16be', 'ascii'):
            strings = []
            for index in range(5):
                block = blob[start + index * 20:start + (index + 1) * 20]
                strings.append(block.decode(encoding, errors='replace').split('\0', 1)[0])
            score = sum(bool(re.fullmatch(r'[a-z0-9_]+\.mrp', text, re.I)) for text in strings)
            if score >= 3:
                package_tables.append({'function': 'thumb_00009904', 'materialization_site': '0x9950', 'offset': start, 'entry_bytes': 20, 'count': 5, 'encoding': encoding, 'names': strings, 'basis': 'five-iteration loop with index*20 plus decoded fixed-stride data'})
    root = ROOT / 'unpacked/ssjx'
    file_paths = sorted(str(path.relative_to(root)) for path in root.rglob('*') if path.is_file() and not path.is_symlink())
    map_files = [path for path in file_paths if path.lower().endswith('.map')]
    related = [path for path in file_paths if path in ('worldmap.data', 'sfc.bin') or path.endswith('header.json')]
    related_functions = sorted({ref['function'] for ref in filename_patterns})
    focused_calls = {name: report['functions'][name]['calls'] for name in related_functions}
    api_by_function = collections.defaultdict(set)
    for row in matches:
        api_by_function[row['function']].add(row['sdk_api'])
    for rows in focused_calls.values():
        for row in rows:
            row['callee_sdk_apis'] = sorted(api_by_function.get(row['target'], set()))
    result = {'schema_version': 1, 'input_sha256': report['input_sha256'], 'sdk_reference': reference, 'summary': {'sdk_matched_sites': len({(row['site'], row['mode']) for row in matches}), 'network_matched_sites': len({(row['site'], row['mode']) for row in network_matches}), 'network_functions': len(network_functions), 'cached_sdk_alias_candidates': len(aliases), 'local_numeric_map_files': len(map_files), 'decoded_package_tables': len(package_tables)}, 'sdk_matches': matches, 'network_matches': network_matches, 'network_upstream_callers': upstream, 'cached_sdk_alias_candidates': aliases, 'filename_patterns': filename_patterns, 'utf16_resource_strings': raw_strings, 'package_tables': package_tables, 'local_map_files': map_files, 'local_related_files': related, 'resource_related_calls': focused_calls, 'limitations': ['SDK field names match a public compatible layout; this is not proof of the original SDK version.', 'Cached global aliases may be overwritten at runtime.', 'Missing .map files are a resource-gap clue, not proof of a particular network command.', 'No original server address, live endpoint, packet capture, or recovered server-side resource is claimed.']}
    (OUT / 'gameonline_resource_findings.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    lines = ['# gameonline.ext 网络 API 与资源线索', '', '## 证据边界', '', f"输入 SHA-256：`{report['input_sha256']}`。地址均为文件偏移。", 'API 名称来自固定版本公开 SDK 表布局匹配；缓存函数指针仅标记静态赋值候选。未执行游戏代码，未连接原服务器。', '', '## 网络调用候选', '', '| 所属函数 | 调用点 | SDK 槽位 | API | 依据 |', '|---|---|---|---|---|']
    for row in network_matches:
        lines.append(f"| `{row['function']}` | `0x{row['site']:x}` | `0x{row['sdk_slot']:x}` | `{row['sdk_api']}` | {row['sdk_evidence']} |")
    lines += ['', '## 网络调用的上游', '', '| 调用函数 | 调用点 | 被调用网络函数 | 前四个参数的静态值 |', '|---|---|---|---|']
    for row in upstream:
        lines.append(f"| `{row['caller_function']}` | `0x{row['site']:x}` | `{row['network_function']}` | `{','.join(row['arguments'])}` |")
    lines += ['', '## 资源文件线索', '', f'当前解包目录中 `.map` 文件数：**{len(map_files)}**。`%d.map` 的出现说明客户端按数字构造该文件名，不能单独证明这些文件由服务器下发。', '']
    for ref in filename_patterns:
        lines.append(f"- `{ref['function']}` / `0x{ref['site']:x}` → `{ref['text']}`（数据位置 `0x{ref['offset']:x}`）。")
    for table in package_tables:
        lines += ['', f"固定表：`0x{table['offset']:x}`，{table['encoding']}，每项 {table['entry_bytes']} 字节，共 {table['count']} 项。", ', '.join('`' + name + '`' for name in table['names'])]
    lines += ['', '## 后续优先项', '', '从 mr_connect/mr_send/mr_recv 对应的调用点向上追踪地址来源与报文读写；核对资源版本列表、分块落盘和 `%d.map` 的读取／写入路径。尚不能生成可靠的原服登录响应或补回丢失场景。', '', '## SDK 依据', '', reference['source_url'], '', '原始参考仓库：GPL-3.0；此报告只记录接口名称、偏移和分析证据，没有将参考实现合入客户端。', '']
    (OUT / 'gameonline_resource_findings.md').write_text('\n'.join(lines), encoding='utf-8')
    print(json.dumps({'summary': result['summary'], 'network_matches': network_matches, 'network_upstream_callers': upstream[:20], 'package_tables': package_tables, 'filename_patterns': filename_patterns, 'utf16_resource_strings': raw_strings[:20]}, ensure_ascii=False))


if __name__ == '__main__':
    main()
