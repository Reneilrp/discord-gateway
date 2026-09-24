#!/usr/bin/env bash
# ==============================================================================
# iptables-rules.sh
# ------------------------------------------------------------------------------
# Applies strict firewall forwarding rules for the WireGuard interface (wg0)
# on an Ubuntu VPS:
#   1. Allows established and related connections.
#   2. Allows outbound DNS (UDP/TCP port 53).
#   3. Allows outbound traffic exclusively to Discord IP CIDRs (AS49544 + edge).
#   4. Drops all other forwarded traffic from the WireGuard interface.
#   5. Configures NAT/MASQUERADE for WireGuard clients out to the internet.
#
# Supports:
#   - High-performance ipset with fallback to direct iptables rules
#   - Dedicated WG-FORWARD chain (avoids collisions with Docker / host rules)
#   - Safe dry-run inspection (--dry-run)
#   - Flush / status / persistence commands
#   - Optional execution inside Docker container (--container)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration defaults
WG_INTERFACE="wg0"
WG_SUBNET="10.8.0.0/24"
WG_SUBNET_V6="fd42:42:42::/64"
WAN_INTERFACE=""
CIDR_FILE="${SCRIPT_DIR}/discord-cidrs.txt"
DNS_IPS=""                  # Empty = any DNS; or comma-separated IPs (e.g. 1.1.1.1,1.0.0.1)
LOG_DROPS=true              # Log dropped forwarded packets (rate limited)
DRY_RUN=false
VERBOSE=false
ACTION="apply"              # apply, flush, status, save
ENABLE_IPV6=false
CONTAINER_NAME=""           # If set, execute inside docker container

# Set names
IPSET_V4="discord_v4"
IPSET_V6="discord_v6"
CHAIN_FWD="WG-FORWARD"

# Terminal Colors
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
Usage: sudo ./iptables-rules.sh [ACTION] [OPTIONS]

Actions:
  -a, --apply             Apply WireGuard forwarding firewall rules (default)
  -f, --flush             Remove WireGuard firewall rules and flush WG-FORWARD chain
  -s, --status            Display active WireGuard firewall rules and statistics
  -p, --save              Persist active firewall rules to survive VPS reboot

Options:
  -i, --interface IFACE   WireGuard interface name (default: wg0)
  -o, --wan IFACE         WAN/public interface for NAT (default: auto-detected)
  -n, --subnet CIDR       WireGuard IPv4 client subnet (default: 10.8.0.0/24)
  --subnet-v6 CIDR        WireGuard IPv6 client subnet (default: fd42:42:42::/64)
  -c, --cidrs FILE        Path to Discord CIDRs list (default: discord-cidrs.txt)
  --dns-servers IPS       Restrict DNS to specific IPs (e.g. "1.1.1.1,1.0.0.1"; default: any)
  --enable-ipv6           Also configure ip6tables rules for Discord IPv6 blocks
  --no-log                Do not log dropped packets
  --container NAME        Apply rules inside a Docker container (e.g. wg-easy)
  -d, --dry-run           Print all commands without executing them
  -v, --verbose           Show detailed execution output
  -h, --help              Show this help message

Examples:
  # Apply Discord-only lockdown rules:
  sudo ./iptables-rules.sh --apply

  # Dry-run preview:
  ./iptables-rules.sh --dry-run

  # Apply and persist across reboots:
  sudo ./iptables-rules.sh --apply --save

  # Check active rules and packet counters:
  sudo ./iptables-rules.sh --status

  # Flush/remove rules:
  sudo ./iptables-rules.sh --flush
EOF
}

# Parse command line
while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--apply)
            ACTION="apply"
            shift
            ;;
        -f|--flush)
            ACTION="flush"
            shift
            ;;
        -s|--status)
            ACTION="status"
            shift
            ;;
        -p|--save)
            ACTION="save"
            shift
            ;;
        -i|--interface)
            WG_INTERFACE="$2"
            shift 2
            ;;
        -o|--wan)
            WAN_INTERFACE="$2"
            shift 2
            ;;
        -n|--subnet)
            WG_SUBNET="$2"
            shift 2
            ;;
        --subnet-v6)
            WG_SUBNET_V6="$2"
            shift 2
            ;;
        -c|--cidrs)
            CIDR_FILE="$2"
            shift 2
            ;;
        --dns-servers)
            DNS_IPS="$2"
            shift 2
            ;;
        --enable-ipv6)
            ENABLE_IPV6=true
            shift
            ;;
        --no-log)
            LOG_DROPS=false
            shift
            ;;
        --container)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
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

# Wrapper to execute commands or display in dry-run
run_cmd() {
    local cmd="$*"
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${CYAN}[DRY-RUN]${NC} $cmd"
    else
        if [[ "$VERBOSE" == true ]]; then
            log_info "Executing: $cmd"
        fi
        if [[ -n "$CONTAINER_NAME" ]]; then
            docker exec "$CONTAINER_NAME" bash -c "$cmd"
        else
            eval "$cmd"
        fi
    fi
}

# Auto-detect default WAN interface if not specified
detect_wan_interface() {
    if [[ -n "$WAN_INTERFACE" ]]; then
        return
    fi

    if [[ "$DRY_RUN" == true ]]; then
        WAN_INTERFACE="eth0 (auto-detect simulated)"
        return
    fi

    local detected
    if command -v ip >/dev/null 2>&1; then
        detected=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -n1 || true)
    fi

    if [[ -z "$detected" ]]; then
        detected="eth0"
        log_warn "Could not auto-detect WAN interface, falling back to 'eth0'."
    else
        log_info "Auto-detected WAN interface: $detected"
    fi
    WAN_INTERFACE="$detected"
}

# Privilege check
check_privileges() {
    if [[ "$DRY_RUN" == true ]]; then
        return
    fi
    if [[ -n "$CONTAINER_NAME" ]]; then
        if ! command -v docker >/dev/null 2>&1; then
            log_error "Docker is required when targeting container '$CONTAINER_NAME'."
            exit 1
        fi
        return
    fi
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo) to modify iptables."
        exit 1
    fi
}

# Detect if ipset is available and functional
has_ipset() {
    if [[ "$DRY_RUN" == true ]]; then
        return 0
    fi
    if [[ -n "$CONTAINER_NAME" ]]; then
        docker exec "$CONTAINER_NAME" command -v ipset >/dev/null 2>&1
        return $?
    fi
    command -v ipset >/dev/null 2>&1
}

# Read or fetch CIDR blocks
load_cidrs() {
    local target_file="$1"
    if [[ ! -f "$target_file" ]]; then
        log_warn "CIDR file '${target_file}' not found. Attempting to fetch..."
        if [[ -x "${SCRIPT_DIR}/fetch-discord-cidrs.sh" ]]; then
            local flags=("-f" "list" "-o" "$target_file")
            if [[ "$ENABLE_IPV6" == true ]]; then
                flags+=("--all")
            fi
            "${SCRIPT_DIR}/fetch-discord-cidrs.sh" "${flags[@]}"
        else
            log_error "Could not find fetch-discord-cidrs.sh to generate CIDR list."
            exit 1
        fi
    fi
}

# Flush WireGuard firewall rules
flush_rules() {
    log_info "Flushing WireGuard firewall rules..."

    # Remove jump rules from FORWARD chain if present
    run_cmd "iptables -D FORWARD -i ${WG_INTERFACE} -j ${CHAIN_FWD} 2>/dev/null || true"
    run_cmd "iptables -D FORWARD -o ${WG_INTERFACE} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true"
    run_cmd "iptables -D FORWARD -o ${WG_INTERFACE} -j DROP 2>/dev/null || true"

    # Flush and delete custom chain
    run_cmd "iptables -F ${CHAIN_FWD} 2>/dev/null || true"
    run_cmd "iptables -X ${CHAIN_FWD} 2>/dev/null || true"

    # Destroy ipset if exists
    if has_ipset; then
        run_cmd "ipset destroy ${IPSET_V4} 2>/dev/null || true"
    fi

    # IPv6 cleanup if enabled
    if [[ "$ENABLE_IPV6" == true ]]; then
        run_cmd "ip6tables -D FORWARD -i ${WG_INTERFACE} -j ${CHAIN_FWD} 2>/dev/null || true"
        run_cmd "ip6tables -D FORWARD -o ${WG_INTERFACE} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true"
        run_cmd "ip6tables -D FORWARD -o ${WG_INTERFACE} -j DROP 2>/dev/null || true"
        run_cmd "ip6tables -F ${CHAIN_FWD} 2>/dev/null || true"
        run_cmd "ip6tables -X ${CHAIN_FWD} 2>/dev/null || true"
        if has_ipset; then
            run_cmd "ipset destroy ${IPSET_V6} 2>/dev/null || true"
        fi
    fi

    # Remove NAT rule
    if [[ -n "$WAN_INTERFACE" && "$WAN_INTERFACE" != *"simulated"* ]]; then
        run_cmd "iptables -t nat -D POSTROUTING -s ${WG_SUBNET} -o ${WAN_INTERFACE} -j MASQUERADE 2>/dev/null || true"
        if [[ "$ENABLE_IPV6" == true ]]; then
            run_cmd "ip6tables -t nat -D POSTROUTING -s ${WG_SUBNET_V6} -o ${WAN_INTERFACE} -j MASQUERADE 2>/dev/null || true"
        fi
    fi

    log_success "WireGuard firewall rules flushed successfully."
}

# Apply lockdown rules
apply_rules() {
    detect_wan_interface
    load_cidrs "$CIDR_FILE"

    log_info "Applying WireGuard lockdown rules on interface: ${WG_INTERFACE}..."
    log_info "Subnet: ${WG_SUBNET} | WAN Interface: ${WAN_INTERFACE}"

    # 1. Clean up any existing instance of the custom chain
    run_cmd "iptables -D FORWARD -i ${WG_INTERFACE} -j ${CHAIN_FWD} 2>/dev/null || true"
    run_cmd "iptables -F ${CHAIN_FWD} 2>/dev/null || true"
    run_cmd "iptables -N ${CHAIN_FWD} 2>/dev/null || true"

    # 2. Connection Tracking: Allow ESTABLISHED, RELATED
    run_cmd "iptables -A ${CHAIN_FWD} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"

    # 3. Allow DNS Traffic (UDP/TCP Port 53)
    if [[ -n "$DNS_IPS" ]]; then
        IFS=',' read -ra DNS_ARRAY <<< "$DNS_IPS"
        for dns in "${DNS_ARRAY[@]}"; do
            dns=$(echo "$dns" | xargs)
            run_cmd "iptables -A ${CHAIN_FWD} -p udp -d ${dns} --dport 53 -j ACCEPT"
            run_cmd "iptables -A ${CHAIN_FWD} -p tcp -d ${dns} --dport 53 -j ACCEPT"
        done
        log_info "Allowed DNS traffic restricted to: ${DNS_IPS}"
    else
        run_cmd "iptables -A ${CHAIN_FWD} -p udp --dport 53 -j ACCEPT"
        run_cmd "iptables -A ${CHAIN_FWD} -p tcp --dport 53 -j ACCEPT"
        log_info "Allowed all outgoing DNS (port 53 UDP/TCP)"
    fi

    # 4. Allow Discord CIDRs
    # Filter IPv4 CIDRs from CIDR_FILE
    local v4_cidrs=()
    local v6_cidrs=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        line=$(echo "$line" | sed 's/^[ \t]*//;s/[ \t]*$//')
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        if [[ "$line" == *":"* ]]; then
            v6_cidrs+=("$line")
        else
            v4_cidrs+=("$line")
        fi
    done < "$CIDR_FILE"

    log_info "Loaded ${#v4_cidrs[@]} IPv4 Discord CIDR(s) from ${CIDR_FILE}"

    if has_ipset; then
        log_info "Using ipset for O(1) high-performance CIDR filtering..."
        # Create temporary swap set to ensure atomic updates without downtime
        run_cmd "ipset create ${IPSET_V4}_new hash:net maxelem 65536 -exist"
        run_cmd "ipset flush ${IPSET_V4}_new"

        for cidr in "${v4_cidrs[@]}"; do
            run_cmd "ipset add ${IPSET_V4}_new ${cidr} -exist"
        done

        # Create target set if it doesn't exist yet
        run_cmd "ipset create ${IPSET_V4} hash:net maxelem 65536 -exist"
        # Atomically swap
        run_cmd "ipset swap ${IPSET_V4}_new ${IPSET_V4}"
        run_cmd "ipset destroy ${IPSET_V4}_new"

        # Match destination against ipset
        run_cmd "iptables -A ${CHAIN_FWD} -m set --match-set ${IPSET_V4} dst -j ACCEPT"
    else
        log_warn "ipset not found. Inserting ${#v4_cidrs[@]} individual iptables rules..."
        for cidr in "${v4_cidrs[@]}"; do
            run_cmd "iptables -A ${CHAIN_FWD} -d ${cidr} -j ACCEPT"
        done
    fi

    # 5. Drop all remaining traffic from WireGuard interface
    if [[ "$LOG_DROPS" == true ]]; then
        run_cmd "iptables -A ${CHAIN_FWD} -m limit --limit 10/min --limit-burst 20 -j LOG --log-prefix '[WG-DISCORD-DROP]: ' --log-level 4"
    fi
    run_cmd "iptables -A ${CHAIN_FWD} -j DROP"

    # 6. Hook the WG-FORWARD chain into host FORWARD chain
    run_cmd "iptables -I FORWARD 1 -i ${WG_INTERFACE} -j ${CHAIN_FWD}"

    # 7. Protect return path into WireGuard interface
    run_cmd "iptables -D FORWARD -o ${WG_INTERFACE} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true"
    run_cmd "iptables -I FORWARD 2 -o ${WG_INTERFACE} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
    run_cmd "iptables -D FORWARD -o ${WG_INTERFACE} -j DROP 2>/dev/null || true"
    run_cmd "iptables -A FORWARD -o ${WG_INTERFACE} -j DROP"

    # 8. Configure NAT / MASQUERADE in POSTROUTING
    if [[ -n "$WAN_INTERFACE" && "$WAN_INTERFACE" != *"simulated"* ]]; then
        local nat_exists
        nat_exists=$(iptables -t nat -C POSTROUTING -s "${WG_SUBNET}" -o "${WAN_INTERFACE}" -j MASQUERADE 2>/dev/null && echo "yes" || echo "no")
        if [[ "$nat_exists" == "no" ]]; then
            run_cmd "iptables -t nat -A POSTROUTING -s ${WG_SUBNET} -o ${WAN_INTERFACE} -j MASQUERADE"
            log_info "Configured NAT MASQUERADE for ${WG_SUBNET} -> ${WAN_INTERFACE}"
        fi
    fi

    # 9. Handle IPv6 if requested
    if [[ "$ENABLE_IPV6" == true && ${#v6_cidrs[@]} -gt 0 ]]; then
        log_info "Configuring ip6tables for ${#v6_cidrs[@]} IPv6 Discord CIDRs..."
        run_cmd "ip6tables -D FORWARD -i ${WG_INTERFACE} -j ${CHAIN_FWD} 2>/dev/null || true"
        run_cmd "ip6tables -F ${CHAIN_FWD} 2>/dev/null || true"
        run_cmd "ip6tables -N ${CHAIN_FWD} 2>/dev/null || true"
        run_cmd "ip6tables -A ${CHAIN_FWD} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
        run_cmd "ip6tables -A ${CHAIN_FWD} -p udp --dport 53 -j ACCEPT"
        run_cmd "ip6tables -A ${CHAIN_FWD} -p tcp --dport 53 -j ACCEPT"

        if has_ipset; then
            run_cmd "ipset create ${IPSET_V6}_new hash:net family inet6 maxelem 65536 -exist"
            run_cmd "ipset flush ${IPSET_V6}_new"
            for cidr in "${v6_cidrs[@]}"; do
                run_cmd "ipset add ${IPSET_V6}_new ${cidr} -exist"
            done
            run_cmd "ipset create ${IPSET_V6} hash:net family inet6 maxelem 65536 -exist"
            run_cmd "ipset swap ${IPSET_V6}_new ${IPSET_V6}"
            run_cmd "ipset destroy ${IPSET_V6}_new"
            run_cmd "ip6tables -A ${CHAIN_FWD} -m set --match-set ${IPSET_V6} dst -j ACCEPT"
        else
            for cidr in "${v6_cidrs[@]}"; do
                run_cmd "ip6tables -A ${CHAIN_FWD} -d ${cidr} -j ACCEPT"
            done
        fi

        if [[ "$LOG_DROPS" == true ]]; then
            run_cmd "ip6tables -A ${CHAIN_FWD} -m limit --limit 10/min --limit-burst 20 -j LOG --log-prefix '[WG6-DISCORD-DROP]: ' --log-level 4"
        fi
        run_cmd "ip6tables -A ${CHAIN_FWD} -j DROP"
        run_cmd "ip6tables -I FORWARD 1 -i ${WG_INTERFACE} -j ${CHAIN_FWD}"
        run_cmd "ip6tables -I FORWARD 2 -o ${WG_INTERFACE} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
        run_cmd "ip6tables -A FORWARD -o ${WG_INTERFACE} -j DROP"

        if [[ -n "$WAN_INTERFACE" && "$WAN_INTERFACE" != *"simulated"* ]]; then
            run_cmd "ip6tables -t nat -A POSTROUTING -s ${WG_SUBNET_V6} -o ${WAN_INTERFACE} -j MASQUERADE 2>/dev/null || true"
        fi
    fi

    log_success "WireGuard lockdown firewall successfully applied!"
    log_info "Traffic on ${WG_INTERFACE} is now restricted to DNS + Discord only."
}

# Display firewall status
show_status() {
    log_info "=== WireGuard FORWARD Chain Status ==="
    if command -v iptables >/dev/null 2>&1; then
        echo -e "${YELLOW}iptables -L ${CHAIN_FWD} -v -n --line-numbers:${NC}"
        iptables -L "${CHAIN_FWD}" -v -n --line-numbers 2>/dev/null || log_warn "Chain ${CHAIN_FWD} does not exist."
        echo ""
        echo -e "${YELLOW}iptables -L FORWARD -v -n --line-numbers | grep ${WG_INTERFACE}:${NC}"
        iptables -L FORWARD -v -n --line-numbers 2>/dev/null | grep -E "${WG_INTERFACE}|${CHAIN_FWD}" || true
    fi

    if has_ipset; then
        echo ""
        echo -e "${YELLOW}ipset header ${IPSET_V4}:${NC}"
        ipset list "${IPSET_V4}" -terse 2>/dev/null || true
    fi
}

# Save rules to persist across reboot
save_rules() {
    log_info "Persisting firewall rules across reboots..."
    if command -v netfilter-persistent >/dev/null 2>&1; then
        run_cmd "netfilter-persistent save"
        log_success "Saved with netfilter-persistent."
    elif command -v iptables-save >/dev/null 2>&1; then
        mkdir -p /etc/iptables
        run_cmd "iptables-save > /etc/iptables/rules.v4"
        if [[ "$ENABLE_IPV6" == true ]] && command -v ip6tables-save >/dev/null 2>&1; then
            run_cmd "ip6tables-save > /etc/iptables/rules.v6"
        fi
        log_success "Saved to /etc/iptables/rules.v4."
    else
        log_warn "Neither netfilter-persistent nor iptables-save found."
        log_info "Install netfilter-persistent: sudo apt-get install -y iptables-persistent"
    fi

    if has_ipset; then
        mkdir -p /etc/iptables
        run_cmd "ipset save > /etc/iptables/ipset.rules"
        log_success "Saved ipset entries to /etc/iptables/ipset.rules."
    fi
}

# Execution Entry Point
check_privileges

case "$ACTION" in
    apply)
        apply_rules
        ;;
    flush)
        flush_rules
        ;;
    status)
        show_status
        ;;
    save)
        save_rules
        ;;
    *)
        log_error "Unknown action: $ACTION"
        exit 1
        ;;
esac
