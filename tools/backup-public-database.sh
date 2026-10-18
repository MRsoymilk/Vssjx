#!/bin/sh
# Full logical database backup, including all accounts, characters and sequences.
set -eu
umask 077
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$task_root"
backup_dir=${SSJX_BACKUP_DIR:-"$(dirname -- "$task_root")/vssjx-backups"}
mkdir -p "$backup_dir"
backup_file=$(mktemp "$backup_dir/vssjx-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX.dump")
trap 'rm -f -- "$backup_file" "$backup_file.sha256"' EXIT HUP INT TERM
docker compose --env-file .env -f deploy/compose.yaml exec -T postgres \
    sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$backup_file"
test -s "$backup_file"
docker compose --env-file .env -f deploy/compose.yaml exec -T postgres \
    pg_restore --list < "$backup_file" > /dev/null
sha256sum "$backup_file" > "$backup_file.sha256"
trap - EXIT HUP INT TERM
printf 'Database backup verified: %s\n' "$backup_file"
