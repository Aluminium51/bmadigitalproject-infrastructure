#!/usr/bin/env bash
set -Eeuo pipefail

# Read-only Application VM readiness report. This script never applies Netplan,
# changes permissions, restarts services, or modifies Docker state.

: "${EXPECTED_APP_ADDRESS:?Set EXPECTED_APP_ADDRESS to the approved Application VM address.}"
: "${EXPECTED_HTTP_PORT:?Set EXPECTED_HTTP_PORT.}"
: "${EXPECTED_HTTPS_PORT:?Set EXPECTED_HTTPS_PORT.}"
: "${UPLOAD_PATH:?Set UPLOAD_PATH.}"
: "${MIN_UPLOAD_FREE_GB:?Set MIN_UPLOAD_FREE_GB.}"

ROUTE_TEST_DESTINATION="${ROUTE_TEST_DESTINATION:-}"
BMA_ROOT="${BMA_ROOT:-/opt/bma}"
blocked_count=0
warn_count=0
checked_count=0

report() {
  local state="$1" name="$2" detail="$3"
  checked_count=$((checked_count + 1))
  printf '[%s] %s: %s\n' "$state" "$name" "$detail"
  case "$state" in
    BLOCKED) blocked_count=$((blocked_count + 1)) ;;
    WARN) warn_count=$((warn_count + 1)) ;;
  esac
}

if ! [[ "$EXPECTED_HTTP_PORT" =~ ^[1-9][0-9]*$ && "$EXPECTED_HTTPS_PORT" =~ ^[1-9][0-9]*$ ]]; then
  echo "EXPECTED_HTTP_PORT and EXPECTED_HTTPS_PORT must be positive integers." >&2
  exit 2
fi
if ! [[ "$MIN_UPLOAD_FREE_GB" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "MIN_UPLOAD_FREE_GB must be a non-negative number." >&2
  exit 2
fi

tmp_root="$(mktemp -d)"
cleanup() { rm -rf "$tmp_root"; }
trap cleanup EXIT

if [[ -r /etc/os-release ]]; then
  os_name="$(. /etc/os-release; printf '%s %s' "${NAME:-unknown}" "${VERSION_ID:-unknown}")"
  report PASS "Operating system" "$os_name"
else
  report WARN "Operating system" "/etc/os-release is unavailable"
fi

if command -v nproc >/dev/null 2>&1; then report PASS "CPU" "$(nproc) logical CPUs"; else report NOT_CHECKED "CPU" "nproc is unavailable"; fi
if command -v free >/dev/null 2>&1; then report PASS "Memory and swap" "$(free -h | awk 'NR==2 {print "RAM "$2", used "$3", available "$7} NR==3 {print "; swap "$2", used "$3}' | tr '\n' ' ')"; else report NOT_CHECKED "Memory and swap" "free is unavailable"; fi
if command -v df >/dev/null 2>&1; then report PASS "Disk" "root filesystem: $(df -h / | awk 'NR==2 {print $4 " available"}')"; else report NOT_CHECKED "Disk" "df is unavailable"; fi
if command -v lsblk >/dev/null 2>&1; then report PASS "LVM and block layout" "$(lsblk -dn -o NAME,SIZE,TYPE | tr '\n' ';')"; else report NOT_CHECKED "LVM and block layout" "lsblk is unavailable"; fi

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  docker_available=true
  report PASS "Docker Engine" "available"
else
  docker_available=false
  report BLOCKED "Docker Engine" "Docker is unavailable or the daemon is not ready"
fi
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then report PASS "Docker Compose" "available"; else report BLOCKED "Docker Compose" "Docker Compose is unavailable"; fi

if [[ "$(id -u)" -eq 0 ]]; then
  report PASS "Current user" "running as root for read-only inspection"
else
  report PASS "Current user" "$(id -un)"
fi
if command -v sudo >/dev/null 2>&1 && sudo -n -v >/dev/null 2>&1; then report PASS "Sudo capability" "non-interactive sudo is available"; else report WARN "Sudo capability" "non-interactive sudo is unavailable"; fi

if command -v ip >/dev/null 2>&1; then
  interface_ips="$(ip -o -4 addr show scope global | awk '$2 !~ /^(docker|br-|veth)/ {print $4}' | cut -d/ -f1 | tr '\n' ' ')"
  if [[ " $interface_ips " == *" $EXPECTED_APP_ADDRESS "* ]]; then report PASS "Application address" "$EXPECTED_APP_ADDRESS exists on a non-Docker interface"; else report BLOCKED "Application address" "$EXPECTED_APP_ADDRESS is not present on a non-Docker interface"; fi

  default_routes="$(ip route show default | awk 'NF {count++} END {print count+0}')"
  if [[ "$default_routes" -eq 1 ]]; then report PASS "Default routes" "one default route"; elif [[ "$default_routes" -eq 0 ]]; then report BLOCKED "Default routes" "no default route"; else report BLOCKED "Default routes" "$default_routes default routes configured"; fi

  if [[ -n "$ROUTE_TEST_DESTINATION" ]]; then
    if ip route get "$ROUTE_TEST_DESTINATION" >/dev/null 2>&1; then report PASS "Operational route" "route exists to configured destination"; else report BLOCKED "Operational route" "no route to configured destination"; fi
  else
    report NOT_CHECKED "Operational route" "set ROUTE_TEST_DESTINATION to run this check"
  fi
else
  report NOT_CHECKED "Network interfaces" "ip command is unavailable"
  report NOT_CHECKED "Default routes" "ip command is unavailable"
fi

if command -v netplan >/dev/null 2>&1; then
  mkdir -p "$tmp_root/etc"
  if [[ -d /etc/netplan ]]; then cp -a /etc/netplan "$tmp_root/etc/"; fi
  if netplan generate --root-dir "$tmp_root" >/dev/null 2>&1; then report PASS "Netplan validation" "configuration generates successfully in a temporary root"; else report BLOCKED "Netplan validation" "netplan generate failed"; fi
else
  report NOT_CHECKED "Netplan validation" "netplan is unavailable"
fi

if command -v ss >/dev/null 2>&1; then
  for port in "$EXPECTED_HTTP_PORT" "$EXPECTED_HTTPS_PORT"; do
    listeners="$(ss -lntp 2>/dev/null | awk -v port=":$port" '$4 ~ port"$" {print}')"
    if [[ -n "$listeners" ]]; then report BLOCKED "Port $port ownership" "a process is listening on the expected port"; else report PASS "Port $port ownership" "no process is listening"; fi
  done
else
  report NOT_CHECKED "Port ownership" "ss is unavailable"
fi

if [[ "$docker_available" == true ]]; then
  containers="$(docker ps -a --format '{{.Names}}' | tr '\n' ' ')"
  if [[ -n "$containers" ]]; then report WARN "Existing containers" "$containers"; else report PASS "Existing containers" "none"; fi
  projects="$(docker compose ls --format '{{.Name}}' 2>/dev/null | tr '\n' ' ')"
  if [[ -n "$projects" ]]; then report WARN "Compose projects" "$projects"; else report PASS "Compose projects" "none"; fi
  logging_driver="$(docker info --format '{{.LoggingDriver}}' 2>/dev/null || true)"
  if [[ "$logging_driver" == "json-file" ]]; then report PASS "Docker logging driver" "json-file"; else report WARN "Docker logging driver" "${logging_driver:-not available}"; fi
  if docker ps -aq | while read -r id; do [[ -z "$id" ]] && continue; docker inspect --format '{{.HostConfig.LogConfig.Options.max-size}}' "$id"; done | grep -qv '^$'; then report PASS "Docker log rotation" "at least one container has max-size configured"; else report WARN "Docker log rotation" "no configured max-size was found"; fi
else
  report NOT_CHECKED "Docker containers" "Docker is unavailable"
  report NOT_CHECKED "Compose projects" "Docker is unavailable"
  report NOT_CHECKED "Docker logging" "Docker is unavailable"
fi

if [[ -d "$UPLOAD_PATH" ]]; then
  owner="$(stat -c '%U:%G' "$UPLOAD_PATH" 2>/dev/null || stat -f '%Su:%Sg' "$UPLOAD_PATH" 2>/dev/null || printf 'unknown')"
  mode="$(stat -c '%a' "$UPLOAD_PATH" 2>/dev/null || stat -f '%Lp' "$UPLOAD_PATH" 2>/dev/null || printf 'unknown')"
  if [[ -w "$UPLOAD_PATH" ]]; then report PASS "Upload path" "$UPLOAD_PATH owner=$owner mode=$mode"; else report BLOCKED "Upload path" "$UPLOAD_PATH is not writable"; fi
  free_kb="$(df -Pk "$UPLOAD_PATH" | awk 'NR==2 {print $4}')"
  required_kb="$(awk -v gb="$MIN_UPLOAD_FREE_GB" 'BEGIN {printf "%.0f", gb * 1024 * 1024}')"
  if [[ "$free_kb" =~ ^[0-9]+$ ]] && (( free_kb >= required_kb )); then report PASS "Upload capacity" "$free_kb KiB available"; else report BLOCKED "Upload capacity" "less than $MIN_UPLOAD_FREE_GB GiB available"; fi
else
  report BLOCKED "Upload path" "$UPLOAD_PATH does not exist"
fi

if [[ -d "$BMA_ROOT" ]]; then report PASS "Deployment layout" "$BMA_ROOT exists"; else report BLOCKED "Deployment layout" "$BMA_ROOT does not exist"; fi
if [[ -d "$BMA_ROOT/env" ]]; then
  env_mode="$(stat -c '%a' "$BMA_ROOT/env" 2>/dev/null || stat -f '%Lp' "$BMA_ROOT/env" 2>/dev/null || printf 'unknown')"
  if [[ "$env_mode" == "700" ]]; then report PASS "Environment directory" "$BMA_ROOT/env has mode 700"; else report WARN "Environment directory" "$BMA_ROOT/env has mode $env_mode"; fi
else
  report BLOCKED "Environment directory" "$BMA_ROOT/env does not exist"
fi

echo
echo "Preflight summary: checked=$checked_count warnings=$warn_count blockers=$blocked_count"
if (( blocked_count > 0 )); then
  echo "RESULT: BLOCKED"
  exit 1
fi
if (( warn_count > 0 )); then echo "RESULT: READY_WITH_WARNINGS"; else echo "RESULT: READY"; fi
