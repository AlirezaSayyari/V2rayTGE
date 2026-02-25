#!/usr/bin/env bash
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/AlirezaSayyari/V2rayTGE/main"

INSTALL_DIR="/opt/tge"
BIN_DIR="/usr/local/bin"

FAST_INSTALL="${FAST_INSTALL:-0}"                 # 1=stop apt background services temporarily (opt-in)
APT_LOCK_TIMEOUT_SEC="${APT_LOCK_TIMEOUT_SEC:-1800}"
APT_LOCK_POLL_SEC="${APT_LOCK_POLL_SEC:-10}"

# Docker install policy:
#  - auto (default): try ubuntu docker.io, if fails -> fallback to get.docker.com
#  - ubuntu: only ubuntu repo docker.io
#  - getdocker: only get.docker.com
DOCKER_INSTALL_MODE="${DOCKER_INSTALL_MODE:-auto}"

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
      err "Try again later, or set FAST_INSTALL=1, or increase APT_LOCK_TIMEOUT_SEC."
      show_lock_holders
      exit 50
    fi
    warn "still locked... elapsed=${elapsed}s"
    sleep "${APT_LOCK_POLL_SEC}"
  done
}

# -----------------------------
# FAST MODE (opt-in)
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
# APT helpers
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
# Docker install strategies
# -----------------------------
docker_ok(){
  have_cmd docker || return 1
  docker version >/dev/null 2>&1 || return 1
  return 0
}

install_docker_ubuntu(){
  warn "Trying Docker via Ubuntu packages (docker.io)..."
  apt_install docker.io || return 1
  systemctl enable --now docker >/dev/null 2>&1 || true
  docker_ok
}

install_docker_getdocker(){
  warn "Trying Docker via get.docker.com (Docker CE)..."
  # We do not purge/remove anything. This is for fresh servers or where ubuntu install failed.
  curl -fsSL https://get.docker.com -o /tmp/install-docker.sh
  sh /tmp/install-docker.sh --dry-run >/dev/null 2>&1 || true
  sh /tmp/install-docker.sh
  systemctl enable --now docker >/dev/null 2>&1 || true
  docker_ok
}

ensure_docker(){
  if docker_ok; then
    log "Docker is already installed and working. Skipping Docker installation."
    return 0
  fi

  case "$DOCKER_INSTALL_MODE" in
    ubuntu)
      install_docker_ubuntu || return 1
      ;;
    getdocker)
      install_docker_getdocker || return 1
      ;;
    auto)
      if install_docker_ubuntu; then
        return 0
      fi
      warn "Ubuntu docker.io install failed (often containerd conflicts). Falling back to get.docker.com..."
      install_docker_getdocker || return 1
      ;;
    *)
      err "Unknown DOCKER_INSTALL_MODE=$DOCKER_INSTALL_MODE (use: auto|ubuntu|getdocker)"
      return 1
      ;;
  esac
}

ensure_compose(){
  if docker_ok && docker compose version >/dev/null 2>&1; then
    log "docker compose is available."
    return 0
  fi

  warn "docker compose not detected. Trying to install docker-compose-plugin (best-effort)."
  apt_install docker-compose-plugin >/dev/null 2>&1 || true

  if docker_ok && docker compose version >/dev/null 2>&1; then
    log "docker compose plugin installed."
  else
    warn "docker compose still not available. (Not fatal for deploy.)"
  fi
}

# -----------------------------
# Install our files (always)
# -----------------------------
install_files(){
  log "Installing V2rayTGE files..."

  mkdir -p /opt/tge/bin
  mkdir -p /usr/local/sbin
  mkdir -p /opt/v2raytge

  # Download full set
  curl -fsSL "$REPO_RAW/tge/bin/tge"        -o /opt/tge/bin/tge
  curl -fsSL "$REPO_RAW/tge/bin/tge-config" -o /opt/tge/bin/tge-config
  curl -fsSL "$REPO_RAW/tge/bin/tge-apply"  -o /opt/tge/bin/tge-apply
  curl -fsSL "$REPO_RAW/tge/bin/tge-lib.sh" -o /opt/tge/bin/tge-lib.sh

  chmod +x /opt/tge/bin/tge /opt/tge/bin/tge-config /opt/tge/bin/tge-apply

  # Install to standard locations
  install -m 0755 /opt/tge/bin/tge        /usr/local/bin/tge
  install -m 0755 /opt/tge/bin/tge-config /usr/local/sbin/tge-config
  install -m 0755 /opt/tge/bin/tge-apply  /usr/local/sbin/tge-apply
  install -m 0644 /opt/tge/bin/tge-lib.sh /opt/v2raytge/tge-lib.sh

  log "Installed:"
  log "  /usr/local/bin/tge"
  log "  /usr/local/sbin/tge-config"
  log "  /usr/local/sbin/tge-apply"
  log "  /opt/v2raytge/tge-lib.sh"
}

post_notes(){
  cat <<EOF

✅ V2rayTGE deployed.

Run:
  sudo tge

Docker install behavior:
- If Docker exists & works → deploy will NOT touch Docker.
- If Docker is missing:
    DOCKER_INSTALL_MODE=auto    → try Ubuntu docker.io then fallback to get.docker.com
    DOCKER_INSTALL_MODE=ubuntu  → only Ubuntu docker.io
    DOCKER_INSTALL_MODE=getdocker → only get.docker.com

Examples:
  curl -fsSL $REPO_RAW/deploy.sh | sudo bash
  curl -fsSL $REPO_RAW/deploy.sh | sudo FAST_INSTALL=1 bash
  curl -fsSL $REPO_RAW/deploy.sh | sudo DOCKER_INSTALL_MODE=getdocker bash

EOF
}

main(){
  need_root

  stop_apt_background_services

  apt_update
  log "Installing base dependencies..."
  apt_install ca-certificates curl jq iproute2 iptables lsof >/dev/null

  # Docker may be needed for v2rayA; try to ensure it.
  if ensure_docker; then
    ensure_compose || true
  else
    warn "Docker is not available. You can install Docker manually then rerun deploy."
  fi

  # Always install tge CLI
  install_files

  start_apt_background_services
  post_notes
}

main "$@"