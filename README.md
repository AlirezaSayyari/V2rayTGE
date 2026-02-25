![GitHub stars](https://img.shields.io/github/stars/alirezasayyari/V2rayTGE?style=for-the-badge)
![GitHub forks](https://img.shields.io/github/forks/alirezasayyari/V2rayTGE?style=for-the-badge)
![License](https://img.shields.io/badge/license-MIT-blue?style=for-the-badge)
![Docker](https://img.shields.io/badge/docker-ready-blue?style=for-the-badge)
![Network](https://img.shields.io/badge/network-egress-orange?style=for-the-badge)

# V2rayTGE (Traffic Gateway Egress) — Production-Safe GRE → v2rayA Egress Gateway

V2rayTGE is a **production-safe** installer + CLI toolkit that turns an Ubuntu server into an **Egress Gateway**.
It receives traffic from your LAN via a **GRE tunnel** (from an edge device such as FortiGate / Router / Firewall / …)
and forwards it to the Internet through **v2rayA** by policy-routing to `tun0` (created by v2rayA running in Docker).

This project is designed for real production environments:
- **No iptables flush**
- **No ip rule flush**
- **No default route change**
- Fully **idempotent** (“ensure-only”; safe to run multiple times)
- **Self-healing** across reboot / docker restart / network restart

---

## Architecture

### Interfaces on EgressGW
- `ensXXX` : Primary NIC (management + default route stays here)
- `gre-egress` : GRE tunnel interface (to your edge device)
- `tun0` : created by v2rayA (Docker host networking)

### Traffic Flow

LAN (one or multiple CIDRs)
↓
Edge Device (any vendor)
↓  GRE tunnel
EgressGW (gre-egress)
↓  Policy Routing (table: v2ray)
tun0 (v2rayA)
↓
Internet

---


## Install (one-liner)

```bash
curl -fsSL https://raw.githubusercontent.com/AlirezaSayyari/V2rayTGE/main/deploy.sh | sudo bash
sudo tge
````

After install:

* Config: `/opt/v2raytge/config.env`
* Compose: `/opt/v2raytge/docker/docker-compose.yml`
* CLI: `/usr/local/sbin/tge`
* Logs: `/var/log/v2raytge/`

---

## Key Design Principles

### 1) We do NOT touch the system default route
Your server keeps its default route on `ensXXX`.  
V2rayTGE only:
- ensures a separate routing table (`v2ray`)
- ensures policy rules for traffic entering via `gre-egress`

### 2) Policy Routing Rules
V2rayTGE ensures these rules exist (and does not delete/flush others):
- `pref 100`: traffic **incoming on `gre-egress`** → `lookup v2ray`
- `pref 110`: helper rule for traffic involving `tun0` → `lookup v2ray`
- `pref 101`: keep GRE subnet stable in `main` (stability helper)

### 3) Forwarding + NAT
To let LAN subnets behind GRE reach the Internet via `tun0`:
- FORWARD: allow `gre-egress → tun0`
- FORWARD: allow return `tun0 → gre-egress` for `RELATED,ESTABLISHED`
- NAT: `MASQUERADE` LAN CIDRs out of `tun0`

### 4) MSS Clamp (fix “ping works but HTTPS/TLS hangs”)
A very common real-world issue:
- ICMP ping works
- HTTPS/TLS stalls after ClientHello

This is typically a **PMTU blackhole** on GRE paths:
large packets with DF=1 can’t pass a smaller MTU link.

✅ Fix used here:
- clamp MSS on **SYN** for `gre-egress → tun0` to **1436** (default),
  assuming GRE MTU **1476** (default).

Defaults:
- `GRE MTU = 1476`
- `MSS Clamp = 1436` (≈ MTU - 40)

---

## Requirements

### On EgressGW (Ubuntu)
- Ubuntu Server
- Docker + v2rayA (we deploy docker-compose)
- root access (systemd + iptables ensure)

### On the Edge Device (Any Vendor)
You must configure:
1) A GRE tunnel towards the EgressGW (wizard prints parameters)
2) Route or PBR so your LAN CIDRs are sent into the GRE tunnel

V2rayTGE is **vendor-neutral** and does not assume FortiGate.

---

## CLI Dashboard

Run:

```bash
sudo tge
```

Menu:

1. Help & Introduction
2. Configure Egress System (Wizard)
3. Activate Egress System
4. Deactivate Egress System
5. Health Check
6. Logs

---

## Configure (Wizard)

The wizard asks you step-by-step:

* primary NIC selection (used to discover local server IP)
* GRE remote IP (edge device IP)
* GRE tunnel IP/CIDR for the server (example: `10.255.255.2/30`)
* one or more LAN CIDRs (validated: correct format, no duplicates, no overlap)
* MSS clamp (validated range)
* v2rayA GUI port (default 2017)

At the end it:

* saves config to `/opt/v2raytge/config.env`
* prints the **edge device** tunnel + routing requirements
* checks whether `tun0` exists:

  * if `tun0` is missing, it will not fail—apply is deferred and auto-runs when `tun0` appears
* asks if you want to activate immediately

---

## v2rayA GUI

v2rayA runs in Docker with host networking and creates `tun0` on the host.

Default GUI:

```
http://<EgressGW-IP>:2017
```

In v2rayA:

1. Add your outbound (VLESS/VMess/…)
2. Enable it so `tun0` becomes available
3. V2rayTGE services will then apply routing/firewall rules automatically

---

## Activate / Deactivate

### Activate

From CLI menu, or:

```bash
sudo tge-apply --activate
```

Activate does:

* starts v2rayA via docker compose
* enables systemd units (GRE ensure + apply + path + timer)
* runs an immediate safe ensure pass

### Deactivate

```bash
sudo tge-apply --deactivate
```

Deactivate is safe:

* disables units
* removes only the project’s own known rules (no flush)

---

## Self-Healing (systemd)

Installed units:

* `tge-gre.service`
  Ensures GRE tunnel exists (**idempotent, no delete**)
* `tge-apply.service`
  Ensures policy routing + iptables + MSS fix (**no flush**)
* `tge-apply.path`
  Triggers apply when `tun0` appears
* `tge-apply.timer`
  Periodic safe ensure (failsafe)

So it survives:

* reboot ✅
* docker restart ✅
* network restart ✅

---

## Health Check

```bash
sudo tge-health
```

Checks:

* `gre-egress` exists
* `tun0` exists
* required `ip rule` entries exist
* `v2ray` table routes exist
* MSS clamp rule exists
* optional quick curl test from the gateway

---

## Troubleshooting

### A) Ping works, but HTTPS/TLS hangs

This is usually PMTU/MSS.

Check MSS rule:

```bash
sudo iptables-legacy -t mangle -S FORWARD | grep 'set-mss'
```

You should see something like:

```
-A FORWARD -i gre-egress -o tun0 ... -j TCPMSS --set-mss 1436
```

### B) Missing policy rules (100/110)

```bash
ip -o rule show | egrep '^(100|101|110):'
sudo systemctl restart tge-apply.service
```

### C) GRE tunnel missing

```bash
sudo systemctl status tge-gre.service --no-pager -l
ip -d tunnel show gre-egress
```

---

## Safety Notes

V2rayTGE avoids destructive operations by design:

* no `iptables -F`, no `iptables -X`
* no `ip rule flush`
* no default route changes
* ensures only the exact rules it owns

---

## Uninstall (Safe)

1. Deactivate:

```bash
sudo tge-apply --deactivate
```

2. Disable units:

```bash
sudo systemctl disable --now tge-apply.timer tge-apply.path tge-apply.service tge-gre.service
```

3. Remove files:

```bash
sudo rm -rf /opt/v2raytge /var/log/v2raytge
sudo rm -f /usr/local/sbin/tge /usr/local/sbin/tge-*
sudo rm -f /etc/systemd/system/tge-*.service /etc/systemd/system/tge-*.timer /etc/systemd/system/tge-*.path
sudo systemctl daemon-reload
```