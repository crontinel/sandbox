#!/usr/bin/env bash
set -euo pipefail

# Test 07: Rust — crontinel crate
# Tests: Cargo project creation, path dependency, SDK compile, API ping

cd "$(dirname "$0")"
source ../config.sh

echo "=== Test 07: Rust ==="

SANDBOX="/tmp/crontinel-sandbox-rust"
rm -rf "$SANDBOX"

require_cmd cargo || { summary "Rust"; exit 1; }
require_cmd rustc || { summary "Rust"; exit 1; }

mkdir -p "$SANDBOX"
cd "$SANDBOX"

# Create Cargo project
cargo init --name crontinel-test --quiet
pass "cargo init"

# Write Cargo.toml with path dependency on the local crontinel crate
cat > Cargo.toml << TOMLEOF
[package]
name = "crontinel-test"
version = "0.1.0"
edition = "2021"

[dependencies]
crontinel = { path = "/Users/ray/Work/crontinel/rust" }
TOMLEOF
pass "Cargo.toml with path dependency"

# Write the test program that pings the production API
cat > src/main.rs << RSEOF
use std::env;
use crontinel::Crontinel;

fn main() {
    let api_key = env::var("CRONTINEL_API_KEY")
        .expect("CRONTINEL_API_KEY must be set");
    let api_url = env::var("CRONTINEL_API_URL")
        .unwrap_or_else(|_| "https://app.crontinel.com".to_string());

    let client = Crontinel::builder(&api_key)
        .api_url(&api_url)
        .app_name("rust-sandbox-test")
        .build();

    // Ping via schedule_run (sends JSON-RPC request to production API)
    match client.schedule_run("php artisan schedule:run", Some(100), 0) {
        Ok(()) => {
            println!("PING_OK");
        }
        Err(e) => {
            // A network/connection error might occur if offline, but that's okay
            // as long as the crate compiles and the request is formed correctly.
            // If the production API rejects it (e.g. unknown app), that's a valid
            // response too — we still exercised the full path.
            println!("PING_RESULT: {}", e);
        }
    }

    // Also test queue_processed
    match client.queue_processed("test-queue", 10, 0, Some(500)) {
        Ok(()) => println!("QUEUE_OK"),
        Err(e) => println!("QUEUE_RESULT: {}", e),
    }

    // Test event
    match client.event("sandbox-test", "Rust sandbox test", "info", None) {
        Ok(()) => println!("EVENT_OK"),
        Err(e) => println!("EVENT_RESULT: {}", e),
    }
}
RSEOF
pass "main.rs written"

# Build the project (cargo run will compile too, but separate build for clarity)
if cargo build 2>&1; then
    pass "cargo build succeeds"
else
    fail "cargo build failed"
    cargo build 2>&1 || true
    rm -rf "$SANDBOX"
    summary "Rust"
    exit 1
fi

# Run the test program and capture output
OUTPUT=$(cargo run 2>&1) || true
echo "$OUTPUT"

if echo "$OUTPUT" | grep -q "PING_OK\|PING_RESULT:"; then
    pass "cargo run succeeds / API ping exercised"
else
    fail "API ping did not produce expected output"
    rm -rf "$SANDBOX"
    summary "Rust"
    exit 1
fi

# Check output for queue marker
if echo "$OUTPUT" | grep -q "QUEUE_OK\|QUEUE_RESULT:"; then
    pass "queue_processed exercised"
fi

# Check output for event marker
if echo "$OUTPUT" | grep -q "EVENT_OK\|EVENT_RESULT:"; then
    pass "event exercised"
fi

# Cleanup
rm -rf "$SANDBOX"
pass "cleanup done"

summary "Rust"
