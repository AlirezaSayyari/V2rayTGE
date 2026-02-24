![GitHub stars](https://img.shields.io/github/stars/alirezasayyari/V2rayTGE?style=for-the-badge)
![GitHub forks](https://img.shields.io/github/forks/alirezasayyari/V2rayTGE?style=for-the-badge)
![License](https://img.shields.io/badge/license-MIT-blue?style=for-the-badge)
![Docker](https://img.shields.io/badge/docker-ready-blue?style=for-the-badge)
![Network](https://img.shields.io/badge/network-egress-orange?style=for-the-badge)

# 🚀 V2rayTGE — Turn Any Linux Server Into a Smart Egress Gateway

> A production-ready, **GRE + Policy Routing + v2rayA** egress system  
> deployable with **one curl command**.

---

## ✨ Why this project exists (The Story)

In many enterprise networks, routing outbound traffic through a secure and controlled path is not optional — it's required.

Sometimes you need:
- selective internet egress
- bypass paths for specific VLANs
- encrypted tunnels
- or simply **control over where traffic exits**

After building multiple real-world enterprise networks with:
- FortiGate
- Cisco
- MikroTik
- custom GRE tunnels
- and Docker-based proxy gateways

this project was born.

---

## ⚡ One-Line Install

bash
curl -fsSL https://raw.githubusercontent.com/alirezasayyari/V2rayTGE/main/deploy.sh | sudo bash
sudo egressctl


That's it.



**V2rayTGE** is not just another proxy script.  
It's a **network architecture component**.

It turns a Linux server into:

> 🧠 A controlled egress brain for your network.

---

## 🧩 Architecture Overview

mermaid
flowchart LR
    A[LAN Clients]
    B[Edge Device<br>Router/Firewall]
    C[GRE Tunnel]
    D[Linux Egress Gateway]
    E[v2rayA tun0]
    F[Internet]

    A --> B
    B --> C
    C --> D
    D --> E
    E --> F



Clients LAN
↓
Edge Device (router/firewall)
↓ GRE Tunnel
Linux Egress Server (this repo)
↓
v2rayA (TUN mode)
↓
Internet



This project handles:

- GRE tunnel termination
- Policy-based routing (PBR)
- MSS clamp handling
- Dockerized v2rayA
- health checks
- CLI dashboard
- idempotent routing apply


## 🖥 CLI Dashboard

After install:

bash
sudo egressctl

Menu:

1) Help & Introduction
2) Config Egress System
3) Activate/Deactivate
4) Health Check
5) Logs

---

## 🔧 What the Config Wizard asks

You will be guided step-by-step:

* Primary NIC
* GRE remote public IP
* GRE tunnel IP
* LAN CIDRs (multi)
* MSS clamp
* v2rayA GUI port

Everything validated:

* CIDR overlap
* private ranges
* syntax
* duplicates

---

## 🌐 Edge Device (Router/Firewall) Setup

Works with **any device**:

* FortiGate
* MikroTik
* Cisco
* Linux router
* cloud firewall

You just need:

### 1️⃣ GRE tunnel

Create GRE tunnel to Linux server public IP.

### 2️⃣ Tunnel IPs

Example:

Linux: 10.255.255.2/30
Router: 10.255.255.1/30

### 3️⃣ Policy Route

Route selected LAN CIDRs into GRE.

### 4️⃣ Allow GRE protocol

Protocol 47 between endpoints.

The CLI wizard prints a ready-to-use summary.

---

## 🧠 v2rayA Setup

Open GUI:

http://SERVER-IP:2017

Then:

1. Import config
2. Enable **TUN mode**
3. Start profile

When `tun0` appears → routing auto-applies.

---

## 🛡 Safety Design

No dangerous:

* iptables flush
* routing wipe
* destructive changes

Everything:

* idempotent
* safe apply
* tun0 aware
* systemd controlled

---

## 📊 Health Check

sudo egressctl → Health Check

Shows:

* GRE status
* tun0
* PBR table
* docker
* rules
* logs

---

## 🏗 Real Use Cases

* enterprise controlled egress
* branch office routing
* selective proxy networks
* dev/test isolated internet
* multi-site GRE overlay
* cloud exit node
* secure research network

---

## 🧭 Philosophy

This repo is designed for:

> Network engineers
> DevOps architects
> CTOs building real infrastructure

Not just home users.

---

## 🛠 Future roadmap

* multi-tunnel support
* HA mode
* metrics exporter
* web status page
* config backup/restore
* cluster mode

---

## 🤝 Contributing

PRs welcome.

---

## 🧑‍💻 Author

Built from real production experience
in enterprise networks and fintech infrastructure.

---

## ⭐ If this helps your network

Give it a star.
It helps the project grow.