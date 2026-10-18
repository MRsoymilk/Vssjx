#!/bin/sh
# Run on the Linux Docker host. Certbot never receives the Docker daemon socket.
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$task_root"
dc() {
    docker compose --env-file .env \
        -f deploy/compose.yaml \
        -f deploy/public.compose.yaml \
        -f deploy/public.tls.compose.yaml "$@"
}
dc run --rm certbot renew --quiet \
    --deploy-hook 'touch /var/lib/letsencrypt/nginx-reload-required'
if dc run --rm --entrypoint sh certbot -c 'test -f /var/lib/letsencrypt/nginx-reload-required'; then
    dc exec -T nginx nginx -t
    dc exec -T nginx nginx -s reload
    dc run --rm --entrypoint sh certbot -c 'rm -f /var/lib/letsencrypt/nginx-reload-required'
fi
