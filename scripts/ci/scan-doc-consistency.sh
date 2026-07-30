#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

legacy_matches="$(git grep -n -E \
  'BACKEND_IMAGE=|FRONTEND_IMAGE=|BACKEND_VERSION=|FRONTEND_VERSION=|Copy-Item env/app\.staging\.example env/app\.staging\.local|Copy-Item env/db\.staging\.example env/db\.staging\.local' \
  -- README.md docs env 'compose*.yml' ':!docs/evidence/**' ':!docs/local-runtime-validation.md' || true)"
if [[ -n "$legacy_matches" ]]; then
  printf '%s\n' "$legacy_matches" >&2
  echo "Outdated deployment documentation or environment contract found." >&2
  exit 1
fi

if git grep -n 'localhost:8080' -- docs/staging-runbook.md; then
  echo "Staging runbook contains an obsolete local staging port." >&2
  exit 1
fi

if git grep -n -E 'proxy_pass[[:space:]]+https?://127\.0\.0\.1|EDGE_HOST_GATEWAY_ADDRESS=127\.0\.0\.1' -- 'compose.app.staging*.yml' 'nginx/*.conf'; then
  echo "Loopback proxy target found in staging application configuration." >&2
  exit 1
fi

if ! grep -Eq '^    image: \$\{BACKEND_IMAGE_REF:\?BACKEND_IMAGE_REF is required\}$' compose.app.staging.yml; then
  echo "Staging Compose must use BACKEND_IMAGE_REF." >&2
  exit 1
fi

if ! grep -Eq '^    image: \$\{FRONTEND_IMAGE_REF:\?FRONTEND_IMAGE_REF is required\}$' compose.app.staging.yml; then
  echo "Staging Compose must use FRONTEND_IMAGE_REF." >&2
  exit 1
fi

obsolete_compose_matches="$(git grep -n -E \
  '\$\{BACKEND_IMAGE(:|_VERSION)|\$\{FRONTEND_IMAGE(:|_VERSION)|\$\{BACKEND_VERSION|\$\{FRONTEND_VERSION' \
  -- 'compose.app.staging*.yml' || true)"
if [[ -n "$obsolete_compose_matches" ]]; then
  printf '%s\n' "$obsolete_compose_matches" >&2
  echo "Obsolete image/version variables remain in active staging Compose." >&2
  exit 1
fi

unsafe_edge_matches="$(git grep -n -E \
  'PROJECT_EDGE_HTTP_BIND_ADDRESS:-0\.0\.0\.0|PROJECT_EDGE_HTTPS_BIND_ADDRESS:-0\.0\.0\.0|PROJECT_EDGE_HTTP_PORT:-80|PROJECT_EDGE_HTTPS_PORT:-443' \
  -- compose.app.staging.project-edge.yml || true)"
if [[ -n "$unsafe_edge_matches" ]]; then
  printf '%s\n' "$unsafe_edge_matches" >&2
  echo "Project Nginx has unsafe default bind addresses or ports." >&2
  exit 1
fi

echo "Deployment documentation and path consistency checks passed."
