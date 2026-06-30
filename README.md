# Crontinel Sandbox 🧪

End-to-end connection tests for all Crontinel framework packages.

## What it tests

Each framework package gets a standalone test script that:

1. **Installs** the package in a temp sandbox
2. **Initializes** the connection with API credentials
3. **Pings** the production API to verify connectivity
4. **Lists** monitors/jobs
5. **Cleans up** the temp sandbox

## Packages covered

| # | Package | Language | Test |
|---|---|---|---|
| 01 | **CLI** | Go binary | `tests/01-cli.sh` |
| 02 | **Laravel** | PHP (composer) | `tests/02-laravel.sh` |
| 03 | **Node** | JavaScript/TypeScript | `tests/03-node.sh` |
| 04 | **Python** | Python (pip) | `tests/04-python.sh` |
| 05 | **PHP** | PHP (composer) | `tests/05-php.sh` |
| 06 | **Go** | Go (module) | `tests/06-go.sh` |
| 07 | **Rust** | Rust (cargo) | `tests/07-rust.sh` |
| 08 | **Ruby** | Ruby (gem) | `tests/08-ruby.sh` |
| 09 | **Rails** | Ruby on Rails | `tests/09-rails.sh` |
| 10 | **Trigger** | Cloud API | `tests/10-trigger.sh` |

## Prerequisites

- **API key** — set `CRONTINEL_API_KEY` env var (defaults to the TestTriggerApp key)
- Each test checks for its required runtime (`composer`, `node`, `python3`, `ruby`, `cargo`, etc.) and skips gracefully if missing

## Running

```bash
# Run all tests
./run-all.sh

# Run a single test
bash tests/01-cli.sh

# Run with a specific API key
CRONTINEL_API_KEY=your_key ./run-all.sh
```

## How it works

Each test script sources `config.sh` for shared config (API key, URL, pass/fail helpers). Tests create temp directories under `/tmp/crontinel-sandbox-*`, install packages locally, verify API connectivity, then clean up.
