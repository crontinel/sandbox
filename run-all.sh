#!/usr/bin/env bash
set -euo pipefail

# Crontinel Sandbox — full test suite runner
# Runs all test scripts and reports a final summary.

cd "$(dirname "$0")"
source config.sh

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   Crontinel Package Sandbox Test Suite   ║"
echo "╚══════════════════════════════════════════╝"
echo ""

export CRONTINEL_API_KEY CRONTINEL_API_URL

TOTAL_PASS=0
TOTAL_FAIL=0
RESULTS=()

for test in tests/*.sh; do
    name=$(basename "$test" .sh)
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Running: $name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    set +e
    output=$(bash "$test" 2>&1)
    exit_code=$?
    set -e

    # Extract pass/fail counts from test output
    passed=$(echo "$output" | grep -oP '\d+(?= passed)' | tail -1)
    failed=$(echo "$output" | grep -oP '\d+(?= failed)' | tail -1)
    passed=${passed:-0}
    failed=${failed:-0}

    TOTAL_PASS=$((TOTAL_PASS + passed))
    TOTAL_FAIL=$((TOTAL_FAIL + failed))

    if [ "$exit_code" -eq 0 ]; then
        RESULTS+=("  ✅ $name — ${passed} passed, ${failed} failed")
    else
        RESULTS+=("  ❌ $name — CRASHED (exit $exit_code)")
    fi

    echo "$output" | tail -5
done

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║            FINAL SUMMARY                 ║"
echo "╚══════════════════════════════════════════╝"
echo ""
for r in "${RESULTS[@]}"; do
    echo "$r"
done
echo ""
echo "  Total: ${TOTAL_PASS} passed, ${TOTAL_FAIL} failed"
echo ""
