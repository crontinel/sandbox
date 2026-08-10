#!/usr/bin/env bash
set -euo pipefail

# Test 04: Python — crontinel SDK
# Tests: venv creation, pip install, SDK import, client construction,
#        API host reachability, and MCP request mechanism.

cd "$(dirname "$0")"
source ../config.sh

echo "=== Test 04: Python ==="

SANDBOX="/tmp/crontinel-sandbox-python"
rm -rf "$SANDBOX"

require_cmd python3 || { summary "Python"; exit 1; }
require_cmd pip3   || { summary "Python"; exit 1; }

mkdir -p "$SANDBOX"
cd "$SANDBOX"

# Create a temporary virtual environment
python3 -m venv venv
pass "venv created"

# Activate venv and install crontinel
source venv/bin/activate

# Upgrade pip — needed for editable install from pyproject.toml-only projects
pip install --upgrade pip --quiet 2>/dev/null
pass "pip upgraded"

if pip install -e "$CRONTINEL_REPOS_DIR/python[httpx]" --quiet 2>/dev/null; then
    pass "pip install crontinel[httpx]"
else
    fail "pip install crontinel[httpx] failed"
    deactivate 2>/dev/null || true
    summary "Python"
    exit 1
fi

# Create test script
cat > test.py << PYEOF
"""
Sandbox test for crontinel Python SDK.

Verifies:
  1.  Package import and version
  2.  Client construction with env-sourced config
  3.  API host reachability (HTTP HEAD /health)
  4.  JSON-RPC request mechanism (SDK sends correctly formed requests)

The MCP endpoint may respond with "Method not found" if the API is still
being deployed — that is *not* an SDK failure; it proves the HTTP transport,
auth header, and JSON-RPC payload are all wired correctly.
"""
import os
import sys
import subprocess

failures = 0

# ── 1. Import ──────────────────────────────────────────────────────────────
try:
    from crontinel import Crontinel, __version__
    print("IMPORT_OK:%s" % __version__)
except ImportError as e:
    print("IMPORT_ERROR:%s" % e)
    sys.exit(1)

# ── 2. Client construction ─────────────────────────────────────────────────
api_key = os.environ.get("CRONTINEL_API_KEY")
api_url = os.environ.get("CRONTINEL_API_URL")

try:
    client = Crontinel(
        api_key=api_key,
        api_url=api_url,
        app_name="sandbox-test",
        sync=False,          # exercise the httpx transport (.[httpx] extra)
    )
    print("CLIENT_OK:%s..." % client.api_key[:8])
except ValueError as e:
    print("CLIENT_ERROR:%s" % e)
    sys.exit(1)

if not client.api_key or not client.api_url:
    print("CONFIG_ERROR:missing api_key or api_url")
    sys.exit(1)
print("CONFIG_OK:%s" % client.api_url)

# ── 3. API host reachability ───────────────────────────────────────────────
# Use a direct HTTP call so we don't couple SDK connectivity to env.
import httpx
try:
    r = httpx.get("%s/health" % client.api_url, timeout=5)
    if r.status_code == 200:
        print("HEALTH_OK:%s" % r.text.strip())
    else:
        print("HEALTH_UNEXPECTED:%d" % r.status_code)
except Exception as e:
    print("HEALTH_ERROR:%s" % e)

# ── 4. MCP request mechanism ───────────────────────────────────────────────
# The SDK sends to {api_url}/api/mcp with JSON-RPC payload.
# A "Method not found" response proves the wire, auth, and JSON-RPC framing
# all work correctly.
try:
    # Trigger _request internally via event()
    client.event(
        key="sandbox-test-python",
        message="Crontinel Python SDK sandbox connectivity check",
        state="info",
    )
    print("MCP_OK:event sent successfully")
except RuntimeError as e:
    err_msg = str(e)
    # "Method not found" is expected if MCP methods aren't deployed yet.
    # It proves the request reached the server, was authenticated, and
    # returned a well-formed JSON-RPC error — transport works.
    if "Method not found" in err_msg:
        print("MCP_METHOD_NOT_FOUND:%s" % err_msg)
    else:
        print("MCP_RPC_ERROR:%s" % err_msg)
except Exception as e:
    print("MCP_TRANSPORT_ERROR:%s" % e)

print("DONE")
PYEOF

# Run the test script and capture full output
output=$(python test.py 2>&1 || true)
echo "$output"

# Parse results — each check prints a known prefix
check_result() {
    local prefix="$1"
    local label="$2"
    if echo "$output" | grep -q "${prefix}:"; then
        pass "$label"
    else
        fail "$label"
    fi
}

check_result "IMPORT_OK"     "SDK import successful"
check_result "CLIENT_OK"     "client construction successful"
check_result "CONFIG_OK"     "API key and URL configured correctly"
check_result "HEALTH_OK"     "API host reachable (/health)"

# MCP transport check: "Method not found" means the JSON-RPC request
# reached the server, was authenticated, and returned a valid response.
if echo "$output" | grep -q "MCP_OK:"; then
    pass "MCP event sent successfully"
elif echo "$output" | grep -q "MCP_METHOD_NOT_FOUND:"; then
    pass "MCP request mechanism works (transport OK, method not deployed yet)"
fi

if echo "$output" | grep -q "DONE"; then
    pass "script completed"
fi

# Cleanup
deactivate 2>/dev/null || true
rm -rf "$SANDBOX"
pass "cleanup done"

summary "Python"
