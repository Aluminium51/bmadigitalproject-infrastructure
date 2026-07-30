#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if git -C "$repo_root" grep -n -E '/opt/bma/infrastructure/(ensure-backup-role|backup-staging)' -- scripts ':!scripts/ci/scan-obsolete-paths.sh' >/dev/null; then
  echo "Obsolete operational path found." >&2
  exit 1
fi
echo "No obsolete operational paths found."
