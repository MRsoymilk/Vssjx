"""Read-only checks for a local or deployed Flarum subpath; no credentials needed."""
import argparse
from http.cookies import SimpleCookie
import json
import re
from urllib.error import HTTPError
from urllib.request import build_opener, ProxyHandler, Request


def check(base, registration='closed'):
    opener = build_opener(ProxyHandler({}))
    count = 0

    def get(path):
        try:
            response = opener.open(Request(base + path, headers={'User-Agent': 'Flarum-deployment-check'}), timeout=30)
        except HTTPError as error:
            response = error
        with response:
            return response.status, response.headers, response.read()

    def expect(value, label):
        nonlocal count
        assert value, label
        count += 1
        print('PASS: ' + label)

    status, headers, body = get('/')
    expect(status == 200, 'Forum homepage returns 200')
    text = body.decode()
    expect('剑侠茶馆' in text, 'Chinese title is present')
    payload = json.loads(re.search(r'<script id="flarum-json-payload" type="application/json">(.*?)</script>', text, re.S)[1])
    forum = next(row for row in payload['resources'] if row['type'] == 'forums')['attributes']
    expect(forum['baseUrl'] == base, 'Canonical forum URL and subpath are correct')
    expect(forum['allowSignUp'] is (registration == 'open'), 'Registration matches expected state: ' + registration)
    expect(not forum['debug'], 'Debug is disabled')
    cookies = SimpleCookie()
    cookies.load(headers.get('Set-Cookie', ''))
    cookie = cookies.get('flarum_session')
    expect(cookie and cookie['path'] == '/flarum' and cookie['secure'] and cookie['httponly'], 'Session cookie stays private and forum-scoped')
    resources = set(re.findall(r'(?:src|href)="([^"]+/assets/[^"#]+)"', text))
    expect(len(resources) >= 3, 'Forum HTML refers to built assets')
    for url in sorted(resources):
        expect(url.startswith(base + '/assets/'), 'Asset remains under the configured forum prefix')
        asset_status, _, data = get(url[len(base):])
        expect(asset_status == 200 and len(data) > 0, 'Forum asset is served: ' + url.split('?')[0].rsplit('/', 1)[-1])
    for path in ('/config.php', '/site.php', '/composer.json', '/composer.lock', '/vendor/autoload.php',
                 '/storage/logs/flarum.log', '/forum.sqlite', '/.git/config', '/assets/.htaccess', '/assets/unknown.php'):
        status, _, _ = get(path)
        expect(status in (403, 404), 'Private or executable path is denied: ' + path)
    status, _, data = get('/api/discussions')
    expect(status == 200 and isinstance(json.loads(data)['data'], list), 'Forum discussion API works without writing production posts')
    print(f'FLARUM HTTP: {count} checks passed')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('base', help='Canonical URL ending in /flarum, without trailing slash')
    parser.add_argument('--registration', choices=('closed', 'open'), default='closed')
    args = parser.parse_args()
    check(args.base.rstrip('/'), args.registration)
