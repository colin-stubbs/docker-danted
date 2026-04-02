#!/bin/bash
set -euo pipefail

DANTE_PORT="${DANTE_PORT:-1080}"
DANTE_ROTATION="${DANTE_ROTATION:-same-same}"
DANTE_SOCKSMETHOD="${DANTE_SOCKSMETHOD:-none}"
DANTE_CLIENTMETHOD="${DANTE_CLIENTMETHOD:-none}"
DANTE_USER_PRIVILEGED="${DANTE_USER_PRIVILEGED:-root}"
DANTE_USER_UNPRIVILEGED="${DANTE_USER_UNPRIVILEGED:-nobody}"

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
  local ipv4_addrs ipv6_addrs
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
  echo "INFO: Auto-detecting addresses and generating ${DANTE_CONFIG_FILE}..." >&2
  generate_config > "${DANTE_CONFIG_FILE}"
  echo "INFO: Generated config:" >&2
  cat "${DANTE_CONFIG_FILE}" >&2
  echo "---" >&2
fi

export TMPDIR="/run/danted"
mkdir -p "${TMPDIR}"
chmod 0700 "${TMPDIR}"

echo "INFO: Starting danted..." >&2
exec /usr/sbin/danted -f "${DANTE_CONFIG_FILE}" -N 1
