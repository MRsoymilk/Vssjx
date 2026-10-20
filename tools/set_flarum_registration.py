"""Open forum registration only after an operator confirms SMTP test receipt."""
import argparse
import subprocess

PHP = r'''
try {
    $site = require '/var/www/flarum/site.php';
    $container = $site->bootApp()->getContainer();
    $settings = $container->make(Flarum\Settings\SettingsRepositoryInterface::class);
    if ($settings->get('mail_driver') !== 'smtp'
        || $settings->get('mail_host') !== 'smtp.qq.com'
        || (string)$settings->get('mail_port') !== '465'
        || $settings->get('mail_encryption') !== 'ssl'
        || (string)$settings->get('mail_smtp_verify_peer') !== '1'
        || !$settings->get('mail_username') || !$settings->get('mail_password')
        || !$settings->get('mail_from')) {
        throw new RuntimeException('SMTP_NOT_READY');
    }
    $container->make(Illuminate\Database\ConnectionInterface::class)->transaction(function () use ($settings) {
        $settings->set('allow_sign_up', '1');
        if ($settings->get('welcome_message') === '交流游戏心得与反馈。论坛试运行中，暂不开放注册。') {
            $settings->set('welcome_message', '交流游戏心得与反馈。欢迎注册，请验证邮箱后参与讨论。');
        }
    });
    echo "REGISTRATION_OPEN_EMAIL_VERIFICATION_UNCHANGED\n";
} catch (Throwable $error) {
    fwrite(STDERR, "REGISTRATION_UPDATE_FAILED\n");
    exit(1);
}
'''


def enable(receipt_confirmed=False, container='vssjx-forum-forum-1'):
    if not receipt_confirmed:
        raise ValueError('CONFIRM_SMTP_TEST_RECEIPT_FIRST')
    result = subprocess.run(['docker', 'exec', '-u', 'www-data', container, 'php', '-d',
                             'display_errors=0', '-d', 'log_errors=0', '-r', PHP],
                            capture_output=True, text=True, timeout=30)
    if result.returncode or result.stdout.strip() != 'REGISTRATION_OPEN_EMAIL_VERIFICATION_UNCHANGED':
        raise RuntimeError('REGISTRATION_UPDATE_FAILED_CHECK_PRIVATE_SETTINGS')
    print('Registration is open; built-in email verification and permissions are unchanged.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--confirm-smtp-receipt', action='store_true', required=True)
    parser.add_argument('--container', default='vssjx-forum-forum-1')
    args = parser.parse_args()
    try:
        enable(args.confirm_smtp_receipt, args.container)
    except (ValueError, RuntimeError, OSError, subprocess.TimeoutExpired):
        raise SystemExit('Registration update did not complete; check private settings.')
