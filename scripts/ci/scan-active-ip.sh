#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
matches="$(git -C "$repo_root" grep -n -E '(^|[^0-9])(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[0-1])\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3})([^0-9]|$)' -- '*.yml' '*.yaml' 'env/*.example' 'nginx/*.conf' 'scripts/**' ':!docs/**' ':!README.md' || true)"
if [[ -n "$matches" ]]; then
  echo "Private IP found in active infrastructure configuration:" >&2
  echo "$matches" >&2
  exit 1
fi
echo "No active private IP values found in infrastructure configuration."
