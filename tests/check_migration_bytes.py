"""Verify immutable SQLx migration bytes; optional read-only database comparison."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', help='Existing PostgreSQL container to query read-only')
    args = parser.parse_args()
    manifest = json.loads((ROOT/'deploy/migration-checksums.json').read_text())['migrations']
    versions = {}
    for name, expected in manifest.items():
        data = (ROOT/'server/migrations'/name).read_bytes()
        assert hashlib.sha384(data).hexdigest()==expected, 'Migration bytes changed: '+name
        versions[int(name.split('_',1)[0])] = expected
    print(f'PASS: {len(manifest)} migration files retain their pinned SHA-384 bytes')
    if args.container:
        query = "SELECT version,encode(checksum,'hex') FROM _sqlx_migrations ORDER BY version"
        result = subprocess.run(['docker','exec',args.container,'sh','-c',
            'exec psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At -c "$1"','sh',query],
            capture_output=True,text=True,check=True,timeout=30)
        rows = result.stdout.splitlines()
        for row in rows:
            version, checksum = row.split('|')
            assert versions.get(int(version))==checksum, 'Applied migration bytes differ: '+version
        print(f'PASS: {len(rows)} applied database migration checksums match these exact files')

if __name__=='__main__': main()
