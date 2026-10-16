"""Create a private development CA and a LAN TLS leaf; publish only the CA certificate.

Never alters OS trust, firewall, backend, client policy or an existing certificate set.
"""
import argparse
import hashlib
import ipaddress
import json
from pathlib import Path
import plistlib
import secrets
import shutil
import subprocess
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]


def prepare(address, output, openssl, port=8443):
    ip = ipaddress.IPv4Address(address)
    ranges = [ipaddress.ip_network(value) for value in ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16']]
    if not any(ip in network for network in ranges) or not 1 <= port <= 65535:
        raise ValueError('Use an RFC1918 IPv4 address and a valid HTTPS port')
    output = output.resolve()
    if output.exists() and any(output.iterdir()):
        raise ValueError('Choose a new directory; existing certificates must not be overwritten')
    output.mkdir(parents=True, exist_ok=True)
    server, public = output / 'server', output / 'public'
    server.mkdir()
    public.mkdir()

    def run(*args):
        result = subprocess.run([openssl, *map(str, args)], capture_output=True)
        if result.returncode:
            raise RuntimeError('OpenSSL failed: ' + result.stderr.decode(errors='replace'))
        return result.stdout

    name = 'Vssjx LAN CA ' + secrets.token_hex(6)
    ca_key, ca_cert = output / 'ca.key', output / 'ca.crt'
    run('genpkey', '-algorithm', 'RSA', '-pkeyopt', 'rsa_keygen_bits:3072', '-out', ca_key)
    run('req', '-new', '-x509', '-sha256', '-days', '365', '-key', ca_key, '-out', ca_cert,
        '-subj', '/CN=' + name, '-addext', 'basicConstraints=critical,CA:TRUE,pathlen:0',
        '-addext', 'keyUsage=critical,keyCertSign,cRLSign')
    run('genpkey', '-algorithm', 'RSA', '-pkeyopt', 'rsa_keygen_bits:2048', '-out', server / 'server.key')
    run('req', '-new', '-sha256', '-key', server / 'server.key', '-out', output / 'server.csr',
        '-subj', '/CN=' + str(ip))
    extensions = output / 'server.ext'
    extensions.write_text('basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\n'
                          'extendedKeyUsage=serverAuth\nsubjectAltName=IP:' + str(ip) + ',IP:127.0.0.1,DNS:localhost\n')
    run('x509', '-req', '-in', output / 'server.csr', '-CA', ca_cert, '-CAkey', ca_key,
        '-set_serial', '0x' + secrets.token_hex(16), '-days', '90', '-sha256', '-extfile', extensions,
        '-out', server / 'server.crt')
    run('verify', '-CAfile', ca_cert, '-verify_ip', str(ip), server / 'server.crt')
    certificate = run('x509', '-in', ca_cert, '-outform', 'DER')
    (public / 'vssjx-lan-ca.cer').write_bytes(certificate)
    fingerprint = hashlib.sha256(certificate).hexdigest().upper()
    payload = {'PayloadType': 'Configuration', 'PayloadVersion': 1, 'PayloadIdentifier': 'local.vssjx.lan.' + str(uuid4()),
               'PayloadUUID': str(uuid4()), 'PayloadDisplayName': name, 'PayloadDescription': '蜀山剑侠局域网 HTTPS 证书',
               'PayloadContent': [{'PayloadType': 'com.apple.security.root', 'PayloadVersion': 1,
                                   'PayloadIdentifier': 'local.vssjx.lan.root.' + str(uuid4()), 'PayloadUUID': str(uuid4()),
                                   'PayloadDisplayName': name, 'PayloadCertificateFileName': 'vssjx-lan-ca.cer',
                                   'PayloadContent': certificate}]}
    (public / 'vssjx-lan.mobileconfig').write_bytes(plistlib.dumps(payload))
    html = (ROOT / 'deploy/lan_setup.html').read_text(encoding='utf-8')
    game = f'https://{ip}:{port}'
    html = html.replace('{{GAME_URL}}', game + '/').replace('{{CA_NAME}}', name).replace('{{FINGERPRINT}}', fingerprint)
    (public / 'index.html').write_text(html, encoding='utf-8')
    manifest = {'ip': str(ip), 'origin': game, 'ca_name': name, 'ca_sha256': fingerprint,
                'ca_days': 365, 'leaf_days': 90, 'public_files': ['index.html', 'vssjx-lan-ca.cer', 'vssjx-lan.mobileconfig']}
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    # Restrictive POSIX mode where applicable; Windows ACL is managed by the operator.
    ca_key.chmod(0o600)
    (server / 'server.key').chmod(0o600)
    print(json.dumps(manifest, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ip', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--openssl', default=shutil.which('openssl'))
    parser.add_argument('--port', type=int, default=8443)
    args = parser.parse_args()
    if not args.openssl:
        parser.error('Set --openssl to the OpenSSL executable')
    prepare(args.ip, args.output, args.openssl, args.port)


if __name__ == '__main__':
    main()
