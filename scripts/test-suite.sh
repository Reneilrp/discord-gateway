#!/usr/bin/env bash
# ==============================================================================
# scripts/test-suite.sh
# ------------------------------------------------------------------------------
# Automated verification test suite for Discord WireGuard Gateway files
# ==============================================================================

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    exit 1
}

echo "=== Running Discord Gateway Verification Suite ==="

# 1. Syntax check shell scripts
echo "Checking shell scripts syntax..."
bash -n fetch-discord-cidrs.sh || fail "fetch-discord-cidrs.sh syntax error"
bash -n iptables-rules.sh || fail "iptables-rules.sh syntax error"
bash -n scripts/update-discord-gateway.sh || fail "scripts/update-discord-gateway.sh syntax error"
pass "All shell scripts passed syntax checks"

# 2. Check docker-compose.yml YAML validity and required fields
echo "Validating docker-compose.yml..."
python3 -c "
import yaml
with open('docker-compose.yml') as f:
    cfg = yaml.safe_load(f)
assert 'services' in cfg, 'Missing services'
assert 'wg-easy' in cfg['services'], 'Missing wg-easy service'
service = cfg['services']['wg-easy']
assert 'image' in service, 'Missing image'
caps = service.get('cap_add', [])
assert 'NET_ADMIN' in caps, 'Missing NET_ADMIN cap'
assert 'SYS_MODULE' in caps, 'Missing SYS_MODULE cap'
vols = service.get('volumes', [])
assert any('./data:/etc/wireguard' in str(v) for v in vols), 'Missing ./data:/etc/wireguard volume'
assert any('/lib/modules:/lib/modules:ro' in str(v) for v in vols), 'Missing /lib/modules volume'
sysctls = service.get('sysctls', [])
assert any('net.ipv4.ip_forward=1' in str(s) for s in sysctls), 'Missing ip_forward sysctl'
" || fail "docker-compose.yml validation failed"
pass "docker-compose.yml structure, capabilities, volumes, and sysctls validated"

# 3. Test fetch-discord-cidrs.sh
echo "Testing fetch-discord-cidrs.sh..."
ALLOWED_IPS_OUT=$(./fetch-discord-cidrs.sh)
if [[ -z "$ALLOWED_IPS_OUT" || "$ALLOWED_IPS_OUT" != *"/"* ]]; then
    fail "fetch-discord-cidrs.sh output is empty or invalid"
fi
CIDR_COUNT=$(echo "$ALLOWED_IPS_OUT" | awk -F',' '{print NF}')
if [[ $CIDR_COUNT -lt 10 ]]; then
    fail "Too few CIDRs returned ($CIDR_COUNT)"
fi
pass "fetch-discord-cidrs.sh returned $CIDR_COUNT aggregated CIDRs"

# 4. Test fetch-discord-cidrs.sh format options
echo "Testing CIDR list format..."
LIST_OUT=$(./fetch-discord-cidrs.sh -f list)
LINE_COUNT=$(echo "$LIST_OUT" | grep -c . || true)
if [[ $LINE_COUNT -ne $CIDR_COUNT ]]; then
    fail "Mismatch between list line count ($LINE_COUNT) and allowed-ips count ($CIDR_COUNT)"
fi
pass "List format matches CIDR count ($LINE_COUNT lines)"

# 5. Test iptables-rules.sh dry-run
echo "Testing iptables-rules.sh --dry-run..."
DRY_OUT=$(./iptables-rules.sh --dry-run)
echo "$DRY_OUT" | grep -q "WG-FORWARD" || fail "Missing WG-FORWARD chain in dry run"
echo "$DRY_OUT" | grep -q "dport 53" || fail "Missing DNS port 53 rule in dry run"
echo "$DRY_OUT" | grep -q "DROP" || fail "Missing DROP rule in dry run"
pass "iptables-rules.sh dry-run validated (WG-FORWARD chain, DNS allow, DROP rules confirmed)"

# 6. Test iptables-rules.sh --flush dry-run
echo "Testing iptables-rules.sh --flush --dry-run..."
FLUSH_OUT=$(./iptables-rules.sh --flush --dry-run)
echo "$FLUSH_OUT" | grep -q "iptables -F WG-FORWARD" || fail "Missing chain flush in dry run"
pass "iptables-rules.sh --flush dry-run validated"

# 7. Check sysctl.d/99-wireguard.conf
echo "Validating sysctl.d/99-wireguard.conf..."
grep -q "net.ipv4.ip_forward = 1" sysctl.d/99-wireguard.conf || fail "Missing net.ipv4.ip_forward = 1"
grep -q "net.ipv4.conf.all.src_valid_mark = 1" sysctl.d/99-wireguard.conf || fail "Missing src_valid_mark = 1"
pass "sysctl.d/99-wireguard.conf validated"

# 8. Check README.md documentation
echo "Validating README.md..."
grep -q "net.ipv4.ip_forward" README.md || fail "README missing sysctl documentation"
grep -q "fetch-discord-cidrs.sh" README.md || fail "README missing fetch script documentation"
grep -q "iptables-rules.sh" README.md || fail "README missing iptables script documentation"
grep -q "docker-compose" README.md || fail "README missing docker compose documentation"
pass "README.md validated"

echo ""
echo -e "${GREEN}=== ALL TESTS PASSED SUCCESSFULLY! ===${NC}"
