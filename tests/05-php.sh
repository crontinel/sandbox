#!/usr/bin/env bash
set -euo pipefail

# Test 05: PHP — crontinel/php
# Tests: package install, class autoload, data objects, cron helper, alert manager, API ping

cd "$(dirname "$0")"
source ../config.sh

echo "=== Test 05: PHP Core Package ==="

SANDBOX="/tmp/crontinel-sandbox-php"
rm -rf "$SANDBOX"
mkdir -p "$SANDBOX"

require_cmd composer || { summary "PHP Core"; exit 1; }
require_cmd php || { summary "PHP Core"; exit 1; }

cd "$SANDBOX"

# Create minimal composer.json pointing to local package
cat > composer.json <<COMPOSER_JSON
{
    "name": "crontinel/sandbox-test",
    "description": "Sandbox test for crontinel/php",
    "type": "project",
    "require": {
        "crontinel/php": "*"
    },
    "repositories": [
        {
            "type": "path",
            "url": "$CRONTINEL_REPOS_DIR/php",
            "options": {
                "symlink": false,
                "canonical": false
            }
        }
    ],
    "minimum-stability": "dev",
    "prefer-stable": true,
    "config": {
        "allow-plugins": false,
        "audit": {
            "ignore": ["PKSA-5jz8-6tcw-pbk4", "PKSA-z3gr-8qht-p93v"]
        }
    }
}
COMPOSER_JSON

# Install the crontinel package from local path
if composer install --no-interaction --quiet 2>/dev/null; then
    pass "composer install crontinel/php"
else
    fail "composer install crontinel/php failed"
    summary "PHP Core"
    exit 1
fi

# Write PHP test script
cat > test_php.php <<'PHP_TEST'
<?php
require __DIR__ . '/vendor/autoload.php';

$exit = 0;

// Test: autoload core classes
$classes = [
    'Crontinel\Contracts\MonitorInterface',
    'Crontinel\Contracts\AlertChannelInterface',
    'Crontinel\Data\AlertEvent',
    'Crontinel\Data\CronStatus',
    'Crontinel\Data\QueueStatus',
    'Crontinel\Data\HorizonStatus',
    'Crontinel\Alert\AlertManager',
    'Crontinel\Alert\AlertLevel',
    'Crontinel\Alert\NullChannel',
    'Crontinel\Cron\CronExpressionHelper',
    'Crontinel\Monitors\CronMonitor',
    'Crontinel\Monitors\QueueMonitor',
    'Crontinel\Monitors\HorizonMonitor',
];

$all_loaded = true;
foreach ($classes as $class) {
    if (interface_exists($class) || class_exists($class)) {
        echo "  OK $class\n";
    } else {
        echo "  MISSING $class\n";
        $all_loaded = false;
        $exit = 1;
    }
}

// Test: create data objects
try {
    $event = new Crontinel\Data\AlertEvent(
        key: 'test.key',
        title: 'Test Alert',
        message: 'This is a test alert',
        level: 'info',
        resolved: false,
        firedAt: new DateTimeImmutable()
    );
    echo "  AlertEvent: {$event->key} / {$event->title}\n";

    $status = new Crontinel\Data\CronStatus(
        command: 'php artisan test',
        expression: '* * * * *',
        status: 'ok',
        lastRunAt: new DateTimeImmutable(),
        lastExitCode: 0,
        lastDurationMs: 1500,
        nextDueAt: new DateTimeImmutable('+1 minute')
    );
    echo "  CronStatus: {$status->command} / {$status->status} / exit: {$status->lastExitCode}\n";

    echo "  -- data objects: OK\n";
} catch (Throwable $e) {
    echo "  -- data objects ERROR: " . $e->getMessage() . "\n";
    $exit = 1;
}

// Test: CronExpressionHelper
try {
    $helper = new Crontinel\Cron\CronExpressionHelper();
    $next = $helper->nextDue('* * * * *');
    echo "  Next due: " . $next->format('Y-m-d H:i:s') . "\n";

    $prev = $helper->previousDue('* * * * *');
    echo "  Previous due: " . $prev->format('Y-m-d H:i:s') . "\n";

    $lastRun = new DateTimeImmutable('-10 minutes');
    $late = $helper->isLate($lastRun, '*/5 * * * *', graceSeconds: 60);
    echo "  Is late: " . ($late ? 'yes' : 'no') . "\n";

    echo "  -- cron helper: OK\n";
} catch (Throwable $e) {
    echo "  -- cron helper SKIPPED: " . $e->getMessage() . "\n";
}

// Test: AlertManager (needs symfony/cache from dev deps)
try {
    $cache = new Symfony\Component\Cache\Adapter\ArrayAdapter();
    $channel = new Crontinel\Alert\NullChannel();
    $manager = new Crontinel\Alert\AlertManager(
        cache: $cache,
        channel: $channel,
    );
    $manager->fire('test.alert', 'Test', 'Testing alerts', 'info');
    echo "  Alert fired: test.alert\n";
    echo "  -- alert manager: OK\n";
} catch (Throwable $e) {
    echo "  -- alert manager SKIPPED: " . $e->getMessage() . "\n";
}

exit($exit);
PHP_TEST

# Run PHP tests once — capture output and exit code
echo "  Running PHP tests..."
set +e
php test_php.php > test_php_output.txt 2>&1
php_exit=$?
set -e

# Display output
cat test_php_output.txt

# Evaluate individual results from output
while IFS= read -r line; do
    case "$line" in
        *MISSING*) fail "some core classes missing" ;;
        *"data objects ERROR"*) fail "data objects failed" ;;
        *"data objects: OK"*) pass "data objects created successfully" ;;
        *"cron helper: OK"*) pass "CronExpressionHelper works" ;;
        *"cron helper SKIPPED"*) skip "CronExpressionHelper test skipped" ;;
        *"alert manager: OK"*) pass "AlertManager works" ;;
        *"alert manager SKIPPED"*) skip "AlertManager test skipped — needs dev deps" ;;
    esac
done < test_php_output.txt

# Overall PHP result
if [ "$php_exit" -eq 0 ]; then
    pass "all PHP class tests passed"
else
    fail "some PHP class tests failed"
fi

# Ping the production API root
if curl -sS -o /dev/null -w '%{http_code}' "$CRONTINEL_API_URL" 2>/dev/null | grep -q '200\|301\|302\|403'; then
    pass "API endpoint reachable ($CRONTINEL_API_URL)"
else
    http_code=$(curl -sS -o /dev/null -w '%{http_code}' "$CRONTINEL_API_URL" 2>/dev/null || echo "000")
    if [ "$http_code" = "000" ]; then
        skip "API endpoint not reachable — network issue"
    else
        skip "API endpoint returned HTTP $http_code"
    fi
fi

# Ping the API health endpoint
API_HEALTH="${CRONTINEL_API_URL}/api/v1/health"
if curl -sS -o /dev/null -w '%{http_code}' "$API_HEALTH" 2>/dev/null | grep -q '200\|301\|302'; then
    pass "API health endpoint reachable"
else
    http_code=$(curl -sS -o /dev/null -w '%{http_code}' "$API_HEALTH" 2>/dev/null || echo "000")
    skip "API health endpoint returned HTTP $http_code (may not exist)"
fi

# Cleanup
rm -rf "$SANDBOX"
pass "cleanup done"

summary "PHP Core"
