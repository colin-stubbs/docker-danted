#!/bin/bash
set -euo pipefail

DANTE_PORT="${DANTE_PORT:-1080}"
DANTE_ROTATION="${DANTE_ROTATION:-same-same}"
DANTE_SOCKSMETHOD="${DANTE_SOCKSMETHOD:-none}"
DANTE_CLIENTMETHOD="${DANTE_CLIENTMETHOD:-none}"
DANTE_USER_PRIVILEGED="${DANTE_USER_PRIVILEGED:-root}"
DANTE_USER_UNPRIVILEGED="${DANTE_USER_UNPRIVILEGED:-nobody}"

# Online CPU count for Dante -N (main servers). Unset DANTE_N to use this default.
detect_cpu_count() {
  local n
  if n=$(nproc 2>/dev/null) && [[ -n "${n}" ]]; then
    :
  elif n=$(getconf _NPROCESSORS_ONLN 2>/dev/null) && [[ -n "${n}" ]]; then
    :
  else
    n=1
  fi
  [[ "${n}" =~ ^[0-9]+$ ]] || n=1
  if [[ "${n}" -lt 1 ]]; then
    n=1
  fi
  echo "${n}"
}

DANTE_N="${DANTE_N:-$(detect_cpu_count)}"
if ! [[ "${DANTE_N}" =~ ^[0-9]+$ ]] || [[ "${DANTE_N}" -lt 1 ]]; then
  echo "WARNING: invalid DANTE_N=${DANTE_N:-empty}, using 1" >&2
  DANTE_N=1
fi

# Interface for DANTE_ASSIGN_* (default: first "default" route dev, else first non-lo, else eth0).
detect_default_device() {
  local d
  d=$(ip route show default 2>/dev/null | awk '/default/ {
    for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit }
  }' | head -n1)
  if [[ -n "$d" ]]; then
    echo "$d"
    return 0
  fi
  d=$(ip -o link show 2>/dev/null | awk -F': ' '$2 != "lo" && $2 != "" { print $2; exit }')
  if [[ -n "$d" ]]; then
    echo "$d"
    return 0
  fi
  echo "eth0"
}

# Parse comma- or whitespace-separated tokens.
parse_token_list() {
  local raw="${1:-}"
  [[ -z "${raw// }" ]] && return 0
  local normalized="${raw//,/ }"
  local token
  for token in $normalized; do
    [[ -n "$token" ]] && printf '%s\n' "$token"
  done
}

# Run before discovery: ip addr add addr/prefix dev IFACE for each token.
# Requires CAP_NET_ADMIN in the container if addresses are not already present.
assign_addrs_from_env() {
  local dev="$1"
  local cidr
  while IFS= read -r cidr; do
    [[ -z "$cidr" ]] && continue
    if [[ "$cidr" != */* ]]; then
      echo "WARNING: skip \"${cidr}\" (DANTE_ASSIGN_* tokens must be addr/prefix, e.g. 203.0.113.4/24)" >&2
      continue
    fi
    if ip addr add "${cidr}" dev "${dev}" 2>/dev/null; then
      echo "INFO: ip addr add ${cidr} dev ${dev}" >&2
    else
      echo "WARNING: ip addr add ${cidr} dev ${dev} failed (already present, wrong subnet, or missing CAP_NET_ADMIN)" >&2
    fi
  done
}

apply_assign_lists() {
  local dev
  dev="${DANTE_DEVICE:-$(detect_default_device)}"
  if [[ -z "${DANTE_ASSIGN_IPV4:-}" && -z "${DANTE_ASSIGN_IPV6:-}" ]]; then
    return 0
  fi
  echo "INFO: Applying DANTE_ASSIGN_IPV4 / DANTE_ASSIGN_IPV6 on dev ${dev} (before discovery)" >&2
  parse_token_list "${DANTE_ASSIGN_IPV4:-}" | assign_addrs_from_env "${dev}"
  parse_token_list "${DANTE_ASSIGN_IPV6:-}" | assign_addrs_from_env "${dev}"
}

discover_ipv4() {
  ip -4 addr show scope global 2>/dev/null \
    | grep -oP 'inet \K[0-9.]+' \
    || true
}

discover_ipv6() {
  ip -6 addr show scope global 2>/dev/null \
    | grep -oP 'inet6 \K[0-9a-f:]+' \
    || true
}

generate_config() {
  local -a ipv4_addrs ipv6_addrs
  mapfile -t ipv4_addrs < <(discover_ipv4)
  mapfile -t ipv6_addrs < <(discover_ipv6)

  echo "# Auto-generated danted.conf — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""
  echo "logoutput: stderr"
  echo ""

  echo "internal: 0.0.0.0 port = ${DANTE_PORT}"
  echo "internal: :: port = ${DANTE_PORT}"
  echo ""

  if [ ${#ipv4_addrs[@]} -gt 0 ]; then
    echo "# Outbound Pool (IPv4) — ${#ipv4_addrs[@]} address(es)"
    for addr in "${ipv4_addrs[@]}"; do
      echo "external: ${addr}"
    done
  else
    echo "# No global IPv4 addresses detected"
  fi
  echo ""

  if [ ${#ipv6_addrs[@]} -gt 0 ]; then
    echo "# Outbound Pool (IPv6) — ${#ipv6_addrs[@]} address(es)"
    for addr in "${ipv6_addrs[@]}"; do
      echo "external: ${addr}"
    done
  else
    echo "# No global IPv6 addresses detected"
  fi
  echo ""

  echo "external.rotation: ${DANTE_ROTATION}"
  echo ""
  echo "socksmethod: ${DANTE_SOCKSMETHOD}"
  echo "clientmethod: ${DANTE_CLIENTMETHOD}"
  echo ""
  echo "user.privileged: ${DANTE_USER_PRIVILEGED}"
  echo "user.unprivileged: ${DANTE_USER_UNPRIVILEGED}"
  echo ""
  echo "client pass {"
  echo "  from: 0/0 to: 0/0"
  echo "  log: error"
  echo "}"
  echo ""
  echo "socks pass {"
  echo "  from: 0/0 to: 0/0"
  echo "  command: bind connect udpassociate"
  echo "  log: error"
  echo "}"
}

if [ -n "${DANTE_CONFIG_FILE:-}" ]; then
  echo "INFO: DANTE_CONFIG_FILE is set, using existing config at ${DANTE_CONFIG_FILE}" >&2
else
  DANTE_CONFIG_FILE="/tmp/danted.conf"
  apply_assign_lists
  echo "INFO: Auto-detecting addresses and generating ${DANTE_CONFIG_FILE}..." >&2
  generate_config > "${DANTE_CONFIG_FILE}"
  echo "INFO: Generated config:" >&2
  cat "${DANTE_CONFIG_FILE}" >&2
  echo "---" >&2
fi

export TMPDIR="/run/danted"
mkdir -p "${TMPDIR}"
chmod 0700 "${TMPDIR}"

echo "INFO: Starting danted with -N ${DANTE_N} (Dante main servers; default matches online CPUs)" >&2
exec /usr/sbin/danted -f "${DANTE_CONFIG_FILE}" -N "${DANTE_N}"
