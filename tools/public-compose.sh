#!/bin/sh
# Daily commands for an already-issued HTTPS deployment.
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$task_root"
if grep -q '^SSJX_PUBLIC_WEB_ROOT=.' .env; then
    set -- -f deploy/public.web.compose.yaml "$@"
fi
exec docker compose --env-file .env \
    -f deploy/compose.yaml -f deploy/public.compose.yaml \
    -f deploy/public.tls.compose.yaml "$@"
