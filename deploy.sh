#!/usr/bin/env bash
set -euo pipefail

REPO_SLUG_DEFAULT="alirezasayyari/V2rayTGE"
REPO_BRANCH_DEFAULT="main"

APP_DIR="/opt/egress-v2raya"
BIN_LINK="/usr/local/bin/egressctl"

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Please run as root: sudo bash $0"
    exit 1
  fi
}

detect_pkg_mgr() {
  if command -v apt-get >/dev/null 2>&1; then echo "apt"; return; fi
  echo "unsupported"
}

install_deps_apt() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y \
    ca-certificates curl jq iproute2 iptables python3 python3-venv \
    systemd openssl net-tools \
    docker.io docker-compose-plugin

  systemctl enable --now docker >/dev/null 2>&1 || true
}

fetch_repo() {
  local repo="${REPO_SLUG:-$REPO_SLUG_DEFAULT}"
  local branch="${REPO_BRANCH:-$REPO_BRANCH_DEFAULT}"

  mkdir -p "$APP_DIR"
  local tmp="/tmp/egress-v2raya.$$"
  mkdir -p "$tmp"

  local url="https://codeload.github.com/${repo}/tar.gz/refs/heads/${branch}"
  echo "[*] Downloading repo archive: ${repo} (${branch})"
  curl -fsSL "$url" -o "$tmp/repo.tgz"

  echo "[*] Extracting..."
  rm -rf "$APP_DIR"/*
  tar -xzf "$tmp/repo.tgz" -C "$tmp"

  local topdir
  topdir="$(find "$tmp" -maxdepth 1 -type d -name "$(basename "$repo")-*" | head -n1)"
  if [[ -z "$topdir" ]]; then
    echo "ERROR: could not find extracted top directory"
    exit 1
  fi

  cp -a "$topdir"/* "$APP_DIR"/
  rm -rf "$tmp"

  chmod +x "$APP_DIR/bin/egressctl" || true
  chmod +x "$APP_DIR/scripts/"*.sh || true
  chmod +x "$APP_DIR/deploy.sh" || true
}

install_systemd_units() {
  echo "[*] Installing systemd units..."
  install -m 0644 "$APP_DIR/systemd/egress-apply.service" /etc/systemd/system/egress-apply.service
  install -m 0644 "$APP_DIR/systemd/egress-apply.path" /etc/systemd/system/egress-apply.path
  install -m 0644 "$APP_DIR/systemd/egress-health.timer" /etc/systemd/system/egress-health.timer

  systemctl daemon-reload
  systemctl enable --now egress-apply.path >/dev/null 2>&1 || true
  systemctl enable --now egress-health.timer >/dev/null 2>&1 || true
}

install_cli() {
  echo "[*] Installing CLI: $BIN_LINK"
  ln -sf "$APP_DIR/bin/egressctl" "$BIN_LINK"
}

main() {
  require_root

  local mgr
  mgr="$(detect_pkg_mgr)"
  if [[ "$mgr" != "apt" ]]; then
    echo "ERROR: Unsupported package manager. Ubuntu/Debian required."
    exit 1
  fi

  echo "[*] Installing dependencies..."
  install_deps_apt

  fetch_repo
  install_systemd_units
  install_cli

  echo
  echo "======================================"
  echo "✅ V2rayTGE installed successfully"
  echo "======================================"
  echo
  echo "Run:"
  echo "  sudo egressctl"
  echo
}

main "$@"