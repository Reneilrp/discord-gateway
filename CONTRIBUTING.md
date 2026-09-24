# 🇵🇭 Contributing Guide: Anti-Censorship Gateway

Mabuhay! We welcome contributions from Filipino developers, network engineers, sysadmins, and open-source contributors to help keep the internet open, uncensored, and fast for everyone across the Philippines.

---

## 📖 Contributor Setup Guides by Operating System

Before contributing features, testing PRs, or reporting ISP benchmarks, set up your local development node following the dedicated guide for your machine's operating system:

| Operating System | Dedicated Setup Guide | Container Engine | WireGuard Client |
| :--- | :--- | :--- | :--- |
| **Windows 11 Pro** | 🪟 [**Windows 11 Setup Guide**](docs/WINDOWS.md) | Docker in WSL 2 Ubuntu | WireGuard for Windows |
| **Linux (Ubuntu/Debian/Arch/Fedora)** | 🐧 [**Linux Setup Guide**](docs/LINUX.md) | Native Docker (Zero VM overhead) | Native `wg-quick` (`wg0.conf`) |
| **macOS (M1-M4 & Intel)** | 🍎 [**macOS Setup Guide**](docs/MACOS.md) | [OrbStack](https://orbstack.dev/) or Docker Desktop | WireGuard for Mac |

---

## 🎯 Priority Areas Where We Need Help & Changes

We are looking for community pull requests in the following specific areas:

### 1. Additional Blocked Services & Automated CIDR Fetchers
- [ ] **Reddit & Media CDNs**: Enhance [`fetch-service-cidrs.sh`](file:///home/pheinz/discord-gateway/fetch-service-cidrs.sh) with direct BGP updates for newly announced Fastly/Reddit Anycast IP pools.
- [ ] **Gaming Endpoints & Voice Relays**: Add CIDR profiles for Valorant, Steam, or Twitch voice servers throttled during peak hours.
- [ ] **Automated GitHub Actions**: Implement a weekly GitHub Actions workflow that automatically queries RIPE NCC BGP RIS and commits fresh CIDR blocks.

### 2. OS-Specific Automation Scripts
- [ ] **Windows 11**: Create a unified `install-windows.ps1` PowerShell script that detects WSL 2, copies `.wslconfig`, and configures power policies in one click.
- [ ] **Linux**: Create a `discord-gateway.service` systemd unit file to auto-start the WireGuard tunnel and Marzban container on system boot.
- [ ] **macOS**: Create a `launchd` plist to auto-start the node on MacBook boot.

### 3. VLESS-Reality & Stealth TLS Spoofing
- [ ] Pre-configure target SNIs with high Philippine CDN presence (e.g. `gateway.discord.gg`, `dl.google.com`, `www.microsoft.com`).
- [ ] Add automated Reality private/public key generation within [`scripts/toggle-services.sh`](file:///home/pheinz/discord-gateway/scripts/toggle-services.sh).

### 4. ISP Testing & Latency Benchmarks
We need community members across different telcos to benchmark and report findings:
- [ ] **Globe Fiber & Globe Mobile** (CGNAT behavior, DNS hijacking tests)
- [ ] **PLDT Home Fibr & Smart 5G** (Voice RTC packet drop tests)
- [ ] **Converge ICT** (MTU optimization tests, e.g. 1360 vs 1420)
- [ ] **DITO Telecommunity** (Routing latency to Singapore VPS)

---

## 🧪 Development & Testing Workflow

### Running the Test Suite
Before submitting any pull request, make sure all automated verification checks pass:

```bash
cd discord-gateway
./scripts/test-suite.sh
```

### Script & Code Guidelines
- Write POSIX-compliant or bash scripts with `set -euo pipefail`.
- Always implement a `--dry-run` flag in scripts that modify `iptables` or system firewall rules.
- Never commit private keys, `.env` files, or production credentials.

---

## 📝 Submitting Pull Requests
1. Fork the repository on GitHub.
2. Create your feature branch (`git checkout -b feature/awesome-feature`).
3. Commit your changes (`git commit -m "Add automated Reddit CIDR fetcher"`).
4. Run the test suite: `./scripts/test-suite.sh`.
5. Push to your fork (`git push origin feature/awesome-feature`).
6. Open a Pull Request on GitHub with a description of what was tested, on which OS, and on which Philippine ISP.
