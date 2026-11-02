#!/usr/bin/env bash
set -euo pipefail
umask 077
rand() { openssl rand -hex 24; }
cat > .env.ci <<EOF
POSTGRES_DB=labdb
POSTGRES_USER=labuser
POSTGRES_PASSWORD=$(rand)
APP_DB_USER=flask_app
APP_DB_PASSWORD=$(rand)
REPORT_DB_USER=report_reader
REPORT_DB_PASSWORD=$(rand)
METRICS_DB_USER=metrics_reader
METRICS_DB_PASSWORD=$(rand)
PGADMIN_DEFAULT_EMAIL=admin@example.invalid
PGADMIN_DEFAULT_PASSWORD=$(rand)
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=$(rand)
WEB_PORT=8080
PGADMIN_PORT=5050
GRAFANA_PORT=3000
PROMETHEUS_PORT=9090
ALERTMANAGER_PORT=9093
MAILPIT_UI_PORT=8025
EOF
printf 'Created temporary CI environment file (no secrets printed).\n'
