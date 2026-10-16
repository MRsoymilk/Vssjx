"""Read-only checks of an already deployed loopback Web entry and its real backend.

No accounts, characters, database rows or server configuration are changed.
"""
import argparse
import hashlib
import json
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import ProxyHandler, build_opener

from ws_fixture import WebSocket


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', default='http://127.0.0.1:8000')
    parser.add_argument('--public', type=Path, required=True)
    args = parser.parse_args()
    # The RFC6455 fixture intentionally supports only this owned loopback target.
    assert args.base.startswith('http://127.0.0.1:') and args.base.count('/') == 2
    opener = build_opener(ProxyHandler({}))
    checks = 0

    def check(value, description):
        nonlocal checks
        assert value, description
        checks += 1
        print('PASS: ' + description)

    for name in ['index.html', 'index.js', 'index.wasm', 'index.pck']:
        with opener.open(args.base + '/' + name, timeout=20) as response:
            body = response.read()
            check(hashlib.sha256(body).digest() == hashlib.sha256((args.public / name).read_bytes()).digest(),
                  'Deployed artifact matches exported file: ' + name)
            if name.endswith('.wasm'):
                check(response.headers.get_content_type() == 'application/wasm', 'WASM has the correct MIME type')
    with opener.open(args.base + '/api/v1/server-info', timeout=5) as response:
        info = json.load(response)
        check(info.get('service') == 'vssjx' and 'account_auth' in info.get('capabilities', []),
              'Same-origin API reaches the running account service')
    for path, expected in [('/api/v1/auth/me', 401), ('/.env', 404), ('/api/status', 404),
                           ('/api/announcements', 404), ('/scripts/admin/data_browser.gd', 404),
                           ('/missing.wasm', 404)]:
        try:
            with opener.open(args.base + path, timeout=5) as response:
                status = response.status
        except HTTPError as error:
            status = error.code
        check(status == expected, 'Expected HTTP status for ' + path)
    address = args.base.replace('http://', 'ws://', 1) + '/api/v1/world/ws'
    with_origin = WebSocket(address, origin=args.base)
    with_origin.close()
    check(True, 'Allowed browser Origin completes WebSocket upgrade through the proxy')
    try:
        denied = WebSocket(address, origin='https://untrusted.invalid')
    except AssertionError as error:
        check('403 Forbidden' in str(error), 'Proxy preserves untrusted Origin for backend rejection')
    else:
        denied.close()
        raise AssertionError('Untrusted Origin was accepted')
    print(f'WEB DEPLOYMENT: {checks} checks, 0 failures')


if __name__ == '__main__':
    main()
