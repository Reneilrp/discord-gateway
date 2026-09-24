#!/usr/bin/env bash
# ==============================================================================
# scripts/toggle-services.sh
# ------------------------------------------------------------------------------
# Interactive & CLI tool to toggle which services to route/bypass:
#   - Discord  (AS49544 + Cloudflare 162.159.128.0/21)
#   - Reddit   (Fastly CDN edge + reddit domains)
#   - Facebook (Meta AS32934 + facebook/instagram/messenger domains)
#
# Updates:
#   1. WireGuard AllowedIPs (.env & service-cidrs.txt)
#   2. Xray-core Routing Rules (reverse-tunnel/laptop/config/config.json)
# ==============================================================================

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XRAY_CONFIG="${BASE_DIR}/reverse-tunnel/laptop/config/config.json"
SERVICE_CIDRS_FILE="${BASE_DIR}/service-cidrs.txt"
ENV_FILE="${BASE_DIR}/.env"

SERVICES=""
MODE="whitelist"  # whitelist (only selected services routed, others blocked) or full (all traffic allowed)
UPDATE_FIREWALL=false

# Terminal colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

show_help() {
    cat << 'EOF'
Usage: ./scripts/toggle-services.sh [OPTIONS]

Toggles which platforms are routed and bypassed through your gateway.

Options:
  -s, --services LIST     Comma-separated list of services:
                            discord   : Discord Voice/RTC & Cloudflare edge
                            reddit    : Reddit CDN & domains
                            facebook  : Meta (Facebook, Instagram, Messenger)
                            all       : Enable all services
  -m, --mode MODE         Proxy Mode:
                            whitelist : Gateway routes ONLY selected services, drops all others (default)
                            full      : Gateway routes all traffic (full VPN)
  -a, --apply-firewall    Automatically re-apply iptables rules (requires sudo)
  -h, --help              Show this help message

Examples:
  # Route ONLY Discord:
  ./scripts/toggle-services.sh --services discord

  # Route Discord and Reddit:
  ./scripts/toggle-services.sh --services discord,reddit

  # Route Facebook only:
  ./scripts/toggle-services.sh --services facebook

  # Route all platforms and reapply firewall:
  sudo ./scripts/toggle-services.sh --services all --apply-firewall
EOF
}

# Parse command line
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--services)
            SERVICES="$2"
            shift 2
            ;;
        -m|--mode)
            MODE="$2"
            shift 2
            ;;
        -a|--apply-firewall)
            UPDATE_FIREWALL=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}[ERROR] Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# If no services specified via CLI, prompt interactively
if [[ -z "$SERVICES" ]]; then
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}          DISCORD / REDDIT / FACEBOOK SERVICE SELECTOR          ${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo "Which services do you want to bypass through the gateway?"
    echo "  1) Discord ONLY"
    echo "  2) Reddit ONLY"
    echo "  3) Facebook ONLY (Meta / IG / Messenger)"
    echo "  4) Discord + Reddit"
    echo "  5) Discord + Facebook"
    echo "  6) ALL Services (Discord, Reddit, Facebook)"
    echo ""
    read -rp "Select an option [1-6]: " CHOICE

    case "$CHOICE" in
        1) SERVICES="discord" ;;
        2) SERVICES="reddit" ;;
        3) SERVICES="facebook" ;;
        4) SERVICES="discord,reddit" ;;
        5) SERVICES="discord,facebook" ;;
        6) SERVICES="all" ;;
        *)
            echo -e "${RED}Invalid choice. Defaulting to Discord.${NC}"
            SERVICES="discord"
            ;;
    esac
fi

echo -e "${BLUE}[INFO] Configuring gateway for services: [${SERVICES}] (Mode: ${MODE})...${NC}"

# 1. Update CIDR blocks and .env for WireGuard
echo -e "${BLUE}[1/2] Updating BGP IP CIDR blocks and .env...${NC}"
"${BASE_DIR}/fetch-service-cidrs.sh" --services "$SERVICES" -f list -o "$SERVICE_CIDRS_FILE"
"${BASE_DIR}/fetch-service-cidrs.sh" --services "$SERVICES" --update-env

# 2. Update Xray-core Routing Configuration
echo -e "${BLUE}[2/2] Updating Xray-core routing rules in ${XRAY_CONFIG}...${NC}"

python3 - << PYEOF
import json
import sys

config_path = "${XRAY_CONFIG}"
services_str = "${SERVICES}".lower()
mode = "${MODE}".lower()

if "all" in services_str:
    services = ["discord", "reddit", "facebook"]
else:
    services = [s.strip() for s in services_str.split(",") if s.strip()]

with open(config_path, "r") as f:
    cfg = json.load(f)

# Build domain and IP rules based on selected services
domain_list = []
ip_list = []

for s in services:
    if s == "discord":
        domain_list.extend(["geosite:discord", "domain:discord.com", "domain:discord.gg", "domain:discordapp.com", "domain:discordapp.net"])
        ip_list.append("162.159.128.0/21")
    elif s == "reddit":
        domain_list.extend(["geosite:reddit", "domain:reddit.com", "domain:redd.it", "domain:redditmedia.com", "domain:redditstatic.com"])
    elif s in ("facebook", "meta"):
        domain_list.extend(["geosite:facebook", "domain:facebook.com", "domain:fbcdn.net", "domain:instagram.com", "domain:messenger.com", "domain:whatsapp.com", "domain:threads.net"])
        ip_list.append("geoip:facebook")

rules = [
    {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
    },
    {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "blocked"
    },
    {
        "type": "field",
        "port": "25,465,587",
        "outboundTag": "blocked"
    }
]

if mode == "whitelist":
    # Only route selected domains and IPs through direct internet outbound
    rules.append({
        "type": "field",
        "domain": domain_list,
        "outboundTag": "direct"
    })
    if ip_list:
        rules.append({
            "type": "field",
            "ip": ip_list,
            "outboundTag": "direct"
        })
    # Drop/block everything else
    rules.append({
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "blocked"
    })
else:
    # Full mode: all traffic allowed
    rules.append({
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "direct"
    })

cfg["routing"]["rules"] = rules

with open(config_path, "w") as f:
    json.dump(cfg, f, indent=2)

print(f"[OK] Xray routing updated with {len(domain_list)} domain rules and {len(ip_list)} IP rules.")
PYEOF

# 3. Re-apply iptables if requested
if [[ "$UPDATE_FIREWALL" == true ]]; then
    echo -e "${BLUE}[INFO] Re-applying iptables firewall rules...${NC}"
    if [[ $EUID -eq 0 ]]; then
        "${BASE_DIR}/iptables-rules.sh" --apply
    elif command -v sudo >/dev/null 2>&1; then
        sudo "${BASE_DIR}/iptables-rules.sh" --apply
    else
        echo -e "${YELLOW}[WARN] Sudo required to update iptables. Run: sudo ./iptables-rules.sh --apply${NC}"
    fi
fi

echo ""
echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}               SERVICE CONFIGURATION UPDATED!                   ${NC}"
echo -e "${GREEN}================================================================${NC}"
echo -e "Active Services: ${YELLOW}${SERVICES}${NC}"
echo -e "Proxy Mode:      ${YELLOW}${MODE}${NC}"
echo -e "WireGuard CIDRs: ${CYAN}${SERVICE_CIDRS_FILE}${NC}"
echo -e "Xray Config:     ${CYAN}${XRAY_CONFIG}${NC}"
echo ""
echo -e "To restart Xray on your laptop with the new routing:"
echo -e "  ${YELLOW}cd reverse-tunnel/laptop && docker compose restart${NC}"
echo -e "  (or in Marzban: Core Settings -> Save & Restart)${NC}"
echo -e "${GREEN}================================================================${NC}"
