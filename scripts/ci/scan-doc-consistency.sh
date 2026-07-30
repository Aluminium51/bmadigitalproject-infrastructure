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

echo "Deployment documentation and path consistency checks passed."
