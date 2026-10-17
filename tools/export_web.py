"""Export the real game in an isolated public-source copy (Godot 4.7.2 Web).

Only output/public is deployable. Source copies, logs and reports stay outside it.
No server, admin source, tests, environment files or player saves are copied.
"""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]
TEMPLATES = {
    'debug': '08962aefef811b603541d7951ac67ef00413aad2d978855183c28adee98f626a',
    'release': 'd3ee2f08cef0cf3cf6678a6355a92a8db48ccdd35cbd2e8bfd5f0e8a0b4032a0',
}


def prepare_static_assets(public):
    """Version the engine/data together; only versioned URLs may cache immutably."""
    artifacts = sorted(file for file in public.iterdir() if file.suffix in ['.js', '.wasm', '.pck', '.png'])
    digest = hashlib.sha256()
    for file in artifacts:
        digest.update(file.name.encode())
        digest.update(hashlib.sha256(file.read_bytes()).digest())
    version = digest.hexdigest()[:16]
    relative = 'assets/' + version + '/'
    versioned = public / relative
    versioned.mkdir(parents=True)
    transfers = {}
    for file in artifacts:
        shutil.copy2(file, versioned / file.name)
        if file.suffix in ['.js', '.wasm', '.pck']:
            data = file.read_bytes()
            compressed = gzip.compress(data, compresslevel=9, mtime=0)
            if len(compressed) < len(data):
                for target in [file, versioned / file.name]:
                    target.with_name(target.name + '.gz').write_bytes(compressed)
                    os.utime(target.with_name(target.name + '.gz'), ns=(target.stat().st_atime_ns, target.stat().st_mtime_ns))
                transfers[file.name] = {'raw_bytes': len(data), 'gzip_bytes': len(compressed)}
    entry = public / 'index.html'
    html = entry.read_text(encoding='utf8')
    match = re.search(r'const config = (\{[^\n]+\});', html)
    if not match:
        raise RuntimeError('Missing exported engine config')
    config = json.loads(match.group(1))
    main_pack = config.get('mainPack', config['executable'] + '.pck')
    config['executable'] = relative + config['executable']
    config['mainPack'] = relative + main_pack
    config['fileSizes'] = {relative + name: size for name, size in config['fileSizes'].items()}
    html = html[:match.start(1)] + json.dumps(config, separators=(',', ':')) + html[match.end(1):]
    html = html.replace('src="index.js"', 'src="' + relative + 'index.js"')
    entry.write_text(html, encoding='utf8')
    return {'version': version, 'prefix': relative, 'transfers': transfers}


def build(output, template=None, debug=False, loopback=False):
    output = output.resolve()
    public = output / 'public'
    if public.exists() and any(public.iterdir()):
        raise ValueError('Use a new output directory; refusing to overwrite an existing public package')
    output.mkdir(parents=True, exist_ok=True)
    project = output / ('source-' + uuid4().hex)
    project.mkdir()
    for name in ['project.godot', 'export_presets.cfg']:
        shutil.copy2(ROOT / 'client' / name, project / name)

    def ignored(directory, names):
        return [name for name in names if name.startswith('.') or name in ['admin', 'tests'] or name.endswith(('.import', '.tmp'))]

    for name in ['scripts', 'assets', 'scenes', 'web']:
        shutil.copytree(ROOT / 'client' / name, project / name, ignore=ignored)
    if loopback:
        profile = project / 'scripts/interface/profiles/web_runtime.tres'
        profile.write_text(profile.read_text().replace('allow_loopback_http = false', 'allow_loopback_http = true'))
    mode = 'debug' if debug else 'release'
    if template:
        template = template.resolve()
        if hashlib.sha256(template.read_bytes()).hexdigest() != TEMPLATES[mode]:
            raise ValueError('Expected pinned official 4.7.2 web_nothreads_' + mode + '.zip')
        presets = project / 'export_presets.cfg'
        presets.write_text(presets.read_text().replace('[preset.2.options]', '[preset.2.options]\ncustom_template/' + mode + '=' + json.dumps(str(template))))
    source_hashes = {str(file.relative_to(project)): hashlib.sha256(file.read_bytes()).hexdigest()
                     for file in sorted(project.rglob('*')) if file.is_file()}
    env = {key: value for key, value in os.environ.items() if not key.startswith('SSJX_')}
    env.update(XDG_DATA_HOME=str(output / 'userdata'), XDG_CONFIG_HOME=str(output / 'config'), XDG_CACHE_HOME=str(output / 'cache'))
    godot = env.get('GODOT_BIN', 'godot')
    version = subprocess.check_output([godot, '--version'], text=True).strip()
    if not version.startswith('4.7.2.'):
        raise ValueError('Use Godot 4.7.2 with matching official export templates')
    public.mkdir(exist_ok=True)
    for name, command in [
        ('import', [godot, '--headless', '--editor', '--path', str(project), '--import']),
        ('export', [godot, '--headless', '--path', str(project), '--export-' + mode, 'Game (Web)', str(public / 'index.html')]),
    ]:
        result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=600)
        text = result.stdout + result.stderr
        (output / (name + '.log')).write_text(text)
        if result.returncode or re.search(r'(^ERROR:|SCRIPT ERROR|Parse Error)', text, re.M):
            raise RuntimeError(name + ': see ' + str(output / (name + '.log')))
        print(name + ': PASS', flush=True)
    # The bundled font's license must also be accessible to site operators/users.
    shutil.copy2(ROOT / 'client/assets/fonts/OFL.txt', public / 'FONT-LICENSE.txt')
    for suffix in ['html', 'js', 'wasm', 'pck']:
        if not (public / ('index.' + suffix)).is_file():
            raise RuntimeError('Missing Web artifact: ' + suffix)
    static_assets = prepare_static_assets(public)
    report = {'editor': version, 'mode': mode, 'loopback_development': loopback,
              'single_threaded': True, 'pwa': False, 'template_sha256': TEMPLATES[mode] if template else 'installed template; not pinned by this tool',
              'git_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'git_working_tree_dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip()),
              'source_sha256': hashlib.sha256(json.dumps(source_hashes, sort_keys=True).encode()).hexdigest(),
              'static_assets': static_assets,
              'files': {file.relative_to(public).as_posix(): {'bytes': file.stat().st_size, 'sha256': hashlib.sha256(file.read_bytes()).hexdigest()} for file in public.rglob('*') if file.is_file()}}
    (output / 'build-report.json').write_text(json.dumps(report, indent=2))
    (output / 'source-manifest.json').write_text(json.dumps(source_hashes, indent=2, sort_keys=True))
    print('Web package: ' + str(public), flush=True)
    return public


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--template', type=Path, help='Optional pinned matching official single-threaded Web ZIP; otherwise installed templates')
    parser.add_argument('--debug', action='store_true')
    parser.add_argument('--allow-loopback-http', action='store_true', help='Development build only; production keeps HTTPS-only target policy')
    args = parser.parse_args()
    build(args.output, args.template, args.debug, args.allow_loopback_http)


if __name__ == '__main__':
    main()
