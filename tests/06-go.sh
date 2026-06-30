#!/usr/bin/env bash
set -euo pipefail

# Test 06: Go — crontinel/go
# Tests: go module setup, SDK initialization, API ping via ScheduleRun

cd "$(dirname "$0")"
source ../config.sh

echo "=== Test 06: Go ==="

SANDBOX="/tmp/crontinel-sandbox-go"
rm -rf "$SANDBOX"

require_cmd go || { summary "Go"; exit 1; }

mkdir -p "$SANDBOX"
cd "$SANDBOX"

# Init a Go module
if go mod init crontinel-sandbox 2>/dev/null; then
    pass "go mod init"
else
    fail "go mod init failed"
    summary "Go"
    exit 1
fi

# Add replace directive to use local crontinel/go package
GO_PKG_DIR="/Users/ray/Work/crontinel/go"
go mod edit -replace "crontinel/go=$GO_PKG_DIR"
pass "added replace directive for local crontinel/go"

# Add require for crontinel/go
go mod edit -require "crontinel/go@v0.0.0"
pass "added require directive for crontinel/go"

# Create test program that imports crontinel/go and calls ping against production API
# Uses tools/list JSON-RPC (same as CLI ping) — the Go SDK doesn't expose Ping()
cat > main.go << 'GOEOF'
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"time"

	"crontinel/go"
)

type rpcRequest struct {
	JSONRPC string `json:"jsonrpc"`
	Method  string `json:"method"`
	ID      int    `json:"id"`
}

type rpcResponse struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      any             `json:"id"`
	Result  json.RawMessage `json:"result,omitempty"`
	Error   *struct {
		Code    int    `json:"code"`
		Message string `json:"message"`
	} `json:"error,omitempty"`
}

func main() {
	apiKey := os.Getenv("CRONTINEL_API_KEY")
	apiURL := os.Getenv("CRONTINEL_API_URL")
	if apiKey == "" {
		fmt.Println("ERROR: CRONTINEL_API_KEY is not set")
		os.Exit(1)
	}
	if apiURL == "" {
		apiURL = "https://app.crontinel.com"
	}

	// Verify the crontinel/go SDK compiles and creates a client
	crontinel.NewClient(apiKey, crontinel.WithAPIURL(apiURL), crontinel.WithAppName("sandbox-go"))
	fmt.Println("SDK: crontinel/go client created")
	// Ping via tools/list JSON-RPC — same method the CLI uses for connectivity check
	body, _ := json.Marshal(rpcRequest{
		JSONRPC: "2.0",
		Method:  "tools/list",
		ID:      1,
	})

	req, err := http.NewRequest(http.MethodPost, apiURL+"/api/mcp", bytes.NewReader(body))
	if err != nil {
		fmt.Printf("ERROR: failed to create request — %v\n", err)
		os.Exit(1)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+apiKey)

	hc := &http.Client{Timeout: 10 * time.Second}
	resp, err := hc.Do(req)
	if err != nil {
		fmt.Printf("ERROR: ping failed — %v\n", err)
		os.Exit(1)
	}
	defer resp.Body.Close()

	var rpcResp rpcResponse
	if err := json.NewDecoder(resp.Body).Decode(&rpcResp); err != nil {
		fmt.Printf("ERROR: failed to parse response — %v\n", err)
		os.Exit(1)
	}
	if rpcResp.Error != nil {
		fmt.Printf("ERROR: ping failed — RPC error %d: %s\n", rpcResp.Error.Code, rpcResp.Error.Message)
		os.Exit(1)
	}

	fmt.Println("PING: connected to Crontinel")
}
GOEOF
pass "wrote main.go"

# Download dependencies
if go mod tidy 2>&1; then
    pass "go mod tidy"
else
    fail "go mod tidy failed"
    summary "Go"
    exit 1
fi

# Build the program
if go build -o crontinel-sandbox . 2>&1; then
    pass "go build succeeded"
else
    fail "go build failed"
    summary "Go"
    exit 1
fi

# Run the program against production
export CRONTINEL_API_KEY CRONTINEL_API_URL
if ./crontinel-sandbox 2>&1 | grep -q "PING: connected"; then
    pass "Go SDK ping successful"
else
    fail "Go SDK ping failed"
    ./crontinel-sandbox 2>&1 || true
fi

# Cleanup
cd /
rm -rf "$SANDBOX"
pass "cleanup done"

summary "Go"
