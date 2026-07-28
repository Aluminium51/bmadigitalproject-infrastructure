#!/usr/bin/env bash
set -Eeuo pipefail

# Safe VM2 PostgreSQL deployment wrapper. It validates the rendered port bind
# before starting PostgreSQL, waits for bounded readiness, and never removes
# volumes.

ENV_FILE="${DB_ENV_FILE:-/opt/bma/env/db.staging}"
COMPOSE_FILE="${DB_COMPOSE_FILE:-/opt/bma/infrastructure/compose.db.staging.yml}"
EXPECTED_BIND_ADDRESS="${EXPECTED_BIND_ADDRESS:-}"
EXPECTED_BIND_PORT="${EXPECTED_BIND_PORT:-5432}"
HEALTH_ATTEMPTS="${POSTGRES_HEALTH_ATTEMPTS:-30}"
HEALTH_INTERVAL_SECONDS="${POSTGRES_HEALTH_INTERVAL_SECONDS:-2}"

if [[ -z "$EXPECTED_BIND_ADDRESS" ]]; then
  echo "Set EXPECTED_BIND_ADDRESS to the approved Database VM private IP." >&2
  exit 1
fi

if ! [[ "$HEALTH_ATTEMPTS" =~ ^[1-9][0-9]*$ ]]; then
  echo "POSTGRES_HEALTH_ATTEMPTS must be a positive integer." >&2
  exit 1
fi

if ! [[ "$HEALTH_INTERVAL_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
  echo "POSTGRES_HEALTH_INTERVAL_SECONDS must be a positive integer." >&2
  exit 1
fi

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

if grep -Eq 'host_ip: (0\.0\.0\.0|::|\[::\])' "$rendered_config"; then
  echo "Refusing to start: PostgreSQL is configured with a public wildcard bind." >&2
  exit 1
fi

if ! grep -Fq "host_ip: $EXPECTED_BIND_ADDRESS" "$rendered_config"; then
  echo "Refusing to start: expected private bind $EXPECTED_BIND_ADDRESS was not rendered." >&2
  exit 1
fi

if ! grep -Fq "published: \"$EXPECTED_BIND_PORT\"" "$rendered_config"; then
  echo "Refusing to start: expected host port $EXPECTED_BIND_PORT was not rendered." >&2
  exit 1
fi

docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d

healthy=false
for ((attempt=1; attempt<=HEALTH_ATTEMPTS; attempt++)); do
  if docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T postgres \
    sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"'; then
    healthy=true
    break
  fi

  sleep "$HEALTH_INTERVAL_SECONDS"
done

docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps

if [[ "$healthy" != true ]]; then
  echo "PostgreSQL did not become ready after ${HEALTH_ATTEMPTS} attempts." >&2
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" logs --tail=100 postgres >&2 || true
  exit 1
fi

echo "PostgreSQL VM2 deployment is healthy and bound to $EXPECTED_BIND_ADDRESS:$EXPECTED_BIND_PORT."
