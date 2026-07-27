#!/usr/bin/env bash
set -Eeuo pipefail

# Safe VM2 PostgreSQL deployment wrapper. It validates the rendered port bind
# before starting PostgreSQL and never removes volumes.

ENV_FILE="${DB_ENV_FILE:-/opt/bma/env/db.staging}"
COMPOSE_FILE="${DB_COMPOSE_FILE:-/opt/bma/infrastructure/compose.db.staging.yml}"
EXPECTED_BIND_ADDRESS="${EXPECTED_BIND_ADDRESS:-172.27.168.249}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing environment file: $ENV_FILE" >&2
  exit 1
fi
if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "Missing Compose file: $COMPOSE_FILE" >&2
  exit 1
fi

umask 077
rendered_config="$(mktemp)"
trap 'rm -f "$rendered_config"' EXIT

docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" config >"$rendered_config"

if grep -Eq '0\.0\.0\.0:5432|:::5432|\[::\]:5432' "$rendered_config"; then
  echo "Refusing to start: PostgreSQL is configured with a public wildcard bind." >&2
  exit 1
fi

if ! grep -Fq "$EXPECTED_BIND_ADDRESS" "$rendered_config"; then
  echo "Refusing to start: expected private bind $EXPECTED_BIND_ADDRESS was not rendered." >&2
  exit 1
fi

docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec postgres \
  sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"'

echo "PostgreSQL VM2 deployment is healthy and bound to $EXPECTED_BIND_ADDRESS."
