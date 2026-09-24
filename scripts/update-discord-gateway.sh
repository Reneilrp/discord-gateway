#!/usr/bin/env bash
# ==============================================================================
# scripts/update-discord-gateway.sh
# ------------------------------------------------------------------------------
# Cron / Automation script to periodically refresh Discord AS49544 CIDRs
# and reload iptables and WireGuard configuration without connection downtime.
# ==============================================================================

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_CIDRS="/tmp/discord-cidrs-new.$$.txt"

echo "[$(date -u +"%Y-%m-%d %H:%M:%SZ")] Starting periodic Discord CIDR sync..."

# Fetch new CIDRs into temporary file
"${BASE_DIR}/fetch-discord-cidrs.sh" -f list -o "$TEMP_CIDRS"

# Compare with existing file
if [[ -f "${BASE_DIR}/discord-cidrs.txt" ]] && cmp -s "$TEMP_CIDRS" "${BASE_DIR}/discord-cidrs.txt"; then
    echo "[$(date -u +"%Y-%m-%d %H:%M:%SZ")] No CIDR changes detected for AS49544. Everything is up to date."
    rm -f "$TEMP_CIDRS"
    exit 0
fi

echo "[$(date -u +"%Y-%m-%d %H:%M:%SZ")] CIDR changes detected! Updating discord-cidrs.txt..."
mv "$TEMP_CIDRS" "${BASE_DIR}/discord-cidrs.txt"

# Reload iptables rules atomically using ipset
echo "[$(date -u +"%Y-%m-%d %H:%M:%SZ")] Reloading iptables rules..."
"${BASE_DIR}/iptables-rules.sh" --apply

# Update .env AllowedIPs
echo "[$(date -u +"%Y-%m-%d %H:%M:%SZ")] Updating .env configuration..."
"${BASE_DIR}/fetch-discord-cidrs.sh" --update-env

echo "[$(date -u +"%Y-%m-%d %H:%M:%SZ")] Successfully synchronized Discord CIDRs and updated firewall."
