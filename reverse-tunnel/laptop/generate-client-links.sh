#!/usr/bin/env bash
# ==============================================================================
# reverse-tunnel/laptop/generate-client-links.sh
# ------------------------------------------------------------------------------
# Generates shareable vless:// import links, SOCKS5 proxy details, and terminal
# QR codes for your friends to import into their client apps.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config/config.json"

# Read VPS IP from argument or prompt
VPS_IP="${1:-}"

if [[ -z "$VPS_IP" ]]; then
    read -rp "Enter your remote VPS Public IP address: " VPS_IP
fi

if [[ -z "$VPS_IP" ]]; then
    echo "VPS IP is required."
    exit 1
fi

echo "================================================================="
echo "   DISCORD GATEWAY - CLIENT CONNECTION PROFILES (REVERSE TUNNEL) "
echo "   Public Entry Point: ${VPS_IP}"
echo "================================================================="
echo ""
echo "Recommended Client Apps for Friends:"
echo "  - Android:  v2rayNG (Google Play / GitHub) or NekoBox"
echo "  - iOS:      FoXray / Streisand / Shadowrocket (App Store)"
echo "  - Windows:  Nekoray / v2rayN (GitHub)"
echo "  - macOS:    V2RayXS / FoXray / Nekoray"
echo ""

# Extract client IDs from config.json
python3 - << PYEOF
import json
import urllib.parse

vps_ip = "${VPS_IP}"
config_path = "${CONFIG_FILE}"

with open(config_path) as f:
    cfg = json.load(f)

for inbound in cfg.get("inbounds", []):
    proto = inbound.get("protocol")
    port = inbound.get("port")
    tag = inbound.get("tag")
    stream = inbound.get("streamSettings", {})
    net_type = stream.get("network", "tcp")

    if proto == "vless":
        clients = inbound.get("settings", {}).get("clients", [])
        for c in clients:
            uid = c.get("id")
            email = c.get("email", "friend")
            label = urllib.parse.quote(f"Discord-Gateway-{email}")

            if net_type == "ws":
                path = urllib.parse.quote(stream.get("wsSettings", {}).get("path", "/"))
                link = f"vless://{uid}@{vps_ip}:{port}?encryption=none&type=ws&path={path}#{label}"
            else:
                link = f"vless://{uid}@{vps_ip}:{port}?encryption=none&type=tcp#{label}"

            print("-----------------------------------------------------------------")
            print(f"Profile: [{email.upper()}] (Port {port} / {net_type.upper()})")
            print("Import Link (Copy and send to friend):")
            print(f"  {link}")

    elif proto == "socks":
        accounts = inbound.get("settings", {}).get("accounts", [])
        for acc in accounts:
            user = acc.get("user")
            pwd = acc.get("pass")
            print("-----------------------------------------------------------------")
            print(f"Profile: [BROWSER SOCKS5 PROXY] (Port {port})")
            print(f"  Server / Host: {vps_ip}")
            print(f"  Port:          {port}")
            print(f"  Username:      {user}")
            print(f"  Password:      {pwd}")
            print(f"  Proxy URL:     socks5://{user}:{pwd}@{vps_ip}:{port}")

PYEOF

echo "-----------------------------------------------------------------"
echo ""
echo "How your friends connect:"
echo "  1. Friend opens v2rayNG (Android), FoXray (iOS), or Nekoray (PC)."
echo "  2. Friend clicks '+' or 'Import config from clipboard' and pastes the vless:// link."
echo "  3. Friend clicks Connect / Start."
echo "  4. All their Discord / Reddit traffic is now routed through your laptop to bypass telco blocks!"
