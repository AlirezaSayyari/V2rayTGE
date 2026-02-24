#!/usr/bin/env bash
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/AlirezaSayyari/V2rayTGE/main"

INSTALL_DIR="/opt/tge"
BIN_DIR="/usr/local/bin"

FAST_INSTALL="${FAST_INSTALL:-0}"          # 1 = stop apt background services temporarily (opt-in)
APT_LOCK_TIMEOUT_SEC="${APT_LOCK_TIMEOUT_SEC:-1800}"
APT_LOCK_POLL_SEC="${APT_LOCK_POLL_SEC:-10}"

log(){ echo -e "\e[32m[deploy]\e[0m $*"; }
warn(){ echo -e "\e[33m[deploy][WARN]\e[0m $*"; }
err(){ echo -e "\e[31m[deploy][ERR]\e[0m $*"; }

need_root(){
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    err "Run as root (sudo)."
    exit 1
  fi
}

have_cmd(){ command -v "$1" >/dev/null 2>&1; }

# -----------------------------
# APT LOCK HANDLING (safe)
# -----------------------------
apt_locked(){
  lsof /var/lib/dpkg/lock-frontend >/dev/null 2>&1 && return 0 || true
  lsof /var/lib/dpkg/lock >/dev/null 2>&1 && return 0 || true
  lsof /var/cache/apt/archives/lock >/dev/null 2>&1 && return 0 || true
  return 1
}

show_lock_holders(){
  echo "---- lock holders (best-effort) ----"
  lsof /var/lib/dpkg/lock-frontend 2>/dev/null | sed -n '1,10p' || true
  lsof /var/lib/dpkg/lock          2>/dev/null | sed -n '1,10p' || true
  lsof /var/cache/apt/archives/lock 2>/dev/null | sed -n '1,10p' || true
  echo "-----------------------------------"
}

wait_for_apt_lock(){
  local start now elapsed
  start="$(date +%s)"

  if apt_locked; then
    warn "apt/dpkg lock detected. Waiting up to ${APT_LOCK_TIMEOUT_SEC}s (poll=${APT_LOCK_POLL_SEC}s)."
    warn "We will NOT kill processes and will NOT remove lock files."
    show_lock_holders
  fi

  while apt_locked; do
    now="$(date +%s)"
    elapsed=$((now - start))
    if (( elapsed >= APT_LOCK_TIMEOUT_SEC )); then
      err "Timed out waiting for apt/dpkg lock after ${elapsed}s."
      err "Try again later, or opt-in FAST_INSTALL=1, or increase APT_LOCK_TIMEOUT_SEC."
      show_lock_holders
      exit 50
    fi
    warn "still locked... elapsed=${elapsed}s"
    sleep "${APT_LOCK_POLL_SEC}"
  done
}

# -----------------------------
# FAST MODE (opt-in, still safe)
# -----------------------------
stop_apt_background_services(){
  [[ "$FAST_INSTALL" == "1" ]] || return 0
  warn "FAST_INSTALL=1: stopping apt background services temporarily (best-effort)."
  systemctl stop unattended-upgrades.service 2>/dev/null || true
  systemctl stop apt-daily.service 2>/dev/null || true
  systemctl stop apt-daily-upgrade.service 2>/dev/null || true
  systemctl stop packagekit.service 2>/dev/null || true
  systemctl reset-failed unattended-upgrades.service apt-daily.service apt-daily-upgrade.service packagekit.service 2>/dev/null || true
}

start_apt_background_services(){
  [[ "$FAST_INSTALL" == "1" ]] || return 0
  warn "FAST_INSTALL=1: starting apt background services back (best-effort)."
  systemctl start apt-daily.service 2>/dev/null || true
  systemctl start apt-daily-upgrade.service 2>/dev/null || true
  systemctl start unattended-upgrades.service 2>/dev/null || true
  systemctl start packagekit.service 2>/dev/null || true
}

# -----------------------------
# APT helpers (safe, no tricks)
# -----------------------------
apt_update(){
  wait_for_apt_lock
  DEBIAN_FRONTEND=noninteractive apt-get update -y
}

apt_install(){
  wait_for_apt_lock
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

# -----------------------------
# Docker strategy (avoid conflicts)
# -----------------------------
ensure_docker(){
  if have_cmd docker; then
    log "Docker already present. Skipping docker package installation (avoids containerd conflicts)."
    systemctl enable --now docker >/dev/null 2>&1 || true
    return 0
  fi

  warn "Docker not found. Will try to install Ubuntu docker.io (best-effort)."
  # If this fails due to local repo conflicts, we do NOT break; we just warn.
  if apt_install docker.io; then
    systemctl enable --now docker >/dev/null 2>&1 || true
    log "Docker installed (docker.io)."
    return 0
  else
    warn "Docker installation failed (possibly containerd/containerd.io conflict)."
    warn "We will continue installing tge, but tge requires Docker to run v2rayA."
    return 1
  fi
}

ensure_compose(){
  if have_cmd docker && docker compose version >/dev/null 2>&1; then
    log "docker compose is available."
    return 0
  fi

  warn "docker compose plugin not detected. Trying to install docker-compose-plugin (best-effort)."
  apt_install docker-compose-plugin >/dev/null 2>&1 || true

  if have_cmd docker && docker compose version >/dev/null 2>&1; then
    log "docker compose plugin installed."
  else
    warn "docker compose plugin still not available. (Not fatal for install.)"
  fi
}

# -----------------------------
# Install repo files (minimal)
# -----------------------------
install_files(){
  log "Installing V2rayTGE files..."

  mkdir -p "$INSTALL_DIR/bin"

  curl -fsSL "$REPO_RAW/tge/bin/tge" -o "$INSTALL_DIR/bin/tge"
  curl -fsSL "$REPO_RAW/tge/bin/tge-apply" -o "$INSTALL_DIR/bin/tge-apply"
  curl -fsSL "$REPO_RAW/tge/bin/tge-config" -o "$INSTALL_DIR/bin/tge-config" || true

  chmod +x "$INSTALL_DIR/bin/"*

  ln -sf "$INSTALL_DIR/bin/tge" "$BIN_DIR/tge"

  log "Installed: $BIN_DIR/tge"
}

post_notes(){
  cat <<EOF

✅ V2rayTGE deployed.

Run:
  sudo tge

Notes:
- If you hit apt/dpkg locks, deploy waits safely (no kill, no lock deletion).
- If Docker install conflicts (containerd vs containerd.io), deploy will NOT force changes.
  Install/repair Docker manually, then rerun deploy.

Optional:
  FAST_INSTALL=1      → stops apt background services temporarily (opt-in)
  APT_LOCK_TIMEOUT_SEC=5400  → longer lock wait

Examples:
  curl -fsSL $REPO_RAW/deploy.sh | sudo bash
  curl -fsSL $REPO_RAW/deploy.sh | sudo FAST_INSTALL=1 bash

EOF
}

main(){
  need_root

  stop_apt_background_services

  apt_update

  # Core deps that never cause Docker conflicts
  log "Installing base dependencies..."
  apt_install ca-certificates curl jq iproute2 iptables lsof >/dev/null

  # Docker is optional install (skip if exists)
  ensure_docker || true
  ensure_compose || true

  # Always install our files (even if docker deps failed)
  install_files

  start_apt_background_services
  post_notes
}

main "$@"