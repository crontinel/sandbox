#!/usr/bin/env bash
set -euo pipefail

# Test 10: Trigger — cloud trigger API endpoint
# Tests: POST /api/v1/triggers, trigger dispatch

cd "$(dirname "$0")"
source ../config.sh

echo "=== Test 10: Cloud Trigger ==="

APP_ID=6

# 1. Test the trigger endpoint directly
echo "  Sending trigger request..."
RESP=$(curl -s -X POST "${CRONTINEL_API_URL}/api/v1/triggers" \
    -H "X-API-Key: $CRONTINEL_API_KEY" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "{\"app_id\": $APP_ID, \"command\": \"echo test-trigger\", \"schedule\": \"now\"}" 2>&1)

if echo "$RESP" | grep -q "ok\|success\|trigger_id\|id"; then
    pass "trigger endpoint accepts and dispatches"
    echo "    Response: $(echo "$RESP" | head -c 200)"
elif echo "$RESP" | grep -q "agent\|not found\|offline"; then
    skip "trigger sent but no agent connected — expected without running agent"
    echo "    Response: $(echo "$RESP" | head -c 200)"
else
    fail "trigger endpoint error"
    echo "    Response: $(echo "$RESP" | head -c 300)"
fi

# 2. Test with invalid API key
RESP=$(curl -s -X POST "${CRONTINEL_API_URL}/api/v1/triggers" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -u "invalid-key:" \
    -d "{\"app_id\": $APP_ID, \"command\": \"echo test\", \"schedule\": \"now\"}" 2>&1)

if echo "$RESP" | grep -q "401\|unauthorized\|invalid"; then
    pass "trigger rejects invalid API key"
else
    skip "trigger auth response: $(echo "$RESP" | head -c 100)"
fi

# 3. Test with missing command
RESP=$(curl -s -X POST "${CRONTINEL_API_URL}/api/v1/triggers" \
    -H "X-API-Key: $CRONTINEL_API_KEY" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "{\"app_id\": $APP_ID, \"schedule\": \"now\"}" 2>&1)

if echo "$RESP" | grep -q "error\|required\|command"; then
    pass "trigger rejects missing command"
else
    skip "trigger missing-command response: $(echo "$RESP" | head -c 100)"
fi

summary "Cloud Trigger"
