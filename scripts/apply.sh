#!/usr/bin/env bash
set -euo pipefail

CFG_FILE="/etc/egress/config.env"
[[ -f "$CFG_FILE" ]] || { echo "Config not found: $CFG_FILE"; exit 1; }
# shellcheck disable=SC1090
source "$CFG_FILE"

ensure_rt_table() {
  local f="/etc/iproute2/rt_tables"
  grep -qE "^[[:space:]]*${PBR_TABLE_ID}[[:space:]]+${PBR_TABLE_NAME}\$" "$f" \
    || echo "${PBR_TABLE_ID} ${PBR_TABLE_NAME}" >> "$f"
}

ensure_gre() {
  # Create GRE if missing
  if ! ip link show "$GRE_IF" >/dev/null 2>&1; then
    ip tunnel add "$GRE_IF" mode gre local "$(ip -4 addr show dev "$PRIMARY_NIC" | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)" remote "$GRE_REMOTE_IP" ttl 255
  fi

  ip link set "$GRE_IF" up

  # Ensure IP address on GRE
  if ! ip -4 addr show dev "$GRE_IF" | grep -qF "${GRE_LOCAL_CIDR%/*}"; then
    ip addr flush dev "$GRE_IF" || true
    ip addr add "$GRE_LOCAL_CIDR" dev "$GRE_IF"
  fi
}

tun0_ready() {
  ip link show tun0 >/dev/null 2>&1
}

apply_pbr_rules() {
  ensure_rt_table

  # Mark packets coming from GRE
  iptables-legacy -t mangle -C PREROUTING -i "$GRE_IF" -j MARK --set-mark 0x1 2>/dev/null \
    || iptables-legacy -t mangle -A PREROUTING -i "$GRE_IF" -j MARK --set-mark 0x1

  # Policy rule: marked traffic -> v2ray table
  ip rule | grep -q "fwmark 0x1 lookup ${PBR_TABLE_NAME}" \
    || ip rule add fwmark 0x1 table "$PBR_TABLE_NAME" priority 100

  # Default route in v2ray table via tun0
  ip route replace default dev tun0 table "$PBR_TABLE_NAME"

  # Ensure GRE/LAN routes are reachable
  ip route replace "$(python3 - <<PY
import ipaddress
print(str(ipaddress.ip_interface("$GRE_LOCAL_CIDR").network))
PY
)" dev "$GRE_IF" table "$PBR_TABLE_NAME" || true

  # MSS clamp
  iptables-legacy -t mangle -C FORWARD -o tun0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss "$MSS_CLAMP" 2>/dev/null \
    || iptables-legacy -t mangle -A FORWARD -o tun0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss "$MSS_CLAMP"
}

main() {
  ensure_gre

  if ! tun0_ready; then
    echo "INFO: tun0 is not UP yet. Config is OK, but PBR rules will be applied after tun0 appears."
    echo "Hint: open v2rayA GUI and enable TUN mode. Then rerun Activate or wait for auto-apply."
    exit 0
  fi

  apply_pbr_rules
  echo "✅ Applied GRE + PBR rules (tun0 is present)."
}

main "$@"