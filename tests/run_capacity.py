"""Isolated real-auth 1000-client hotspot probe. Never accepts an external target."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time

from pg_fixture import PostgresFixture
from run_server_connection import wait_for_server

ROOT = Path(__file__).resolve().parents[1]


def proc_sample(pid):
    try:
        fields = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
        return {'cpu_seconds': (int(fields[11]) + int(fields[12])) / os.sysconf('SC_CLK_TCK'),
                'rss_mib': int(fields[21]) * os.sysconf('SC_PAGE_SIZE') / 1048576,
                'threads': int(fields[17]), 'fds': len(list(Path(f'/proc/{pid}/fd').iterdir()))}
    except (FileNotFoundError, ProcessLookupError):
        return None


def mem_available():
    return next(int(line.split()[1]) / 1024 for line in Path('/proc/meminfo').read_text().splitlines() if line.startswith('MemAvailable:'))


def fingerprint():
    digest = hashlib.sha256()
    paths = sorted([*(p for p in ROOT.glob('server/src/**/*') if p.is_file()), *ROOT.glob('server/migrations/*.sql'), ROOT / 'server/Cargo.toml', ROOT / 'server/Cargo.lock', ROOT / 'shared/data/qingyun-v1.json'])
    for path in paths:
        digest.update(str(path.relative_to(ROOT)).encode() + b'\0' + path.read_bytes())
    return digest.hexdigest()


def terminate(process):
    if process is None or process.poll() is not None: return
    process.terminate()
    try: process.wait(timeout=8)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--profile', type=Path, default=ROOT / 'tests/capacity_profile.json')
    parser.add_argument('--output', type=Path, default=Path('/tmp/opencode/vssjx-capacity'))
    args = parser.parse_args()
    if not sys.platform.startswith('linux'):
        parser.error('Capacity probes require Linux /proc metrics; report summarization is available on all platforms.')
    import resource

    args.output.mkdir(parents=True, exist_ok=True)
    profile = json.loads(args.profile.read_text())
    assert 1 <= profile['players'] <= 1000
    assert all(1 <= stage['players'] <= profile['players'] and 0 <= stage['moving_percent'] <= 100 and 1 <= stage['seconds'] <= 3600 for stage in profile['stages'])
    build_env = dict(os.environ, CARGO_TARGET_DIR=str(ROOT / 'server/target'))
    for manifest in ['server/Cargo.toml', 'tests/load_driver/Cargo.toml']:
        subprocess.run(['cargo', 'build', '--locked', '--offline', '--release', '--manifest-path', str(ROOT / manifest)], env=build_env, check=True)
    metadata = {'profile': profile, 'date_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
                'host': platform.platform(), 'cpu_model': next(line.split(':', 1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines() if line.startswith('model name')),
                'logical_cpus': os.cpu_count(), 'affinity': sorted(os.sched_getaffinity(0)), 'memory_available_before_mib': mem_available(),
                'nofile_limit': resource.getrlimit(resource.RLIMIT_NOFILE), 'source_sha256': fingerprint(),
                'git_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                'dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True)),
                'rustc': subprocess.check_output(['rustc', '--version'], text=True).strip(),
                'server_binary_sha256': hashlib.sha256((ROOT / 'server/target/release/vssjx-server').read_bytes()).hexdigest(),
                'driver_binary_sha256': hashlib.sha256((ROOT / 'server/target/release/vssjx-capacity-driver').read_bytes()).hexdigest(),
                'transport': 'loopback WS/HTTP, no TLS/proxy/compression; server, driver and DB on same host',
                'database_storage': 'disposable PostgreSQL 17 Docker tmpfs; not production durable disk',
                'scope': 'one shared map, all players visible; 2s fixed-rate destination changes, 3s heartbeat, 1 global chat message/s; NO PVE/inventory workload'}
    (args.output / 'environment.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2))
    server = driver = None
    samples = []
    aborted = None
    with PostgresFixture() as db:
        env = {k: v for k, v in os.environ.items() if not k.startswith('SSJX_')}
        # Same-IP robots need an explicit entrance-rate exception. Runtime world,
        # database and password-worker limits otherwise retain production defaults.
        overrides = {'SSJX_ENV_FILE': '', 'SSJX_BIND_ADDR': '127.0.0.1:0', 'RUST_LOG': 'info',
                     'SSJX_AUTH_RATE_GLOBAL': '100000', 'SSJX_AUTH_RATE_IP': '10000', 'SSJX_AUTH_RATE_ACCOUNT': '1000',
                     'SSJX_AUTH_ACCESS_SECONDS': '3600', 'SSJX_MONITOR_BIND_ADDR': '', 'SSJX_LOG_DIR': ''}
        env.update(overrides, SSJX_DATABASE_URL=db.url)
        metadata['nonsecret_overrides'] = overrides
        try:
            server = subprocess.Popen([str(ROOT / 'server/target/release/vssjx-server')], cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            base = wait_for_server(server)
            # Drain remaining logging to a regular file so a full pipe cannot bias load.
            import threading
            server_log = (args.output / 'server.log').open('w')
            def log_server():
                for line in server.stdout:
                    assert db.password not in line
                    server_log.write(line)
                server_log.flush()
            logger = threading.Thread(target=log_server, daemon=True)
            logger.start()
            config = dict(profile, base=base, map_path=str(ROOT / 'shared/data/qingyun-v1.json'), output=str(args.output / 'results.json'))
            config_path = args.output / 'driver-config.json'
            config_path.write_text(json.dumps(config))
            with (args.output / 'driver.log').open('w') as log:
                driver = subprocess.Popen([str(ROOT / 'server/target/release/vssjx-capacity-driver'), str(config_path)], env=env, stdout=log, stderr=subprocess.STDOUT)
                deadline = time.monotonic() + 1200
                while driver.poll() is None:
                    sample = {'time_unix': time.time(), 'server': proc_sample(server.pid), 'driver': proc_sample(driver.pid), 'available_memory_mib': mem_available()}
                    samples.append(sample)
                    if len(samples) % 10 == 0:
                        collected = subprocess.run(['docker', 'stats', '--no-stream', '--format', '{{json .}}', db.name], capture_output=True, text=True, timeout=5)
                        if collected.returncode == 0:
                            try: sample['database_container'] = json.loads(collected.stdout)
                            except ValueError: pass
                    if server.poll() is not None: aborted = 'SERVER_EXITED'
                    if sample['available_memory_mib'] < 1024: aborted = 'HOST_MEMORY_SAFETY_LIMIT'
                    if any(sample[name] and sample[name]['rss_mib'] > 1800 for name in ('server', 'driver')): aborted = 'PROCESS_RSS_SAFETY_LIMIT'
                    if time.monotonic() > deadline: aborted = 'RUN_DEADLINE'
                    if aborted:
                        terminate(driver)
                        break
                    time.sleep(1)
                metadata['driver_exit_code'] = driver.returncode
                metadata['aborted'] = aborted
            metadata['database'] = db.query("SELECT json_build_object('version',version(),'fsync',current_setting('fsync'),'synchronous_commit',current_setting('synchronous_commit'),'shared_buffers',current_setting('shared_buffers'),'max_connections',current_setting('max_connections'));")
            metadata['database_statistics'] = db.query("SELECT row_to_json(d) FROM (SELECT numbackends,xact_commit,xact_rollback,deadlocks,temp_bytes FROM pg_stat_database WHERE datname=current_database()) d;")
        finally:
            terminate(driver)
            terminate(server)
            if 'logger' in locals():
                logger.join(timeout=3)
                server_log.close()
            (args.output / 'samples.json').write_text(json.dumps(samples))
            (args.output / 'environment.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2))
    if aborted or driver.returncode: raise SystemExit(1)
    from summarize_capacity import summarize
    summary = summarize(args.output)
    (args.output / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2))
    passed = all(result['preliminary_gate'] == 'PASS' for result in summary['results'])
    print(json.dumps({'output': str(args.output), 'aborted': aborted, 'driver_exit_code': driver.returncode, 'capacity_gate': 'PASS' if passed else 'FAIL'}))
    if not passed: raise SystemExit(2)


if __name__ == '__main__': main()
