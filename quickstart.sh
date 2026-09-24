#!/usr/bin/env bash
# ==============================================================================
# quickstart.sh
# ------------------------------------------------------------------------------
# Universal interactive setup wizard for anyone deploying their own gateway.
# Perfect for IT students, graduates, and community hosts.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

clear || true
echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN} 🇵🇭 Anti-Censorship Gateway Wizard (Deploy Your Own Network)     ${NC}"
echo -e "${CYAN}================================================================${NC}"
echo -e "Welcome! Anyone can use this open-source project to become an"
echo -e "independent Gateway Owner and host for their friends or family."
echo ""
echo -e "What role are you setting up on THIS machine?"
echo ""
echo -e "  ${GREEN}1) Remote VPS (Recommended Forwarder Hub)${NC}"
echo -e "     - You rented a cheap cloud VPS (DigitalOcean, Vultr, Linode)."
echo -e "     - Forwards traffic down a reverse tunnel to a home laptop."
echo ""
echo -e "  ${GREEN}2) Home Laptop / PC (The 'Brains' & Marzban Web Panel)${NC}"
echo -e "     - Runs on Windows 11 (WSL 2), Linux, or macOS."
echo -e "     - Features a web dashboard to manage friends, QR codes & links."
echo ""
echo -e "  ${GREEN}3) Standalone Direct VPS (No Laptop Required)${NC}"
echo -e "     - 100% in the cloud. Strict firewall allowing Discord + DNS only."
echo ""
read -rp "Select an option [1-3]: " ROLE_CHOICE

case "$ROLE_CHOICE" in
    1)
        echo ""
        echo -e "${BLUE}=== Setting up Remote VPS Traffic Forwarder ===${NC}"
        if [[ $EUID -ne 0 ]]; then
            echo -e "${YELLOW}[NOTE] Root privileges required for iptables. Running with sudo...${NC}"
            sudo ./marzban-wsl/vps/setup-vps-marzban-forwarder.sh
        else
            ./marzban-wsl/vps/setup-vps-marzban-forwarder.sh
        fi
        ;;

    2)
        echo ""
        echo -e "${BLUE}=== Setting up Laptop Gateway Node ===${NC}"
        echo "Detecting operating system..."
        OS_TYPE="$(uname -s)"

        if [[ "$OS_TYPE" == "Linux" ]]; then
            if grep -qi microsoft /proc/version 2>/dev/null; then
                echo -e "${GREEN}[DETECTED] Windows 11 (WSL 2 Ubuntu)${NC}"
                echo -e "Starting Marzban setup for WSL 2..."
                ./marzban-wsl/setup-marzban.sh
                echo ""
                echo -e "${YELLOW}Reminder: Follow WINDOWS.md to apply .wslconfig and power settings!${NC}"
            else
                echo -e "${GREEN}[DETECTED] Native Linux Host${NC}"
                if [[ $EUID -eq 0 ]]; then
                    ./host-os/linux/linux-server-prep.sh
                elif command -v sudo >/dev/null 2>&1; then
                    sudo ./host-os/linux/linux-server-prep.sh
                fi
                ./marzban-wsl/setup-marzban.sh
            fi
        elif [[ "$OS_TYPE" == "Darwin" ]]; then
            echo -e "${GREEN}[DETECTED] macOS MacBook / Mac Mini${NC}"
            ./host-os/macos/macos-server-prep.sh
            cd marzban-wsl && docker compose up -d
        else
            echo -e "${RED}[ERROR] Unsupported OS: $OS_TYPE${NC}"
            exit 1
        fi
        ;;

    3)
        echo ""
        echo -e "${BLUE}=== Setting up Standalone Direct VPS Gateway ===${NC}"
        ./fetch-discord-cidrs.sh -f list -o discord-cidrs.txt
        ./fetch-discord-cidrs.sh --update-env
        if command -v docker >/dev/null 2>&1; then
            docker compose up -d
        fi
        if [[ $EUID -ne 0 ]] && command -v sudo >/dev/null 2>&1; then
            sudo ./iptables-rules.sh --apply --save
        else
            ./iptables-rules.sh --apply --save
        fi
        echo -e "${GREEN}[SUCCESS] Standalone WireGuard Gateway is active!${NC}"
        ;;

    *)
        echo -e "${RED}[ERROR] Invalid option selected.${NC}"
        exit 1
        ;;
esac
