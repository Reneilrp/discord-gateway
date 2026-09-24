# 🐧 Linux (Ubuntu, Debian, Fedora, Arch) Setup Guide

This guide walks you through setting up a **native Linux laptop or PC** as the gateway node. Linux provides the highest performance and lowest latency because everything runs **natively on the host kernel with zero virtualization overhead**.

---

## 📋 Prerequisites
- **OS**: Ubuntu 20.04+, Debian 11+, Fedora 38+, or Arch Linux.
- **Access**: Root / `sudo` privileges.
- **A Singapore VPS**: ~$3.50/mo on DigitalOcean, Linode, Vultr, or Hetzner.

---

## Step 1: Configure Singapore VPS (The Forwarder)

SSH into your remote Singapore VPS and run:
```bash
sudo ./marzban-wsl/vps/setup-vps-marzban-forwarder.sh
```
*This enables `net.ipv4.ip_forward = 1` and forwards incoming traffic on Port 443 (TCP/UDP) and Port 8000 directly to your Linux machine's tunnel IP (`10.0.0.2`).*

---

## Step 2: Prepare Your Linux Laptop / PC

Run the automated Linux host preparation script with `sudo`:
```bash
sudo ./host-os/linux/linux-server-prep.sh
```

### What this script configures automatically:
1. **Lid-Close Power Policy (`systemd-logind`)**:
   Sets `HandleLidSwitch=ignore` in `/etc/systemd/logind.conf` so your laptop does not suspend when the lid is closed.
2. **Kernel IP Forwarding**:
   Enables `net.ipv4.ip_forward = 1` in `/etc/sysctl.d/99-gateway-forward.conf`.
3. **Installs Packages**:
   Installs Docker, Docker Compose, WireGuard, and `wireguard-tools` using your distribution's native package manager (`apt`, `dnf`, or `pacman`).

---

## Step 3: Connect WireGuard Client on Linux

1. Create `/etc/wireguard/wg0.conf`:
   ```bash
   sudo nano /etc/wireguard/wg0.conf
   ```
2. Paste the client configuration:
   ```ini
   [Interface]
   PrivateKey = <YOUR_LAPTOP_PRIVATE_KEY>
   Address = 10.0.0.2/24

   [Peer]
   PublicKey = <SINGAPORE_VPS_PUBLIC_KEY>
   Endpoint = <SINGAPORE_VPS_PUBLIC_IP>:51820
   AllowedIPs = 10.0.0.0/24
   PersistentKeepalive = 25
   ```
   > [!NOTE]
   > `AllowedIPs = 10.0.0.0/24` ensures that only the tunnel traffic routes through WireGuard. Your Linux laptop's normal internet access and local network remain completely untouched.

3. Start and enable WireGuard on system boot:
   ```bash
   sudo systemctl enable --now wg-quick@wg0
   ```
4. Verify connectivity:
   ```bash
   ping -c 3 10.0.0.1
   ```

---

## Step 4: Launch Marzban Natively

Run the Marzban setup script directly on Linux (zero WSL needed):
```bash
cd marzban-wsl
./setup-marzban.sh
```
Follow the prompt to create your initial admin username and password.

---

## Step 5: Access Marzban Web UI & Add Friends

1. Open your browser on Linux (or on any local LAN device at `http://<LAPTOP_LOCAL_IP>:8000`):
   ```
   http://127.0.0.1:8000/dashboard/
   ```
2. Log in with your admin credentials.
3. In **Inbounds**, verify that VLESS is active on Port 443.
4. Click **Users** -> **Create User** -> generate a `vless://` link or QR code for your friends!

---

## 🛠️ Linux Troubleshooting

- **`wg-quick` command not found**:
  Install wireguard tools: `sudo apt install wireguard-tools` (or `sudo dnf install wireguard-tools`).
- **Laptop suspends when unplugged**:
  Edit `/etc/systemd/logind.conf` and ensure both `HandleLidSwitch=ignore` and `HandleLidSwitchExternalPower=ignore` are set, then run `sudo systemctl restart systemd-logind`.
- **Check live Xray logs**:
  ```bash
  docker logs -f marzban
  ```
