#!/usr/bin/env bash
# Run as a dedicated Ubuntu deploy user, after manual GitHub Environment approval.
set -euo pipefail
image="${1:?Supply GHCR image:SHA}"
if ! [[ "$image" =~ ^ghcr\.io/[a-z0-9._/-]+/flask-app:[0-9a-f]{40}$ ]]; then
  echo 'ERROR: Invalid GHCR image reference' >&2
  exit 1
fi

cd /opt/docker-lab
[ -f .env ] && [ -f compose.yaml ] && [ -f compose.deploy.yaml ] || {
  echo 'ERROR: Server must be provisioned with v7 project and private .env first.' >&2
  exit 1
}

# All existing database and monitoring services must be deployed separately beforehand.
docker compose --env-file .env exec -T db sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null

previous=''
if [ -f .ci-last-good-image ]; then
  previous="$(cat .ci-last-good-image)"
fi

printf 'Pulling approved image: %s\n' "$image"
docker pull "$image"

run_overlay() {
  DEPLOY_IMAGE="$1" docker compose --env-file .env -f compose.yaml -f compose.deploy.yaml up -d --no-build --no-deps app
}

rollback() {
  echo 'Deployment health check failed. Attempting app-only rollback.' >&2
  if [ -n "$previous" ] && [[ "$previous" =~ ^ghcr\.io/[a-z0-9._/-]+/flask-app:[0-9a-f]{40}$ ]]; then
    run_overlay "$previous" || true
  else
    docker compose --env-file .env -f compose.yaml up -d --no-build --no-deps app || true
  fi
}

trap rollback ERR
run_overlay "$image"

ok=0
for i in $(seq 1 30); do
  if curl -fsS --max-time 3 http://127.0.0.1:8080/healthz | grep -q '"status":"ok"'; then
    ok=1
    break
  fi
  sleep 2
done

if [ "$ok" -ne 1 ]; then
  echo 'ERROR: Flask failed health check after deployment.' >&2
  trap - ERR
  rollback
  exit 1
fi

# Write last-known-good only after passing health check.
printf '%s\n' "$image" > .ci-last-good-image
trap - ERR
printf 'SUCCESS: %s\n' "$image"
