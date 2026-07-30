#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if git -C "$repo_root" grep -n -E 'docker compose[^\n]*down[[:space:]]+-v|docker[[:space:]]+(system[[:space:]]+prune|volume[[:space:]]+rm)|netplan[[:space:]]+(apply|try)|rm[[:space:]]+-rf[[:space:]]+(/|~|\$HOME|\$BMA_ROOT)' -- scripts compose*.yml .github ':!scripts/ci/scan-destructive-commands.sh' >/dev/null; then
  echo "Destructive operational command found." >&2
  exit 1
fi
echo "No prohibited destructive operational commands found."
