# Marzban (Xray-Core) on Windows 11 Pro + WSL 2 Ubuntu Gateway

Host the **Marzban Web Dashboard & Xray-Core** inside your **WSL 2 Ubuntu** environment while using a cheap Singapore VPS ($3.50/month) as a lightweight **"Traffic Forwarder"**.

This setup keeps your Windows host clean, lets you create and manage user accounts with QR codes and links through a sleek web UI, and uses your laptop's CPU, RAM, and 505 Mbps home connection to cleanly bypass Philippine ISP blocks (Globe / PLDT).

---

## Architecture: End-to-End Traffic Flow

```
[Friends & Family Devices]
       │
       │ 1. Connects to Singapore VPS Public IP:443 (VLESS)
       ▼
┌────────────────────────────────────────────────────────┐
│  SINGAPORE VPS (Traffic Forwarder - $3.50/mo)          │
│  - WireGuard Server (10.0.0.1/24)                      │
│  - iptables DNAT: Port 443 ──> 10.0.0.2:443           │
│  - Pure packet pass-through; zero CPU/RAM decryption   │
└──────────────────────────┬─────────────────────────────┘
                           │
                           │ 2. Encrypted WireGuard Reverse Tunnel
                           ▼
┌────────────────────────────────────────────────────────┐
│  YOUR LAPTOP (Windows 11 Pro Host)                     │
│  - Official WireGuard for Windows (IP: 10.0.0.2/24)    │
│  - PersistentKeepalive = 25 (holds tunnel open)        │
│  - Mirrored Networking (.wslconfig) bridges to WSL 2   │
└──────────────────────────┬─────────────────────────────┘
                           │
                           │ 3. Instant local bridge (no NAT needed)
                           ▼
┌────────────────────────────────────────────────────────┐
│  WSL 2 UBUNTU (The Brains / Proxy Node)                │
│  - Marzban Web Panel (http://127.0.0.1:8000)          │
│  - Xray-core Container handles all multi-user sessions │
│  - Uses your laptop hardware + 505 Mbps connection     │
└──────────────────────────┬─────────────────────────────┘
                           │
                           │ 4. Fetches Discord, Reddit, and Open Internet
                           ▼
┌────────────────────────────────────────────────────────┐
│  THE OPEN INTERNET (Bypasses Globe & PLDT Censorship)  │
└──────────────────────────┘
```

---

## Directory Structure

```
marzban-wsl/
├── docker-compose.yml             # Marzban + Xray-core service for WSL Ubuntu
├── .env.example                   # Environment configuration template
├── .env                           # Active configuration (database, ports, JWT)
├── setup-marzban.sh               # WSL installation and startup helper
├── create-admin.sh                # Helper to create/reset Marzban admin credentials
├── README.md                      # This comprehensive guide
├── windows/
│   ├── .wslconfig                 # Windows 11 mirrored networking configuration
│   ├── windows-power-settings.bat # Disables sleep on lid close via powercfg
│   └── windows-portproxy-setup.ps1# Fallback portproxy script for older Windows builds
└── vps/
    └── setup-vps-marzban-forwarder.sh # VPS iptables script forwarding port 443 to 10.0.0.2
```

---

## Step 1: Install & Launch Marzban inside WSL Ubuntu

Open your **WSL Ubuntu terminal** and run the automated setup script:

```bash
cd /home/pheinz/discord-gateway/marzban-wsl
chmod +x setup-marzban.sh create-admin.sh
./setup-marzban.sh
```

### What this does:
1. Installs Docker engine if not present.
2. Launches Marzban container on ports `8000` (Web UI) and `443` (VLESS).
3. Prompts you to create an admin username and password via `marzban cli admin create --sudo`.

Once launched, verify Marzban is running:
```bash
docker compose ps
```

---

## Step 2: Configure Windows 11 Pro Networking & Power

### 1. Enable WSL 2 Mirrored Networking Mode
Windows 11 Pro includes **Mirrored Networking Mode** (`networkingMode=mirrored`), which directly shares the Windows network stack (including your WireGuard tunnel) with WSL 2.

Copy the provided [.wslconfig](file:///home/pheinz/discord-gateway/marzban-wsl/windows/.wslconfig) to your Windows user profile directory:
```powershell
# Run in Windows PowerShell:
Copy-Item \\wsl$\Ubuntu\home\pheinz\discord-gateway\marzban-wsl\windows\.wslconfig C:\Users\$env:USERNAME\.wslconfig
wsl --shutdown
```
Now reopen your WSL terminal. When Marzban listens on port 443 in WSL, Windows automatically makes it available on `10.0.0.2:443` with zero port-forwarding commands!

### 2. Connect Windows WireGuard
Open the **WireGuard for Windows** application:
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
   > [!IMPORTANT]
   > `AllowedIPs = 10.0.0.0/24` routes only the tunnel traffic through the VPN. Your laptop's regular gaming, browsing, and downloads remain on your local 505 Mbps connection.
   > `PersistentKeepalive = 25` prevents your home router from closing the NAT connection.
3. Click **Activate**. Test with `ping 10.0.0.1`.

### 3. Crucial Windows 11 Power Tweaks
To prevent Windows from putting your laptop or network card to sleep when idle or when the lid is closed:

1. **Run the Power Settings Batch Script**:
   Right-click `windows/windows-power-settings.bat` and select **Run as Administrator**.
   This sets the lid close action to **Do Nothing** and prevents system sleep when plugged in.
2. **Prevent Network Adapter Disconnect**:
   - Press `Win + X` -> **Device Manager**.
   - Expand **Network adapters**.
   - Right-click your active Wi-Fi or Ethernet adapter -> **Properties**.
   - Click the **Power Management** tab.
   - **Uncheck** *"Allow the computer to turn off this device to save power"*.
   - Click **OK**.

---

## Step 3: Configure Forwarding on Singapore VPS

Log into your Singapore VPS via SSH and run:

```bash
# Upload and run the VPS forwarder script
sudo chmod +x setup-vps-marzban-forwarder.sh
sudo ./setup-vps-marzban-forwarder.sh
```

Or execute directly:
```bash
# 1. Enable IPv4 Forwarding
sudo sysctl -w net.ipv4.ip_forward=1

# 2. Forward incoming port 443 to your laptop (10.0.0.2)
sudo iptables -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to-destination 10.0.0.2:443
sudo iptables -t nat -A PREROUTING -p udp --dport 443 -j DNAT --to-destination 10.0.0.2:443

# 3. Allow forwarded traffic
sudo iptables -A FORWARD -p tcp -d 10.0.0.2 --dport 443 -j ACCEPT
sudo iptables -A FORWARD -p udp -d 10.0.0.2 --dport 443 -j ACCEPT

# 4. Masquerade outgoing packets on wg0
sudo iptables -t nat -A POSTROUTING -o wg0 -j MASQUERADE
```

---

## Step 4: Add Your Friends in the Marzban Web UI

1. Open your browser on Windows 11 and navigate to:
   ```
   http://127.0.0.1:8000/dashboard/
   ```
2. Log in using the admin username and password created during setup.

### A. Configure the VLESS Inbound
1. Go to **Core Settings** / **Inbounds**.
2. Ensure you have a **VLESS** inbound listening on:
   - Protocol: `VLESS`
   - Port: `443`
   - Network: `TCP` or `WebSocket`
   - Security: `None` or `Reality`

### B. Add a Friend
1. Navigate to **Users** in the left sidebar.
2. Click **Create User**.
3. Enter your friend's name (e.g. `pete_discord`).
4. (Optional) Set data limits or expiration dates.
5. Click **Add**.

### C. Share the Connection
- Click on the newly created user.
- Marzban will instantly display:
  - A **QR Code** (for scanning via phone camera).
  - A **`vless://...` import URL**.
  - A **Subscription URL** (allows client apps to automatically receive updates).
- Copy the link and send it to your friend!

---

## How Your Friends Connect

Your friends simply paste the link into their preferred app:

| Platform | Recommended App | Where to Get |
| :--- | :--- | :--- |
| **Android** | **v2rayNG** or **NekoBox** | Google Play Store / GitHub |
| **iOS (iPhone/iPad)** | **FoXray**, **Streisand**, or **Shadowrocket** | Apple App Store |
| **Windows** | **Nekoray** or **v2rayN** | GitHub |
| **macOS** | **FoXray** or **V2RayXS** | App Store / GitHub |

When their device connects to `<VPS_PUBLIC_IP>:443`:
1. The VPS immediately funnels the packet down the WireGuard tunnel to your laptop (`10.0.0.2`).
2. WSL 2 receives the packet via mirrored networking.
3. Marzban/Xray-core decrypts the connection, fetches Discord/Reddit using your laptop's 505 Mbps ISP, and routes the response back out.
4. Friends enjoy zero packet loss and uncensored internet while your $3.50 VPS stays at 0% CPU utilization.
