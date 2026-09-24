#!/usr/bin/env bash
# ==============================================================================
# host-os/macos/macos-server-prep.sh
# ------------------------------------------------------------------------------
# Prepares a macOS MacBook (Apple Silicon M1/M2/M3/M4 or Intel) to run as
# a 24/7 gateway node:
#   1. Prevents system sleep when lid is closed on AC power (pmset).
#   2. Verifies Docker (Docker Desktop, OrbStack, or Colima).
#   3. Guides WireGuard setup for macOS.
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Configuring macOS MacBook as a Gateway Node ===${NC}"

# 1. Power Management via pmset
echo -e "${BLUE}[1/3] Configuring macOS power management (AC Charger)...${NC}"
echo -e "Setting system sleep to NEVER while plugged into charger..."
sudo pmset -c sleep 0
sudo pmset -c disablesleep 1
sudo pmset -c displaysleep 10
echo -e "${GREEN}[OK] Mac will stay awake when plugged in even with lid closed.${NC}"
echo -e "${YELLOW}[TIP] You can also use the free 'Amphetamine' app from the Mac App Store.${NC}"

# 2. Check Docker
echo -e "${BLUE}[2/3] Checking Docker environment...${NC}"
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${YELLOW}[INFO] Docker not found.${NC}"
    echo -e "Recommended options for macOS:"
    echo -e "  - ${GREEN}OrbStack${NC} (Fastest, uses 10x less battery/RAM than Docker Desktop): brew install --cask orbstack"
    echo -e "  - ${GREEN}Docker Desktop${NC}: brew install --cask docker"
else
    echo -e "${GREEN}[OK] Docker is installed.$(docker --version)${NC}"
fi

# 3. Check WireGuard
echo -e "${BLUE}[3/3] Checking WireGuard for Mac...${NC}"
echo -e "Options for WireGuard on macOS:"
echo -e "  1. ${GREEN}Official WireGuard for Mac${NC} (App Store) - GUI, very easy."
echo -e "  2. ${GREEN}CLI wireguard-tools${NC} (via Homebrew): brew install wireguard-tools"
echo ""

echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}             MACOS NODE PREPARATION COMPLETE!                   ${NC}"
echo -e "${GREEN}================================================================${NC}"
echo -e "Next steps on your Mac:"
echo -e "  1. Import your WireGuard config into WireGuard for Mac and click 'Activate'."
echo -e "  2. Start Marzban on your Mac:"
echo -e "       ${YELLOW}cd marzban-wsl && docker compose up -d${NC}"
echo -e "  3. Open your browser: ${GREEN}http://127.0.0.1:8000/dashboard/${NC}"
echo -e "${GREEN}================================================================${NC}"
