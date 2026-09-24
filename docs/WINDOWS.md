# 🪟 Windows 11 Pro + WSL 2 Setup Guide

This guide walks you through setting up your **Windows 11 Pro laptop** as the gateway host using **WSL 2 Ubuntu** and the **Marzban Web UI**.

---

## 📋 Prerequisites
- **OS**: Windows 11 Pro (Build 22621+ recommended for Mirrored Networking).
- **WSL 2**: Ubuntu distribution installed (`wsl --install -d Ubuntu`).
- **WireGuard**: Official [WireGuard for Windows](https://www.wireguard.com/install/).
- **A Singapore VPS**: ~$3.50/mo on DigitalOcean, Linode, Vultr, or Hetzner.

---

## Step 1: Configure Singapore VPS (The Forwarder)

SSH into your remote Singapore VPS and run:
```bash
sudo ./marzban-wsl/vps/setup-vps-marzban-forwarder.sh
```
*This enables `net.ipv4.ip_forward = 1` and configures `iptables` to forward Port 443 (TCP/UDP) and Port 8000 directly to your laptop's tunnel IP (`10.0.0.2`).*

---

## Step 2: Configure Windows 11 Host Settings

### 1. Enable Mirrored Networking Mode (`.wslconfig`)
Windows 11 includes **Mirrored Networking Mode**, which directly shares the Windows network stack (including your WireGuard tunnel) with WSL 2.

In **PowerShell**:
```powershell
# Copy .wslconfig from WSL to your Windows User profile
Copy-Item \\wsl$\Ubuntu\home\pheinz\discord-gateway\marzban-wsl\windows\.wslconfig C:\Users\$env:USERNAME\.wslconfig

# Restart WSL 2 to apply
wsl --shutdown
```

### 2. Prevent Laptop Sleep (Lid Closed Server Operation)
Right-click [`marzban-wsl/windows/windows-power-settings.bat`](file:///home/pheinz/discord-gateway/marzban-wsl/windows/windows-power-settings.bat) and select **Run as Administrator**.
- Sets lid close action to **Do Nothing** (screen powers off after 10 mins to prevent heat, but CPU/RAM remains active).
- Sets system sleep timeout to **Never** when plugged in.

*Device Manager Check:*
1. Press `Win + X` -> **Device Manager**.
2. Expand **Network adapters** -> Right-click your Wi-Fi or Ethernet -> **Properties**.
3. Go to the **Power Management** tab.
4. **Uncheck** *"Allow the computer to turn off this device to save power"*.

### 3. Connect WireGuard for Windows
Open the official WireGuard app on Windows:
1. Click **Add Tunnel** -> **Add empty tunnel**.
2. Name it `Singapore-VPS` and paste the client configuration:
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
3. Click **Activate**. Test in Command Prompt: `ping 10.0.0.1`.

---

## Step 3: Launch Marzban in WSL 2 Ubuntu

Open your WSL 2 Ubuntu terminal:
```bash
cd /home/pheinz/discord-gateway/marzban-wsl
./setup-marzban.sh
```
Follow the prompt to create your admin username and password.

---

## Step 4: Access Marzban Web UI & Add Friends

1. Open your browser in Windows 11:
   ```
   http://127.0.0.1:8000/dashboard/
   ```
2. Log in with your admin credentials.
3. Go to **Core Settings** -> **Inbounds** and verify VLESS protocol is enabled on port 443.
4. Click **Users** -> **Create User** -> Enter your friend's name.
5. Copy the generated **QR Code** or **`vless://` link** and send it to your friend!

---

## 🛠️ Windows Troubleshooting

- **`http://127.0.0.1:8000` does not load**:
  Ensure Docker is running inside WSL (`sudo service docker status`). Run `docker compose ps` inside `marzban-wsl/`.
- **Friends cannot connect**:
  Make sure Port 443 is open in your VPS provider's firewall settings (Security Groups).
  If you are on an older Windows 11 build that does not support mirrored mode, run [`marzban-wsl/windows/windows-portproxy-setup.ps1`](file:///home/pheinz/discord-gateway/marzban-wsl/windows/windows-portproxy-setup.ps1) as Administrator.
