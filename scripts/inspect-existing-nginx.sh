#!/usr/bin/env bash
set -Eeuo pipefail

container_name="${NGINX_CONTAINER:-bma-nginx}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required" >&2
  exit 2
fi

if ! docker inspect "$container_name" >/dev/null 2>&1; then
  echo "Nginx container not found: $container_name" >&2
  exit 1
fi

echo "Container: $container_name"
docker inspect --format 'Image={{.Config.Image}} Status={{.State.Status}} Networks={{json .NetworkSettings.Networks}}' "$container_name"
echo
echo "Loaded Nginx configuration (read-only):"
docker exec "$container_name" nginx -T

cat >&2 <<'EOF'

Inspection complete. No container was stopped, restarted, replaced, or modified.
Review the output before copying approved routes into Project Nginx.
EOF
