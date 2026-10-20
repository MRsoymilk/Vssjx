"""Create private first-install inputs; never print the generated password."""
import argparse
import json
import os
from pathlib import Path
import secrets
from urllib.parse import urlsplit


def prepare(directory, base_url):
    parsed = urlsplit(base_url)
    if (parsed.scheme not in ('https', 'http') or not parsed.hostname or parsed.query or parsed.fragment
            or parsed.path != '/flarum' or parsed.username or parsed.password):
        raise ValueError('Expected explicit forum base URL ending in /flarum')
    directory = Path(directory)
    directory.mkdir(mode=0o700, parents=True, exist_ok=False)
    password = secrets.token_urlsafe(32)
    config = {
        'debug': False,
        'baseUrl': base_url,
        'databaseConfiguration': {'driver': 'sqlite', 'database': '/data/forum.sqlite', 'prefix': ''},
        'adminUser': {'username': 'admin', 'password': password, 'email': 'admin@example.invalid'},
        'settings': {
            'forum_title': '蜀山剑侠 · 剑侠茶馆',
            'forum_description': '蜀山剑侠玩家交流社区',
            'welcome_title': '欢迎来到剑侠茶馆',
            'welcome_message': '交流游戏心得与反馈。论坛试运行中，暂不开放注册。',
            'theme_primary_color': '#476554',
            'theme_secondary_color': '#e7eee8',
            'allow_sign_up': '0',
            'default_locale': 'zh-Hans',
            'mail_driver': 'log',
        },
        'extensions': ','.join(['flarum-lang-english', 'flarum-lang-chinese-simplified',
                               'flarum-tags', 'flarum-likes', 'flarum-lock', 'flarum-sticky',
                               'flarum-markdown', 'flarum-mentions', 'flarum-bbcode', 'flarum-emoji']),
    }
    for name, value in [('install.json', config), ('admin-credentials.json', {
        'url': base_url, 'username': 'admin', 'password': password,
        'email': 'admin@example.invalid',
        'notice': 'Replace the placeholder email and rotate the password; registration is disabled until SMTP is configured.',
    })]:
        descriptor = os.open(directory / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, 'w') as stream:
            json.dump(value, stream, ensure_ascii=False, indent=2)
    return directory


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--base-url', required=True)
    args = parser.parse_args()
    print('Private installation inputs: ' + str(prepare(args.directory, args.base_url)))
