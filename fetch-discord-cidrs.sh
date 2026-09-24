#!/usr/bin/env bash
# ==============================================================================
# fetch-discord-cidrs.sh
# ------------------------------------------------------------------------------
# Queries AS49544 (Discord Inc.) to automatically fetch and export all current
# Discord IP CIDR blocks into an AllowedIPs string or CIDR list.
#
# Primary Source: RIPE Stat API (Routing Information Service - BGP announced)
# Fallback Source: RADb WHOIS (IRR Route Objects)
# Optional: Discord Cloudflare edge prefixes for Discord API/Gateway/CDN
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASN="AS49544"

# Default configuration
IP_VERSION="4"              # 4, 6, or both
COLLAPSE=true               # Aggregate contiguous CIDRs
FORMAT="allowed-ips"        # allowed-ips, list, env
OUTPUT_FILE=""              # Write output to file
UPDATE_ENV=false            # Update .env file
ENV_FILE="${SCRIPT_DIR}/.env"
INCLUDE_CLOUDFLARE=true     # Include Discord's Cloudflare edge (162.159.128.0/21)
VERBOSE=false

# Discord Cloudflare edge prefixes (used for discord.com, gateway.discord.gg, cdn.discordapp.com)
DISCORD_CF_IPV4=("162.159.128.0/21")
DISCORD_CF_IPV6=("2606:4700:7::/48")

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

show_help() {
    cat << 'EOF'
Usage: ./fetch-discord-cidrs.sh [OPTIONS]

Queries AS49544 (Discord Inc.) to retrieve current IP CIDR blocks and formats
them for WireGuard AllowedIPs or iptables firewall filtering.

Options:
  -4, --ipv4              Fetch IPv4 CIDRs only (default)
  -6, --ipv6              Fetch IPv6 CIDRs only
  -a, --all               Fetch both IPv4 and IPv6 CIDRs
  -f, --format FORMAT     Output format:
                            allowed-ips : Comma-separated AllowedIPs string (default)
                            list        : One CIDR per line (ideal for iptables/ipset)
                            env         : Outputs WG_ALLOWED_IPS="..."
  -o, --output FILE       Write result to FILE (also keeps stdout clean)
  --no-collapse           Do not collapse/aggregate contiguous CIDR prefixes
  --no-cloudflare         Exclude Discord Cloudflare edge prefixes (AS13335)
                          (Note: Cloudflare hosts discord.com, gateway.discord.gg,
                           cdn.discordapp.com. Excluding it means text/login must
                           bypass the VPN or route directly).
  --update-env [FILE]     Automatically update WG_ALLOWED_IPS and INIT_ALLOWED_IPS
                          in .env file (default: .env in script directory)
  -v, --verbose           Show detailed log messages
  -h, --help              Show this help message

Examples:
  # Output AllowedIPs string for client WireGuard config:
  ./fetch-discord-cidrs.sh

  # Save CIDRs as a list for iptables:
  ./fetch-discord-cidrs.sh -f list -o discord-cidrs.txt

  # Fetch both IPv4 and IPv6 and update .env:
  ./fetch-discord-cidrs.sh --all --update-env

  # Output list including both IPv4 & IPv6:
  ./fetch-discord-cidrs.sh -a -f list
EOF
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -4|--ipv4)
            IP_VERSION="4"
            shift
            ;;
        -6|--ipv6)
            IP_VERSION="6"
            shift
            ;;
        -a|--all|--both)
            IP_VERSION="both"
            shift
            ;;
        -f|--format)
            FORMAT="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --no-collapse)
            COLLAPSE=false
            shift
            ;;
        --no-cloudflare)
            INCLUDE_CLOUDFLARE=false
            shift
            ;;
        --update-env)
            UPDATE_ENV=true
            if [[ $# -gt 1 && ! "$2" =~ ^- ]]; then
                ENV_FILE="$2"
                shift 2
            else
                shift
            fi
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

if [[ "$FORMAT" != "allowed-ips" && "$FORMAT" != "list" && "$FORMAT" != "env" ]]; then
    log_error "Invalid format '$FORMAT'. Supported: allowed-ips, list, env"
    exit 1
fi

# Fetch prefixes using Python (preferred for speed, robust JSON parsing, and CIDR collapsing)
fetch_with_python() {
    python3 - << PYEOF
import sys
import json
import urllib.request
import ipaddress

asn = "${ASN}"
ip_version = "${IP_VERSION}"
collapse = "${COLLAPSE}".lower() == "true"
include_cf = "${INCLUDE_CLOUDFLARE}".lower() == "true"
format_type = "${FORMAT}"

cf_v4 = ["162.159.128.0/21"]
cf_v6 = ["2606:4700:7::/48"]

prefixes = []

# 1. Primary query: RIPE Stat API
ripe_url = f"https://stat.ripe.net/data/announced-prefixes/data.json?resource={asn}"
req = urllib.request.Request(ripe_url, headers={"User-Agent": "Mozilla/5.0 (Discord-Gateway-CIDR-Fetcher)"})

try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read().decode("utf-8"))
        for item in data.get("data", {}).get("prefixes", []):
            p = item.get("prefix")
            if p:
                prefixes.append(p)
except Exception as e:
    sys.stderr.write(f"[WARN] RIPE Stat API query failed: {e}\n")

# 2. Fallback query if RIPE yielded nothing: RADb WHOIS
if not prefixes:
    sys.stderr.write("[INFO] Attempting fallback to RADb WHOIS...\n")
    import subprocess
    try:
        whois_out = subprocess.check_output(
            ["whois", "-h", "whois.radb.net", "--", f"-i origin {asn}"],
            timeout=10,
            text=True
        )
        for line in whois_out.splitlines():
            line = line.strip()
            if line.startswith("route:") or line.startswith("route6:"):
                parts = line.split()
                if len(parts) >= 2:
                    prefixes.append(parts[1])
    except Exception as e:
        sys.stderr.write(f"[ERROR] RADb fallback also failed: {e}\n")

if not prefixes:
    sys.stderr.write(f"[ERROR] Could not fetch any prefixes for {asn}.\n")
    sys.exit(1)

# Deduplicate raw prefixes
prefixes = sorted(list(set(prefixes)))

# Separate IPv4 and IPv6
raw_v4 = []
raw_v6 = []

for p in prefixes:
    try:
        net = ipaddress.ip_network(p, strict=False)
        if net.version == 4:
            raw_v4.append(net)
        elif net.version == 6:
            raw_v6.append(net)
    except ValueError:
        continue

# Add Cloudflare edge blocks if requested
if include_cf:
    for p in cf_v4:
        raw_v4.append(ipaddress.IPv4Network(p))
    for p in cf_v6:
        raw_v6.append(ipaddress.IPv6Network(p))

# Collapse/aggregate if enabled
if collapse:
    final_v4 = sorted(list(ipaddress.collapse_addresses(raw_v4)), key=lambda x: (x.network_address, x.prefixlen))
    final_v6 = sorted(list(ipaddress.collapse_addresses(raw_v6)), key=lambda x: (x.network_address, x.prefixlen))
else:
    final_v4 = sorted(raw_v4, key=lambda x: (x.network_address, x.prefixlen))
    final_v6 = sorted(raw_v6, key=lambda x: (x.network_address, x.prefixlen))

# Select based on IP_VERSION
selected = []
if ip_version in ("4", "both"):
    selected.extend([str(net) for net in final_v4])
if ip_version in ("6", "both"):
    selected.extend([str(net) for net in final_v6])

# Output formatting
if format_type == "allowed-ips":
    print(", ".join(selected))
elif format_type == "list":
    for net in selected:
        print(net)
elif format_type == "env":
    print(f'WG_ALLOWED_IPS="{", ".join(selected)}"')

PYEOF
}

# Fetch prefixes using pure curl/whois/awk as fallback if python3 is unavailable
fetch_with_shell() {
    log_warn "Python3 not found. Using shell fallback (aggregation disabled)..."
    local raw_prefixes=()

    # Try RIPE
    if command -v curl >/dev/null 2>&1; then
        local ripe_json
        ripe_json=$(curl -s -m 10 "https://stat.ripe.net/data/announced-prefixes/data.json?resource=${ASN}" 2>/dev/null || true)
        if [[ -n "$ripe_json" ]]; then
            mapfile -t raw_prefixes < <(echo "$ripe_json" | grep -oE '"prefix":"[^"]+"' | cut -d'"' -f4 | sort -u)
        fi
    fi

    # Try WHOIS if empty
    if [[ ${#raw_prefixes[@]} -eq 0 ]] && command -v whois >/dev/null 2>&1; then
        mapfile -t raw_prefixes < <(whois -h whois.radb.net -- "-i origin ${ASN}" 2>/dev/null | awk '/^route:|^route6:/ {print $2}' | sort -u)
    fi

    if [[ ${#raw_prefixes[@]} -eq 0 ]]; then
        log_error "Failed to retrieve prefixes for ${ASN} using shell fallback."
        exit 1
    fi

    local v4=()
    local v6=()

    for p in "${raw_prefixes[@]}"; do
        if [[ "$p" == *":"* ]]; then
            v6+=("$p")
        else
            v4+=("$p")
        fi
    done

    if [[ "$INCLUDE_CLOUDFLARE" == true ]]; then
        v4+=("${DISCORD_CF_IPV4[@]}")
        v6+=("${DISCORD_CF_IPV6[@]}")
    fi

    local selected=()
    if [[ "$IP_VERSION" == "4" || "$IP_VERSION" == "both" ]]; then
        selected+=("${v4[@]}")
    fi
    if [[ "$IP_VERSION" == "6" || "$IP_VERSION" == "both" ]]; then
        selected+=("${v6[@]}")
    fi

    # Format
    if [[ "$FORMAT" == "allowed-ips" ]]; then
        local IFS=", "
        echo "${selected[*]}"
    elif [[ "$FORMAT" == "list" ]]; then
        printf "%s\n" "${selected[@]}"
    elif [[ "$FORMAT" == "env" ]]; then
        local IFS=", "
        echo "WG_ALLOWED_IPS=\"${selected[*]}\""
    fi
}

# Run query
if [[ "$VERBOSE" == true ]]; then
    log_info "Querying prefixes for ${ASN} (IP version: ${IP_VERSION}, Cloudflare edge: ${INCLUDE_CLOUDFLARE})..."
fi

RESULT=""
if command -v python3 >/dev/null 2>&1; then
    RESULT=$(fetch_with_python)
else
    RESULT=$(fetch_with_shell)
fi

if [[ -z "$RESULT" ]]; then
    log_error "No prefixes returned."
    exit 1
fi

# Count CIDRs
CIDR_COUNT=0
if [[ "$FORMAT" == "allowed-ips" ]]; then
    CIDR_COUNT=$(echo "$RESULT" | awk -F',' '{print NF}')
elif [[ "$FORMAT" == "list" ]]; then
    CIDR_COUNT=$(echo "$RESULT" | grep -c . || true)
fi

if [[ "$VERBOSE" == true ]]; then
    log_success "Successfully resolved ${CIDR_COUNT} CIDR block(s)."
fi

# Handle output destination
if [[ -n "$OUTPUT_FILE" ]]; then
    echo "$RESULT" > "$OUTPUT_FILE"
    log_success "Saved output to: ${OUTPUT_FILE} (${CIDR_COUNT} CIDRs)"
else
    echo "$RESULT"
fi

# Handle updating .env file
if [[ "$UPDATE_ENV" == true ]]; then
    if [[ ! -f "$ENV_FILE" ]]; then
        if [[ -f "${SCRIPT_DIR}/.env.example" ]]; then
            cp "${SCRIPT_DIR}/.env.example" "$ENV_FILE"
            log_info "Created ${ENV_FILE} from .env.example"
        else
            touch "$ENV_FILE"
            log_info "Created empty ${ENV_FILE}"
        fi
    fi

    # Format as AllowedIPs string for .env
    ALLOWED_IPS_VAL="$RESULT"
    if [[ "$FORMAT" != "allowed-ips" ]]; then
        ALLOWED_IPS_VAL=$(echo "$RESULT" | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
    fi

    # Update or append WG_ALLOWED_IPS
    if grep -q "^WG_ALLOWED_IPS=" "$ENV_FILE"; then
        sed -i "s|^WG_ALLOWED_IPS=.*|WG_ALLOWED_IPS=\"${ALLOWED_IPS_VAL}\"|" "$ENV_FILE"
    else
        echo "WG_ALLOWED_IPS=\"${ALLOWED_IPS_VAL}\"" >> "$ENV_FILE"
    fi

    # Update or append INIT_ALLOWED_IPS (for wg-easy v15+)
    if grep -q "^INIT_ALLOWED_IPS=" "$ENV_FILE"; then
        sed -i "s|^INIT_ALLOWED_IPS=.*|INIT_ALLOWED_IPS=\"${ALLOWED_IPS_VAL}\"|" "$ENV_FILE"
    else
        echo "INIT_ALLOWED_IPS=\"${ALLOWED_IPS_VAL}\"" >> "$ENV_FILE"
    fi

    log_success "Updated WG_ALLOWED_IPS and INIT_ALLOWED_IPS in ${ENV_FILE}"
fi
