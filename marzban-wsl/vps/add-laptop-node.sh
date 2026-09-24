#!/usr/bin/env bash
# ==============================================================================
# marzban-wsl/vps/add-laptop-node.sh
# ------------------------------------------------------------------------------
# Enables a SINGLE VPS to act as a "Shared Community Hub" for multiple laptops.
# A friend who has a laptop but DOES NOT want to buy or configure a VPS can
# connect to your VPS hub.
#
# Each laptop gets:
#   - An internal WireGuard IP (e.g. 10.0.0.3, 10.0.0.4)
#   - A dedicated public port on the VPS (e.g. 8443, 9443) forwarded to their laptop's port 443.
# ==============================================================================

set -euo pipefail

CONFIG_DIR="/etc/wireguard"
WG_IFACE="wg0"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR] This script must be run as root (use sudo) on the VPS.${NC}"
    exit 1
fi

NODE_NAME="${1:-}"
PUBLIC_PORT="${2:-}"

if [[ -z "$NODE_NAME" || -z "$PUBLIC_PORT" ]]; then
    echo -e "${CYAN}=== Add New Laptop Node to Shared VPS Hub ===${NC}"
    read -rp "Enter Node Name (e.g. friend_alex_laptop): " NODE_NAME
    read -rp "Enter Dedicated Public VPS Port for this node (e.g. 8443, 9443): " PUBLIC_PORT
fi

if [[ -z "$NODE_NAME" || -z "$PUBLIC_PORT" ]]; then
    echo -e "${RED}[ERROR] Node Name and Public Port are required.${NC}"
    exit 1
fi

# Determine next available IP in 10.0.0.x subnet
EXISTING_IPS=$(grep -oP '10\.0\.0\.\d+' "${CONFIG_DIR}/wg0.conf" 2>/dev/null || echo "10.0.0.2")
HIGHEST_OCTET=2
for ip in $EXISTING_IPS; do
    octet=$(echo "$ip" | awk -F'.' '{print $4}')
    if [[ $octet -gt $HIGHEST_OCTET ]]; then
        HIGHEST_OCTET=$octet
    fi
done
NEXT_OCTET=$((HIGHEST_OCTET + 1))
NEW_IP="10.0.0.${NEXT_OCTET}"

echo -e "${BLUE}[INFO] Assigning IP ${NEW_IP} and forwarding public port ${PUBLIC_PORT} -> ${NEW_IP}:443...${NC}"

# Detect Public IP and WAN interface
WAN_IFACE=$(ip route show default | awk '/default/ {print $5}' | head -n1)
PUBLIC_IP=$(curl -s -m 5 https://api.ipify.org || ip -4 addr show "$WAN_IFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)

# Generate WireGuard keys for the new laptop
NODE_PRIV=$(wg genkey)
NODE_PUB=$(echo "$NODE_PRIV" | wg pubkey)
VPS_PUB=$(cat "${CONFIG_DIR}/vps_public.key" 2>/dev/null || wg show "$WG_IFACE" public-key)

# Append peer to VPS wg0.conf
cat >> "${CONFIG_DIR}/wg0.conf" << EOF

# Laptop Node: ${NODE_NAME}
[Peer]
PublicKey = ${NODE_PUB}
AllowedIPs = ${NEW_IP}/32
EOF

# Dynamically add peer to running WireGuard interface
wg set "$WG_IFACE" peer "$NODE_PUB" allowed-ips "${NEW_IP}/32"

# Apply iptables DNAT rules for the new port
iptables -t nat -A PREROUTING -p tcp --dport "$PUBLIC_PORT" -j DNAT --to-destination "${NEW_IP}:443"
iptables -t nat -A PREROUTING -p udp --dport "$PUBLIC_PORT" -j DNAT --to-destination "${NEW_IP}:443"
iptables -A FORWARD -p tcp -d "$NEW_IP" --dport 443 -j ACCEPT
iptables -A FORWARD -p udp -d "$NEW_IP" --dport 443 -j ACCEPT

# Persist iptables rules
if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null 2>&1 || true
fi

# Generate the client config file for this friend's laptop
CLIENT_CONF="/root/${NODE_NAME}-wg0.conf"
cat > "$CLIENT_CONF" << EOF
[Interface]
PrivateKey = ${NODE_PRIV}
Address = ${NEW_IP}/24

[Peer]
PublicKey = ${VPS_PUB}
Endpoint = ${PUBLIC_IP}:51820
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
EOF

chmod 600 "$CLIENT_CONF"

echo ""
echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}        NEW LAPTOP NODE CREATED ON SHARED VPS HUB!              ${NC}"
echo -e "${GREEN}================================================================${NC}"
echo -e "Node Name:     ${YELLOW}${NODE_NAME}${NC}"
echo -e "Tunnel IP:     ${YELLOW}${NEW_IP}${NC}"
echo -e "Public Port:   ${YELLOW}${PUBLIC_PORT}${NC} (Forwarded to ${NEW_IP}:443)"
echo ""
echo -e "${CYAN}SEND THIS WIREGUARD CONFIG TO YOUR FRIEND FOR THEIR LAPTOP:${NC}"
echo -e "${YELLOW}----------------------------------------------------------------${NC}"
cat "$CLIENT_CONF"
echo -e "${YELLOW}----------------------------------------------------------------${NC}"
echo ""
echo -e "Instructions for your friend:"
echo -e "  1. Import the configuration above into WireGuard on their laptop (Windows/Mac/Linux)."
echo -e "  2. Start Marzban on their laptop (listening on port 443)."
echo -e "  3. Their friends can connect to your VPS at: ${GREEN}${PUBLIC_IP}:${PUBLIC_PORT}${NC}"
echo -e "     (All traffic will route to THEIR laptop using THEIR home internet!)${NC}"
echo -e "${GREEN}================================================================${NC}"
