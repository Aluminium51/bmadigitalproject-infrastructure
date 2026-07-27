#!/usr/bin/env bash
set -Eeuo pipefail

# Read-only baseline collector for the BMA Ubuntu VMs.
# Optional environment variables: EXPECTED_HOSTNAME, EXPECTED_IP, OUTPUT_DIR.

umask 077
OUTPUT_DIR="${OUTPUT_DIR:-./artifacts/server-baseline}"
EXPECTED_HOSTNAME="${EXPECTED_HOSTNAME:-}"
EXPECTED_IP="${EXPECTED_IP:-}"
mkdir -p "$OUTPUT_DIR"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
output_file="$OUTPUT_DIR/${HOSTNAME:-server}-baseline-$timestamp.txt"
exec > >(tee "$output_file") 2>&1

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

actual_hostname="$(hostname -s)"
actual_ips="$(hostname -I 2>/dev/null || true)"

if [[ -n "$EXPECTED_HOSTNAME" && "$actual_hostname" != "$EXPECTED_HOSTNAME" ]]; then
  fail "Hostname mismatch: expected '$EXPECTED_HOSTNAME', got '$actual_hostname'"
fi

if [[ -n "$EXPECTED_IP" && ! " $actual_ips " == *" $EXPECTED_IP "* ]]; then
  fail "IP mismatch: expected '$EXPECTED_IP', got '$actual_ips'"
fi

echo "BMA server baseline"
echo "Collected UTC: $timestamp"
echo
echo "## Identity"
hostnamectl 2>/dev/null || true
echo "Current user: $(id -un)"
echo "Hostname: $actual_hostname"
echo "IP addresses: $actual_ips"

echo
echo "## System"
date
timedatectl 2>/dev/null || true
uname -a
cat /etc/os-release
nproc
free -h
df -h
lsblk
uptime

echo
echo "## Docker"
docker --version
docker compose version
docker info
docker ps -a
docker volume ls
docker network ls
docker system df

echo
echo "## Listening ports"
if command -v ss >/dev/null 2>&1; then
  ss -lntup 2>/dev/null || true
else
  echo "ss is not installed"
fi

echo
echo "Baseline written to: $output_file"
