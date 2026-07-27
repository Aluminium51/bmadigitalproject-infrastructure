#!/usr/bin/env bash
set -Eeuo pipefail

# Creates deployment directories without deleting or replacing existing files.
# Run with sudo on VM1 or VM2.

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

deploy_user="${BMA_DEPLOY_USER:-${SUDO_USER:-}}"
if [[ -z "$deploy_user" || "$deploy_user" == "root" ]]; then
  echo "Set BMA_DEPLOY_USER to the non-root deployment user." >&2
  exit 1
fi

root_dir="${BMA_ROOT:-/opt/bma}"
directories=(
  "$root_dir"
  "$root_dir/infrastructure"
  "$root_dir/env"
  "$root_dir/logs"
)

if [[ "${BMA_DATABASE_VM:-false}" == "true" ]]; then
  directories+=("$root_dir/backups" "$root_dir/backups/database")
fi

for directory in "${directories[@]}"; do
  if [[ -e "$directory" && ! -d "$directory" ]]; then
    echo "Refusing to replace non-directory: $directory" >&2
    exit 1
  fi
  install -d -o "$deploy_user" -g "$deploy_user" -m 0750 "$directory"
done

chmod 0700 "$root_dir/env"
if [[ "${BMA_DATABASE_VM:-false}" == "true" ]]; then
  chmod 0700 "$root_dir/backups/database"
fi

echo "Prepared deployment directories under $root_dir for $deploy_user."
