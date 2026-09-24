# Contributing to Discord & Censorship Bypass Gateway (PH)

Mabuhay! We welcome contributions from Filipino developers, network engineers, and open-source contributors to help keep the internet open, accessible, and fast for everyone in the Philippines.

---

## The Problem We Are Solving

Philippine ISPs (Globe, PLDT, Smart, Converge, DITO) frequently implement DNS poisoning, IP blackholing, and aggressive Deep Packet Inspection (DPI) affecting Discord (voice/RTC channels, streaming), Reddit, and various online services.

Traditional commercial VPNs often get blocked, suffer from terrible latency, or cost expensive monthly fees. Hosting a full VPN server directly on a cheap VPS ($3.50/mo) crashes under multi-user video/voice loads.

This repository provides **two production-grade architectures**:
1. **Direct VPS Gateway (`/`)**: WireGuard on a VPS with a strict iptables kernel firewall that allows *only* Discord traffic and DNS, dropping everything else.
2. **Reverse Tunnel Gateway (`marzban-wsl/` & `reverse-tunnel/`)**: A Singapore VPS acts solely as an iptables "Traffic Forwarder", tunneling traffic to a home laptop (Windows 11 Pro + WSL 2) running **Marzban (Xray-core)**. The laptop's CPU, RAM, and 500+ Mbps home connection handle all the crypto and multi-user load.

---

## Priority Areas Where We Need Help & Changes

### 1. Additional Blocked Services & CIDR Lists
- [ ] Add scripts to fetch CIDR blocks and domains for **Reddit** and other throttled community platforms.
- [ ] Implement an automated GitHub Actions cron job that runs weekly to verify and commit updated BGP ASN announced prefixes.

### 2. Windows 11 PowerShell Automation
- [ ] Create a one-click `install-windows.ps1` that automatically:
  - Checks if WSL 2 is installed.
  - Automatically copies `.wslconfig` to `$env:USERPROFILE\.wslconfig`.
  - Configures the network adapter power management.
  - Downloads the official WireGuard for Windows installer if missing.

### 3. VLESS-Reality & TLS Spoofing
- [ ] Add automated setup for **Xray-core Reality** (stealth TLS spoofing against SNI blocking).
- [ ] Pre-configure target SNIs with high Philippine CDN presence (e.g. `gateway.discord.gg`, `dl.google.com`, `www.microsoft.com`).

### 4. ISP Testing & Latency Benchmarks
We need community members across different telcos to benchmark and report findings:
- [ ] **Globe Fiber & Globe Mobile** (CGNAT behavior, DNS hijacking tests)
- [ ] **PLDT Home Fibr & Smart 5G** (Voice RTC packet drop tests)
- [ ] **Converge ICT** (MTU optimization tests, e.g. 1360 vs 1420)
- [ ] **DITO Telecommunity** (Routing latency to Singapore VPS)

---

## Development & Testing Workflow

### Running the Test Suite
Before submitting any pull request, make sure all automated verification checks pass:

```bash
cd discord-gateway
./scripts/test-suite.sh
```

### Script Guidelines
- Write POSIX-compliant or bash scripts with `set -euo pipefail`.
- Always implement a `--dry-run` flag in scripts that modify `iptables` or system firewall rules.
- Never commit private keys, `.env` files, or production credentials.

---

## Submitting Pull Requests
1. Fork the repository.
2. Create your feature branch (`git checkout -b feature/awesome-improvement`).
3. Commit your changes (`git commit -m "Add automated Reddit CIDR fetcher"`).
4. Run the test suite: `./scripts/test-suite.sh`.
5. Push to the branch (`git push origin feature/awesome-improvement`).
6. Open a Pull Request with a clear description of what was tested and on which ISP.
