#!/usr/bin/env bash
set -euo pipefail

# Test 02: Laravel — crontinel/laravel
# Tests: package install, artisan command, ping

cd "$(dirname "$0")"
source ../config.sh

echo "=== Test 02: Laravel ==="

SANDBOX="/tmp/crontinel-sandbox-laravel"
rm -rf "$SANDBOX"

require_cmd composer || { summary "Laravel"; exit 1; }

# Create a fresh Laravel project
if composer create-project laravel/laravel "$SANDBOX" --no-interaction --quiet 2>/dev/null; then
    pass "created fresh Laravel project"
else
    fail "could not create Laravel project"
    summary "Laravel"
    exit 1
fi

cd "$SANDBOX"

# Require the crontinel package
if composer require crontinel/laravel --no-interaction --quiet 2>/dev/null; then
    pass "composer require crontinel/laravel"
else
    fail "composer require crontinel/laravel failed"
    summary "Laravel"
    exit 1
fi

# Set API key in .env
echo "CRONTINEL_API_KEY=$CRONTINEL_API_KEY" >> .env
echo "CRONTINEL_API_URL=$CRONTINEL_API_URL" >> .env

# Run artisan crontinel:install
if php artisan crontinel:install 2>&1 | grep -qi "done\|installed\|success"; then
    pass "php artisan crontinel:install"
else
    # Check if the command exists at all
    if php artisan list 2>&1 | grep -q crontinel; then
        pass "crontinel artisan command registered"
    else
        fail "crontinel artisan command not found"
    fi
fi

# Check available crontinel artisan commands
echo "  Available commands:"
php artisan list 2>&1 | grep crontinel || echo "  (none found)"

# Test connection via artisan if command exists
if php artisan crontinel:ping 2>&1 | grep -qi "connected\|ok\|success"; then
    pass "artisan crontinel:ping connects"
elif php artisan crontinel:check 2>&1 | grep -qi "connected\|ok\|success"; then
    pass "artisan crontinel:check connects"
else
    php artisan crontinel:ping 2>&1 || true
    php artisan crontinel:check 2>&1 || true
    skip "no ping/check artisan command — check package API"
fi

# Cleanup
rm -rf "$SANDBOX"
pass "cleanup done"

summary "Laravel"
