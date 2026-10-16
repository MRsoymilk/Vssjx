"""Validate real LAN HTTPS/WSS using the generated CA, without disabling verification."""
import argparse
import base64
import hashlib
import http.client
import ipaddress
import json
import os
from pathlib import Path
import ssl
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import HTTPSHandler, ProxyHandler, build_opener


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lan-dir', type=Path, required=True)
    parser.add_argument('--public', type=Path, required=True)
    parser.add_argument('--setup-port', type=int, default=8001)
    args = parser.parse_args()
    manifest = json.loads((args.lan_dir / 'manifest.json').read_text())
    base = manifest['origin']
    url = urlsplit(base)
    assert url.scheme == 'https' and ipaddress.ip_address(url.hostname).is_private
    context = ssl.create_default_context(cafile=str(args.lan_dir / 'ca.crt'))
    opener = build_opener(ProxyHandler({}), HTTPSHandler(context=context))
    checks = 0

    def check(value, label):
        nonlocal checks
        assert value, label
        checks += 1
        print('PASS: ' + label)

    for name in ['index.html', 'index.js', 'index.wasm', 'index.pck']:
        with opener.open(base + '/' + name, timeout=20) as response:
            body = response.read()
            check(hashlib.sha256(body).digest() == hashlib.sha256((args.public / name).read_bytes()).digest(),
                  'CA-verified LAN HTTPS serves the correct ' + name)
    with opener.open(base + '/api/v1/server-info', timeout=5) as response:
        check('account_auth' in json.load(response).get('capabilities', []), 'LAN HTTPS forwards the account service')
    setup = f'http://{url.hostname}:{args.setup_port}'
    with opener.open(setup + '/vssjx-lan-ca.cer', timeout=5) as response:
        check(hashlib.sha256(response.read()).hexdigest().upper() == manifest['ca_sha256'],
              'Public setup certificate matches the exact generated CA fingerprint')
        check(response.headers.get_content_type() == 'application/x-x509-ca-cert', 'CA download has the certificate MIME type')
    with opener.open(setup + '/vssjx-lan.mobileconfig', timeout=5) as response:
        check(response.headers.get_content_type() == 'application/x-apple-aspen-config', 'iOS profile has the configuration MIME type')
    for entry in [base, setup]:
        for path in ['/ca.key', '/server/server.key', '/.env', '/api/status']:
            try:
                with opener.open(entry + path, timeout=5) as response:
                    status = response.status
            except HTTPError as error:
                status = error.code
            check(status == 404, 'Private material is absent from ' + entry + path)

    def upgrade(origin):
        connection = http.client.HTTPSConnection(url.hostname, url.port, context=context, timeout=5)
        key = base64.b64encode(os.urandom(16)).decode()
        try:
            connection.request('GET', '/api/v1/world/ws', headers={'Origin': origin,
                'Connection': 'Upgrade', 'Upgrade': 'websocket', 'Sec-WebSocket-Version': '13', 'Sec-WebSocket-Key': key})
            response = connection.getresponse()
            if response.status == 101:
                expected = base64.b64encode(hashlib.sha1((key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()).decode()
                check(response.getheader('Sec-WebSocket-Accept') == expected, 'WSS upgrade accept digest is valid')
            return response.status
        finally:
            connection.close()

    check(upgrade(base) == 101, 'CA-verified LAN WSS accepts the configured page Origin')
    check(upgrade('https://untrusted.invalid') == 403, 'LAN TLS proxy preserves rejection of unknown Origins')
    print(f'LAN HTTPS DEPLOYMENT: {checks} checks, 0 failures')


if __name__ == '__main__':
    main()
