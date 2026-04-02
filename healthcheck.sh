#!/bin/bash
# HTTP HEAD via local SOCKS5 on a non-loopback address so same-same outbound matches a real external.
set -euo pipefail

port="${DANTE_PORT:-1080}"
url="${DANTE_HEALTHCHECK_URL:-http://connectivitycheck.gstatic.com/generate_204}"

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

mapfile -t ipv4_list < <(discover_ipv4)
mapfile -t ipv6_list < <(discover_ipv6)

socks_host=""
if [[ ${#ipv4_list[@]} -gt 0 && -n "${ipv4_list[0]}" ]]; then
  socks_host="${ipv4_list[0]}"
elif [[ ${#ipv6_list[@]} -gt 0 && -n "${ipv6_list[0]}" ]]; then
  socks_host="${ipv6_list[0]}"
else
  echo "healthcheck: no global IPv4/IPv6 address found; cannot probe SOCKS without same-same using 127.0.0.1" >&2
  exit 1
fi

if [[ "${socks_host}" == *:* ]]; then
  proxy="socks5h://[${socks_host}]:${port}"
else
  proxy="socks5h://${socks_host}:${port}"
fi

exec curl -fsS -I \
  --connect-timeout 4 \
  --max-time 8 \
  -x "${proxy}" \
  -o /dev/null \
  "${url}"
