#!/usr/bin/env bash
set -euo pipefail

# Test 08: Ruby — crontinel gem
# Tests: bundler setup, gem install from local path, SDK import,
#        client construction, API connectivity (health + task_started)

cd "$(dirname "$0")"
source ../config.sh

echo "=== Test 08: Ruby ==="

SANDBOX="/tmp/crontinel-sandbox-ruby"
rm -rf "$SANDBOX"

require_cmd ruby || { summary "Ruby"; exit 1; }

# The crontinel gem requires Ruby >= 2.7
ruby_major=$(ruby -e 'puts RUBY_VERSION.split(".").first(2).join(".")')
if ! ruby -e "exit(RUBY_VERSION >= '2.7' ? 0 : 1)" 2>/dev/null; then
    skip "Ruby $ruby_major detected — crontinel gem requires >= 2.7"
    summary "Ruby"
    exit 0
fi

require_cmd gem    || { summary "Ruby"; exit 1; }

mkdir -p "$SANDBOX"
cd "$SANDBOX"

# Use gem install directly (avoids Bundler version quirks on older setups)
GEM_HOME="$SANDBOX/gems"

# Build the .gem from the local source
if gem build $CRONTINEL_REPOS_DIR/ruby/crontinel.gemspec --output "$SANDBOX/crontinel-0.1.0.gem" 2>/dev/null; then
    pass "gem built successfully"
else
    fail "gem build failed"
    summary "Ruby"
    exit 1
fi

# Install into isolated gem home (no system pollution)
if gem install --no-document --install-dir "$GEM_HOME" "$SANDBOX/crontinel-0.1.0.gem" 2>/dev/null; then
    pass "gem install successful"
else
    fail "gem install failed"
    summary "Ruby"
    exit 1
fi

# ---------------------------------------------------------------------------
# 2) Test script — exercises import, client creation, config, health, start
# ---------------------------------------------------------------------------
cat > test.rb << 'RBEOF'
require "rubygems"
require "crontinel"
require "json"

api_key = ENV["CRONTINEL_API_KEY"]
api_url = ENV["CRONTINEL_API_URL"]

puts "RUBY_VERSION: #{RUBY_VERSION}"
puts "CRONTINEL_VERSION: #{Crontinel::VERSION}"

# 1) Create client
client = Crontinel::Client.new(
  api_key: api_key,
  endpoint: api_url
)
puts "CLIENT_OK: Crontinel::Client created"

# 2) Verify config
if client.config.api_key && client.config.endpoint
  key_preview = client.config.api_key[0..8]
  puts "CONFIG_OK: api_key=#{key_preview}..., endpoint=#{client.config.endpoint}"
else
  puts "CONFIG_ERROR: missing api_key or endpoint"
  exit 1
end

# 3) Health check — lightweight API connectivity
health_ok = client.health_check
if health_ok
  puts "HEALTH_OK: Crontinel API is reachable"
else
  puts "HEALTH_WARN: health check returned false (API may be down)"
  # Don't exit — the task_started is the real end-to-end check
end

# 4) Send a task_started event to the production API
client.task_started(
  name: "sandbox-test-ruby",
  output: "Crontinel Ruby SDK sandbox connectivity check"
)
puts "TASK_SENT: task_started sent successfully"

puts "ALL_OK"
RBEOF
pass "test script created"

# ---------------------------------------------------------------------------
# 3) Execute
# ---------------------------------------------------------------------------
output=$(GEM_HOME="$GEM_HOME" ruby test.rb 2>&1 || true)
echo "$output"

# ---------------------------------------------------------------------------
# 4) Parse results
# ---------------------------------------------------------------------------
if echo "$output" | grep -q "CRONTINEL_VERSION:"; then
    version=$(echo "$output" | grep "CRONTINEL_VERSION:" | sed 's/.*: //')
    pass "SDK import successful (version: $version)"
else
    fail "SDK import failed"
fi

if echo "$output" | grep -q "CLIENT_OK:"; then
    pass "client construction successful"
else
    fail "client construction failed"
fi

if echo "$output" | grep -q "CONFIG_OK:"; then
    pass "API key and endpoint configured correctly"
else
    fail "API key or endpoint misconfigured"
fi

if echo "$output" | grep -q "HEALTH_OK:"; then
    pass "API health check successful"
elif echo "$output" | grep -q "HEALTH_WARN:"; then
    fail "API health check failed"
fi

if echo "$output" | grep -q "TASK_SENT:"; then
    pass "API connectivity (task_started event) successful"
else
    # Include error detail when available
    if echo "$output" | grep -qi "error"; then
        echo "  Error detail: $(echo "$output" | grep -i error | head -1)"
    fi
    fail "API connectivity check failed"
fi

if echo "$output" | grep -q "ALL_OK"; then
    pass "all checks passed"
fi

# ---------------------------------------------------------------------------
# 5) Cleanup
# ---------------------------------------------------------------------------
rm -rf "$SANDBOX"
pass "cleanup done"

summary "Ruby"
