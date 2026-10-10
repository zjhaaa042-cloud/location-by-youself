import datetime as dt
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import zipfile
import installer


class InstallerTests(unittest.TestCase):
    def profile(self):
        return {'ExpirationDate': dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=7),
                'ProvisionedDevices': ['phone'], 'ApplicationIdentifierPrefix': ['TEAM'],
                'DeveloperCertificates': [b'cert'],
                'Entitlements': {'application-identifier': 'TEAM.com.example.*'}}

    def test_profile_device_bundle_certificate_and_expiry(self):
        self.assertGreater(installer.validate_profile(self.profile(), 'phone', 'com.example.app', b'cert')['days_remaining'], 0)
        for field, value, code in [('ProvisionedDevices', [], 'DEVICE_NOT_REGISTERED'),
                                   ('DeveloperCertificates', [], 'CERTIFICATE_MISMATCH'),
                                   ('ExpirationDate', dt.datetime(2000, 1, 1), 'PROFILE_EXPIRED')]:
            profile = self.profile()
            profile[field] = value
            with self.assertRaises(installer.InstallError) as error:
                installer.validate_profile(profile, 'phone', 'com.example.app', b'cert')
            self.assertEqual(error.exception.code, code)
        with self.assertRaises(installer.InstallError):
            installer.validate_profile(self.profile(), 'phone', 'another.app')

    def test_archive_attacks(self):
        for name in ('../outside', '/absolute', 'Payload/A.app/../../escape', 'C:/file', 'Payload\\evil'):
            with tempfile.TemporaryDirectory() as temp:
                ipa = Path(temp) / 'bad.ipa'
                with zipfile.ZipFile(ipa, 'w') as archive:
                    archive.writestr(name, b'bad')
                with self.assertRaises(installer.InstallError):
                    installer.unpack(ipa, Path(temp) / 'out')

    def test_prepare_preserves_frameworks_and_writes_pairing(self):
        from argparse import Namespace
        with tempfile.TemporaryDirectory() as temp:
            ipa, output = Path(temp) / 'input.ipa', Path(temp) / 'output.ipa'
            with zipfile.ZipFile(ipa, 'w') as archive:
                archive.writestr('Payload/LocationMocker.app/Info.plist', plistlib.dumps({'CFBundleIdentifier': 'com.example.app'}))
                archive.writestr('Payload/LocationMocker.app/Frameworks/OpenSSL.framework/OpenSSL', b'binary')
            async def pairing(udid, target):
                target.write_bytes(plistlib.dumps({'identifier': udid}))
            with patch.object(installer, 'require_device'), patch.object(installer, 'make_pairing', pairing):
                result = installer.prepare(Namespace(ipa=str(ipa), output=str(output), udid='phone'))
            self.assertTrue(result['requires_signing'])
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(archive.read('Payload/LocationMocker.app/Frameworks/OpenSSL.framework/OpenSSL'), b'binary')
                self.assertEqual(plistlib.loads(archive.read('Payload/LocationMocker.app/rp_pairing_file.plist'))['identifier'], 'phone')

    def test_subprocess_errors_hide_secrets(self):
        import subprocess
        with patch.object(installer.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, b'secret', b'private_key')):
            with self.assertRaises(installer.InstallError) as error:
                installer.run(['tool'])
            self.assertNotIn('private_key', str(error.exception))

    def test_packaged_exe_dispatches_device_cli(self):
        with patch.object(installer.sys, 'frozen', True, create=True), patch.object(installer, 'run', return_value=b'[]') as run:
            installer.pmd('usbmux', 'list')
            self.assertEqual(run.call_args.args[0][1:], ['--pmd', 'usbmux', 'list'])


if __name__ == '__main__':
    unittest.main()
