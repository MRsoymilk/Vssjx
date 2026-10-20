import importlib.util
import json
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('configure_flarum_smtp', ROOT / 'tools/configure_flarum_smtp.py')
smtp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smtp)
registration_spec = importlib.util.spec_from_file_location('set_flarum_registration', ROOT / 'tools/set_flarum_registration.py')
registration = importlib.util.module_from_spec(registration_spec)
registration_spec.loader.exec_module(registration)


class SmtpTests(unittest.TestCase):
    def setUp(self):
        self.temporary = TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name) / 'smtp.json'
        self.config = {'host': 'smtp.qq.com', 'port': 465, 'encryption': 'ssl',
                       'username': 'fixture@qq.com', 'password': 'fixture-secret',
                       'from_address': 'fixture@qq.com', 'from_name': '剑侠茶馆'}
        self.write()

    def write(self):
        self.path.write_text(json.dumps(self.config))
        self.path.chmod(0o600)

    def test_private_file_is_required_and_symlinks_are_rejected(self):
        self.assertEqual(smtp.read_config(self.path), self.config)
        self.path.chmod(0o644)
        with self.assertRaises(ValueError):
            smtp.read_config(self.path)
        self.path.chmod(0o600)
        link = self.path.parent / 'link.json'
        link.symlink_to(self.path)
        with self.assertRaises(OSError):
            smtp.read_config(link)

    def test_wrong_host_sender_tls_or_control_characters_are_rejected(self):
        for key, value in [('host', 'untrusted.example'), ('encryption', ''), ('port', True),
                           ('password', 'secret\nvalue'), ('password', 'secret value'), ('from_address', 'different@qq.com')]:
            with self.subTest(key=key):
                original = self.config[key]
                self.config[key] = value
                self.write()
                with self.assertRaises(ValueError):
                    smtp.read_config(self.path)
                self.config[key] = original

    def test_secret_only_passes_stdin_and_success_does_not_enable_registration(self):
        result = subprocess.CompletedProcess([], 0, 'SMTP_TEST_ACCEPTED_REGISTRATION_STILL_CLOSED\n', '')
        with patch.object(smtp.subprocess, 'run', return_value=result) as run, patch('builtins.print') as output:
            smtp.configure(self.path)
        self.assertNotIn(self.config['password'], str(run.call_args.args))
        self.assertEqual(json.loads(run.call_args.kwargs['input']), self.config)
        self.assertNotIn(self.config['password'], str(output.call_args))
        self.assertNotIn("'allow_sign_up' => '1'", smtp.PHP)
        self.assertIn("'mail_smtp_verify_peer' => '1'", smtp.PHP)
        self.assertIn('instanceof Flarum\\Mail\\SmtpDriver', smtp.PHP)

    def test_transport_output_is_not_exposed_on_failure(self):
        result = subprocess.CompletedProcess([], 1, '', 'fixture-secret sensitive debug')
        with patch.object(smtp.subprocess, 'run', return_value=result), self.assertRaises(RuntimeError) as failure:
            smtp.configure(self.path)
        self.assertEqual(str(failure.exception), 'SMTP_CONFIGURATION_FAILED')

    def test_registration_requires_explicit_receipt_confirmation(self):
        with patch.object(registration.subprocess, 'run') as run:
            with self.assertRaises(ValueError):
                registration.enable()
            run.assert_not_called()
        self.assertIn("$settings->get('mail_driver') !== 'smtp'", registration.PHP)
        self.assertIn("$settings->set('allow_sign_up', '1')", registration.PHP)
        self.assertNotIn('is_email_confirmed', registration.PHP)
        self.assertNotIn('permissions', registration.PHP)

    def test_registration_result_is_checked_without_printing_transport_output(self):
        result = subprocess.CompletedProcess([], 0, 'REGISTRATION_OPEN_EMAIL_VERIFICATION_UNCHANGED\n', '')
        with patch.object(registration.subprocess, 'run', return_value=result), patch('builtins.print'):
            registration.enable(receipt_confirmed=True)
        failed = subprocess.CompletedProcess([], 1, '', 'sensitive debug')
        with patch.object(registration.subprocess, 'run', return_value=failed), self.assertRaises(RuntimeError) as failure:
            registration.enable(receipt_confirmed=True)
        self.assertNotIn('sensitive debug', str(failure.exception))


if __name__ == '__main__':
    unittest.main()
