# 🇵🇭 Anti-Censorship Discord & Community Gateway (PH ISP Bypass)

A high-performance, open-source routing gateway built to bypass Discord voice/RTC drops, streaming issues, and online censorship implemented by Philippine telecommunications providers (**Globe**, **PLDT / Smart**, **Converge ICT**, and **DITO**).

---

## ⚡ Which Setup Should You Use?

This repository supports two production deployment architectures depending on your hardware:

| Feature | 🌟 Option A: Laptop-Powered Reverse Tunnel (Recommended) | ☁️ Option B: Direct VPS Gateway |
| :--- | :--- | :--- |
| **Directory** | [`marzban-wsl/`](file:///home/pheinz/discord-gateway/marzban-wsl) (Windows 11 + WSL 2) or [`reverse-tunnel/`](file:///home/pheinz/discord-gateway/reverse-tunnel) | Root directory (`/`) |
| **User Experience** | **Sleek Web Admin Panel (Marzban)** with user accounts, QR codes, and 1-click links | WireGuard `.conf` configuration files |
| **VPS Requirement** | Cheaper is fine ($3.50/mo 512MB RAM VPS) | Needs enough RAM/CPU if many friends join |
| **Laptop Requirement**| Laptop stays on when friends are connected | Laptop can be turned off (100% in cloud) |
| **Multi-User Sharing**| Friends import single `vless://` link into **v2rayNG** / **FoXray** (no WireGuard keys needed) | Each friend needs a dedicated WireGuard key pair |
| **Local Telco Bypass**| **100% Bypassed**: Laptop resolves queries via Cloudflare DoH (1.1.1.1) | **100% Bypassed**: Traffic routed via Singapore VPS |
### 📖 Step-by-Step Setup Guides by OS:
- 🪟 [**Windows 11 Pro Guide**](WINDOWS.md) — WSL 2 Ubuntu + Mirrored Networking + Marzban Web UI
- 🐧 [**Linux Guide**](LINUX.md) — Native Docker + systemd-logind + zero virtualization overhead
- 🍎 [**macOS Guide**](MACOS.md) — Apple Silicon / Intel + OrbStack + pmset sleep prevention

---

## 🚀 Deploy Your Own Gateway (Anyone Can Become a Host!)

This project is open-source so that **any IT student, graduate, gamer, or community member can host their own gateway** for their friends, school, or gaming clan.

You don't need expensive infrastructure. A basic $3.50/mo Singapore VPS (or free cloud credits from the [GitHub Student Developer Pack](https://education.github.com/pack)) plus your home PC/laptop is all it takes!

### ⚡ 1-Minute Interactive Quickstart:
Clone the repository and run our setup wizard on any machine:
```bash
git clone https://github.com/Reneilrp/discord-gateway.git
cd discord-gateway
./quickstart.sh
```
The wizard will detect your operating system (Windows/Linux/Mac/VPS) and guide you step-by-step through configuring your forwarder or launching the Marzban web UI.

---

## 🎯 The Host Checklist: What Is Left For You To Do?

All configuration files, Docker Compose definitions, automation scripts, and Windows power policies are fully written and verified in this repository.

Here is the exact step-by-step checklist of what is left for **you** to perform:

```
[ ] 1. Obtain a Singapore VPS ($3.50 - $5/month on DigitalOcean, Linode, Vultr, or Hetzner).
        Why Singapore? It delivers the lowest latency from the Philippines (~25-35 ms).

[ ] 2. On the VPS: Run the forwarder script:
        sudo ./marzban-wsl/vps/setup-vps-marzban-forwarder.sh
        (Enables IP forwarding and forwards Port 443 down the tunnel).

[ ] 3. On Your Laptop / Home Server:
        - If Windows 11 Pro:
            • Copy .wslconfig to C:\Users\<YourUsername>\.wslconfig & wsl --shutdown
            • Run windows-power-settings.bat as Admin (prevents laptop sleep on lid close)
            • Activate WireGuard for Windows (IP: 10.0.0.2/24, PersistentKeepalive = 25)
            • In WSL 2: cd marzban-wsl && ./setup-marzban.sh
        - If Linux (Ubuntu / Debian / Arch / Fedora):
            • Run: sudo ./host-os/linux/linux-server-prep.sh (disables lid sleep & enables forwarding)
            • Start WireGuard: sudo wg-quick up wg0
            • Start Marzban natively: cd marzban-wsl && ./setup-marzban.sh
        - If macOS (MacBook):
            • Run: ./host-os/macos/macos-server-prep.sh (sets pmset sleep prevention)
            • Activate WireGuard for Mac app (App Store or Homebrew)
            • Start Marzban: cd marzban-wsl && docker compose up -d

[ ] 4. In Browser: Access http://127.0.0.1:8000/dashboard/
        - Click "Users" -> "Create User" (e.g. friend_name).
        - Copy the vless:// link or QR code and send it to your friend!
```

---

## 🌐 Shared Community Hub (1 VPS, Multiple Laptops)

**What if a friend or community member wants to host for their squad using their laptop, but DOES NOT want to buy or configure a VPS?**

A single $3.50/mo Singapore VPS can act as a **Shared Community Hub** for multiple laptops across the Philippines:
- **You (The Hub Owner)**: Run the Singapore VPS.
- **Your Friend (Laptop Node Host)**: Connects their laptop (in Cebu, Davao, Manila, etc.) to your VPS without paying for cloud servers or configuring complex Linux firewalls.
- **Their Friends**: Connect to `YOUR_VPS_IP:<THEIR_PORT>` (e.g. port `8443`). The VPS forwards traffic directly to *their* laptop using *their* home internet!

### How to add a friend's laptop to your VPS Hub:
On your VPS, run:
```bash
sudo ./marzban-wsl/vps/add-laptop-node.sh --name "friend_laptop" --port 8443
```
1. Automatically assigns an internal tunnel IP (e.g. `10.0.0.3`) and configures `iptables` to forward public port `8443` -> `10.0.0.3:443`.
2. Generates a client configuration block for your friend's laptop.
3. Your friend imports it into WireGuard, launches Marzban ([`marzban-wsl/`](file:///home/pheinz/discord-gateway/marzban-wsl)), and their squad connects through `YOUR_VPS_IP:8443`!

---

## 📁 Repository Structure

```
.
├── marzban-wsl/                     # [RECOMMENDED] Web UI Stack (WSL 2 / Native Docker)
│   ├── docker-compose.yml           # Marzban & Xray-core container definition
│   ├── setup-marzban.sh             # 1-click installer and admin creator
│   ├── windows/                     # Windows 11 power policies & .wslconfig
│   ├── vps/                         # VPS port 443 forwarder script
│   └── README.md                    # Detailed Marzban deployment guide
│
├── host-os/                         # Multi-OS Host Setup Scripts
│   ├── linux/                       # Linux laptop prep (systemd-logind lid ignore, wg-quick)
│   └── macos/                       # macOS MacBook prep (pmset sleep prevention, OrbStack)
│
├── reverse-tunnel/                  # Pure Docker / Linux Laptop Reverse Tunnel (Headless)
│   ├── docker-compose.yml           # Xray-core container
│   ├── config/config.json           # VLESS, WebSocket, SOCKS5, and DoH routing
│   ├── generate-client-links.sh     # Generates vless:// URLs from terminal
│   └── README.md                    # Headless reverse tunnel guide
│
├── fetch-service-cidrs.sh           # Modular BGP CIDR fetcher (Discord, Reddit, Meta/Facebook)
├── fetch-discord-cidrs.sh           # Legacy AS49544 (Discord Inc.) BGP fetcher
├── iptables-rules.sh                # Direct VPS firewall script (service lockdown)
├── docker-compose.yml               # Standalone VPS wg-easy container
├── sysctl.d/99-wireguard.conf       # Kernel parameters for IP forwarding & UDP buffers
├── scripts/
│   ├── toggle-services.sh           # Interactive CLI to toggle Discord / Reddit / Facebook
│   ├── update-discord-gateway.sh    # Weekly cron helper for zero-downtime BGP prefix updates
│   └── test-suite.sh                # Automated repository verification test suite
├── WINDOWS.md                       # 🪟 Windows 11 Pro + WSL 2 + Marzban Guide
├── LINUX.md                         # 🐧 Native Linux (Ubuntu/Debian/Fedora/Arch) Guide
├── MACOS.md                         # 🍎 macOS (Apple Silicon M1-M4 & Intel) Guide
├── CONTRIBUTING.md                  # Contributor portal & roadmap for PH programmers
└── README.md                        # Master project guide (this document)
```

---

## 🎛️ Service Toggling (Discord, Reddit, Facebook)

You are not locked into bypassing only Discord. You can choose to bypass **Discord**, **Reddit**, **Facebook (Meta / IG / Messenger)**, or any combination using our built-in toggle tool:

```bash
# Interactive selection menu:
./scripts/toggle-services.sh

# Or via command-line flags:
./scripts/toggle-services.sh --services discord              # Discord only
./scripts/toggle-services.sh --services discord,reddit       # Discord + Reddit
./scripts/toggle-services.sh --services facebook             # Meta / Facebook only
./scripts/toggle-services.sh --services all                  # All 3 platforms
```

### What this tool updates automatically:
1. **WireGuard AllowedIPs**: Updates `.env` (`WG_ALLOWED_IPS`) and exports to `service-cidrs.txt`.
2. **Xray-Core / Marzban Domain Rules**: Updates `geosite:discord`, `geosite:reddit`, and `geosite:facebook` routing rules in `config.json`.
3. **Firewall Lockdown**: Updates the VPS `ipset` table when `--apply-firewall` is passed.

---

## 📱 Per-App Proxying on Friends' Phones

Your friends can also decide *on their own devices* which apps route through your gateway!
- **Android ([v2rayNG](https://play.google.com/store/apps/details?id=com.v2ray.ang))**:
  Open Settings -> **Per-app proxy mode** -> Enable -> Check **Discord**, **Reddit**, and **Facebook**. All other phone traffic stays on their local connection!
- **Windows / Mac ([Nekoray](https://github.com/MatsuriDayo/nekoray))**:
  In Routing Settings, traffic can be filtered per process name (e.g. `Discord.exe`).


---

## 🛠️ Philippine ISP Quirks & Technical Optimizations

### 1. Carrier-Grade NAT (CGNAT)
Most residential connections in the Philippines (Globe Fiber, PLDT Home Fibr) operate behind CGNAT, meaning your home router does not have a public IPv4 address.
- **How we solve it**: The laptop initiates an *outbound* WireGuard tunnel to the VPS with `PersistentKeepalive = 25`. Your router's NAT table stays permanently open, allowing the VPS to push your friends' incoming connections straight into your laptop without requiring port forwarding on your home modem!

### 2. MTU Size (Fragmented Voice Packets)
Philippine mobile data (Smart 5G, Globe LTE) and some PPPoE fiber connections encapsulate packets with extra headers. Standard `1500` MTU can cause silent voice packet drops in Discord WebRTC.
- **Recommended MTU**: `1280` (safe minimum for IPv6/IPv4) or `1360` (optimal for WireGuard over PPPoE).

### 3. DNS Poisoning & SNI Throttling
Philippine telcos inject forged DNS responses for blocked or throttled domains.
- **How we solve it**: In [config.json](file:///home/pheinz/discord-gateway/reverse-tunnel/laptop/config/config.json) and [marzban-wsl](file:///home/pheinz/discord-gateway/marzban-wsl), all outbound DNS lookups are strictly routed through **Cloudflare DNS-over-HTTPS (DoH)** at `https+local://1.1.1.1/dns-query`, bypassing local ISP DNS tampering entirely.

---

## ⚙️ VPS Sysctl Kernel Parameters (For Option B: Standalone WireGuard Gateway)

If deploying the standalone WireGuard gateway directly on your VPS (`docker-compose.yml`), the host kernel must have packet forwarding and buffer tuning enabled:

```bash
sudo cp sysctl.d/99-wireguard.conf /etc/sysctl.d/99-wireguard.conf
sudo sysctl --system
```

Key parameters configured in [sysctl.d/99-wireguard.conf](file:///home/pheinz/discord-gateway/sysctl.d/99-wireguard.conf):
- `net.ipv4.ip_forward = 1`: Enables Linux kernel IPv4 packet forwarding between interfaces.
- `net.ipv4.conf.all.src_valid_mark = 1`: Required for WireGuard fwmark routing.
- `net.core.default_qdisc = fq` & `net.ipv4.tcp_congestion_control = bbr`: TCP BBR congestion control for jitter-free Discord voice/streaming.
- `net.core.rmem_max = 26214400` & `net.core.wmem_max = 26214400`: 25MB UDP socket buffers preventing packet loss during peak voice traffic.

To run Option B on your VPS:
```bash
./fetch-discord-cidrs.sh -f list -o discord-cidrs.txt
./fetch-discord-cidrs.sh --update-env
docker compose up -d
sudo ./iptables-rules.sh --apply --save
```


## 📱 How Your Friends Connect

Your friends do **not** need to install WireGuard. They connect using open-source, user-friendly proxy applications:

| Platform | Recommended Free Client App | Import Method |
| :--- | :--- | :--- |
| **Android** | [v2rayNG](https://play.google.com/store/apps/details?id=com.v2ray.ang) or [NekoBox](https://github.com/MatsuriDayo/NekoBoxForAndroid) | Tap `+` -> *Import config from clipboard* -> Connect |
| **iOS (iPhone/iPad)** | [FoXray](https://apps.apple.com/app/foxray/id6448398796) or [Streisand](https://apps.apple.com/app/streisand/id6450534064) | Tap `+` -> *Import from clipboard* -> Connect |
| **Windows** | [Nekoray](https://github.com/MatsuriDayo/nekoray) or [v2rayN](https://github.com/2dust/v2rayN) | `Ctrl + V` to import -> Enable *Tun Mode* |
| **macOS** | [FoXray](https://apps.apple.com/app/foxray/id6448398796) or [Nekoray](https://github.com/MatsuriDayo/nekoray) | Paste link -> Enable *System Proxy* / *Tun Mode* |
| **Browser (Zero-App)**| Direct SOCKS5 Proxy | Host: `<VPS_IP>`, Port: `10808`, Username/Password |

---

## 🤝 For Programmers & Contributors

Planning to fork, review, or submit changes?
See [`CONTRIBUTING.md`](file:///home/pheinz/discord-gateway/CONTRIBUTING.md) for priority tasks:
- Adding automated CIDR fetchers for Reddit and gaming endpoints.
- Developing a 1-click Windows PowerShell installer (`install.ps1`).
- Implementing automated Xray-core Reality TLS spoofing.
- Benchmark reports on Converge, PLDT, Globe, and DITO.

### Run Verification Test Suite
```bash
./scripts/test-suite.sh
```

---

## 🛡️ Security & Host Protection

Hosting for friends comes with valid security questions: *What if a friend's phone has malware? Can they access my home Wi-Fi devices?*
Read our complete [**Security Policy & Threat Mitigation Guide (SECURITY.md)**](SECURITY.md).

**Key built-in defenses:**
- 🚫 **Private LAN Isolation (`geoip:private`)**: Users/malware cannot access your home router (`192.168.1.1`), smart TVs, NAS, or family PCs.
- 🚫 **Anti-Spam Filter**: Outgoing mail ports (`25`, `465`, `587`) are blocked so your IP cannot be abused by spam bots.
- 🚫 **BitTorrent Block**: P2P torrenting is blocked to protect you from ISP copyright strikes.
- 🚫 **Whitelist Isolation**: In default mode, only verified Discord, Reddit, and Facebook traffic passes; malware Command & Control (C2) connections are immediately dropped.
- ⚡ **1-Click User Revocation**: Ban or limit any compromised friend instantly in your Marzban Web Dashboard.

---

## ⚖️ License

MIT License. Built for privacy, open connectivity, and digital freedom in the Philippines.
