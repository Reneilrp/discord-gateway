# 🍎 macOS (Apple Silicon M1-M4 & Intel) Setup Guide

This guide walks you through setting up an **Apple MacBook or Mac Mini** as the gateway node. MacBooks are exceptionally power-efficient 24/7 home servers.

---

## 📋 Prerequisites
- **Hardware**: Any MacBook, Mac Mini, or iMac (Apple Silicon M1/M2/M3/M4 or Intel).
- **Container Engine**: [OrbStack](https://orbstack.dev/) (strongly recommended for macOS; uses 10x less battery/RAM than Docker Desktop) or Docker Desktop.
- **WireGuard**: Official [WireGuard for Mac](https://apps.apple.com/app/wireguard/id1451685025) (Mac App Store) or Homebrew (`brew install wireguard-tools`).
- **A Singapore VPS**: ~$3.50/mo on DigitalOcean, Linode, Vultr, or Hetzner.

---

## Step 1: Configure Singapore VPS (The Forwarder)

SSH into your remote Singapore VPS and run:
```bash
sudo ./marzban-wsl/vps/setup-vps-marzban-forwarder.sh
```
*This enables `net.ipv4.ip_forward = 1` and forwards Port 443 (TCP/UDP) and Port 8000 directly to your Mac's tunnel IP (`10.0.0.2`).*

---

## Step 2: Configure macOS Power & Sleep Prevention

MacBooks aggressively enter sleep when the lid is closed. To run your MacBook as a 24/7 server while plugged in:

### 1. Run the macOS Prep Script
```bash
chmod +x host-os/macos/macos-server-prep.sh
./host-os/macos/macos-server-prep.sh
```
*This configures `pmset` so macOS disables sleep when connected to the AC charger, and sets the display sleep to 10 minutes to protect your screen and keep heat low.*

### 2. Optional: Use the "Amphetamine" App (Recommended)
Install the free [Amphetamine App](https://apps.apple.com/app/amphetamine/id937984704) from the Mac App Store:
- In Amphetamine Preferences -> **Drive / System Sleep** -> Check *"Allow system sleep when display is closed: OFF"*.
- Start a session: *"Indefinitely (While on AC Power)"*.
- Now you can close your MacBook lid completely without interrupting connections!

---

## Step 3: Connect WireGuard on macOS

1. Open the **WireGuard for Mac** application.
2. Click **Add Tunnel** -> **Add empty tunnel**.
3. Name it `Singapore-VPS` and paste the client configuration:
   ```ini
   [Interface]
   PrivateKey = <YOUR_MAC_PRIVATE_KEY>
   Address = 10.0.0.2/24

   [Peer]
   PublicKey = <SINGAPORE_VPS_PUBLIC_KEY>
   Endpoint = <SINGAPORE_VPS_PUBLIC_IP>:51820
   AllowedIPs = 10.0.0.0/24
   PersistentKeepalive = 25
   ```
   > [!NOTE]
   > `AllowedIPs = 10.0.0.0/24` routes only the tunnel traffic through WireGuard. Your MacBook's normal internet access remains on your local home Wi-Fi/Ethernet.

4. Click **Activate**. Test in Terminal: `ping -c 3 10.0.0.1`.

---

## Step 4: Launch Marzban on macOS

With OrbStack or Docker Desktop running on your Mac:

```bash
cd marzban-wsl
docker compose up -d
```

Create your initial admin user:
```bash
docker exec -it marzban marzban cli admin create --sudo
```

---

## Step 5: Access Marzban Web UI & Add Friends

1. Open Safari or Chrome on your Mac:
   ```
   http://127.0.0.1:8000/dashboard/
   ```
2. Log in with your admin credentials.
3. In **Inbounds**, verify that VLESS is active on Port 443.
4. Click **Users** -> **Create User** -> generate a `vless://` link or QR code for your friends!

---

## 🛠️ macOS Troubleshooting

- **Docker Desktop is using too much CPU/RAM**:
  Switch to [OrbStack](https://orbstack.dev/) (`brew install --cask orbstack`). It launches in under 2 seconds and uses virtually 0% background CPU.
- **Mac sleeps when unplugged**:
  The `pmset -c` settings only apply when plugged into the charger (AC power). Keep your MacBook plugged in while serving as a gateway.
