"""Native preset, packaging safety, and PE checks (not device execution)."""
import configparser
import importlib.util
import json
import os
import re
from pathlib import Path
import struct
import tarfile
from tempfile import TemporaryDirectory
import unittest
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('native_export', ROOT / 'tools/export_native.py')
export = importlib.util.module_from_spec(spec)
spec.loader.exec_module(export)


class NativeExportTests(unittest.TestCase):
    def test_pack_audit_completion_allows_catalog_growth_but_never_failures(self):
        for count in [70, 71, 100]:
            self.assertIsNotNone(re.search(export.EXPORT_AUDIT_MARKER, f'GAME EXPORT: {count} checks, 0 failures', re.M))
        for text in ['GAME EXPORT: 71 checks, 1 failures', 'GAME EXPORT: 0 checks, 0 failures',
                     'GAME EXPORT: 71 checks, 0 failures trailing', 'incomplete']:
            self.assertIsNone(re.search(export.EXPORT_AUDIT_MARKER, text, re.M))

    def presets(self):
        config = configparser.ConfigParser(interpolation=None)
        config.read(ROOT / 'client/export_presets.cfg', encoding='utf8')
        return config

    def test_windows_embeds_pack_without_faking_codesigning(self):
        config = self.presets()
        self.assertEqual(json.loads(config['preset.1']['platform']), 'Windows Desktop')
        self.assertEqual(config['preset.1.options']['binary_format/embed_pck'], 'true')
        self.assertEqual(config['preset.1.options']['codesign/enable'], 'false')

    def test_linux_has_embedded_pack_and_opt_in_shipped_cjk_font(self):
        config = self.presets()
        self.assertEqual(json.loads(config['preset.0']['platform']), 'Linux')
        self.assertEqual(config['preset.0.options']['binary_format/embed_pck'], 'true')
        self.assertEqual(json.loads(config['preset.0.options']['binary_format/architecture']), 'x86_64')
        self.assertEqual(json.loads(config['preset.0']['custom_features']), 'bundled_cjk')
        self.assertIn('assets/licenses/*.txt', config['preset.0']['include_filter'])

    def test_android_is_signed_arm_apk_with_minimal_permissions(self):
        config = self.presets()
        self.assertEqual(json.loads(config['preset.3']['platform']), 'Android')
        options = config['preset.3.options']
        for key in ['package/signed', 'architectures/arm64-v8a', 'architectures/armeabi-v7a', 'permissions/internet']:
            self.assertEqual(options[key], 'true')
        for key in ['gradle_build/use_gradle_build', 'architectures/x86', 'architectures/x86_64', 'user_data_backup/allow']:
            self.assertEqual(options[key], 'false')
        self.assertEqual(options['gradle_build/export_format'], '0')
        self.assertEqual([key for key, value in options.items() if key.startswith('permissions/') and value == 'true'], ['permissions/internet'])
        self.assertFalse(any(key.startswith('keystore/') for key in options))

    def test_mobile_overrides_keep_desktop_canvas_and_save_before_back_exit(self):
        project = (ROOT / 'client/project.godot').read_text(encoding='utf8')
        self.assertIn('window/stretch/aspect.android="keep"', project)
        self.assertIn('window/handheld/orientation.android=1', project)
        self.assertIn('config/quit_on_go_back.android=false', project)
        self.assertIn('window/size/viewport_width=320', project)
        self.assertIn('textures/vram_compression/import_etc2_astc=true', project)
        main = (ROOT / 'client/scripts/main.gd').read_text(encoding='utf8')
        notification = main.split('func _notification(', 1)[1].split('\nfunc ', 1)[0]
        self.assertIn('OS.has_feature("android")', notification)
        self.assertIn('NOTIFICATION_WM_GO_BACK_REQUEST', notification)
        self.assertIn('_close_requested()', notification)

    def test_fonts_cover_native_platforms_without_global_linux_metrics_change(self):
        text = (ROOT / 'client/scripts/interface/adapters/common/cjk_system_font.gd').read_text(encoding='utf8')
        for feature in ['web', 'android', 'windows']:
            self.assertIn('OS.has_feature("' + feature + '")', text)
        self.assertNotIn('OS.has_feature("linux")', text)
        self.assertIn('OS.has_feature("bundled_cjk")', text)

    def test_copy_filter_excludes_private_material_and_admin(self):
        names = ['admin', 'tests', 'android', '.env', '.godot', 'key.keystore', 'key.jks', 'cert.pem', 'secret.key', 'signing.pfx', 'file.import', 'main.gd']
        self.assertEqual(set(export.public_ignore('/unused', names)), set(names) - {'main.gd'})

    def test_existing_artifacts_are_not_overwritten(self):
        with TemporaryDirectory(prefix='vssjx-native-safety-', dir='/tmp/opencode') as folder:
            output = Path(folder)
            dist = output / 'dist'
            dist.mkdir()
            marker = dist / 'user-owned.txt'
            marker.write_text('preserve')
            with self.assertRaisesRegex(ValueError, 'Refusing to overwrite'):
                export.build(SimpleNamespace(output=output))
            self.assertEqual(marker.read_text(), 'preserve')
            self.assertEqual(list(output.iterdir()), [dist])

    def test_pe_check_rejects_wrong_architecture_and_signed_claims(self):
        with TemporaryDirectory(prefix='vssjx-pe-', dir='/tmp/opencode') as folder:
            file = Path(folder) / 'test.exe'
            data = bytearray(512)
            data[:2] = b'MZ'
            struct.pack_into('<I', data, 0x3c, 64)
            data[64:68] = b'PE\0\0'
            struct.pack_into('<H', data, 68, 0x8664)
            struct.pack_into('<H', data, 88, 0x20b)
            file.write_bytes(data)
            export.check_pe(file)
            struct.pack_into('<H', data, 68, 0x14c)
            file.write_bytes(data)
            with self.assertRaises(AssertionError):
                export.check_pe(file)
            struct.pack_into('<H', data, 68, 0x8664)
            struct.pack_into('<II', data, 64 + 24 + 112 + 32, 100, 100)
            file.write_bytes(data)
            with self.assertRaises(AssertionError):
                export.check_pe(file)

    @unittest.skipIf(os.name == 'nt', 'Windows filesystems do not expose POSIX executable mode bits')
    def test_linux_binary_requires_elf64_x86_64_and_execute_permission(self):
        with TemporaryDirectory(prefix='vssjx-elf-', dir='/tmp/opencode') as folder:
            path = Path(folder) / 'vssjx.x86_64'
            data = bytearray(64)
            data[:6] = b'\x7fELF\x02\x01'
            struct.pack_into('<HH', data, 16, 3, 62)
            path.write_bytes(data)
            path.chmod(0o755)
            export.check_linux_binary(path)
            path.chmod(0o644)
            with self.assertRaises(AssertionError):
                export.check_linux_binary(path)
            path.chmod(0o755)
            struct.pack_into('<H', data, 18, 183)
            path.write_bytes(data)
            with self.assertRaises(AssertionError):
                export.check_linux_binary(path)

    def test_linux_tar_preserves_executable_and_removes_host_owner(self):
        with TemporaryDirectory(prefix='vssjx-tar-', dir='/tmp/opencode') as directory:
            folder = Path(directory) / 'linux-x64'
            folder.mkdir()
            executable = folder / 'vssjx.x86_64'
            executable.write_bytes(b'test binary')
            (folder / 'README.txt').write_text('test instructions')
            archive = Path(directory) / 'game.tar.gz'
            export.write_linux_archive(folder, archive)
            with tarfile.open(archive) as pack:
                members = {member.name: member for member in pack.getmembers()}
                self.assertEqual(set(members), {'vssjx-linux-x64/vssjx.x86_64', 'vssjx-linux-x64/README.txt'})
                self.assertEqual(members['vssjx-linux-x64/vssjx.x86_64'].mode, 0o755)
                self.assertEqual(members['vssjx-linux-x64/README.txt'].mode, 0o644)
                for member in members.values():
                    self.assertEqual((member.uid, member.gid, member.uname, member.gname), (0, 0, '', ''))
            (folder / 'private-link').symlink_to(executable)
            with self.assertRaises(ValueError):
                export.write_linux_archive(folder, Path(directory) / 'bad.tar.gz')

    def test_signing_does_not_overwrite_unrelated_private_files(self):
        with TemporaryDirectory(prefix='vssjx-signing-safety-', dir='/tmp/opencode') as folder:
            marker = Path(folder) / 'user.key'
            marker.write_text('preserve')
            with self.assertRaisesRegex(ValueError, 'unrelated signing files'):
                export.development_signing(Path(folder), lambda *_args: self.fail('Must not run keytool'), {})
            self.assertEqual(marker.read_text(), 'preserve')

    def test_android_arm64_requires_16k_elf_load_alignment(self):
        data = bytearray(128)
        data[:6] = b'\x7fELF\x02\x01'
        struct.pack_into('<H', data, 18, 183)
        struct.pack_into('<Q', data, 32, 64)
        struct.pack_into('<HH', data, 54, 56, 1)
        struct.pack_into('<I', data, 64, 1)
        struct.pack_into('<Q', data, 112, 16384)
        export.check_android_library('lib/arm64-v8a/test.so', data)
        struct.pack_into('<Q', data, 112, 4096)
        with self.assertRaises(AssertionError):
            export.check_android_library('lib/arm64-v8a/test.so', data)

    def test_android_emulator_libraries_require_matching_elf_architecture(self):
        for abi, elf_class, machine in [('x86', 1, 3), ('x86_64', 2, 62)]:
            with self.subTest(abi=abi):
                data = bytearray(128)
                data[:6] = b'\x7fELF' + bytes([elf_class, 1])
                struct.pack_into('<H', data, 18, machine)
                struct.pack_into('<Q' if elf_class == 2 else '<I', data, 32 if elf_class == 2 else 28, 64)
                struct.pack_into('<HH', data, 54 if elf_class == 2 else 42, 56 if elf_class == 2 else 32, 1)
                struct.pack_into('<I', data, 64, 1)
                struct.pack_into('<Q' if elf_class == 2 else '<I', data, 112 if elf_class == 2 else 92, 16384)
                name = 'lib/' + abi + '/test.so'
                export.check_android_library(name, data)
                struct.pack_into('<H', data, 18, 40)
                with self.assertRaises(AssertionError):
                    export.check_android_library(name, data)

    def test_exporter_has_no_git_mutation_commands(self):
        text = (ROOT / 'tools/export_native.py').read_text(encoding='utf8')
        for operation in ['push', 'merge', 'switch', 'checkout', 'reset', 'commit']:
            self.assertNotIn("['git', '" + operation + "'", text)


if __name__ == '__main__':
    unittest.main()
