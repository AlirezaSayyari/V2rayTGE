#!/usr/bin/env bash
set -euo pipefail

CFG_FILE="/etc/egress/config.env"
echo "=== Health Check ==="

if [[ -f "$CFG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CFG_FILE"
  echo "[CFG] OK: $CFG_FILE"
else
  echo "[CFG] MISSING: run Config wizard"
  exit 1
fi

echo
echo "[SYS] systemd:"
systemctl is-active docker >/dev/null 2>&1 && echo " - docker: active" || echo " - docker: not active"
systemctl is-active egress-apply.path >/dev/null 2>&1 && echo " - egress-apply.path: active" || echo " - egress-apply.path: not active"

echo
echo "[NET] interfaces:"
ip link show "$GRE_IF" >/dev/null 2>&1 && echo " - $GRE_IF: present" || echo " - $GRE_IF: missing"
ip link show tun0 >/dev/null 2>&1 && echo " - tun0: present" || echo " - tun0: missing (enable TUN in v2rayA)"

echo
echo "[PBR] ip rule:"
ip rule | sed 's/^/ - /'

echo
echo "[PBR] table routes ($PBR_TABLE_NAME):"
ip route show table "$PBR_TABLE_NAME" | sed 's/^/ - /' || true

echo
echo "[FW] mangle rules relevant:"
iptables-legacy -t mangle -S | egrep "PREROUTING|MARK|TCPMSS" | sed 's/^/ - /' || true

echo
echo "[DOCKER] v2raya:"
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | sed 's/^/ - /' || true

echo
read -rp "Press Enter..."