#!/usr/bin/env bash
# ==============================================================================
# reverse-tunnel/vps/setup-vps-forwarder.sh
# ------------------------------------------------------------------------------
# Configures the remote VPS as a lightweight "Traffic Forwarder":
#   1. Sets up a WireGuard interface (wg0 at 10.0.0.1/24, port 51820 UDP).
#   2. Enables kernel IP forwarding (sysctl net.ipv4.ip_forward=1).
#   3. Configures iptables DNAT + MASQUERADE:
#      Forwards all public incoming traffic on specified ports (e.g. 443, 8443)
#      directly down the WireGuard tunnel to your laptop (10.0.0.2).
#   4. Generates the laptop WireGuard client config with PersistentKeepalive=25.
# ==============================================================================

set -euo pipefail

FORWARD_PORTS=("443" "8443")   # Ports to forward to your laptop
WG_PORT=51820
WG_NET="10.0.0.0/24"
VPS_WG_IP="10.0.0.1/24"
LAPTOP_WG_IP="10.0.0.2/32"
CONFIG_DIR="/etc/wireguard"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR] This script must be run as root (use sudo).${NC}"
    exit 1
fi

echo -e "${BLUE}=== Setting up WireGuard Reverse Tunnel Forwarder on VPS ===${NC}"

# 1. Install prerequisites
echo -e "${BLUE}[1/5] Installing WireGuard and iptables tools...${NC}"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq wireguard iptables iproute2 netfilter-persistent qrencode curl

# 2. Enable IP forwarding
echo -e "${BLUE}[2/5] Enabling kernel IP packet forwarding...${NC}"
cat > /etc/sysctl.d/99-wireguard-forward.conf << 'EOF'
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.default.forwarding = 1
EOF
sysctl -p /etc/sysctl.d/99-wireguard-forward.conf >/dev/null

# 3. Detect Public IP & WAN interface
WAN_IFACE=$(ip route show default | awk '/default/ {print $5}' | head -n1)
PUBLIC_IP=$(curl -s -m 5 https://api.ipify.org || curl -s -m 5 https://ifconfig.me || ip -4 addr show "$WAN_IFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)

echo -e "  Public VPS IP:    ${GREEN}${PUBLIC_IP}${NC}"
echo -e "  WAN Interface:    ${GREEN}${WAN_IFACE}${NC}"
echo -e "  Forwarded Ports:  ${GREEN}${FORWARD_PORTS[*]}${NC}"

# 4. Generate WireGuard keys if missing
mkdir -p "$CONFIG_DIR"
cd "$CONFIG_DIR"

if [[ ! -f vps_private.key ]]; then
    wg genkey | tee vps_private.key | wg pubkey > vps_public.key
fi
if [[ ! -f laptop_private.key ]]; then
    wg genkey | tee laptop_private.key | wg pubkey > laptop_public.key
fi

VPS_PRIV=$(cat vps_private.key)
VPS_PUB=$(cat vps_public.key)
LAPTOP_PRIV=$(cat laptop_private.key)
LAPTOP_PUB=$(cat laptop_public.key)

# 5. Build iptables PostUp / PostDown rules
POST_UP_RULES="iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
POST_DOWN_RULES="iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"

# Add DNAT rules for each forwarded port
for p in "${FORWARD_PORTS[@]}"; do
    POST_UP_RULES="${POST_UP_RULES}; iptables -t nat -A PREROUTING -p tcp --dport ${p} -j DNAT --to-destination 10.0.0.2:${p}"
    POST_UP_RULES="${POST_UP_RULES}; iptables -t nat -A PREROUTING -p udp --dport ${p} -j DNAT --to-destination 10.0.0.2:${p}"
    POST_UP_RULES="${POST_UP_RULES}; iptables -A FORWARD -p tcp -d 10.0.0.2 --dport ${p} -j ACCEPT"
    POST_UP_RULES="${POST_UP_RULES}; iptables -A FORWARD -p udp -d 10.0.0.2 --dport ${p} -j ACCEPT"

    POST_DOWN_RULES="${POST_DOWN_RULES}; iptables -t nat -D PREROUTING -p tcp --dport ${p} -j DNAT --to-destination 10.0.0.2:${p} 2>/dev/null || true"
    POST_DOWN_RULES="${POST_DOWN_RULES}; iptables -t nat -D PREROUTING -p udp --dport ${p} -j DNAT --to-destination 10.0.0.2:${p} 2>/dev/null || true"
    POST_DOWN_RULES="${POST_DOWN_RULES}; iptables -D FORWARD -p tcp -d 10.0.0.2 --dport ${p} -j ACCEPT 2>/dev/null || true"
    POST_DOWN_RULES="${POST_DOWN_RULES}; iptables -D FORWARD -p udp -d 10.0.0.2 --dport ${p} -j ACCEPT 2>/dev/null || true"
done

# Masquerade traffic arriving at laptop so it knows to return through wg0 without policy routing
POST_UP_RULES="${POST_UP_RULES}; iptables -t nat -A POSTROUTING -o wg0 -j MASQUERADE"
POST_DOWN_RULES="${POST_DOWN_RULES}; iptables -t nat -D POSTROUTING -o wg0 -j MASQUERADE 2>/dev/null || true"

# Write VPS wg0.conf
cat > "${CONFIG_DIR}/wg0.conf" << EOF
[Interface]
Address = ${VPS_WG_IP}
ListenPort = ${WG_PORT}
PrivateKey = ${VPS_PRIV}
PostUp = ${POST_UP_RULES}
PostDown = ${POST_DOWN_RULES}

[Peer]
# Laptop Client
PublicKey = ${LAPTOP_PUB}
AllowedIPs = ${LAPTOP_WG_IP}
EOF

chmod 600 "${CONFIG_DIR}/wg0.conf"

# Start and enable WireGuard on VPS
systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0

# Generate Laptop Client Configuration
LAPTOP_CONF="/root/laptop-wg0.conf"
cat > "$LAPTOP_CONF" << EOF
[Interface]
PrivateKey = ${LAPTOP_PRIV}
Address = 10.0.0.2/24
# Note: Laptop's default internet connection remains intact.
# Only traffic destined for the WireGuard tunnel (10.0.0.0/24) routes through wg0.

[Peer]
PublicKey = ${VPS_PUB}
Endpoint = ${PUBLIC_IP}:${WG_PORT}
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
EOF

chmod 600 "$LAPTOP_CONF"

echo ""
echo -e "${GREEN}=== VPS FORWARDER SETUP COMPLETE! ===${NC}"
echo -e "WireGuard Status:"
wg show

echo ""
echo -e "${YELLOW}================================================================${NC}"
echo -e "${YELLOW}          COPY THIS CONFIGURATION TO YOUR LAPTOP                ${NC}"
echo -e "${YELLOW}================================================================${NC}"
cat "$LAPTOP_CONF"
echo -e "${YELLOW}================================================================${NC}"
echo ""
echo -e "On your laptop (Windows/macOS/Linux):"
echo -e "  1. Save the above block as: wg0.conf"
echo -e "  2. Import into the official WireGuard application and click 'Activate'."
echo -e "  3. Start Xray-core on your laptop listening on 10.0.0.2:${FORWARD_PORTS[0]}."
