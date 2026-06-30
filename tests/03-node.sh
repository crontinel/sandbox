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

# Install @crontinel/node
if npm install @crontinel/node --quiet 2>/dev/null; then
    pass "npm install @crontinel/node"
else
    fail "npm install @crontinel/node failed"
    summary "Node"
    exit 1
fi

# Create test script
cat > test.mjs << JSEOF
import { Crontinel } from '@crontinel/node';

const client = new Crontinel({
    apiKey: process.env.CRONTINEL_API_KEY,
    apiUrl: process.env.CRONTINEL_API_URL,
});

async function main() {
    // Ping
    const ping = await client.ping();
    console.log('PING:', JSON.stringify(ping));

    // List monitors
    const monitors = await client.monitors();
    console.log('MONITORS:', typeof monitors === 'object' ? Object.keys(monitors).length + ' entries' : monitors);
}
main().catch(e => { console.error('ERROR:', e.message); process.exit(1); });
JSEOF

if node test.mjs 2>&1 | grep -q "PING:"; then
    pass "SDK ping successful"
else
    fail "SDK ping failed"
    node test.mjs 2>&1 || true
fi

# Check if SDK has monitors method
if node test.mjs 2>&1 | grep -q "MONITORS:"; then
    pass "SDK monitors method works"
fi

# Cleanup
rm -rf "$SANDBOX"
pass "cleanup done"

summary "Node"
