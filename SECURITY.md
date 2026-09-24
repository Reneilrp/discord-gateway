# 🛡️ Security Policy & Threat Mitigation Guide

This document outlines the security architecture, threat model, and host protection mechanisms implemented in this gateway.

Hosting a proxy or VPN node for friends and family comes with legitimate security questions:
* *"What if an invited friend's device has malware or is part of a botnet?"*
* *"Can a user scan or attack my private home Wi-Fi network (router, smart TVs, family PCs)?"*
* *"Am I legally protected if someone tries to download torrents or send spam through my connection?"*

---

## 🎯 Threat Model & Mitigations

### Threat 1: Malware Scanning Your Home Network (Lateral Movement)
- **The Risk**: A user or infected phone tries to access your home router's admin panel (`192.168.1.1`), network printers, family NAS storage, or IoT smart cameras.
- **Our Defense (Built-In)**:
  All private IP address spaces are strictly **blackholed** in [`reverse-tunnel/laptop/config/config.json`](file:///home/pheinz/discord-gateway/reverse-tunnel/laptop/config/config.json) and Marzban:
  ```json
  {
    "type": "field",
    "ip": ["geoip:private"],
    "outboundTag": "blocked"
  }
  ```
  This immediately drops any attempt to connect to:
  - `192.168.0.0/16` (Home Wi-Fi subnets)
  - `10.0.0.0/8` (Private subnets)
  - `172.16.0.0/12` (Internal subnets)
  - `127.0.0.0/8` (Host localhost)
  - `169.254.0.0/16` (Link-local)
  - `::1` (IPv6 localhost)

### Threat 2: Malware Using Your IP as a Spam Zombie (Port 25 Abuse)
- **The Risk**: Email spambots or trojans use your connection to blast spam emails, which would get your home ISP IP blacklisted on Spamhaus or terminated by Globe/PLDT.
- **Our Defense (Built-In)**:
  Outgoing mail ports (`25`, `465`, `587`) are explicitly blocked:
  ```json
  {
    "type": "field",
    "port": "25,465,587",
    "outboundTag": "blocked"
  }
  ```

### Threat 3: BitTorrent & Copyright Infringement Notices
- **The Risk**: A friend downloads copyrighted movies/torrents, resulting in DMCA copyright strikes against your home ISP account.
- **Our Defense (Built-In)**:
  BitTorrent protocol traffic and trackers are blocked:
  ```json
  {
    "type": "field",
    "protocol": ["bittorrent"],
    "outboundTag": "blocked"
  }
  ```

### Threat 4: Malware Reaching Command & Control (C2) or DDoS Targets
- **The Risk**: A compromised laptop or phone tries to send DDoS flood attacks or communicate with a hacker's C2 server.
- **Our Defense (Whitelist Mode)**:
  When using **Whitelist Mode** (the default in `./scripts/toggle-services.sh`):
  - **Only verified Discord, Reddit, and Facebook domains and BGP CIDRs are permitted.**
  - Any connection attempt to unknown hacker IPs, botnet controllers, or arbitrary server ports is **immediately dropped**.
  - A malware on your friend's phone simply cannot communicate with its server through your gateway!

### Threat 5: Bandwidth Hogging & Resource Exhaustion
- **The Risk**: A user or background app downloads 500GB endlessly, saturating your home fiber line.
- **Our Defense (Marzban Dashboard Controls)**:
  - In the Marzban Web UI (`http://127.0.0.1:8000`), every friend has an individual user profile.
  - You can set **Data Limits** (e.g. 15 GB / month) and **Expiration Dates**.
  - If a user's device behaves strangely or consumes abnormal bandwidth, you can **revoke, suspend, or delete their key with 1 click**.

### Threat 6: Rogue Connections to the Public VPS
- **The Risk**: Strangers scan your public VPS IP address and try to use your gateway for free.
- **Our Defense (Cryptographic Authentication)**:
  - VLESS uses unique **128-bit UUIDs** (e.g. `e4d29f8c-8472-4d2a-98b7-6b47c92b0001`).
  - Without a valid cryptographic UUID registered in your Marzban database, the server immediately drops the connection without responding.

---

## 🔒 Host Best Practices (For Server Owners)

1. **Only share links with people you know**:
   Do not post your subscription links on public internet forums or public Discord channels.
2. **Keep Whitelist Mode enabled**:
   If you only intend to help your gaming squad play Discord and browse Reddit, keep `--mode whitelist` active so non-essential traffic is never forwarded.
3. **Monitor Live Usage**:
   Check your Marzban Web Dashboard once in a while. If you notice a friend uploading hundreds of gigabytes at 3:00 AM, their device might be compromised. You can pause their profile immediately.
4. **Isolate Docker**:
   Never run the Marzban container with `--privileged`. The provided Docker Compose definitions adhere to least-privilege standards.

---

## 🚨 Reporting a Vulnerability

If you discover a security flaw or bypass in any script or routing rule in this repository, please open a private GitHub Security Advisory or report it directly to the maintainer.
