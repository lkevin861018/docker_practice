#!/usr/bin/env bash
# Execute manually on a provisioned Ubuntu server.
set -euo pipefail
cd /opt/docker-lab
command -v docker >/dev/null || { echo 'Docker missing' >&2; exit 1; }
command -v curl >/dev/null || { echo 'curl missing' >&2; exit 1; }
test -f .env || { echo '/opt/docker-lab/.env missing' >&2; exit 1; }
test -f compose.deploy.yaml || { echo 'compose.deploy.yaml missing' >&2; exit 1; }
docker compose --env-file .env config --quiet

docker compose --env-file .env exec -T db sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
curl -fsS http://127.0.0.1:8080/healthz
printf '\nPreflight completed; GHCR authentication and SSH trust still need separate verification.\n'
