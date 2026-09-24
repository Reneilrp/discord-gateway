#!/usr/bin/env bash
# ==============================================================================
# host-os/linux/linux-server-prep.sh
# ------------------------------------------------------------------------------
# Prepares a native Linux laptop (Ubuntu, Debian, Fedora, Arch) to run as
# a 24/7 gateway node:
#   1. Disables sleep/suspend when the laptop lid is closed (systemd-logind).
#   2. Enables kernel IP forwarding.
#   3. Installs WireGuard and Docker if not already present.
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR] This script must be run as root (use sudo).${NC}"
    exit 1
fi

echo -e "${BLUE}=== Configuring Linux Laptop as a 24/7 Gateway Node ===${NC}"

# 1. Prevent laptop sleep on lid close via systemd-logind
echo -e "${BLUE}[1/3] Configuring lid-close behavior (Do Nothing)...${NC}"
LOGIND_CONF="/etc/systemd/logind.conf"
if [[ -f "$LOGIND_CONF" ]]; then
    # Backup logind.conf
    cp "$LOGIND_CONF" "${LOGIND_CONF}.bak"

    # Set HandleLidSwitch to ignore
    sed -i 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=ignore/' "$LOGIND_CONF"
    sed -i 's/^#\?HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' "$LOGIND_CONF"
    sed -i 's/^#\?HandleLidSwitchDocked=.*/HandleLidSwitchDocked=ignore/' "$LOGIND_CONF"

    # Restart logind safely
    systemctl restart systemd-logind || true
    echo -e "${GREEN}[OK] Laptop will no longer suspend when lid is closed.${NC}"
else
    echo -e "${YELLOW}[WARN] /etc/systemd/logind.conf not found. Ensure power management does not sleep on lid close.${NC}"
fi

# 2. Enable IP forwarding
echo -e "${BLUE}[2/3] Enabling IPv4 packet forwarding...${NC}"
sysctl -w net.ipv4.ip_forward=1 >/dev/null
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-gateway-forward.conf
sysctl -p /etc/sysctl.d/99-gateway-forward.conf >/dev/null
echo -e "${GREEN}[OK] net.ipv4.ip_forward=1 enabled.${NC}"

# 3. Check / Install WireGuard & Docker
echo -e "${BLUE}[3/3] Checking dependencies (WireGuard & Docker)...${NC}"
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq wireguard wireguard-tools docker.io docker-compose-v2 curl
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y wireguard-tools docker docker-compose-plugin curl
elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm wireguard-tools docker docker-compose curl
fi

systemctl enable --now docker 2>/dev/null || true

echo ""
echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}             LINUX LAPTOP NODE PREPARATION COMPLETE!            ${NC}"
echo -e "${GREEN}================================================================${NC}"
echo -e "Next steps on your Linux laptop:"
echo -e "  1. Copy your WireGuard client config to: /etc/wireguard/wg0.conf"
echo -e "  2. Start the tunnel: ${YELLOW}sudo wg-quick up wg0${NC}"
echo -e "  3. Start Marzban natively: ${YELLOW}cd marzban-wsl && ./setup-marzban.sh${NC}"
echo -e "     (Zero WSL overhead required! Runs natively at http://127.0.0.1:8000)"
echo -e "${GREEN}================================================================${NC}"
