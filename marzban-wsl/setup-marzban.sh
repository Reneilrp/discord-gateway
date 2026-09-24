#!/usr/bin/env bash
# ==============================================================================
# marzban-wsl/setup-marzban.sh
# ------------------------------------------------------------------------------
# Automates the setup of Marzban inside WSL Ubuntu on your laptop:
#   1. Installs Docker prerequisites if not already installed.
#   2. Starts Marzban via Docker Compose.
#   3. Helps create the initial admin user.
#   4. Displays access URLs for Windows 11 browser.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Setting up Marzban Xray Gateway in WSL 2 Ubuntu ===${NC}"

# 1. Check for Docker
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${YELLOW}[INFO] Docker not found. Installing Docker engine in WSL...${NC}"
    sudo apt-get update -qq
    sudo apt-get install -y -qq curl ca-certificates gnupg
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker "$USER"
    echo -e "${GREEN}[SUCCESS] Docker installed successfully.${NC}"
    echo -e "${YELLOW}[NOTE] If you get permission errors, run: newgrp docker or restart WSL.${NC}"
fi

# Ensure docker service is running in WSL
if ! docker info >/dev/null 2>&1; then
    echo -e "${YELLOW}[INFO] Starting Docker daemon...${NC}"
    sudo service docker start || sudo systemctl start docker || true
    sleep 2
fi

# 2. Start Marzban container
echo -e "${BLUE}[INFO] Launching Marzban container via Docker Compose...${NC}"
if docker compose version >/dev/null 2>&1; then
    docker compose up -d
else
    docker-compose up -d
fi

echo -e "${GREEN}[SUCCESS] Marzban container is running!${NC}"
sleep 2

# 3. Create Admin User
echo ""
echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}             CREATE INITIAL MARZBAN ADMIN USER                  ${NC}"
echo -e "${CYAN}================================================================${NC}"
echo -e "Run the following command to create your admin username & password:"
echo -e "  ${YELLOW}docker exec -it marzban marzban cli admin create --sudo${NC}"
echo ""

# Check if running interactively
if [ -t 0 ]; then
    read -rp "Would you like to create the admin user right now? (y/N): " CREATE_NOW
    if [[ "$CREATE_NOW" =~ ^[Yy]$ ]]; then
        docker exec -it marzban marzban cli admin create --sudo || true
    fi
fi

echo ""
echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}             MARZBAN IS READY ON YOUR LAPTOP!                   ${NC}"
echo -e "${GREEN}================================================================${NC}"
echo -e "Open your browser in Windows 11:"
echo -e "  Dashboard URL: ${CYAN}http://127.0.0.1:8000/dashboard/${NC}"
echo -e "  Default Port:  ${YELLOW}8000${NC}"
echo -e "  Proxy Port:    ${YELLOW}443 (VLESS)${NC}"
echo ""
echo -e "Next steps:"
echo -e "  1. Log into http://127.0.0.1:8000/dashboard/"
echo -e "  2. Go to 'Inbounds' and verify VLESS protocol on port 443."
echo -e "  3. Go to 'Users' -> 'Create User' -> Generate QR code / link for friends."
echo -e "${GREEN}================================================================${NC}"
