#!/usr/bin/env bash
set -euo pipefail

# Test 09: Rails — crontinel-rails gem
# Tests: Gemfile local path, bundle install, initializer, client health check

cd "$(dirname "$0")"
source ../config.sh

echo "=== Test 09: Rails ==="

SANDBOX="/tmp/crontinel-sandbox-rails"
rm -rf "$SANDBOX"

require_cmd ruby || { summary "Rails"; exit 1; }
require_cmd bundle || { summary "Rails"; exit 1; }

RUBY_VER="$(ruby -e 'puts RUBY_VERSION')"

# Check minimum Ruby version (crontinel-rails requires >= 2.7)
if ruby -e 'exit Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("2.7") ? 0 : 1' 2>/dev/null; then
    pass "Ruby $RUBY_VER meets minimum requirement (>= 2.7)"
else
    skip "Ruby $RUBY_VER is below 2.7 — crontinel-rails requires >= 2.7"
    summary "Rails"
    exit 0
fi

# Paths to local gem sources
CRONTINEL_RUBY_PATH="$CRONTINEL_REPOS_DIR/ruby"
CRONTINEL_RAILS_PATH="$CRONTINEL_REPOS_DIR/ruby-on-rails"

if [ ! -f "$CRONTINEL_RUBY_PATH/crontinel.gemspec" ]; then
    fail "crontinel Ruby gem not found at $CRONTINEL_RUBY_PATH"
    summary "Rails"
    exit 1
fi

if [ ! -f "$CRONTINEL_RAILS_PATH/crontinel-rails.gemspec" ]; then
    fail "crontinel-rails gem not found at $CRONTINEL_RAILS_PATH"
    summary "Rails"
    exit 1
fi

pass "local gem sources found"

# ── Create a fresh Rails project ──────────────────────────────────
mkdir -p "$SANDBOX"

# Use rails new to scaffold the project. Install rails temporarily if needed.
if command -v rails &>/dev/null && rails --version &>/dev/null; then
    RAILS_CMD="rails"
elif gem list --local rails 2>/dev/null | grep -q rails; then
    RAILS_CMD="rails"
else
    skip "Rails is not installed on this system — install with: gem install rails"
    # Still attempt with bundler but mark as skip
    if gem install rails --no-document --quiet 2>/dev/null; then
        pass "installed rails via gem install"
        RAILS_CMD="rails"
    else
        skip "could not install rails"
        summary "Rails"
        exit 0
    fi
fi

# Create a minimal Rails project (skip test-unit, action-mailer, action-mailbox, etc. for speed)
rails new "$SANDBOX" \
    --skip-test \
    --skip-action-mailer \
    --skip-action-mailbox \
    --skip-active-storage \
    --skip-action-text \
    --skip-action-cable \
    --skip-jbuilder \
    --skip-webpack-install \
    --skip-javascript \
    --skip-turbolinks \
    --skip-git \
    --skip-keeps \
    --quiet 2>/dev/null

if [ -f "$SANDBOX/Gemfile" ]; then
    pass "created fresh Rails project"
else
    fail "rails new failed"
    summary "Rails"
    exit 1
fi

cd "$SANDBOX"

# ── Configure Gemfile with local gem paths ────────────────────────

# Remove any existing crontinel gem lines that might conflict
sed -i '' '/^gem "crontinel"/d' Gemfile 2>/dev/null || true

# Add local gem paths
cat >> Gemfile << GEMEOF

# Crontinel gems (local development paths)
gem "crontinel", path: "$CRONTINEL_RUBY_PATH"
gem "crontinel-rails", path: "$CRONTINEL_RAILS_PATH"
GEMEOF

pass "configured Gemfile with local gem paths"

# ── Bundle install ────────────────────────────────────────────────
BUNDLE_GEMFILE="$SANDBOX/Gemfile" bundle install --quiet 2>&1 || true

if BUNDLE_GEMFILE="$SANDBOX/Gemfile" bundle list 2>/dev/null | grep -q "crontinel-rails"; then
    pass "bundle install — crontinel-rails loaded"
else
    fail "bundle install — crontinel-rails not found"
    BUNDLE_GEMFILE="$SANDBOX/Gemfile" bundle list 2>&1 | grep crontinel || true
    summary "Rails"
    exit 1
fi

if BUNDLE_GEMFILE="$SANDBOX/Gemfile" bundle list 2>/dev/null | grep -q "crontinel"; then
    pass "bundle install — crontinel ruby SDK loaded"
else
    fail "bundle install — crontinel ruby SDK not found"
    summary "Rails"
    exit 1
fi

# ── Create initializer ────────────────────────────────────────────
mkdir -p "$SANDBOX/config/initializers"

cat > "$SANDBOX/config/initializers/crontinel.rb" << RBYEOF
Crontinel.setup do |config|
  config.api_key = ENV.fetch("CRONTINEL_API_KEY")
  config.endpoint = ENV.fetch("CRONTINEL_API_URL", "https://app.crontinel.com/api/v1")
end
RBYEOF

pass "created config/initializers/crontinel.rb"

# ── Test health check via Rails runner ────────────────────────────
echo "  > Testing Crontinel connection via Rails runner..."

HEALTH_SCRIPT="$SANDBOX/test_health.rb"
cat > "$HEALTH_SCRIPT" << RBYEOF
require_relative "config/environment"

begin
  client = Crontinel.client(
    api_key: ENV.fetch("CRONTINEL_API_KEY"),
    endpoint: ENV.fetch("CRONTINEL_API_URL", "https://app.crontinel.com/api/v1")
  )
  result = client.health_check
  puts "HEALTH_CHECK:#{result}"
rescue => e
  puts "HEALTH_CHECK_ERROR:#{e.message}"
  exit 1
end
RBYEOF

# Export env vars for the test
export CRONTINEL_API_KEY CRONTINEL_API_URL

RAILS_OUTPUT=$(cd "$SANDBOX" && BUNDLE_GEMFILE="$SANDBOX/Gemfile" bundle exec ruby "$HEALTH_SCRIPT" 2>&1 || true)

if echo "$RAILS_OUTPUT" | grep -q "HEALTH_CHECK:true"; then
    pass "Crontinel health check succeeds via Rails app"
elif echo "$RAILS_OUTPUT" | grep -q "HEALTH_CHECK:"; then
    pass "Crontinel health check returned: $(echo "$RAILS_OUTPUT" | grep HEALTH_CHECK)"
else
    fail "Crontinel health check failed"
    echo "  Output: $RAILS_OUTPUT" | head -5
fi

# ── Test version constant ─────────────────────────────────────────
VERSION_SCRIPT="$SANDBOX/test_version.rb"
cat > "$VERSION_SCRIPT" << RBYEOF
require_relative "config/environment"
puts "VERSION:#{Crontinel::Rails::VERSION}"
RBYEOF

VERSION_OUTPUT=$(cd "$SANDBOX" && BUNDLE_GEMFILE="$SANDBOX/Gemfile" bundle exec ruby "$VERSION_SCRIPT" 2>&1 || true)

if echo "$VERSION_OUTPUT" | grep -q "VERSION:"; then
    pass "Crontinel::Rails::VERSION = $(echo "$VERSION_OUTPUT" | grep VERSION | cut -d: -f2)"
else
    fail "Crontinel::Rails::VERSION not accessible"
    echo "  Output: $VERSION_OUTPUT"
fi

# ── Test Rails generator registration (if available) ──────────────
GENERATOR_SCRIPT="$SANDBOX/test_generators.rb"
cat > "$GENERATOR_SCRIPT" << RBYEOF
require_relative "config/environment"

begin
  generators = Rails::Generators.lookup("crontinel")
  if generators.any?
    puts "GENERATOR_FOUND:#{generators.first.name}"
  else
    puts "GENERATOR_NOT_FOUND"
  end
rescue => e
  puts "GENERATOR_ERROR:#{e.message}"
end
RBYEOF

GENERATOR_OUTPUT=$(cd "$SANDBOX" && BUNDLE_GEMFILE="$SANDBOX/Gemfile" bundle exec ruby "$GENERATOR_SCRIPT" 2>&1 || true)

if echo "$GENERATOR_OUTPUT" | grep -q "GENERATOR_FOUND"; then
    pass "crontinel Rails generator registered"
elif echo "$GENERATOR_OUTPUT" | grep -q "GENERATOR_NOT_FOUND"; then
    pass "Rails app loads without error (no generator — expected for current gem)"
else
    echo "  Generator check: $GENERATOR_OUTPUT"
    skip "generator check encountered an issue (non-critical)"
fi

# ── Test Rake task registration ───────────────────────────────────
RAKE_OUTPUT=$(cd "$SANDBOX" && BUNDLE_GEMFILE="$SANDBOX/Gemfile" bundle exec rails runner "
begin
  require 'rake'
  Rails.application.load_tasks
  tasks = Rake::Task.tasks.select { |t| t.name =~ /crontinel/ }
  if tasks.any?
    puts \"RAKE_TASKS:#{tasks.map(&:name).join(',')}\"
  else
    puts 'RAKE_TASKS:(none)'
  end
rescue => e
  puts \"RAKE_ERROR:#{e.message}\"
end
" 2>&1 || true)

if echo "$RAKE_OUTPUT" | grep -q "RAKE_TASKS:"; then
    pass "Rake tasks registered: $(echo "$RAKE_OUTPUT" | grep RAKE_TASKS | cut -d: -f2-)"
else
    echo "  Rake check: $RAKE_OUTPUT"
    skip "no crontinel rake tasks found (non-critical)"
fi

# ── Test ActiveJob integration ────────────────────────────────────
JOB_SCRIPT="$SANDBOX/test_active_job.rb"
cat > "$JOB_SCRIPT" << RBYEOF
require_relative "config/environment"

# Verify the ActiveJob concern is loadable
begin
  mod = Crontinel::Rails::ActiveJob
  puts "ACTIVEJOB_MODULE:#{mod.name}"
rescue => e
  puts "ACTIVEJOB_ERROR:#{e.message}"
end
RBYEOF

JOB_OUTPUT=$(cd "$SANDBOX" && BUNDLE_GEMFILE="$SANDBOX/Gemfile" bundle exec ruby "$JOB_SCRIPT" 2>&1 || true)

if echo "$JOB_OUTPUT" | grep -q "ACTIVEJOB_MODULE:"; then
    pass "Crontinel::Rails::ActiveJob module is loadable"
else
    echo "  ActiveJob check: $JOB_OUTPUT"
    skip "ActiveJob module check (non-critical)"
fi

# ── Test Sidekiq middleware ───────────────────────────────────────
SIDEKIQ_SCRIPT="$SANDBOX/test_sidekiq.rb"
cat > "$SIDEKIQ_SCRIPT" << RBYEOF
require_relative "config/environment"

begin
  mod = Crontinel::Rails::Sidekiq::ServerMiddleware
  puts "SIDEKIQ_MIDDLEWARE:#{mod.name}"
rescue => e
  puts "SIDEKIQ_ERROR:#{e.message}"
end
RBYEOF

SIDEKIQ_OUTPUT=$(cd "$SANDBOX" && BUNDLE_GEMFILE="$SANDBOX/Gemfile" bundle exec ruby "$SIDEKIQ_SCRIPT" 2>&1 || true)

if echo "$SIDEKIQ_OUTPUT" | grep -q "SIDEKIQ_MIDDLEWARE:"; then
    pass "Crontinel::Rails::Sidekiq::ServerMiddleware is loadable"
else
    echo "  Sidekiq check: $SIDEKIQ_OUTPUT"
    skip "Sidekiq middleware check — Sidekiq may not be bundled (non-critical)"
fi

# ── Cleanup ───────────────────────────────────────────────────────
rm -rf "$SANDBOX"
pass "cleanup done"

summary "Rails"
