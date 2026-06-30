# Shared config for Crontinel sandbox tests
# Source this from test scripts: source "$(dirname "$0")/config.sh"

# Production API
CRONTINEL_API_URL="${CRONTINEL_API_URL:-https://app.crontinel.com}"

# API key — MUST be set via CRONTINEL_API_KEY env var
: "${CRONTINEL_API_KEY:?CRONTINEL_API_KEY env var is required}"

export CRONTINEL_API_KEY CRONTINEL_API_URL

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS=0
FAIL=0

pass() {
    echo -e "  ${GREEN}✓${NC} $1"
    ((PASS++)) || true
}

fail() {
    echo -e "  ${RED}✗${NC} $1"
    ((FAIL++)) || true
}

skip() {
    echo -e "  ${YELLOW}⊘${NC} $1"
}

summary() {
    local name="$1"
    echo ""
    echo "────────────────────────────────────────"
    echo -e "  ${name}: ${GREEN}$PASS passed${NC}" "${RED}$FAIL failed${NC}"
    echo "────────────────────────────────────────"
    echo ""
}

require_cmd() {
    if ! command -v "$1" &>/dev/null; then
        skip "Missing dependency: $1"
        return 1
    fi
}
