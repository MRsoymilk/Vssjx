from io import BytesIO
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from portal_stats.apks import APK_NAME, ApkError, ApkManager


def apk(content=b'owned fixture'):
    output = BytesIO()
    with zipfile.ZipFile(output, 'w') as archive:
        archive.writestr(zipfile.ZipInfo('AndroidManifest.xml', (2026, 1, 1, 0, 0, 0)), b'\x03\x00\x08\x00' + content)
        archive.writestr(zipfile.ZipInfo('classes.dex', (2026, 1, 1, 0, 0, 0)), b'dex\n035\0' + content)
    return output.getvalue()


class ApkManagerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.manager = ApkManager(self.root / 'private', self.root / 'public', max_upload=4096, quota=16384)

    def upload(self, data=None, name='蜀山预览.apk'):
        data = apk() if data is None else data
        return self.manager.upload(BytesIO(data), len(data), name)

    def test_upload_dedup_sha_and_current_protection(self):
        first = self.upload()['file']
        self.assertEqual(self.upload()['duplicate'], True)
        self.assertEqual(len(self.manager.listing()['files']), 1)
        result = self.manager.publish(first['id'])
        self.assertEqual(result['current'], first['id'])
        self.assertEqual((self.root / 'public/current/downloads' / APK_NAME).read_bytes(), apk())
        self.assertEqual(self.manager.publish(first['id']), result)
        with self.assertRaisesRegex(ApkError, 'APK_IS_CURRENT'):
            self.manager.delete(first['id'])

    def test_publish_switch_and_delete_only_old_managed_version(self):
        old = self.upload()['file']
        new_data = apk(b'new version')
        new = self.upload(new_data)['file']
        self.manager.publish(old['id'])
        self.manager.publish(new['id'])
        self.manager.delete(old['id'])
        self.manager.delete(old['id'])  # Safe retry.
        self.assertEqual((self.root / 'public/current/downloads' / APK_NAME).read_bytes(), new_data)
        self.assertEqual(len(self.manager.listing()['files']), 1)
        self.assertFalse((self.root / 'private/packages' / (old['id'] + '.apk')).exists())

    def test_invalid_names_lengths_zip_and_truncated_stream(self):
        for name in ('../bad.apk', '/tmp/bad.apk', 'bad.exe', 'bad\n.apk', '.hidden.apk'):
            with self.subTest(name=name), self.assertRaises(ApkError):
                self.upload(name=name)
        for data in (b'not a zip', b'PK\x03\x04invalid'):
            with self.assertRaises(ApkError):
                self.upload(data)
        with self.assertRaisesRegex(ApkError, 'APK_TOO_LARGE'):
            self.manager.upload(BytesIO(b'x'), 5000, 'test.apk')
        with self.assertRaisesRegex(ApkError, 'APK_UPLOAD_INCOMPLETE'):
            self.manager.upload(BytesIO(b'x'), 100, 'test.apk')
        self.assertEqual(self.manager.listing()['files'], [])
        self.assertEqual(list(self.manager.packages.iterdir()), [])

    def test_archive_traversal_and_missing_manifest_are_rejected(self):
        for entries in ({'../outside': b'x', 'AndroidManifest.xml': b'x'}, {'classes.dex': b'x'}):
            output = BytesIO()
            with zipfile.ZipFile(output, 'w') as archive:
                for name, value in entries.items():
                    archive.writestr(name, value)
            with self.assertRaisesRegex(ApkError, 'INVALID_APK_STRUCTURE'):
                self.upload(output.getvalue())
        self.assertFalse((self.root / 'outside').exists())

    def test_unmanaged_public_files_and_tampered_versions_are_not_overwritten(self):
        record = self.upload()['file']
        public = self.root / 'public'
        public.mkdir()
        sentinel = public / APK_NAME
        sentinel.write_bytes(b'legacy package, not managed')
        with self.assertRaisesRegex(ApkError, 'UNMANAGED_CURRENT'):
            self.manager.publish(record['id'])
        self.assertEqual(sentinel.read_bytes(), b'legacy package, not managed')
        sentinel.unlink()  # Owned fixture only.
        self.manager.publish(record['id'])
        unknown = public / 'releases' / record['id'] / 'unknown.txt'
        unknown.write_text('owned extra file')
        with self.assertRaisesRegex(ApkError, 'UNMANAGED_RELEASE'):
            self.manager.publish(record['id'])
        self.assertEqual(unknown.read_text(), 'owned extra file')

    def test_quota_readonly_mode_and_invalid_identifiers(self):
        restricted = ApkManager(self.root / 'restricted', max_upload=400, quota=400)
        data = apk()
        restricted.upload(BytesIO(data), len(data), 'first.apk')
        with self.assertRaisesRegex(ApkError, 'APK_QUOTA_EXCEEDED'):
            restricted.upload(BytesIO(data), len(data), 'second.apk')
        with self.assertRaisesRegex(ApkError, 'APK_PUBLISH_DISABLED'):
            restricted.publish('0' * 32)
        with self.assertRaises(ApkError):
            self.manager.delete('../../outside')

    def test_interrupted_old_version_deletion_can_be_retried(self):
        record = self.upload()['file']
        self.manager.publish(record['id'])
        other = self.upload(apk(b'new'))['file']
        self.manager.publish(other['id'])
        with self.manager._database() as database:
            database.execute('UPDATE apks SET state="deleting" WHERE id=?', (record['id'],))
        release = self.root / 'public/releases' / record['id']
        (release / 'downloads' / APK_NAME).unlink()
        self.manager.delete(record['id'])
        self.assertFalse(release.exists())
        self.assertEqual(self.manager.listing()['current'], other['id'])


if __name__ == '__main__':
    unittest.main()
