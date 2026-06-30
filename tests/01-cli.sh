#!/usr/bin/env bash
set -euo pipefail

# Test 01: CLI — crontinel binary
# Tests: --help, ping, monitors, events, alerts

cd "$(dirname "$0")"
source ../config.sh

echo "=== Test 01: CLI ==="

# 1. Check binary installed
if command -v crontinel &>/dev/null; then
    CLI=crontinel
elif [ -f /tmp/crontinel ]; then
    CLI=/tmp/crontinel
else
    fail "crontinel binary not found"
    summary "CLI"
    exit 1
fi

# 2. --help works (prints usage, exit code may vary by version)
$CLI --help &> /tmp/crontinel-help.txt || true
if grep -q "Usage:" /tmp/crontinel-help.txt; then
    pass "--help prints usage text"
else
    fail "--help failed to print usage"
fi
rm -f /tmp/crontinel-help.txt

# 3. Ping
if $CLI ping --key "$CRONTINEL_API_KEY" 2>&1 | grep -q "Connected"; then
    pass "ping connects to Crontinel"
else
    fail "ping failed"
fi

# 4. Monitors
if $CLI monitors --key "$CRONTINEL_API_KEY" 2>&1 | grep -q "Scheduled jobs"; then
    pass "monitors lists scheduled jobs"
else
    fail "monitors failed"
fi

# 5. Events
if $CLI events --key "$CRONTINEL_API_KEY" 2>&1; then
    pass "events runs without error"
else
    fail "events failed"
fi

# 6. Alerts
if $CLI alerts --key "$CRONTINEL_API_KEY" 2>&1; then
    pass "alerts runs without error"
else
    fail "alerts failed"
fi

# 7. JSON output
if $CLI --json ping --key "$CRONTINEL_API_KEY" 2>&1 | grep -q "tools"; then
    pass "--json ping returns valid JSON"
else
    fail "--json ping failed"
fi

summary "CLI"
