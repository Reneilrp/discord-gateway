#!/usr/bin/env bash
# ==============================================================================
# marzban-wsl/vps/setup-vps-marzban-forwarder.sh
# ------------------------------------------------------------------------------
# Configures your remote Singapore VPS to forward incoming traffic directly
# into your Windows 11 laptop running Marzban in WSL (10.0.0.2).
#
# Forwarded Ports:
#   - 443 TCP/UDP  : VLESS proxy traffic (for your friends' client apps)
#   - 8000 TCP     : Marzban subscription & Web UI traffic (optional)
# ==============================================================================

set -euo pipefail

LAPTOP_IP="10.0.0.2"
WG_IFACE="wg0"

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

echo -e "${BLUE}=== Setting up Singapore VPS Forwarder for Laptop Marzban ===${NC}"

# 1. Enable IPv4 Forwarding
echo -e "${BLUE}[1/4] Enabling IPv4 packet forwarding in sysctl...${NC}"
sysctl -w net.ipv4.ip_forward=1
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf || true
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-ip-forward.conf
sysctl -p /etc/sysctl.d/99-ip-forward.conf >/dev/null

# 2. Check if WireGuard is running
if ! ip addr show "$WG_IFACE" >/dev/null 2>&1; then
    echo -e "${YELLOW}[WARN] Interface ${WG_IFACE} not detected. Ensure WireGuard is installed and running.${NC}"
fi

# 3. Configure iptables DNAT rules for Port 443 (VLESS) and Port 8000 (Subscription)
echo -e "${BLUE}[2/4] Applying iptables DNAT port-forwarding rules...${NC}"

# Clean existing rules to prevent duplicates
iptables -t nat -D PREROUTING -p tcp --dport 443 -j DNAT --to-destination "${LAPTOP_IP}:443" 2>/dev/null || true
iptables -t nat -D PREROUTING -p udp --dport 443 -j DNAT --to-destination "${LAPTOP_IP}:443" 2>/dev/null || true
iptables -D FORWARD -p tcp -d "${LAPTOP_IP}" --dport 443 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -p udp -d "${LAPTOP_IP}" --dport 443 -j ACCEPT 2>/dev/null || true

iptables -t nat -D PREROUTING -p tcp --dport 8000 -j DNAT --to-destination "${LAPTOP_IP}:8000" 2>/dev/null || true
iptables -D FORWARD -p tcp -d "${LAPTOP_IP}" --dport 8000 -j ACCEPT 2>/dev/null || true

iptables -t nat -D POSTROUTING -o "${WG_IFACE}" -j MASQUERADE 2>/dev/null || true

# Apply new rules
iptables -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to-destination "${LAPTOP_IP}:443"
iptables -t nat -A PREROUTING -p udp --dport 443 -j DNAT --to-destination "${LAPTOP_IP}:443"
iptables -A FORWARD -p tcp -d "${LAPTOP_IP}" --dport 443 -j ACCEPT
iptables -A FORWARD -p udp -d "${LAPTOP_IP}" --dport 443 -j ACCEPT

# Optional: Forward port 8000 so friends can update subscriptions via your VPS IP
iptables -t nat -A PREROUTING -p tcp --dport 8000 -j DNAT --to-destination "${LAPTOP_IP}:8000"
iptables -A FORWARD -p tcp -d "${LAPTOP_IP}" --dport 8000 -j ACCEPT

# Masquerade so the laptop knows to return packets via wg0 without complex routing tables
iptables -t nat -A POSTROUTING -o "${WG_IFACE}" -j MASQUERADE

echo -e "${GREEN}[3/4] iptables rules successfully applied!${NC}"

# 4. Persist across reboots
echo -e "${BLUE}[4/4] Persisting rules across reboot...${NC}"
if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save
elif command -v iptables-save >/dev/null 2>&1; then
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
fi

echo ""
echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}             VPS TRAFFIC FORWARDER IS ACTIVE!                   ${NC}"
echo -e "${GREEN}================================================================${NC}"
echo -e "All incoming traffic on Port 443 (TCP/UDP) & Port 8000 (TCP)"
echo -e "is now forwarded to your laptop at ${YELLOW}${LAPTOP_IP}${NC} via WireGuard."
echo -e "${GREEN}================================================================${NC}"
