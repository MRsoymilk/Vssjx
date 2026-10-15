"""Server discovery must read subprocess pipes on Windows as well as Unix."""
import subprocess
import sys
import unittest

from run_server_connection import wait_for_server


class ServerProcessDiscoveryTests(unittest.TestCase):
    def test_reads_listener_address_and_leaves_following_logs_available(self):
        script = "print('server starting'); print('address=127.0.0.1:43210 stage=connection_only'); print('next log')"
        with subprocess.Popen([sys.executable, '-u', '-c', script], stdout=subprocess.PIPE, text=True) as process:
            self.assertEqual(wait_for_server(process), 'http://127.0.0.1:43210')
            self.assertEqual(process.stdout.readline().strip(), 'next log')
            process.stdout.close()

    def test_exit_without_listener_is_an_explicit_failure(self):
        with subprocess.Popen([sys.executable, '-u', '-c', "print('startup failed')"], stdout=subprocess.PIPE, text=True) as process:
            with self.assertRaisesRegex(RuntimeError, 'exited before listening'):
                wait_for_server(process)
            process.stdout.close()


if __name__ == '__main__':
    unittest.main()
