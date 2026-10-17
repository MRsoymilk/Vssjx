"""Build isolated Linux executable / Windows EXE / signed Android APK previews.

Only output/dist is distributable. No global Godot settings, shared Git refs,
server configuration, player data, admin pages, or tests are modified/copied.
"""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import struct
import subprocess
import tarfile
from uuid import uuid4
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
WINDOWS_SHA256 = 'd34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562'
LINUX_SHA256 = 'd9f79ab89b5ae369aeed11c6052d402e8218cd503bf85b4a235f9c30c46a7c63'
EXPORT_AUDIT_MARKER = r'^GAME EXPORT: [1-9]\d* checks, 0 failures$'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def public_ignore(directory, names):
    return [name for name in names if name.startswith('.') or name in ['admin', 'tests', 'android']
            or name.endswith(('.import', '.tmp', '.keystore', '.jks', '.p12', '.pfx', '.pem', '.key'))]


def check_pe(path):
    data = path.read_bytes()
    assert data[:2] == b'MZ', 'Not a Windows executable'
    offset = struct.unpack_from('<I', data, 0x3c)[0]
    assert data[offset:offset + 4] == b'PE\0\0'
    assert struct.unpack_from('<H', data, offset + 4)[0] == 0x8664, 'Expected Windows x64'
    assert struct.unpack_from('<H', data, offset + 24)[0] == 0x20b, 'Expected PE32+'
    # Authenticode directory (index 4); preview EXE is explicitly unsigned.
    assert struct.unpack_from('<II', data, offset + 24 + 112 + 4 * 8) == (0, 0)


def check_linux_binary(path):
    with path.open('rb') as stream:
        data = stream.read(64)
    assert len(data) == 64 and data[:6] == b'\x7fELF\x02\x01', 'Expected ELF64 little-endian executable'
    assert struct.unpack_from('<H', data, 16)[0] in [2, 3], 'Expected ELF executable or PIE'
    assert struct.unpack_from('<H', data, 18)[0] == 62, 'Expected Linux x86_64'
    assert path.stat().st_mode & 0o111, 'Linux executable bit is missing'


def write_linux_archive(folder, archive):
    with tarfile.open(archive, 'w:gz') as pack:
        for file in sorted(folder.iterdir()):
            if not file.is_file() or file.is_symlink():
                raise ValueError('Only regular release files may enter the Linux archive')
            info = pack.gettarinfo(str(file), 'vssjx-linux-x64/' + file.name)
            info.uid = info.gid = 0
            info.uname = info.gname = ''
            info.mode = 0o755 if file.name == 'vssjx.x86_64' else 0o644
            with file.open('rb') as stream:
                pack.addfile(info, stream)


def check_android_library(name, data):
    assert data[:4] == b'\x7fELF' and data[5] == 1, name
    is64 = data[4] == 2
    assert struct.unpack_from('<H', data, 18)[0] == (183 if 'arm64-v8a/' in name else 40), name
    assert is64 == ('arm64-v8a/' in name), name
    offset = struct.unpack_from('<Q' if is64 else '<I', data, 32 if is64 else 28)[0]
    size, count = struct.unpack_from('<HH', data, 54 if is64 else 42)
    loads = 0
    for index in range(count):
        start = offset + index * size
        if struct.unpack_from('<I', data, start)[0] != 1:
            continue
        loads += 1
        alignment = struct.unpack_from('<Q' if is64 else '<I', data, start + (48 if is64 else 28))[0]
        assert alignment >= (16384 if is64 else 4096), (name, alignment)
    assert loads > 0, name


def development_signing(folder, run, env):
    folder = folder.resolve()
    if folder.is_relative_to(ROOT):
        raise ValueError('Development signing material must remain outside the repository')
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    record = folder / 'development-signing.json'
    key = folder / 'development.keystore'
    if record.exists():
        identity = json.loads(record.read_text())
        if identity.get('purpose') != 'vssjx-install-test-only' or not key.is_file():
            raise ValueError('Invalid owned development signing directory')
    elif any(folder.iterdir()):
        raise ValueError('Refusing to replace unrelated signing files')
    if os.name == 'nt':
        # chmod does not restrict Windows readers. Protect the private directory
        # with an inheritable ACL instead; signing material never enters dist.
        identity_csv = subprocess.check_output(['whoami', '/user', '/fo', 'csv', '/nh'], text=True)
        sid = next(csv.reader(identity_csv.splitlines()))[1]
        subprocess.run(['icacls', str(folder), '/inheritance:r', '/grant:r', '*' + sid + ':(OI)(CI)F'],
                       check=True, capture_output=True)
    elif folder.stat().st_mode & 0o077:
        raise ValueError('Signing directory must have mode 0700')
    if record.exists():
        if os.name != 'nt' and record.stat().st_mode & 0o077:
            raise ValueError('Signing metadata must have mode 0600')
        if os.name != 'nt' and key.stat().st_mode & 0o077:
            raise ValueError('Development private key must have mode 0600')
    else:
        identity = {'purpose': 'vssjx-install-test-only', 'alias': 'vssjx-preview', 'password': secrets.token_hex(24)}
        env['VSSJX_DEV_KEY_PASSWORD'] = identity['password']
        run('create-development-key', ['keytool', '-genkeypair', '-noprompt', '-storetype', 'PKCS12',
            '-keystore', str(key), '-alias', identity['alias'], '-keyalg', 'RSA', '-keysize', '3072',
            '-validity', '3650', '-dname', 'CN=Vssjx Development Preview,OU=Install Test Only',
            '-storepass:env', 'VSSJX_DEV_KEY_PASSWORD', '-keypass:env', 'VSSJX_DEV_KEY_PASSWORD'])
        key.chmod(0o600)
        fd = os.open(record, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as stream:
            json.dump(identity, stream)
    env.update(GODOT_ANDROID_KEYSTORE_RELEASE_PATH=str(key), GODOT_ANDROID_KEYSTORE_RELEASE_USER=identity['alias'],
               GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=identity['password'])


def build(args):
    output = args.output.resolve()
    dist = output / 'dist'
    if dist.exists() and any(dist.iterdir()):
        raise ValueError('Refusing to overwrite an existing dist directory; use a new output')
    output.mkdir(parents=True, exist_ok=True)
    project = output / ('source-' + uuid4().hex)
    project.mkdir()
    for name in ['project.godot', 'export_presets.cfg']:
        shutil.copy2(ROOT / 'client' / name, project / name)
    for name in ['scripts', 'assets', 'scenes', 'web']:
        shutil.copytree(ROOT / 'client' / name, project / name, ignore=public_ignore)
    env = {key: value for key, value in os.environ.items() if not key.startswith('SSJX_')}
    env.update(XDG_DATA_HOME=str(output / 'userdata'), XDG_CONFIG_HOME=str(output / 'config'), XDG_CACHE_HOME=str(output / 'cache'))
    if os.name == 'nt':
        env.update(APPDATA=str(output / 'config'), LOCALAPPDATA=str(output / 'cache'))
    godot = env.get('GODOT_BIN', 'godot')
    version = subprocess.check_output([godot, '--version'], text=True).strip()
    if not version.startswith('4.7.2.'):
        raise ValueError('Use Godot 4.7.2 and matching native templates')

    def run(name, command, expected=None):
        result = subprocess.run(command, env=env, cwd=output, capture_output=True, text=True, timeout=600)
        text = result.stdout + result.stderr
        (output / (name + '.log')).write_text(text, encoding='utf8')
        if result.returncode or re.search(r'(^ERROR:|SCRIPT ERROR|Parse Error)', text, re.M):
            raise RuntimeError(name + ': see ' + str(output / (name + '.log')))
        if expected and not re.search(expected, text, re.M):
            raise RuntimeError(name + ': completion marker missing')
        print(name + ': PASS', flush=True)
        return text

    presets = project / 'export_presets.cfg'
    config = presets.read_text(encoding='utf8')
    template_hashes = {}
    certificate_sha256 = None
    android = args.target in ['all', 'android']
    windows = args.target in ['all', 'windows']
    linux = args.target in ['all', 'linux']
    linux_runtime = None
    linux_glibc = None
    if linux:
        template = args.linux_template.resolve()
        if sha(template) != LINUX_SHA256:
            raise ValueError('Expected pinned official Godot 4.7.2 Linux x86_64 release template')
        template_hashes['linux_release.x86_64'] = sha(template)
        config = config.replace('[preset.0.options]', '[preset.0.options]\ncustom_template/release=' + json.dumps(str(template)))
    if windows:
        template = args.windows_template.resolve()
        if sha(template) != WINDOWS_SHA256:
            raise ValueError('Expected pinned official Godot 4.7.2 Windows x64 release template')
        template_hashes['windows_release_x86_64.exe'] = sha(template)
        config = config.replace('[preset.1.options]', '[preset.1.options]\ncustom_template/release=' + json.dumps(str(template)))
    if android:
        if (args.templates / 'version.txt').read_text().strip() != '4.7.2.stable':
            raise ValueError('Expected matching installed Android templates version 4.7.2.stable')
        for mode in ['debug', 'release']:
            template = (args.templates / ('android_' + mode + '.apk')).resolve()
            template_hashes[template.name] = sha(template)
            config = config.replace('[preset.3.options]', '[preset.3.options]\ncustom_template/' + mode + '=' + json.dumps(str(template)))
        if args.development_signing:
            if args.development_key_dir.resolve().is_relative_to(output):
                raise ValueError('Signing material must remain outside build output and dist')
            development_signing(args.development_key_dir, run, env)
            config = config.replace('package/unique_name="com.mrsoymilk.vssjx"', 'package/unique_name="com.mrsoymilk.vssjx.preview"')
            config = config.replace('version/name="0.1.0"', 'version/name="0.1.0-preview"')
        elif not all(env.get('GODOT_ANDROID_KEYSTORE_RELEASE_' + key) for key in ['PATH', 'USER', 'PASSWORD']):
            raise ValueError('Provide release signing through GODOT_ANDROID_KEYSTORE_RELEASE_* or explicitly use --development-signing')
        settings = output / 'config/godot/editor_settings-4.7.tres'
        settings.parent.mkdir(parents=True, exist_ok=True)
        settings.write_text('[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
                            'export/android/android_sdk_path=' + json.dumps(str(args.android_sdk.resolve())) + '\n'
                            'export/android/java_sdk_path=' + json.dumps(str(args.java_sdk.resolve())) + '\n')
    presets.write_text(config, encoding='utf8')
    notices_project = output / 'notices-project'
    notices_project.mkdir()
    (notices_project / 'project.godot').write_text('config_version=5\n')
    notices = output / 'GODOT-NOTICES.txt'
    run('engine-notices', [godot, '--headless', '--path', str(notices_project), '--script',
                          str(ROOT / 'tests/export_native_notices.gd'), '--', str(notices)], 'NATIVE NOTICES: written')
    licenses = project / 'assets/licenses'
    licenses.mkdir(exist_ok=True)
    shutil.copy2(ROOT / 'LICENSE', licenses / 'PROJECT-LICENSE.txt')
    shutil.copy2(notices, licenses / 'GODOT-NOTICES.txt')
    sources = {str(file.relative_to(project)): sha(file) for file in sorted(project.rglob('*')) if file.is_file()}
    (output / 'source-manifest.json').write_text(json.dumps(sources, indent=2))
    run('import', [godot, '--headless', '--editor', '--path', str(project), '--import'])
    dist.mkdir(exist_ok=True)
    shutil.copy2(ROOT / 'LICENSE', dist / 'PROJECT-LICENSE.txt')
    shutil.copy2(notices, dist / 'GODOT-NOTICES.txt')
    source_commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    (dist / 'SOURCE.txt').write_text('Internal development preview. Corresponding project source is available to this recipient\n'
        'in the local Git checkout at commit ' + source_commit + '. See build-report.json outside dist for dirty/source hashes.\n'
        'No changes are automatically published. Before redistribution, arrange AGPL corresponding-source availability\n'
        'and verify original artwork permissions. Private signing keys are not distributed.\n', encoding='utf8')
    instructions = ['蜀山剑侠 · 归来：原生预览测试包\n']
    if android:
        instructions.append('Android：安装 ' + ('vssjx-android-preview.apk（开发测试签名）' if args.development_signing else 'vssjx-android.apk（外部提供的签名）') + '。尚未完成设备运行验收。')
    if windows:
        instructions.append('Windows：解压 vssjx-windows-x64-preview.zip，运行 vssjx.exe；资源内嵌。EXE未签名且未在Windows运行验收。')
    if linux:
        instructions.append('Linux x86_64：解压 vssjx-linux-x64-preview.tar.gz，进入目录运行 ./vssjx.x86_64；资源内嵌。需要glibc及OpenGL 3.3图形环境，不是AppImage。')
    (dist / 'README.txt').write_text('\n'.join(instructions) + '\n'
        '离线：封面登陆游戏后，在服务器地址填写 local 再登陆；联机填写合法HTTPS服务地址。\n'
        '存档在应用用户目录；Android卸载或清数据会删除离线存档，换签名之前请先确认备份。\n'
        '请勿把本预览测试包当作完成设备/资源授权/AGPL源码交付/生产签名审核的正式发行版。\n', encoding='utf8')
    probes = output / 'probes'
    probes.mkdir(exist_ok=True)
    if linux:
        folder = dist / 'linux-x64'
        folder.mkdir()
        executable = folder / 'vssjx.x86_64'
        run('linux-export', [godot, '--headless', '--path', str(project), '--export-release', 'Game (Linux)', str(executable)])
        executable.chmod(0o755)
        check_linux_binary(executable)
        if list(folder.glob('*.pck')):
            raise RuntimeError('Linux executable must have its PCK embedded')
        run('linux-embedded-pack-audit', [godot, '--headless', '--main-pack', str(executable), '--script', str(ROOT / 'tests/game_export_probe.gd')], EXPORT_AUDIT_MARKER)
        linux_runtime = run('linux-release-version', [str(executable), '--version']).strip()
        if not linux_runtime.startswith('4.7.2.stable.official'):
            raise RuntimeError('Unexpected Linux release runtime version')
        run('linux-release-startup', [str(executable), '--headless', '--quit-after', '60'])
        version_info = run('linux-elf-versions', ['readelf', '--version-info', str(executable)])
        versions = re.findall(r'\bGLIBC_(\d+\.\d+(?:\.\d+)?)\b', version_info)
        if not versions:
            raise RuntimeError('Unable to determine Linux glibc symbol requirements')
        linux_glibc = max(versions, key=lambda value: tuple(map(int, value.split('.'))))
        for name in ['PROJECT-LICENSE.txt', 'GODOT-NOTICES.txt', 'SOURCE.txt']:
            shutil.copy2(dist / name, folder / name)
        shutil.copy2(ROOT / 'client/assets/fonts/OFL.txt', folder / 'FONT-LICENSE.txt')
        (folder / 'README.txt').write_text('Linux x86_64 preview. Extract the archive and run ./vssjx.x86_64.\n'
            'Game resources are embedded; no Godot installation, separate PCK or root installation is required.\n'
            'Requires glibc ' + linux_glibc + '+ and an OpenGL 3.3 desktop/driver. Not AppImage, not musl/Alpine.\n'
            'If executable permissions were lost during transfer, run: chmod +x vssjx.x86_64\n'
            'Offline: login screen server address = local. Online: enter your HTTPS game server URL.\n'
            'Saves use XDG_DATA_HOME (default ~/.local/share), not the extracted program folder.\n'
            'Only this host startup has been checked by the builder; consult separate GUI acceptance results.\n', encoding='utf8')
        write_linux_archive(folder, dist / 'vssjx-linux-x64-preview.tar.gz')
    if windows:
        folder = dist / 'windows-x64'
        folder.mkdir()
        exe = folder / 'vssjx.exe'
        run('windows-export', [godot, '--headless', '--path', str(project), '--export-release', 'Game (Windows)', str(exe)])
        check_pe(exe)
        if list(folder.glob('*.pck')):
            raise RuntimeError('Windows EXE must have its PCK embedded')
        run('windows-embedded-pack-audit', [godot, '--headless', '--main-pack', str(exe), '--script', str(ROOT / 'tests/game_export_probe.gd')], EXPORT_AUDIT_MARKER)
        shutil.copy2(ROOT / 'client/assets/fonts/OFL.txt', folder / 'FONT-LICENSE.txt')
        for name in ['PROJECT-LICENSE.txt', 'GODOT-NOTICES.txt', 'SOURCE.txt']:
            shutil.copy2(dist / name, folder / name)
        (folder / 'README.txt').write_text('Windows x64 preview. Run vssjx.exe; no Godot installation or separate PCK needed.\n'
            'Unsigned executable: Windows may show SmartScreen/unknown publisher. This is not a store release.\n'
            'Offline: login screen server address = local. Online: enter your HTTPS game server URL.\n'
            'Saves and server preferences stay in Godot user data, not beside the executable.\n', encoding='utf8')
        with ZipFile(dist / 'vssjx-windows-x64-preview.zip', 'w', ZIP_DEFLATED, compresslevel=9) as archive:
            for file in sorted(folder.iterdir()):
                archive.write(file, 'vssjx-windows-x64/' + file.name)
    if android:
        apk = dist / ('vssjx-android-preview.apk' if args.development_signing else 'vssjx-android.apk')
        run('android-export', [godot, '--headless', '--path', str(project), '--export-release', 'Game (Android)', str(apk)])
        tools = args.android_sdk.resolve() / 'build-tools' / args.build_tools
        signature = run('android-signature', [str(tools / ('apksigner.bat' if os.name == 'nt' else 'apksigner')), 'verify', '--verbose', '--print-certs', str(apk)])
        certificate = re.search(r'Signer #1 certificate SHA-256 digest: ([0-9a-f]{64})', signature)
        assert certificate, 'APK signing certificate digest missing'
        certificate_sha256 = certificate.group(1)
        run('android-alignment', [str(tools / ('zipalign.exe' if os.name == 'nt' else 'zipalign')), '-c', '-P', '16', '-v', '4', str(apk)])
        aapt = str(tools / ('aapt.exe' if os.name == 'nt' else 'aapt'))
        badging = run('android-package', [aapt, 'dump', 'badging', str(apk)])
        manifest = run('android-manifest', [aapt, 'dump', 'xmltree', str(apk), 'AndroidManifest.xml'])
        if 'application-debuggable' in badging or 'android:debuggable(0x0101000f)=(type 0x12)0xffffffff' in manifest:
            raise RuntimeError('Unexpected debuggable release APK')
        package = 'com.mrsoymilk.vssjx.preview' if args.development_signing else 'com.mrsoymilk.vssjx'
        assert "name='" + package + "'" in badging
        assert "native-code: 'arm64-v8a' 'armeabi-v7a'" in badging
        assert "sdkVersion:'24'" in badging and "targetSdkVersion:'36'" in badging
        permissions = re.findall(r"uses-permission: name='([^']+)'", badging)
        assert permissions == ['android.permission.INTERNET'], permissions
        assert re.search(r'android:allowBackup[^\n]*0x0\b', manifest), 'Android backup must remain disabled'
        with ZipFile(apk) as archive:
            assert archive.testzip() is None, 'APK ZIP CRC failure'
            names = archive.namelist()
            libraries = [name for name in names if name.startswith('lib/') and name.endswith('.so')]
            assert libraries, 'Missing Android native libraries'
            for name in libraries:
                assert name.startswith(('lib/arm64-v8a/', 'lib/armeabi-v7a/')), name
                check_android_library(name, archive.read(name))
            assets = [name for name in names if name.startswith('assets/') and not name.endswith('/')]
            assert assets and 'assets/project.binary' in assets
            for name in assets:
                assert not re.search(r'/(admin|tests)/|\.env|\.(keystore|jks|pem)$', name), name
            for name in ['assets/assets/data/actors.json', 'assets/assets/fonts/OFL.txt', 'assets/assets/licenses/PROJECT-LICENSE.txt', 'assets/assets/licenses/GODOT-NOTICES.txt']:
                assert name in names, name
            # Repackage actual APK assets for native inspection, never call this Android execution.
            with ZipFile(probes / 'android-assets.zip', 'w', ZIP_DEFLATED) as pack:
                for name in assets:
                    pack.writestr(name.removeprefix('assets/'), archive.read(name))
        run('android-assets-native-audit', [godot, '--headless', '--main-pack', str(probes / 'android-assets.zip'), '--script', str(ROOT / 'tests/game_export_probe.gd')], EXPORT_AUDIT_MARKER)
        shutil.copy2(ROOT / 'client/assets/fonts/OFL.txt', dist / 'FONT-LICENSE.txt')
    files = {str(file.relative_to(dist)): {'bytes': file.stat().st_size, 'sha256': sha(file)}
             for file in sorted(dist.rglob('*')) if file.is_file()}
    (dist / 'SHA256SUMS.txt').write_text(''.join(info['sha256'] + '  ' + name + '\n' for name, info in files.items()))
    report = {'git_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'git_working_tree_dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip()),
              'editor': version, 'target': args.target, 'template_sha256': template_hashes,
              'source_sha256': hashlib.sha256(json.dumps(sources, sort_keys=True).encode()).hexdigest(),
              'android_signing': ('development-preview-only' if args.development_signing else 'external-release-key') if android else 'not-built',
              'android_certificate_sha256': certificate_sha256,
              'windows_signing': 'unsigned' if windows else 'not-built', 'actual_windows_execution': False, 'actual_android_execution': False,
              'actual_linux_execution': linux, 'linux_runtime': linux_runtime, 'linux_glibc_required': linux_glibc,
              'linux_rendered_gameplay': 'not-tested-by-builder',
              'files': files}
    (output / 'build-report.json').write_text(json.dumps(report, indent=2))
    print('Native artifacts: ' + str(dist), flush=True)
    return dist


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--target', choices=['all', 'linux', 'windows', 'android'], default='all')
    parser.add_argument('--linux-template', type=Path, default=Path('/tmp/opencode/vssjx-native-toolchain/linux_release.x86_64'))
    parser.add_argument('--windows-template', type=Path, default=Path('/tmp/opencode/vssjx-native-toolchain/windows_release_x86_64.exe'))
    parser.add_argument('--templates', type=Path, default=Path.home() / '.local/share/godot/export_templates/4.7.2.stable')
    parser.add_argument('--android-sdk', type=Path, default=Path(os.environ.get('ANDROID_HOME', '/opt/android-sdk')))
    parser.add_argument('--java-sdk', type=Path, default=Path(os.environ.get('JAVA_HOME', '/usr/lib/jvm/java-17-openjdk')))
    parser.add_argument('--build-tools', default='36.0.0')
    parser.add_argument('--development-signing', action='store_true', help='Explicit install-test signing; never a production signing key')
    parser.add_argument('--development-key-dir', type=Path, default=Path('/tmp/opencode/vssjx-native-toolchain/development-signing'))
    build(parser.parse_args())


if __name__ == '__main__':
    main()
