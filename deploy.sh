#!/usr/bin/env bash
set -euo pipefail

REPO_NAME="V2rayTGE"
INSTALL_DIR="/opt/v2raytge"
ETC_DIR="/etc/v2raytge"
BIN_DIR="/usr/local/sbin"
SYSTEMD_DIR="/etc/systemd/system"
LOG_DIR="/var/log/v2raytge"

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "[deploy] ERROR: run as root (sudo)."
    exit 1
  fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

log(){ echo "[deploy] $*"; }

ensure_dirs() {
  mkdir -p "$INSTALL_DIR" "$ETC_DIR" "$LOG_DIR"
}

install_deps() {
  log "Installing dependencies..."
  apt-get update -y
  apt-get install -y ca-certificates curl jq python3 iproute2 iptables
  # docker (best effort)
  if ! have_cmd docker; then
    log "Docker not found; installing docker.io..."
    apt-get install -y docker.io
    systemctl enable --now docker
  fi
  if ! docker compose version >/dev/null 2>&1; then
    log "docker compose plugin not found; installing docker-compose-plugin..."
    apt-get install -y docker-compose-plugin || true
  fi
  systemctl enable --now docker || true
}

copy_repo_files() {
  # This deploy.sh is meant to be run from a cloned repo OR via curl.
  # If via curl, user should curl the raw deploy.sh from GitHub; we need to fetch the repo.
  # We'll try to detect if we're already inside repo by checking ./tge/
  if [[ -d "./tge" && -f "./tge/bin/tge" ]]; then
    log "Local repo detected; copying files to $INSTALL_DIR..."
    rsync -a --delete ./ "$INSTALL_DIR/"
  else
    # If not in repo directory, fetch via git if available, otherwise via tarball
    if have_cmd git; then
      log "Fetching repo via git..."
      rm -rf "$INSTALL_DIR"
      git clone --depth=1 "https://github.com/AlirezaSayyari/V2rayTGE.git" "$INSTALL_DIR"
    else
      log "git not found; installing git and fetching repo..."
      apt-get install -y git
      rm -rf "$INSTALL_DIR"
      git clone --depth=1 "https://github.com/AlirezaSayyari/V2rayTGE.git" "$INSTALL_DIR"
    fi
  fi
}

install_binaries() {
  log "Installing CLI binaries..."
  install -m 0755 "$INSTALL_DIR/tge/bin/tge"             "$BIN_DIR/tge"
  install -m 0755 "$INSTALL_DIR/tge/bin/tge-config"      "$BIN_DIR/tge-config"
  install -m 0755 "$INSTALL_DIR/tge/bin/tge-apply"       "$BIN_DIR/tge-apply"
  install -m 0755 "$INSTALL_DIR/tge/bin/tge-gre-ensure"  "$BIN_DIR/tge-gre-ensure"
  install -m 0755 "$INSTALL_DIR/tge/bin/tge-health"      "$BIN_DIR/tge-health"
  install -m 0755 "$INSTALL_DIR/tge/bin/tge-logs"        "$BIN_DIR/tge-logs"
  install -m 0644 "$INSTALL_DIR/tge/bin/tge-lib.sh"      "$ETC_DIR/tge-lib.sh"
  install -m 0755 "$INSTALL_DIR/tge/bin/tge-ctl"         "$BIN_DIR/tge-ctl"
}

install_systemd() {
  log "Installing systemd units..."
  install -m 0644 "$INSTALL_DIR/tge/systemd/tge-gre.service"   "$SYSTEMD_DIR/tge-gre.service"
  install -m 0644 "$INSTALL_DIR/tge/systemd/tge-apply.service" "$SYSTEMD_DIR/tge-apply.service"
  install -m 0644 "$INSTALL_DIR/tge/systemd/tge-apply.path"    "$SYSTEMD_DIR/tge-apply.path"
  install -m 0644 "$INSTALL_DIR/tge/systemd/tge-apply.timer"   "$SYSTEMD_DIR/tge-apply.timer"
  systemctl daemon-reload
}

install_docker_compose() {
  log "Installing docker-compose..."
  mkdir -p "$ETC_DIR/docker"
  install -m 0644 "$INSTALL_DIR/tge/docker/docker-compose.yml" "$ETC_DIR/docker/docker-compose.yml"
}

post_notes() {
  cat <<EOF

✅ Installed.
- CLI: tge
- Config file will be stored at: $ETC_DIR/config.env
- Logs: $LOG_DIR/

Next:
  sudo tge

EOF
}

main() {
  need_root
  ensure_dirs
  install_deps
  copy_repo_files
  install_binaries
  install_systemd
  install_docker_compose
  post_notes
}

main "$@"