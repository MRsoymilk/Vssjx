"""Summarize measurements, never equate successful socket opens with capacity."""
import argparse
import json
from pathlib import Path
import statistics
import re


def resources(samples, name):
    valid = [sample for sample in samples if sample.get(name)]
    cpu = []
    for before, after in zip(valid, valid[1:]):
        elapsed = after['time_unix'] - before['time_unix']
        if elapsed > 0:
            cpu.append(100 * (after[name]['cpu_seconds'] - before[name]['cpu_seconds']) / elapsed)
    return {'rss_peak_mib': max((s[name]['rss_mib'] for s in valid), default=None),
            'fds_peak': max((s[name]['fds'] for s in valid), default=None),
            'threads_peak': max((s[name]['threads'] for s in valid), default=None),
            'cpu_mean_percent_one_core_100': statistics.mean(cpu) if cpu else None,
            'cpu_peak_percent_one_core_100': max(cpu) if cpu else None}


def database_resources(samples):
    readings = [sample['database_container'] for sample in samples if sample.get('database_container')]
    cpu = [float(reading['CPUPerc'].rstrip('%')) for reading in readings]
    def memory_mib(reading):
        found = re.match(r'([\d.]+)([KMG]?i?B)', reading['MemUsage'])
        if not found: return 0
        multipliers = {'B': 1 / 1048576, 'kB': 1000 / 1048576, 'KB': 1000 / 1048576,
                       'KiB': 1 / 1024, 'MB': 1000000 / 1048576, 'MiB': 1,
                       'GB': 1000000000 / 1048576, 'GiB': 1024}
        return float(found[1]) * multipliers[found[2]]
    return {'sample_count': len(readings), 'cpu_mean_percent_one_core_100': statistics.mean(cpu) if cpu else None,
            'cpu_peak_percent_one_core_100': max(cpu) if cpu else None,
            'memory_peak_mib': max((memory_mib(reading) for reading in readings), default=None)}


def summarize(directory):
    env = json.loads((directory / 'environment.json').read_text())
    raw = json.loads((directory / 'results.json').read_text())
    samples = json.loads((directory / 'samples.json').read_text())
    results = []
    for result in raw['results']:
        stage = result['stage']
        population = stage['players']
        duration = result['measured_seconds']
        moving = sum(index * 100 < population * stage['moving_percent'] for index in range(population))
        expected_moves = sum(max(0, int((duration * 1000 - 1 - (index * 431) % 2000) // 2000) + 1) for index in range(moving))
        average_hz = result.get('full_population_state_updates', result.get('full_population_snapshots', 0)) / population / duration
        failures = []
        if result['active_at_start'] != population or result['active_at_end'] != population: failures.append('not all clients stayed online')
        if result['clients_ever_saw_entire_population'] != population: failures.append('not every client verified entire population')
        if result['errors']: failures.append('protocol/server/connection errors')
        if expected_moves and result['moves_sent'] / expected_moves < .98: failures.append('offered movement rate below 98% (generator/load pressure)')
        for metric in ('ping_roundtrip', 'movement_snapshot_observation'):
            value = result[metric]['p95_ms']
            if (metric == 'ping_roundtrip' or moving) and (value is None or value > 500): failures.append(metric + ' p95 above 500ms or missing')
        if moving and average_hz < 8: failures.append('full-population synchronization below 8Hz')
        if result.get('world_sync_version') == 2:
            if result['full_visibility_at_start'] != population: failures.append('not all reconstructed populations established before timing')
            if moving and result['minimum_client_state_updates'] / duration < 8: failures.append('at least one client received fewer than 8 full-state updates/s')
        if result['chat_sends'] < .9 * duration: failures.append('offered chat rate below 0.9/s')
        if result['chat_sends'] and result['chat_accepted'] < result['chat_sends'] - 1: failures.append('chat confirmations missing')
        if result['chat_deliveries'] < max(0, result['chat_accepted'] - 1) * population: failures.append('chat fanout deliveries missing beyond one tail message')
        if result['chat_delivery']['p95_ms'] is None or result['chat_delivery']['p95_ms'] > 1000: failures.append('chat delivery p95 above 1000ms or missing')
        start, end = result.get('measure_start_unix'), result.get('measure_end_unix')
        selected = [s for s in samples if start is not None and start <= s['time_unix'] <= end] if start is not None else []
        results.append(dict(result, expected_fixed_rate_moves=expected_moves,
                            fixed_population_measurement=(result['active_at_start'] == population and result['active_at_end'] == population and result.get('full_visibility_at_start', population) == population),
                            full_population_snapshots_per_client_second=average_hz,
                            full_population_state_updates_per_client_second=average_hz,
                            minimum_client_state_updates_per_second=(result['minimum_client_state_updates'] / duration if 'minimum_client_state_updates' in result else None),
                            preliminary_gate='FAIL' if failures else 'PASS', preliminary_failure_reasons=failures,
                            resources={'server': resources(selected, 'server'), 'driver': resources(selected, 'driver'), 'database': database_resources(selected)}))
    return {'environment': env, 'setup': raw['setup'], 'preliminary_gate_definition': 'short loopback current-feature probe only: all clients online and verify population; zero errors; >=98% fixed offered movement; movement/ping p95<=500ms; complete reconstructed-world frontiers>=8Hz (v1 full snapshots; v2 baseline plus contiguous deltas). V2 additionally requires complete population before timing and every client>=8Hz; >=0.9 chat/s offered and chat p95<=1000ms. NOT full-game or 60min production acceptance.',
            'overall_resources': {'server': resources(samples, 'server'), 'driver': resources(samples, 'driver'), 'database': database_resources(samples)}, 'results': results}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--markdown', type=Path)
    args = parser.parse_args()
    summary = summarize(args.directory)
    target = args.output or args.directory / 'summary.json'
    target.write_text(json.dumps(summary, ensure_ascii=False, indent=2))
    if args.markdown:
        frontier_heading = '重建状态更新Hz/人' if any(r.get('world_sync_version') == 2 for r in summary['results']) else '完整同步Hz/人'
        lines = ['# 当前功能容量实测（自动汇总）', '',
                 '仅当前功能、本机回环短测；不代表完整玩法、公网或60分钟稳定性验收。', '',
                 '| 场景 | 在线（开始/结束） | 验过完整人数的客户端 | %s | 移动观察p95 ms | ping p95 ms | 正文下行MiB/s | 初步门槛 |' % frontier_heading,
                 '|---|---:|---:|---:|---:|---:|---:|---|']
        for result in summary['results']:
            lines.append('| %s | %d/%d | %d | %.2f | %s | %s | %.2f | %s |' % (
                result['stage']['name'], result['active_at_start'], result['active_at_end'],
                result['clients_ever_saw_entire_population'], result['full_population_snapshots_per_client_second'],
                result['movement_snapshot_observation']['p95_ms'] if result['movement_snapshot_observation']['p95_ms'] is not None else '—', result['ping_roundtrip']['p95_ms'],
                result['payload_mib_per_second'], result['preliminary_gate']))
        lines += ['', '未满员行的延迟仅属于实际入场客户端，完整同步Hz=0表示没有形成目标人数快照，不代表完全没有部分地图数据；不能解读为真实满额玩家容量。', '', '服务器与机器人CPU/RSS、错误及环境指纹见同目录JSON报告。', '']
        args.markdown.write_text('\n'.join(lines))
    for result in summary['results']:
        print(json.dumps({key: value for key, value in result.items() if key in ['stage', 'active_at_start', 'active_at_end', 'payload_mib_per_second', 'full_population_snapshots_per_client_second', 'ping_roundtrip', 'movement_snapshot_observation', 'errors', 'resources', 'preliminary_gate', 'preliminary_failure_reasons']}, ensure_ascii=False))


if __name__ == '__main__': main()
