#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/v2raytge"
ETC_DIR="/etc/v2raytge"
BIN_DIR="/usr/local/sbin"
SYSTEMD_DIR="/etc/systemd/system"
LOG_DIR="/var/log/v2raytge"

# ---- lock handling config ----
APT_LOCK_TIMEOUT_SEC="${APT_LOCK_TIMEOUT_SEC:-1800}"   # 30 minutes
APT_LOCK_POLL_SEC="${APT_LOCK_POLL_SEC:-10}"          # poll interval
APT_LOCK_SHOW_WHO="${APT_LOCK_SHOW_WHO:-1}"           # 1=show locking process
# --------------------------------

log(){ echo "[deploy] $*"; }
warn(){ echo "[deploy][WARN] $*" >&2; }
err(){ echo "[deploy][ERROR] $*" >&2; }

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    err "Run as root (sudo)."
    exit 1
  fi
}

have_cmd(){ command -v "$1" >/dev/null 2>&1; }

# Return 0 if dpkg/apt is locked by another process, 1 otherwise
is_apt_locked() {
  # If lock files are open by some process -> locked
  if lsof /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
    return 0
  fi
  if lsof /var/lib/dpkg/lock >/dev/null 2>&1; then
    return 0
  fi
  if lsof /var/cache/apt/archives/lock >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

show_lock_holders() {
  echo "---- lock holders (best-effort) ----"
  lsof /var/lib/dpkg/lock-frontend 2>/dev/null | sed -n '1,10p' || true
  lsof /var/lib/dpkg/lock          2>/dev/null | sed -n '1,10p' || true
  lsof /var/cache/apt/archives/lock 2>/dev/null | sed -n '1,10p' || true
  echo "-----------------------------------"
}

wait_for_apt_lock() {
  local timeout="$APT_LOCK_TIMEOUT_SEC"
  local poll="$APT_LOCK_POLL_SEC"
  local start now elapsed

  start="$(date +%s)"
  if is_apt_locked; then
    warn "apt/dpkg lock detected. Will wait up to ${timeout}s (poll=${poll}s)."
    warn "This is usually unattended-upgrades/apt-daily. We will NOT kill anything."

    if [[ "$APT_LOCK_SHOW_WHO" == "1" ]]; then
      show_lock_holders
    fi
  fi

  while is_apt_locked; do
    now="$(date +%s)"
    elapsed=$((now - start))
    if (( elapsed >= timeout )); then
      err "Timed out waiting for apt/dpkg lock after ${elapsed}s."
      err "Safe exit (no changes). Try again later or increase APT_LOCK_TIMEOUT_SEC."
      if [[ "$APT_LOCK_SHOW_WHO" == "1" ]]; then
        show_lock_holders
      fi
      exit 50
    fi

    # Print periodic status
    warn "Still locked... elapsed=${elapsed}s (waiting)"
    sleep "$poll"
  done

  if (( $(date +%s) - start > 0 )); then
    log "apt/dpkg lock is free. Continuing."
  fi
}

# If dpkg is mid-transaction, configure pending packages (safe)
dpkg_sanity_repair() {
  # Only run if dpkg looks interrupted.
  # We avoid running it while locked.
  wait_for_apt_lock

  # If dpkg is in a bad state, these are standard safe recovery steps.
  log "dpkg sanity check..."
  if dpkg --audit 2>/dev/null | grep -q .; then
    warn "dpkg reports pending/half-installed packages. Running safe repair: dpkg --configure -a"
    dpkg --configure -a
  fi
}

apt_install() {
  wait_for_apt_lock
  DEBIAN_FRONTEND=noninteractive apt-get update -y
  wait_for_apt_lock
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

ensure_dirs() {
  mkdir -p "$INSTALL_DIR" "$ETC_DIR" "$LOG_DIR" "$ETC_DIR/docker"
}

copy_repo_files() {
  # Option A: running from local repo folder
  if [[ -d "./tge" && -f "./tge/bin/tge" ]]; then
    log "Local repo detected; copying into $INSTALL_DIR..."
    rsync -a --delete ./ "$INSTALL_DIR/"
    return 0
  fi

  # Option B: running via curl -> must clone repo
  if ! have_cmd git; then
    log "git not found; installing git..."
    apt_install git
  fi

  if [[ -d "$INSTALL_DIR/.git" ]]; then
    log "Updating existing clone in $INSTALL_DIR..."
    (cd "$INSTALL_DIR" && git pull --ff-only) || true
  else
    log "Cloning repo into $INSTALL_DIR..."
    rm -rf "$INSTALL_DIR"
    git clone --depth=1 "https://github.com/AlirezaSayyari/V2rayTGE.git" "$INSTALL_DIR"
  fi
}

install_deps() {
  log "Installing dependencies..."

  # ensure dpkg is not broken before starting
  dpkg_sanity_repair

  apt_install ca-certificates curl jq python3 iproute2 iptables rsync

  if ! have_cmd docker; then
    log "Docker not found; installing docker.io..."
    apt_install docker.io
  fi
  systemctl enable --now docker || true

  # docker compose plugin (best effort)
  if ! docker compose version >/dev/null 2>&1; then
    log "docker compose plugin not found; installing docker-compose-plugin..."
    # Some repos may not have it; try best-effort
    wait_for_apt_lock
    DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose-plugin || true
  fi
}

install_binaries() {
  log "Installing CLI binaries to $BIN_DIR..."
  install -m 0755 "$INSTALL_DIR/tge/bin/tge"            "$BIN_DIR/tge"
  install -m 0755 "$INSTALL_DIR/tge/bin/tge-config"     "$BIN_DIR/tge-config"
  install -m 0755 "$INSTALL_DIR/tge/bin/tge-apply"      "$BIN_DIR/tge-apply"
  install -m 0755 "$INSTALL_DIR/tge/bin/tge-ctl"        "$BIN_DIR/tge-ctl"
  install -m 0755 "$INSTALL_DIR/tge/bin/tge-gre-ensure" "$BIN_DIR/tge-gre-ensure"
  install -m 0755 "$INSTALL_DIR/tge/bin/tge-health"     "$BIN_DIR/tge-health"
  install -m 0755 "$INSTALL_DIR/tge/bin/tge-logs"       "$BIN_DIR/tge-logs"
  install -m 0644 "$INSTALL_DIR/tge/bin/tge-lib.sh"     "$ETC_DIR/tge-lib.sh"
}

install_systemd() {
  log "Installing systemd units..."
  install -m 0644 "$INSTALL_DIR/tge/systemd/tge-gre.service"   "$SYSTEMD_DIR/tge-gre.service"
  install -m 0644 "$INSTALL_DIR/tge/systemd/tge-apply.service" "$SYSTEMD_DIR/tge-apply.service"
  install -m 0644 "$INSTALL_DIR/tge/systemd/tge-apply.path"    "$SYSTEMD_DIR/tge-apply.path"
  install -m 0644 "$INSTALL_DIR/tge/systemd/tge-apply.timer"   "$SYSTEMD_DIR/tge-apply.timer"
  systemctl daemon-reload
}

install_compose() {
  log "Installing docker-compose.yml..."
  install -m 0644 "$INSTALL_DIR/tge/docker/docker-compose.yml" "$ETC_DIR/docker/docker-compose.yml"
}

post_notes() {
  cat <<EOF

✅ Installed V2rayTGE.

Run:
  sudo tge

Config:
  $ETC_DIR/config.env

Compose:
  $ETC_DIR/docker/docker-compose.yml

Logs:
  $LOG_DIR/

Lock handling:
  - waits for apt/dpkg locks (unattended-upgrades) up to ${APT_LOCK_TIMEOUT_SEC}s
  - no killing processes, no deleting lock files

EOF
}

main() {
  need_root
  ensure_dirs

  # Wait if system is mid-upgrade (avoid dpkg lock error)
  wait_for_apt_lock

  install_deps
  copy_repo_files
  install_binaries
  install_systemd
  install_compose
  post_notes
}

main "$@"