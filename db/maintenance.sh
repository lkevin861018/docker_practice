#!/bin/sh
# Run from inside the PostgreSQL container; secrets are already in the db environment.
set -eu
export PGPASSWORD="${POSTGRES_PASSWORD:?Missing POSTGRES_PASSWORD}"

case "${1:-}" in
  backup)
    archive="${2:?Missing archive path}"
    pg_dump -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
      --format=custom --no-owner --no-privileges --file "$archive"
    pg_restore --list "$archive" >/dev/null
    ;;
  create-test)
    target="${2:?Missing test database name}"
    archive="${3:?Missing archive path}"
    pg_restore --list "$archive" >/dev/null
    createdb -h 127.0.0.1 -U "$POSTGRES_USER" \
      --maintenance-db=postgres -T template0 "$target"
    ;;
  restore-test)
    target="${2:?Missing test database name}"
    archive="${3:?Missing archive path}"
    pg_restore -h 127.0.0.1 -U "$POSTGRES_USER" --dbname "$target" \
      --no-owner --no-privileges --single-transaction --exit-on-error "$archive"
    ;;
  count)
    target="${2:?Missing database name}"
    psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$target" \
      -Atqc 'SELECT COUNT(*) FROM public.visits'
    ;;
  *)
    echo 'Usage: maintenance.sh {backup <archive>|create-test <name> <archive>|restore-test <name> <archive>|count <name>}' >&2
    exit 2
    ;;
esac
