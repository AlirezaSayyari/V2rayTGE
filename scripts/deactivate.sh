#!/usr/bin/env bash
set -euo pipefail

CFG_FILE="/etc/egress/config.env"
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "Run as root"; exit 1; }
[[ -f "$CFG_FILE" ]] || { echo "Config not found."; exit 1; }
# shellcheck disable=SC1090
source "$CFG_FILE"

echo "[*] Removing PBR rules..."
ip rule del fwmark 0x1 table "$PBR_TABLE_NAME" 2>/dev/null || true
ip rule del from all iif "$GRE_IF" table "$PBR_TABLE_NAME" 2>/dev/null || true

echo "[*] Flushing PBR table routes..."
ip route flush table "$PBR_TABLE_NAME" 2>/dev/null || true

echo "[*] Removing iptables mangle mark rules..."
iptables-legacy -t mangle -D PREROUTING -i "$GRE_IF" -j MARK --set-mark 0x1 2>/dev/null || true

echo "[*] Removing MSS clamp..."
iptables-legacy -t mangle -D FORWARD -o tun0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss "$MSS_CLAMP" 2>/dev/null || true

echo "✅ Deactivated (rules removed)."