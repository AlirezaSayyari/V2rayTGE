#!/usr/bin/env bash

need_root(){ [[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "ERROR: sudo required"; exit 1; }; }

have_cmd(){ command -v "$1" >/dev/null 2>&1; }

guess_primary_nic(){
  ip route show default 0.0.0.0/0 2>/dev/null | awk '/default/{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1
}

validate_iface_exists(){
  ip link show "$1" >/dev/null 2>&1 || { echo "ERROR: interface not found: $1"; exit 1; }
}

iface_ipv4(){
  ip -4 -o addr show dev "$1" | awk '{print $4}' | cut -d/ -f1 | head -n1
}

validate_ipv4(){
  python3 - "$1" <<'PY'
import ipaddress,sys
try:
  ipaddress.IPv4Address(sys.argv[1])
except Exception:
  print("ERROR: invalid IPv4:", sys.argv[1])
  sys.exit(1)
PY
}

validate_cidr(){
  python3 - "$1" <<'PY'
import ipaddress,sys
try:
  ipaddress.ip_network(sys.argv[1], strict=False)
except Exception:
  print("ERROR: invalid CIDR:", sys.argv[1])
  sys.exit(1)
PY
}

validate_no_overlap(){
  python3 - "$@" <<'PY'
import ipaddress,sys
nets=[]
for s in sys.argv[1:]:
  n=ipaddress.ip_network(s, strict=False)
  for x in nets:
    if n.overlaps(x):
      print(f"ERROR: overlap detected: {n} overlaps {x}")
      sys.exit(1)
  nets.append(n)
print("OK")
PY
}

validate_int_range(){
  local v="$1" min="$2" max="$3"
  [[ "$v" =~ ^[0-9]+$ ]] || { echo "ERROR: not integer: $v"; exit 1; }
  (( v >= min && v <= max )) || { echo "ERROR: out of range [$min..$max]: $v"; exit 1; }
}

join_by_comma(){
  local IFS=,
  echo "$*"
}

ensure_rt_table(){
  local id="$1" name="$2"
  grep -qE "^[[:space:]]*${id}[[:space:]]+${name}[[:space:]]*$" /etc/iproute2/rt_tables || echo "${id} ${name}" >> /etc/iproute2/rt_tables
}

# robust pref check using ip -o output
ensure_rule_pref(){
  local pref="$1"; shift
  local want_regex="$1"; shift
  local add_cmd=("$@")
  local line
  line="$(ip -o rule show 2>/dev/null | awk -v p="${pref}:" '$1==p{print; exit}')"
  if [[ -z "$line" ]]; then
    "${add_cmd[@]}"
    return 0
  fi
  echo "$line" | grep -qE "$want_regex" && return 0
  echo "[WARN] pref $pref exists but differs; not modifying. line=[$line]"
  return 0
}

iptables_legacy_ensure(){
  local table="$1" chain="$2"
  shift 2
  local spec="$*"
  iptables-legacy -t "$table" -C "$chain" $spec 2>/dev/null || iptables-legacy -t "$table" -A "$chain" $spec
}

# Insert MSS fix as first rule only if missing
iptables_legacy_ensure_mangle_insert_first(){
  local in_if="$1" out_if="$2" mss="$3"
  if ! iptables-legacy -t mangle -C FORWARD -i "$in_if" -o "$out_if" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss "$mss" 2>/dev/null; then
    iptables-legacy -t mangle -I FORWARD 1 -i "$in_if" -o "$out_if" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss "$mss"
  fi
}

# Safe delete helpers (NO flush)
safe_ip_rule_del(){
  local pref="$1" match="$2"
  local line
  line="$(ip -o rule show 2>/dev/null | awk -v p="${pref}:" '$1==p{print; exit}')"
  [[ -z "$line" ]] && return 0
  echo "$line" | grep -q "$match" || return 0
  ip rule del pref "$pref" || true
}

safe_ip_route_del_table(){
  local table="$1"; shift
  local spec="$*"
  ip route del table "$table" $spec 2>/dev/null || true
}

safe_iptables_del_nat(){
  local cidr="$1" outif="$2"
  iptables-legacy -t nat -D POSTROUTING -s "$cidr" -o "$outif" -j MASQUERADE 2>/dev/null || true
}

safe_iptables_del_forward(){
  local gre="$1" tun="$2"
  iptables-legacy -D FORWARD -i "$gre" -o "$tun" -j ACCEPT 2>/dev/null || true
  iptables-legacy -D FORWARD -i "$tun" -o "$gre" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
}

safe_iptables_del_mss(){
  local gre="$1" tun="$2" mss="$3"
  iptables-legacy -t mangle -D FORWARD -i "$gre" -o "$tun" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss "$mss" 2>/dev/null || true
}