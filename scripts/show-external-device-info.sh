#!/usr/bin/env bash
set -euo pipefail

CFG_FILE="/etc/egress/config.env"
[[ -f "$CFG_FILE" ]] || { echo "No config found: $CFG_FILE"; exit 1; }
# shellcheck disable=SC1090
source "$CFG_FILE"

PUB_IP="$(curl -fsSL https://ifconfig.me 2>/dev/null || echo "<YOUR_SERVER_PUBLIC_IP>")"

echo "================================================"
echo " External Edge Device (Router/Firewall) Settings"
echo "================================================"
echo
echo "Create GRE tunnel:"
echo "  - Remote endpoint (Linux server public IP): $PUB_IP"
echo "  - Local endpoint (Edge Device public IP):   $GRE_REMOTE_IP"
echo "  - GRE interface name:                       <any>"
echo
echo "Tunnel IPs:"
echo "  - Linux server tunnel IP:                   $GRE_LOCAL_CIDR"
echo "  - Edge Device tunnel IP:                    (the other IP in the /30)"
echo
echo "PBR / Policy Route:"
echo "  - Route these LAN CIDRs into GRE tunnel:"
echo "    ${LAN_CIDRS//,/ , }"
echo
echo "Firewall:"
echo "  - Allow GRE protocol (47) between endpoints"
echo
echo "Notes:"
echo "  - After v2rayA enables TUN mode, tun0 will appear on Linux."
echo "  - Then Activate will apply PBR rules to send LAN traffic to tun0."
echo