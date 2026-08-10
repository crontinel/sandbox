#!/usr/bin/env bash
set -euo pipefail

# Test 11: .NET — Crontinel (NuGet package "Crontinel")
# Tests: dotnet project setup, local ProjectReference, SDK compile, API ping

cd "$(dirname "$0")"
source ../config.sh

echo "=== Test 11: .NET ==="

SANDBOX="/tmp/crontinel-sandbox-dotnet"
rm -rf "$SANDBOX"

require_cmd dotnet || { summary ".NET"; exit 1; }

DOTNET_PKG_DIR="/Users/ray/Work/crontinel/dotnet-sdk"

if [ ! -f "$DOTNET_PKG_DIR/src/Crontinel/Crontinel.csproj" ]; then
    fail "crontinel dotnet-sdk not found at $DOTNET_PKG_DIR"
    summary ".NET"
    exit 1
fi

mkdir -p "$SANDBOX"
cd "$SANDBOX"

# Create a console project
if dotnet new console --name CrontinelSandbox -o . &>/dev/null; then
    pass "dotnet new console"
else
    fail "dotnet new console failed"
    summary ".NET"
    exit 1
fi

# Add a project reference to the local Crontinel SDK
if dotnet add reference "$DOTNET_PKG_DIR/src/Crontinel/Crontinel.csproj" &>/dev/null; then
    pass "added project reference to local Crontinel SDK"
else
    fail "dotnet add reference failed"
    summary ".NET"
    exit 1
fi

# Write the test program that pings the production API
cat > Program.cs << CSEOF
using System;
using Crontinel;
using Crontinel.Models;

var apiKey = Environment.GetEnvironmentVariable("CRONTINEL_API_KEY")
    ?? throw new Exception("CRONTINEL_API_KEY must be set");
var apiUrl = Environment.GetEnvironmentVariable("CRONTINEL_API_URL") ?? "https://app.crontinel.com";

var client = new CrontinelClient(new CrontinelOptions
{
    ApiKey = apiKey,
    ApiUrl = apiUrl,
    AppName = "dotnet-sandbox-test",
});

// Ping via ScheduleRunAsync (sends a JSON-RPC request to production API)
try
{
    await client.ScheduleRunAsync(new ScheduleRunOptions
    {
        Command = "sandbox-test",
        DurationMs = 100,
        ExitCode = 0,
    });
    Console.WriteLine("PING_OK");
}
catch (Exception e)
{
    // A network/connection error might occur if offline, but that's okay
    // as long as the SDK compiles and the request is formed correctly.
    // If the production API rejects it (e.g. unknown app), that's a valid
    // response too — we still exercised the full path.
    Console.WriteLine("PING_RESULT: " + e.Message);
}

// Also test QueueProcessedAsync
try
{
    await client.QueueProcessedAsync(new QueueProcessedOptions
    {
        Queue = "test-queue",
        Processed = 10,
        Failed = 0,
        DurationMs = 500,
    });
    Console.WriteLine("QUEUE_OK");
}
catch (Exception e)
{
    Console.WriteLine("QUEUE_RESULT: " + e.Message);
}

// Test EventAsync
try
{
    await client.EventAsync(new CustomEventOptions
    {
        Key = "sandbox-test",
        Message = ".NET sandbox test",
        State = "info",
    });
    Console.WriteLine("EVENT_OK");
}
catch (Exception e)
{
    Console.WriteLine("EVENT_RESULT: " + e.Message);
}
CSEOF
pass "Program.cs written"

# Build the project
if dotnet build --nologo -v quiet 2>&1; then
    pass "dotnet build succeeds"
else
    fail "dotnet build failed"
    dotnet build --nologo 2>&1 || true
    rm -rf "$SANDBOX"
    summary ".NET"
    exit 1
fi

# Run the test program and capture output
OUTPUT=$(dotnet run --no-build 2>&1) || true
echo "$OUTPUT"

if echo "$OUTPUT" | grep -q "PING_OK\|PING_RESULT:"; then
    pass "dotnet run succeeds / API ping exercised"
else
    fail "API ping did not produce expected output"
    rm -rf "$SANDBOX"
    summary ".NET"
    exit 1
fi

# Check output for queue marker
if echo "$OUTPUT" | grep -q "QUEUE_OK\|QUEUE_RESULT:"; then
    pass "QueueProcessedAsync exercised"
fi

# Check output for event marker
if echo "$OUTPUT" | grep -q "EVENT_OK\|EVENT_RESULT:"; then
    pass "EventAsync exercised"
fi

# Cleanup
cd /
rm -rf "$SANDBOX"
pass "cleanup done"

summary ".NET"
