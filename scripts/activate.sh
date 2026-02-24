#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/egress-v2raya"
CFG_FILE="/etc/egress/config.env"

[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "Run as root"; exit 1; }
[[ -f "$CFG_FILE" ]] || { echo "Config not found. Run Config wizard first."; exit 1; }

echo "[*] Starting v2rayA (docker)..."
docker compose -f "$APP_DIR/docker-compose.yml" up -d

echo "[*] Applying GRE + PBR (if tun0 exists)..."
systemctl restart egress-apply.service || true

echo "✅ Activate requested."