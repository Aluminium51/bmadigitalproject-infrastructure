#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tracked="$(git -C "$repo_root" ls-files | grep -E '(^|/)(\.env($|\.)|.*\.(pem|key|p12|pfx|crt|cer))' | grep -v -E '(^|/)(\.env\..*\.example|.*\.example)$' || true)"
if [[ -n "$tracked" ]]; then
  echo "Potential secret-bearing tracked files found:" >&2
  echo "$tracked" >&2
  exit 1
fi
echo "No secret-bearing tracked files found."
