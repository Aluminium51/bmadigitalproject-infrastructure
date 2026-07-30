#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

if rg -n --hidden \
  --glob '!\.git/**' \
  --glob '!docs/evidence/**' \
  --glob '!docs/local-runtime-validation.md' \
  -e 'BACKEND_IMAGE=' \
  -e 'FRONTEND_IMAGE=' \
  -e 'BACKEND_VERSION=' \
  -e 'FRONTEND_VERSION=' \
  -e 'Copy-Item env/app\.staging\.example env/app\.staging\.local' \
  -e 'Copy-Item env/db\.staging\.example env/db\.staging\.local' \
  README.md docs env compose*.yml; then
  echo "Outdated deployment documentation or environment contract found." >&2
  exit 1
fi

if rg -n 'localhost:8080' docs/staging-runbook.md; then
  echo "Staging runbook contains an obsolete local staging port." >&2
  exit 1
fi

if rg -n 'proxy_pass[[:space:]]+https?://127\.0\.0\.1|EDGE_HOST_GATEWAY_ADDRESS=127\.0\.0\.1' compose.app.staging*.yml nginx/*.conf; then
  echo "Loopback proxy target found in staging application configuration." >&2
  exit 1
fi

if ! rg -q '^    image: \$\{BACKEND_IMAGE_REF:\?BACKEND_IMAGE_REF is required\}$' compose.app.staging.yml; then
  echo "Staging Compose must use BACKEND_IMAGE_REF." >&2
  exit 1
fi

if ! rg -q '^    image: \$\{FRONTEND_IMAGE_REF:\?FRONTEND_IMAGE_REF is required\}$' compose.app.staging.yml; then
  echo "Staging Compose must use FRONTEND_IMAGE_REF." >&2
  exit 1
fi

if rg -n --glob 'compose.app.staging*.yml' \
  -e '\$\{BACKEND_IMAGE(:|_VERSION)' \
  -e '\$\{FRONTEND_IMAGE(:|_VERSION)' \
  -e '\$\{BACKEND_VERSION' \
  -e '\$\{FRONTEND_VERSION'; then
  echo "Obsolete image/version variables remain in active staging Compose." >&2
  exit 1
fi

if rg -n --glob 'compose.app.staging.project-edge.yml' \
  -e 'PROJECT_EDGE_HTTP_BIND_ADDRESS:-0\.0\.0\.0' \
  -e 'PROJECT_EDGE_HTTPS_BIND_ADDRESS:-0\.0\.0\.0' \
  -e 'PROJECT_EDGE_HTTP_PORT:-80' \
  -e 'PROJECT_EDGE_HTTPS_PORT:-443'; then
  echo "Project Nginx has unsafe default bind addresses or ports." >&2
  exit 1
fi

echo "Deployment documentation and path consistency checks passed."
