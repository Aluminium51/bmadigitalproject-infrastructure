#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT

upload_dir="$tmp_dir/uploads"
mkdir -p "$upload_dir"
app_env="$tmp_dir/app.env"
db_env="$tmp_dir/db.env"
ci_db_address="${CI_COMPOSE_TEST_ADDRESS:-$(printf '%s.%s.%s.%s' 10 254 254 2)}"

cat >"$app_env" <<EOF
BACKEND_IMAGE_REF=ci/bma-backend:ci
FRONTEND_IMAGE_REF=ci/bma-frontend:ci
DATABASE_URL=postgresql://bma_app:ci_disposable_password@$ci_db_address:5432/bma_db
PUBLIC_API_URL=https://staging.example.invalid/api/v1
CORS_ORIGINS=https://staging.example.invalid
JWT_SECRET=ci_disposable_jwt_secret_for_compose_only_2026
COOKIE_SECURE=true
COOKIE_SAME_SITE=lax
COOKIE_DOMAIN=
UPLOAD_HOST_PATH=$upload_dir
MAX_UPLOAD_SIZE=26214400
TRUST_PROXY=true
EDGE_NETWORK_NAME=bma_edge_ci
APP_BIND_ADDRESS=$ci_db_address
EOF

cat >"$db_env" <<EOF
DATABASE_BIND_ADDRESS=$ci_db_address
DATABASE_HOST_PORT=5432
POSTGRES_USER=bma_app
POSTGRES_PASSWORD=ci_disposable_database_password
POSTGRES_DB=bma_db
POSTGRES_BACKUP_USER=bma_backup
POSTGRES_BACKUP_PASSWORD=ci_disposable_backup_password
EOF

docker compose --env-file "$app_env" -f "$repo_root/compose.app.staging.yml" config --quiet
docker compose --env-file "$app_env" -f "$repo_root/compose.app.staging.yml" -f "$repo_root/compose.app.staging.external-edge.yml" config --quiet
docker compose --env-file "$app_env" -f "$repo_root/compose.app.staging.yml" -f "$repo_root/compose.app.staging.project-edge.yml" config --quiet
docker compose --env-file "$app_env" -f "$repo_root/compose.app.staging.yml" -f "$repo_root/compose.app.staging.host-gateway-edge.yml" config --quiet
docker compose --env-file "$app_env" -f "$repo_root/compose.app.staging.yml" -f "$repo_root/compose.staging-local.override.yml" config --quiet
docker compose --env-file "$db_env" -f "$repo_root/compose.db.staging.yml" config --quiet

echo "Compose configuration checks passed using a temporary environment file."
