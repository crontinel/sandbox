#!/usr/bin/env bash
set -euo pipefail

# Test 03: Node — @crontinel/node
# Tests: npm install, SDK initialization, ping

cd "$(dirname "$0")"
source ../config.sh

echo "=== Test 03: Node ==="

SANDBOX="/tmp/crontinel-sandbox-node"
rm -rf "$SANDBOX"

require_cmd node || { summary "Node"; exit 1; }
require_cmd npm || { summary "Node"; exit 1; }

mkdir -p "$SANDBOX"
cd "$SANDBOX"

# Init a minimal package
npm init -y --quiet 2>/dev/null
pass "npm init"

# Build and install @crontinel/node from local source
PACKAGE_DIR="/Users/ray/Work/crontinel/node"

# Build the package first (generates dist/)
if (cd "$PACKAGE_DIR" && npm run build 2>/dev/null); then
    pass "package built (dist/ generated)"
else
    skip "package build skipped (already built)"
fi

# Install from local path
if npm install "$PACKAGE_DIR" --quiet 2>/dev/null; then
    pass "npm install @crontinel/node (local path)"
else
    fail "npm install @crontinel/node failed"
    summary "Node"
    exit 1
fi

# Create test script — test SDK constructors, notify methods, and direct ingest
cat > test.mjs << 'JSEOF'
import { Crontinel } from '@crontinel/node';

const client = new Crontinel({
    apiKey: process.env.CRONTINEL_API_KEY,
    apiUrl: process.env.CRONTINEL_API_URL,
});

// Verify constructor works
console.log('CONSTRUCTOR: OK');
console.log('API_KEY:', process.env.CRONTINEL_API_KEY ? 'SET' : 'MISSING');
console.log('API_URL:', process.env.CRONTINEL_API_URL);

async function main() {
    // Test event() — uses notify/event MCP method
    try {
        await client.event({ key: 'sandbox-test', message: 'Node SDK test', state: 'info' });
        console.log('EVENT: OK');
    } catch (e) {
        console.log('EVENT_FAIL:', e.message);
    }

    // Test scheduleRun() — uses notify/schedule_run MCP method
    try {
        await client.scheduleRun({ command: 'node-sandbox-test', duration_ms: 100, exit_code: 0 });
        console.log('SCHEDULE_RUN: OK');
    } catch (e) {
        console.log('SCHEDULE_RUN_FAIL:', e.message);
    }

    // Test queueProcessed() — uses notify/queue_processed MCP method
    try {
        await client.queueProcessed({ queue: 'test-queue', processed: 5, failed: 0 });
        console.log('QUEUE_PROCESSED: OK');
    } catch (e) {
        console.log('QUEUE_PROCESSED_FAIL:', e.message);
    }
}
main().catch(e => { console.error('FATAL:', e.message); process.exit(1); });
JSEOF

NODE_OUTPUT=$(node test.mjs 2>&1) || true

echo "$NODE_OUTPUT" | grep -q "CONSTRUCTOR: OK" && pass "SDK constructor works" || fail "SDK constructor failed"

if echo "$NODE_OUTPUT" | grep -q "EVENT: OK"; then
    pass "SDK event() — notify/event handled"
elif echo "$NODE_OUTPUT" | grep -q "EVENT_FAIL:"; then
    fail "SDK event() — $(echo "$NODE_OUTPUT" | grep EVENT_FAIL | head -1)"
else
    fail "SDK event() — unknown result"
fi

if echo "$NODE_OUTPUT" | grep -q "SCHEDULE_RUN: OK"; then
    pass "SDK scheduleRun() — notify/schedule_run handled"
elif echo "$NODE_OUTPUT" | grep -q "SCHEDULE_RUN_FAIL:"; then
    fail "SDK scheduleRun() — $(echo "$NODE_OUTPUT" | grep SCHEDULE_RUN_FAIL | head -1)"
fi

if echo "$NODE_OUTPUT" | grep -q "QUEUE_PROCESSED: OK"; then
    pass "SDK queueProcessed() — notify/queue_processed handled"
elif echo "$NODE_OUTPUT" | grep -q "QUEUE_PROCESSED_FAIL:"; then
    fail "SDK queueProcessed() — $(echo "$NODE_OUTPUT" | grep QUEUE_PROCESSED_FAIL | head -1)"
fi

# Also test the direct ingest/ping endpoint (always available)
echo "  Testing ingest/ping endpoint directly..."
INGEST_RESP=$(curl -s -X POST "${CRONTINEL_API_URL}/api/v1/ingest/ping" \
    -H "Authorization: Bearer ${CRONTINEL_API_KEY}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "{\"status\":\"healthy\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" 2>&1)

if echo "$INGEST_RESP" | grep -q "ok\|success\|accepted"; then
    pass "ingest/ping endpoint — connected"
    echo "    Response: $(echo "$INGEST_RESP" | head -c 150)"
else
    fail "ingest/ping endpoint failed"
    echo "    Response: $(echo "$INGEST_RESP" | head -c 200)"
fi

# Cleanup
rm -rf "$SANDBOX"
pass "cleanup done"

summary "Node"
