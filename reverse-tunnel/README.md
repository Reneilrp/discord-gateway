# WireGuard Reverse Tunnel + Laptop Xray Node Gateway

A distributed reverse-tunnel proxy architecture where your **laptop** performs all heavy processing, encryption, and routing, while a cheap remote VPS ($3.50/month) simply acts as a public **"Traffic Forwarder"**.

This setup bypasses blocks and deep packet inspection (DPI) implemented by local ISPs (such as Globe and PLDT in the Philippines) and allows multiple friends or family members to connect via a single shared link without bogging down your VPS.

---

## Architecture: How It Works

```
                                      REVERSE WIREGUARD TUNNEL
 [Friends & Family]                   (Kept alive by laptop)
        │
        │ 1. Connects to Public VPS IP:443 (VLESS / SOCKS5)
        ▼
┌────────────────────────────────────────────────────────┐
│  REMOTE VPS (The "Traffic Forwarder" - $3.50/mo tier)  │
│  - Public IP: 203.0.113.50                             │
│  - WireGuard Server: 10.0.0.1/24 (UDP 51820)           │
│  - iptables DNAT: Port 443/8443 ──> 10.0.0.2 (Laptop) │
│  - Zero CPU/RAM processing; pure packet pass-through   │
└──────────────────────────┬─────────────────────────────┘
                           │
                           │ 2. Encrypted WireGuard packets (10.0.0.1 -> 10.0.0.2)
                           ▼
┌────────────────────────────────────────────────────────┐
│  YOUR LAPTOP (The "Brains" / Proxy Server)             │
│  - WireGuard Client: 10.0.0.2/24 (PersistentKeepalive) │
│  - Xray-core Docker: Inbound VLESS:443 & SOCKS5:10808  │
│  - Handles multi-user sessions, decryption, and crypto │
│  - Uses Cloudflare DoH (1.1.1.1) to bypass DNS poisons │
└──────────────────────────┬─────────────────────────────┘
                           │
                           │ 3. Fetches Discord, Reddit, and Open Web
                           ▼
┌────────────────────────────────────────────────────────┐
│  THE OPEN INTERNET (Uncensored Web, Discord, Reddit)   │
└────────────────────────────────────────────────────────┘
```

### Why This Architecture Wins
1. **Zero VPS CPU/RAM Bottleneck**: In traditional VPNs, 10 friends streaming Discord voice or video would crash a 512MB/1-vCPU VPS. Here, the VPS only forwards raw network packets via `iptables` (takes less than 1% CPU and negligible RAM).
2. **Simplified Multi-User Sharing**: Pure WireGuard requires generating new cryptographic keys, editing server config files, and restarting WireGuard for every single person. With **Xray-core (VLESS)**, you share a single `vless://` link or SOCKS5 proxy that friends paste into their client apps.
3. **ISP Block & DPI Bypass**: Globe and PLDT censor sites using DNS poisoning and Deep Packet Inspection (DPI). The Xray node on your laptop routes queries via Cloudflare DNS-over-HTTPS (DoH), bypassing telco blocks.

---

## Directory Structure

```
reverse-tunnel/
├── vps/
│   └── setup-vps-forwarder.sh     # One-click VPS setup (WireGuard + iptables DNAT)
└── laptop/
    ├── docker-compose.yml         # Xray-core Docker container for your laptop
    ├── config/
    │   └── config.json            # VLESS multi-user, WebSocket, SOCKS5 & DoH configuration
    └── generate-client-links.sh   # Generates shareable vless:// links & proxy details
```

---

## Step 1: Set Up the VPS "Traffic Forwarder"

Run this on your remote VPS (Ubuntu 20.04 / 22.04 / 24.04):

```bash
# Upload and run setup-vps-forwarder.sh
sudo chmod +x reverse-tunnel/vps/setup-vps-forwarder.sh
sudo ./reverse-tunnel/vps/setup-vps-forwarder.sh
```

### What this script does automatically:
- Installs WireGuard and enables kernel packet forwarding (`sysctl net.ipv4.ip_forward = 1`).
- Generates WireGuard keys for both the VPS and your laptop.
- Sets up `iptables` DNAT rules:
  ```bash
  # Forward incoming port 443 to laptop 10.0.0.2:443
  iptables -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to-destination 10.0.0.2:443
  iptables -t nat -A PREROUTING -p udp --dport 443 -j DNAT --to-destination 10.0.0.2:443
  # Masquerade so laptop knows to reply via the tunnel without special routing
  iptables -t nat -A POSTROUTING -o wg0 -j MASQUERADE
  ```
- Starts WireGuard on `10.0.0.1/24` (listening on UDP `51820`).
- Prints the generated `laptop-wg0.conf`.

---

## Step 2: Connect Your Laptop to the VPS

On your laptop (Windows, macOS, or Linux):

1. Install the official [WireGuard App](https://www.wireguard.com/install/).
2. Create a new tunnel named `wg0` and paste the client configuration generated in Step 1:
   ```ini
   [Interface]
   PrivateKey = <LAPTOP_PRIVATE_KEY>
   Address = 10.0.0.2/24

   [Peer]
   PublicKey = <VPS_PUBLIC_KEY>
   Endpoint = <VPS_PUBLIC_IP>:51820
   AllowedIPs = 10.0.0.0/24
   PersistentKeepalive = 25
   ```
   > [!IMPORTANT]
   > `AllowedIPs = 10.0.0.0/24` ensures that only the tunnel traffic routes through WireGuard. Your laptop's normal internet access and local network remain completely untouched!
   > `PersistentKeepalive = 25` keeps the NAT pinhole open through your home router so the VPS can push incoming connections into your laptop at any time.

3. Click **Activate**. Verify ping to the VPS tunnel IP:
   ```bash
   ping 10.0.0.1
   ```

---

## Step 3: Run Xray-core on Your Laptop

On your laptop, navigate to the `laptop` directory and start Xray-core via Docker:

```bash
cd reverse-tunnel/laptop
docker compose up -d
```

Verify that Xray-core is running and listening:
```bash
docker compose ps
docker compose logs -f
```

---

## Step 4: Generate and Share Links with Friends

Run the link generator script, passing your VPS public IP:

```bash
./reverse-tunnel/laptop/generate-client-links.sh <VPS_PUBLIC_IP>
```

Example output:
```text
-----------------------------------------------------------------
Profile: [FRIEND-1@DISCORD-GATEWAY] (Port 443 / TCP)
Import Link (Copy and send to friend):
  vless://e4d29f8c-8472-4d2a-98b7-6b47c92b0001@203.0.113.50:443?encryption=none&type=tcp#Discord-Gateway-friend-1

-----------------------------------------------------------------
Profile: [BROWSER SOCKS5 PROXY] (Port 10808)
  Server / Host: 203.0.113.50
  Port:          10808
  Username:      friend
  Password:      discordgateway2026
  Proxy URL:     socks5://friend:discordgateway2026@203.0.113.50:10808
-----------------------------------------------------------------
```

---

## How Your Friends Connect

Your friends do **not** need to install WireGuard. They connect via user-friendly proxy apps:

### 📱 Android
1. Install **v2rayNG** (from Google Play Store or GitHub).
2. Copy the `vless://` link provided by you.
3. Open v2rayNG -> tap **+** -> **Import config from clipboard**.
4. Tap the **Connect (V)** icon.

### 🍎 iOS (iPhone / iPad)
1. Install **FoXray**, **Streisand**, or **Shadowrocket** from the App Store.
2. Copy the `vless://` link.
3. Open the app -> tap **+** (Import from clipboard) -> tap **Connect**.

### 💻 Windows & macOS
1. Download **Nekoray** or **v2rayN** (GitHub).
2. Press `Ctrl + V` to import the `vless://` link from clipboard.
3. Enable "Tun Mode" or "System Proxy".

### 🌐 Direct Browser SOCKS5 (Zero App Installation)
For friends who cannot install apps:
- Open browser network settings (or extension like *Proxy SwitchyOmega*).
- Select **SOCKS5**.
- Host: `<VPS_PUBLIC_IP>`, Port: `10808`.
- Username: `friend`, Password: `discordgateway2026`.

---

## Verification & Monitoring

### On VPS: Check forwarded traffic counters
```bash
sudo iptables -t nat -L PREROUTING -v -n --line-numbers
```
You will see packet and byte counts increasing under the `DNAT` rules for port 443.

### On Laptop: Check active connections
```bash
docker compose -f reverse-tunnel/laptop/docker-compose.yml logs --tail=50
```
You will observe incoming sessions from your friends being decrypted and serviced by your laptop.
