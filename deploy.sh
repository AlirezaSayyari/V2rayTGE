#!/usr/bin/env bash
set -euo pipefail

REPO="https://raw.githubusercontent.com/AlirezaSayyari/V2rayTGE/main"
INSTALL_DIR="/opt/tge"
BIN_DIR="/usr/local/bin"

FAST_INSTALL="${FAST_INSTALL:-0}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-1800}"
WAIT_INTERVAL=10

log(){ echo -e "\e[32m[deploy]\e[0m $*"; }
warn(){ echo -e "\e[33m[deploy][WARN]\e[0m $*"; }
err(){ echo -e "\e[31m[deploy][ERR]\e[0m $*"; }

need_root(){
  if [[ $EUID -ne 0 ]]; then
    err "Run as root"
    exit 1
  fi
}

# -----------------------------
# APT LOCK HANDLING
# -----------------------------
apt_locked(){
  lsof /var/lib/dpkg/lock-frontend >/dev/null 2>&1 && return 0 || true
  lsof /var/lib/dpkg/lock >/dev/null 2>&1 && return 0 || true
  return 1
}

show_lock_holder(){
  echo "---- lock holders ----"
  lsof /var/lib/dpkg/lock-frontend 2>/dev/null || true
  lsof /var/lib/dpkg/lock 2>/dev/null || true
  echo "----------------------"
}

wait_for_lock(){
  local elapsed=0
  if ! apt_locked; then
    return
  fi

  warn "apt lock detected. waiting (timeout=${WAIT_TIMEOUT}s)"
  show_lock_holder

  while apt_locked; do
    sleep "$WAIT_INTERVAL"
    elapsed=$((elapsed+WAIT_INTERVAL))

    if (( elapsed > WAIT_TIMEOUT )); then
      err "Timeout waiting for apt lock."
      err "You can retry with FAST_INSTALL=1"
      exit 1
    fi

    warn "still locked... ${elapsed}s"
  done

  log "apt lock cleared."
}

# -----------------------------
# FAST MODE (opt-in)
# -----------------------------
stop_apt_services(){
  [[ "$FAST_INSTALL" == "1" ]] || return 0
  warn "FAST_INSTALL=1 → stopping apt background services"

  systemctl stop unattended-upgrades.service 2>/dev/null || true
  systemctl stop apt-daily.service 2>/dev/null || true
  systemctl stop apt-daily-upgrade.service 2>/dev/null || true
  systemctl stop packagekit.service 2>/dev/null || true
  systemctl reset-failed unattended-upgrades.service 2>/dev/null || true
}

start_apt_services(){
  [[ "$FAST_INSTALL" == "1" ]] || return 0
  warn "Restarting apt background services"

  systemctl start apt-daily.service 2>/dev/null || true
  systemctl start apt-daily-upgrade.service 2>/dev/null || true
  systemctl start unattended-upgrades.service 2>/dev/null || true
  systemctl start packagekit.service 2>/dev/null || true
}

# -----------------------------
# INSTALL
# -----------------------------
install_deps(){
  log "Installing dependencies..."
  apt-get update -y
  apt-get install -y docker.io docker-compose curl iproute2 iptables
}

install_repo(){
  log "Installing files..."

  mkdir -p "$INSTALL_DIR/bin"
  mkdir -p "$INSTALL_DIR/systemd"
  mkdir -p "$INSTALL_DIR/config"

  curl -fsSL "$REPO/tge/bin/tge" -o "$INSTALL_DIR/bin/tge"
  curl -fsSL "$REPO/tge/bin/tge-apply" -o "$INSTALL_DIR/bin/tge-apply"

  chmod +x "$INSTALL_DIR/bin/"*

  ln -sf "$INSTALL_DIR/bin/tge" "$BIN_DIR/tge"
}

# -----------------------------
# MAIN
# -----------------------------
main(){
  need_root

  stop_apt_services
  wait_for_lock
  install_deps
  install_repo
  start_apt_services

  log "Install complete."
  echo
  echo "Run:"
  echo "  sudo tge"
}

main "$@"