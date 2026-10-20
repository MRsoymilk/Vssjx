"""Apply a private QQ SMTP file and send one test email without opening registration."""
import argparse
import json
import os
from pathlib import Path
import stat
import subprocess


def read_config(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor) as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o600 or info.st_uid != os.getuid():
            raise ValueError('SMTP_CONFIG_MUST_BE_OWNED_AND_0600')
        raw = stream.read(16385)
    if len(raw) > 16384:
        raise ValueError('SMTP_CONFIG_TOO_LARGE')
    config = json.loads(raw)
    fields = {'host', 'port', 'encryption', 'username', 'password', 'from_address', 'from_name'}
    if not isinstance(config, dict) or set(config) != fields:
        raise ValueError('SMTP_CONFIG_FIELDS_INVALID')
    if config['host'] != 'smtp.qq.com' or type(config['port']) is not int or config['port'] != 465 or config['encryption'] != 'ssl':
        raise ValueError('EXPECTED_QQ_SSL_SMTP')
    if any(not isinstance(config[key], str) or not config[key].strip()
           or any(ord(char) < 32 or ord(char) == 127 for char in config[key]) for key in fields - {'port'}):
        raise ValueError('SMTP_CONFIG_VALUES_INVALID')
    if config['username'] != config['from_address'] or not config['username'].lower().endswith('@qq.com'):
        raise ValueError('QQ_SENDER_ACCOUNT_MISMATCH')
    if any(any(char.isspace() for char in config[key]) for key in ('username', 'password', 'from_address')):
        raise ValueError('SMTP_CREDENTIALS_MUST_NOT_CONTAIN_WHITESPACE')
    return config


PHP = r'''
$before = [];
$changed = false;
try {
    $config = json_decode(file_get_contents('php://stdin'), true, 32, JSON_THROW_ON_ERROR);
    $site = require '/var/www/flarum/site.php';
    $container = $site->bootApp()->getContainer();
    $settings = $container->make(Flarum\Settings\SettingsRepositoryInterface::class);
    $database = $container->make(Illuminate\Database\ConnectionInterface::class);
    if ((string)$settings->get('allow_sign_up') !== '0') {
        throw new RuntimeException('REGISTRATION_MUST_REMAIN_CLOSED');
    }
    $values = [
        'mail_driver' => 'smtp', 'mail_host' => $config['host'], 'mail_port' => '465',
        'mail_encryption' => 'ssl', 'mail_username' => $config['username'],
        'mail_password' => $config['password'], 'mail_from' => $config['from_address'],
        'mail_smtp_verify_peer' => '1',
    ];
    foreach ($values as $key => $value) { $before[$key] = $settings->get($key); }
    $database->transaction(function () use ($settings, $values) {
        foreach ($values as $key => $value) { $settings->set($key, $value); }
    });
    $changed = true;
    if (!($container->make(Flarum\Mail\DriverInterface::class) instanceof Flarum\Mail\SmtpDriver)) {
        throw new RuntimeException('SMTP_DRIVER_VALIDATION_FAILED');
    }
    // Do not put transport exceptions (which may include SMTP debug) in logs.
    $container->instance(Psr\Log\LoggerInterface::class, new Psr\Log\NullLogger());
    $mailer = $container->make(Illuminate\Contracts\Mail\Mailer::class);
    $sent = $mailer->raw(
        "这是剑侠茶馆的 SMTP 配置测试邮件。\n注册尚未开放，请确认收到后通知管理员。\n本邮件不包含密码或授权码。",
        function ($message) use ($config) {
            $message->to($config['from_address']);
            $message->from($config['from_address'], $config['from_name']);
            $message->subject('剑侠茶馆 SMTP 配置测试');
        }
    );
    if ($sent === null) { throw new RuntimeException('MAIL_NOT_SENT'); }
    echo "SMTP_TEST_ACCEPTED_REGISTRATION_STILL_CLOSED\n";
} catch (Throwable $error) {
    if ($changed) {
        try {
            $database->transaction(function () use ($settings, $before) {
                foreach ($before as $key => $value) {
                    if ($value === null) { $settings->delete($key); }
                    else { $settings->set($key, $value); }
                }
            });
        } catch (Throwable $restoreError) {
            fwrite(STDERR, "SMTP_RESTORE_FAILED_REVIEW_PRIVATE_SETTINGS\n");
            exit(2);
        }
    }
    fwrite(STDERR, "SMTP_TEST_FAILED_SETTINGS_UNCHANGED\n");
    exit(1);
}
'''


def configure(path, container='vssjx-forum-forum-1'):
    config = read_config(path)
    result = subprocess.run(['docker', 'exec', '-i', '-u', 'www-data', container, 'php', '-d',
                             'display_errors=0', '-d', 'log_errors=0', '-d', 'default_socket_timeout=20', '-r', PHP],
                            input=json.dumps(config), text=True, capture_output=True, timeout=90)
    if result.returncode:
        raise RuntimeError('SMTP_CONFIGURATION_FAILED' if result.returncode != 2 else 'SMTP_RESTORE_FAILED_REVIEW_PRIVATE_SETTINGS')
    if result.stdout.strip() != 'SMTP_TEST_ACCEPTED_REGISTRATION_STILL_CLOSED':
        raise RuntimeError('UNEXPECTED_SMTP_RESULT_CHECK_PRIVATE_SETTINGS')
    print('SMTP accepted the test email; confirm receipt in the sending mailbox. Registration is still closed.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--container', default='vssjx-forum-forum-1')
    args = parser.parse_args()
    try:
        configure(args.config, args.container)
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired):
        # Never expose input values, subprocess output or raw exception text.
        raise SystemExit('SMTP setup did not complete; registration was not opened. Check private settings before retrying.')
