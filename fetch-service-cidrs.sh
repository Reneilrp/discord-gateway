#!/usr/bin/env bash
# ==============================================================================
# fetch-service-cidrs.sh
# ------------------------------------------------------------------------------
# Modular CIDR fetcher and AllowedIPs exporter with service-level toggling:
#   - Discord  : AS49544 (Discord Inc.) + Cloudflare Edge (162.159.128.0/21)
#   - Reddit   : Fastly Public IP List (Reddit's primary CDN & media edge)
#   - Facebook : AS32934 (Meta Platforms, Inc. / FB, IG, Messenger, WhatsApp)
#
# Allows users to enable any combination (e.g. discord, reddit, facebook, or all)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration defaults
SERVICES="discord"          # Default service; comma-separated: discord,reddit,facebook,all
IP_VERSION="4"              # 4, 6, or both
COLLAPSE=true               # Aggregate contiguous CIDRs
FORMAT="allowed-ips"        # allowed-ips, list, env
OUTPUT_FILE=""
UPDATE_ENV=false
ENV_FILE="${SCRIPT_DIR}/.env"
VERBOSE=false

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

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
Usage: ./fetch-service-cidrs.sh [OPTIONS]

Queries BGP routing tables and public APIs to fetch IP CIDR blocks for
selected services and exports them into WireGuard AllowedIPs or iptables lists.

Options:
  -s, --services LIST     Comma-separated list of services to include:
                            discord   : AS49544 + Discord Cloudflare edge
                            reddit    : Fastly CDN edge blocks used by Reddit
                            facebook  : AS32934 (Meta / FB / IG / Messenger)
                            all       : Include all available services
                          Default: discord

  -4, --ipv4              Fetch IPv4 CIDRs only (default)
  -6, --ipv6              Fetch IPv6 CIDRs only
  -a, --all               Fetch both IPv4 and IPv6 CIDRs

  -f, --format FORMAT     Output format:
                            allowed-ips : Comma-separated AllowedIPs string (default)
                            list        : One CIDR per line (for iptables/ipset)
                            env         : Outputs WG_ALLOWED_IPS="..."

  -o, --output FILE       Write result to FILE
  --update-env [FILE]     Update WG_ALLOWED_IPS & INIT_ALLOWED_IPS in .env
  --no-collapse           Do not collapse contiguous CIDR prefixes
  -v, --verbose           Show detailed log messages
  -h, --help              Show this help message

Examples:
  # Only Discord:
  ./fetch-service-cidrs.sh --services discord

  # Discord + Reddit:
  ./fetch-service-cidrs.sh --services discord,reddit -f list -o service-cidrs.txt

  # Facebook only:
  ./fetch-service-cidrs.sh --services facebook

  # All services, update .env:
  ./fetch-service-cidrs.sh --services all --update-env
EOF
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--services)
            SERVICES="$2"
            shift 2
            ;;
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
        --update-env)
            UPDATE_ENV=true
            if [[ $# -gt 1 && ! "$2" =~ ^- ]]; then
                ENV_FILE="$2"
                shift 2
            else
                shift
            fi
            ;;
        --no-collapse)
            COLLAPSE=false
            shift
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

# Run query in Python for fast BGP parsing, Fastly API, and CIDR collapsing
RESULT=$(python3 - << PYEOF
import sys
import json
import urllib.request
import ipaddress

services_arg = "${SERVICES}".lower().split(",")
if "all" in services_arg:
    services = ["discord", "reddit", "facebook"]
else:
    services = [s.strip() for s in services_arg if s.strip()]

ip_version = "${IP_VERSION}"
collapse = "${COLLAPSE}".lower() == "true"
format_type = "${FORMAT}"

raw_v4 = []
raw_v6 = []

headers = {"User-Agent": "Mozilla/5.0 (Service-CIDR-Fetcher)"}

def fetch_asn_prefixes(asn):
    url = f"https://stat.ripe.net/data/announced-prefixes/data.json?resource={asn}"
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=12) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return [p["prefix"] for p in data.get("data", {}).get("prefixes", []) if p.get("prefix")]
    except Exception as e:
        sys.stderr.write(f"[WARN] Failed to query {asn} from RIPE: {e}\n")
        return []

# 1. DISCORD (AS49544 + Cloudflare 162.159.128.0/21)
if "discord" in services:
    sys.stderr.write("[INFO] Querying Discord Inc. (AS49544)...\n")
    discord_prefixes = fetch_asn_prefixes("AS49544")
    # Add Cloudflare Discord fronting ranges
    discord_prefixes.append("162.159.128.0/21")
    discord_prefixes.append("2606:4700:7::/48")
    for p in discord_prefixes:
        try:
            net = ipaddress.ip_network(p, strict=False)
            if net.version == 4:
                raw_v4.append(net)
            else:
                raw_v6.append(net)
        except ValueError:
            continue

# 2. REDDIT (Fastly CDN public IP list)
if "reddit" in services:
    sys.stderr.write("[INFO] Querying Reddit edge infrastructure (Fastly CDN)...\n")
    try:
        req = urllib.request.Request("https://api.fastly.com/public-ip-list", headers=headers)
        with urllib.request.urlopen(req, timeout=10) as resp:
            fastly_data = json.loads(resp.read().decode("utf-8"))
            for p in fastly_data.get("addresses", []):
                raw_v4.append(ipaddress.IPv4Network(p))
            for p in fastly_data.get("ipv6_addresses", []):
                raw_v6.append(ipaddress.IPv6Network(p))
    except Exception as e:
        sys.stderr.write(f"[WARN] Fastly API failed: {e}. Falling back to standard Fastly prefixes...\n")
        for p in ["151.101.0.0/16", "199.232.0.0/16"]:
            raw_v4.append(ipaddress.IPv4Network(p))

# 3. FACEBOOK / META (AS32934)
if "facebook" in services or "meta" in services:
    sys.stderr.write("[INFO] Querying Meta Platforms / Facebook (AS32934)...\n")
    meta_prefixes = fetch_asn_prefixes("AS32934")
    for p in meta_prefixes:
        try:
            net = ipaddress.ip_network(p, strict=False)
            if net.version == 4:
                raw_v4.append(net)
            else:
                raw_v6.append(net)
        except ValueError:
            continue

if not raw_v4 and not raw_v6:
    sys.stderr.write("[ERROR] No prefixes could be retrieved.\n")
    sys.exit(1)

# Deduplicate
raw_v4 = list(set(raw_v4))
raw_v6 = list(set(raw_v6))

# Collapse/aggregate if enabled
if collapse:
    final_v4 = sorted(list(ipaddress.collapse_addresses(raw_v4)), key=lambda x: (x.network_address, x.prefixlen))
    final_v6 = sorted(list(ipaddress.collapse_addresses(raw_v6)), key=lambda x: (x.network_address, x.prefixlen))
else:
    final_v4 = sorted(raw_v4, key=lambda x: (x.network_address, x.prefixlen))
    final_v6 = sorted(raw_v6, key=lambda x: (x.network_address, x.prefixlen))

selected = []
if ip_version in ("4", "both"):
    selected.extend([str(net) for net in final_v4])
if ip_version in ("6", "both"):
    selected.extend([str(net) for net in final_v6])

# Output
if format_type == "allowed-ips":
    print(", ".join(selected))
elif format_type == "list":
    for net in selected:
        print(net)
elif format_type == "env":
    print(f'WG_ALLOWED_IPS="{", ".join(selected)}"')
PYEOF
)

if [[ -z "$RESULT" ]]; then
    log_error "No prefixes returned."
    exit 1
fi

CIDR_COUNT=0
if [[ "$FORMAT" == "allowed-ips" ]]; then
    CIDR_COUNT=$(echo "$RESULT" | awk -F',' '{print NF}')
elif [[ "$FORMAT" == "list" ]]; then
    CIDR_COUNT=$(echo "$RESULT" | grep -c . || true)
fi

log_success "Successfully resolved ${CIDR_COUNT} CIDR block(s) for services: [${SERVICES}]"

# Handle file output
if [[ -n "$OUTPUT_FILE" ]]; then
    echo "$RESULT" > "$OUTPUT_FILE"
    log_success "Saved output to: ${OUTPUT_FILE} (${CIDR_COUNT} CIDRs)"
else
    echo "$RESULT"
fi

# Handle .env update
if [[ "$UPDATE_ENV" == true ]]; then
    if [[ ! -f "$ENV_FILE" ]]; then
        if [[ -f "${SCRIPT_DIR}/.env.example" ]]; then
            cp "${SCRIPT_DIR}/.env.example" "$ENV_FILE"
        else
            touch "$ENV_FILE"
        fi
    fi

    ALLOWED_IPS_VAL="$RESULT"
    if [[ "$FORMAT" != "allowed-ips" ]]; then
        ALLOWED_IPS_VAL=$(echo "$RESULT" | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
    fi

    if grep -q "^WG_ALLOWED_IPS=" "$ENV_FILE"; then
        sed -i "s|^WG_ALLOWED_IPS=.*|WG_ALLOWED_IPS=\"${ALLOWED_IPS_VAL}\"|" "$ENV_FILE"
    else
        echo "WG_ALLOWED_IPS=\"${ALLOWED_IPS_VAL}\"" >> "$ENV_FILE"
    fi

    if grep -q "^INIT_ALLOWED_IPS=" "$ENV_FILE"; then
        sed -i "s|^INIT_ALLOWED_IPS=.*|INIT_ALLOWED_IPS=\"${ALLOWED_IPS_VAL}\"|" "$ENV_FILE"
    else
        echo "INIT_ALLOWED_IPS=\"${ALLOWED_IPS_VAL}\"" >> "$ENV_FILE"
    fi

    log_success "Updated WG_ALLOWED_IPS and INIT_ALLOWED_IPS in ${ENV_FILE}"
fi
