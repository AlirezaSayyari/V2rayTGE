#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/egress-v2raya"
CFG_DIR="/etc/egress"
CFG_FILE="$CFG_DIR/config.env"
COMPOSE_FILE="$APP_DIR/docker-compose.yml"

ensure_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Please run as root: sudo $0"
    exit 1
  fi
}

load_cfg() {
  if [[ -f "$CFG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CFG_FILE"
  fi
}

help() {
  clear
  cat <<'EOF'
====================================================
Help & Introduction — Egress System (GRE + v2rayA)
====================================================

This project turns your Linux server into an "Egress Gateway" for your LAN clients.

High-level flow:
  LAN Clients -> Edge Device (your router/firewall) --GRE--> Linux Egress GW
  Linux Egress GW -> v2rayA (tun0) -> Internet

Core components:
  1) GRE tunnel (between your Edge Device and this Linux server)
  2) Policy Based Routing (PBR): specific LAN CIDRs are routed to tun0
  3) MSS clamp: avoids MTU/MSS issues in tunneling scenarios
  4) v2rayA (Docker): provides GUI for importing your outbound configs
     and creates tun0 (transparent tunnel interface).

What YOU configure on this Linux server (via Config Wizard):
  - Primary NIC (local interface for GRE)
  - GRE remote public IP (your Edge Device public IP)
  - GRE tunnel IPs (e.g. 10.255.255.2/30)
  - One or more LAN CIDRs (e.g. 192.168.0.0/16, 10.10.10.0/24)
  - MSS Clamp value (typical range: 1200–1460; depends on MTU path)
  - v2rayA GUI port (default 2017)

What YOU configure on the Edge Device (router/firewall):
  - Create GRE tunnel to this Linux server public IP
  - Set tunnel IP to match the /30 you chose
  - Create PBR / policy-route: route your LAN CIDRs to GRE tunnel
  - Optional: firewall rules to allow GRE protocol (47) + keepalive handling

v2rayA GUI:
  - Open: http://<Linux-Egress-IP>:2017
  - Import your VLESS/VMess/etc
  - Enable "TUN mode" (transparent proxy) so tun0 comes up
  - Once tun0 is UP, run Activate (or it will auto-apply via systemd path)

Important notes:
  - This tool will NOT flush your firewall blindly.
  - Rules are applied idempotently.
  - If tun0 is not up, config is saved but routing rules won't apply yet.

Commands:
  egressctl  -> opens the dashboard
  Activate/Deactivate -> manages system state

EOF
  read -rp "Press Enter to return..."
}

actmenu() {
  ensure_root
  clear
  cat <<'EOF'
Activate / Deactivate
---------------------
  1) Activate (apply docker + GRE + PBR rules)
  2) Deactivate (remove PBR rules; keeps docker optional)
  3) Restart apply service
  0) Back
EOF
  echo
  read -rp "Select: " c
  case "${c:-}" in
    1) "$APP_DIR/scripts/activate.sh" ;;
    2) "$APP_DIR/scripts/deactivate.sh" ;;
    3) systemctl restart egress-apply.service || true; echo "Done"; sleep 1 ;;
    *) ;;
  esac
}

logmenu() {
  ensure_root
  clear
  cat <<'EOF'
Logs
----
  1) systemd (egress-apply)
  2) systemd (path watcher)
  3) docker logs (v2raya)
  0) Back
EOF
  echo
  read -rp "Select: " c
  case "${c:-}" in
    1) journalctl -u egress-apply.service -b --no-pager -n 200; read -rp "Enter..." ;;
    2) journalctl -u egress-apply.path -b --no-pager -n 200; read -rp "Enter..." ;;
    3) docker logs --tail 200 v2raya 2>/dev/null || echo "v2raya container not found"; read -rp "Enter..." ;;
    *) ;;
  esac
}
case "${1:-}" in
  help) help ;;
  actmenu) actmenu ;;
  logmenu) logmenu ;;
  *) echo "Usage: $0 {help|actmenu|logmenu}" ;;
esac