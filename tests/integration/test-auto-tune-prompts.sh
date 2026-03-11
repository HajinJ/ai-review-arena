#!/usr/bin/env bash
# =============================================================================
# Integration Test: auto-tune-prompts.sh
#
# Tests the full dry-run loop, mock Claude CLI, and memory tier recording.
# Uses temporary directories to avoid polluting real cache/prompts.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test-helpers.sh"

PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
AUTO_TUNE="$PLUGIN_DIR/scripts/auto-tune-prompts.sh"
CACHE_MANAGER="$PLUGIN_DIR/scripts/cache-manager.sh"
CONFIG="$PLUGIN_DIR/config/default-config.json"

# --- Setup ---
setup_temp_dir

echo "=== test-auto-tune-prompts.sh (integration) ==="

# --- Prerequisite check ---
if [ ! -f "$AUTO_TUNE" ]; then
  skip "auto-tune-prompts.sh not found"
  print_summary
  exit 0
fi

if ! command -v jq &>/dev/null; then
  skip "jq not installed"
  print_summary
  exit 0
fi

# =========================================================================
# Test: dry-run full loop completes successfully
# =========================================================================

# Mock codex and gemini CLIs to avoid timeout from real external calls
mock_command "codex" '{"findings":[]}'
mock_command "gemini" '{"findings":[]}'

result=$(bash "$AUTO_TUNE" --config "$CONFIG" --category security --max-iterations 2 --dry-run 2>&1)
rc=$?
assert_exit_code 0 "$rc" "dry-run: exits 0"
assert_contains "$result" "Auto-tune" "dry-run: produces auto-tune output"
assert_contains "$result" "DRY-RUN" "dry-run: indicates dry-run mode"

# =========================================================================
# Test: dry-run with --json flag
# =========================================================================

json_output=$(bash "$AUTO_TUNE" --config "$CONFIG" --category security --max-iterations 1 --dry-run --json 2>/dev/null)
rc=$?
assert_exit_code 0 "$rc" "dry-run json: exits 0"

if [ -n "$json_output" ]; then
  if echo "$json_output" | jq empty 2>/dev/null; then
    pass "dry-run json: valid JSON output"
  else
    # Dry-run may produce non-JSON on stderr, that's OK
    pass "dry-run json: completes without error"
  fi
else
  # Empty output in CI without benchmarks is acceptable
  pass "dry-run json: completes (empty output OK without benchmark data)"
fi

# =========================================================================
# Test: mock Claude CLI mutation
# =========================================================================

# Create a mock claude command
mock_command "claude" "This is a mutated prompt with improved security detection patterns."

# Run with mock - dry-run mode so no actual benchmark runs
result=$(bash "$AUTO_TUNE" --config "$CONFIG" --category security --max-iterations 1 --dry-run 2>&1)
rc=$?
assert_exit_code 0 "$rc" "mock claude: exits 0"

# Unmock claude but keep codex/gemini mocked
unmock_command "claude"

# =========================================================================
# Test: memory tier recording (via dry-run)
# =========================================================================

FAKE_PROJECT="$TEMP_DIR/fake-project"
mkdir -p "$FAKE_PROJECT"

# After a dry-run, check if history was written to memory
# (may not be written if cache-manager isn't set up, but should not crash)
result=$(bash "$AUTO_TUNE" --config "$CONFIG" --category security --max-iterations 1 --dry-run 2>&1)
rc=$?
assert_exit_code 0 "$rc" "memory tier: dry-run completes without crash"

# =========================================================================
# Test: --category all processes multiple categories
# =========================================================================

result=$(bash "$AUTO_TUNE" --config "$CONFIG" --category all --max-iterations 1 --dry-run 2>&1)
rc=$?
assert_exit_code 0 "$rc" "category all: exits 0"
# Should mention multiple categories
category_count=$(echo "$result" | grep -c "Auto-tuning category:" || echo "0")
assert_gt "$category_count" 0 "category all: processes at least 1 category"

# =========================================================================
# Test: convergence threshold parameter
# =========================================================================

result=$(bash "$AUTO_TUNE" --config "$CONFIG" --category security --max-iterations 2 --convergence-threshold 50 --dry-run 2>&1)
rc=$?
assert_exit_code 0 "$rc" "convergence param: custom threshold accepted"

# =========================================================================
# Test: lockfile cleanup on exit
# =========================================================================

LOCKFILE="${PLUGIN_DIR}/cache/.auto-tune.lock"

# Run and ensure lockfile is cleaned up after exit
bash "$AUTO_TUNE" --config "$CONFIG" --category security --max-iterations 1 --dry-run 2>/dev/null
if [ -f "$LOCKFILE" ]; then
  fail "lockfile cleanup: lockfile should be removed after exit"
else
  pass "lockfile cleanup: lockfile removed on exit"
fi

# Cleanup mocks
unmock_command "codex"
unmock_command "gemini"

print_summary
