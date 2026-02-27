#!/usr/bin/env bash
# =============================================================================
# Tests for scripts/cache-manager.sh
# =============================================================================

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$TESTS_DIR/test-helpers.sh"

SCRIPT="$REPO_DIR/scripts/cache-manager.sh"

echo "=== test-cache-manager.sh ==="

setup_temp_dir

# Override UTILS_PLUGIN_DIR so cache goes into our temp dir
# We do this by setting up a fake plugin structure
FAKE_PLUGIN="$TEMP_DIR/plugin"
mkdir -p "$FAKE_PLUGIN/scripts" "$FAKE_PLUGIN/cache" "$FAKE_PLUGIN/config"

# Copy utils.sh to fake plugin so cache-manager can source it
cp "$REPO_DIR/scripts/utils.sh" "$FAKE_PLUGIN/scripts/"
cp "$REPO_DIR/scripts/cache-manager.sh" "$FAKE_PLUGIN/scripts/"

# Create a minimal default config
cat > "$FAKE_PLUGIN/config/default-config.json" <<'EOF'
{}
EOF

PROJECT_ROOT="$TEMP_DIR/myproject"
mkdir -p "$PROJECT_ROOT"

CM="$FAKE_PLUGIN/scripts/cache-manager.sh"

# =========================================================================
# Test: write (pipe content, verify file created)
# =========================================================================

echo "hello world" | bash "$CM" write "$PROJECT_ROOT" "test-cat" "key1" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "write: exits 0"

# Verify cache file exists by reading it
result=$(bash "$CM" read "$PROJECT_ROOT" "test-cat" "key1" 2>/dev/null)
rc=$?
assert_exit_code 0 "$rc" "read after write: exits 0"
assert_eq "$result" "hello world" "write+read: content matches"

# =========================================================================
# Test: read on non-existent key returns exit 1
# =========================================================================

bash "$CM" read "$PROJECT_ROOT" "test-cat" "nonexistent" 2>/dev/null
rc=$?
assert_exit_code 1 "$rc" "read: non-existent key returns exit 1"

# =========================================================================
# Test: TTL check - fresh entry
# =========================================================================

echo "fresh data" | bash "$CM" write "$PROJECT_ROOT" "ttl-cat" "fresh-key" 2>/dev/null

bash "$CM" check "$PROJECT_ROOT" "ttl-cat" "fresh-key" --ttl 1 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "check: fresh entry within TTL returns 0"

# =========================================================================
# Test: TTL check - stale entry (fake old timestamp)
# =========================================================================

echo "old data" | bash "$CM" write "$PROJECT_ROOT" "ttl-cat" "stale-key" 2>/dev/null

# Manually overwrite timestamp to be very old (epoch 1000)
hash_output=$(bash "$CM" hash "$PROJECT_ROOT" 2>/dev/null)
ts_dir="$FAKE_PLUGIN/cache/$hash_output/ttl-cat"
echo "1000" > "$ts_dir/stale-key.timestamp"

bash "$CM" check "$PROJECT_ROOT" "ttl-cat" "stale-key" --ttl 1 2>/dev/null
rc=$?
assert_exit_code 1 "$rc" "check: stale entry beyond TTL returns 1"

# Read should also fail for stale entry
bash "$CM" read "$PROJECT_ROOT" "ttl-cat" "stale-key" --ttl 1 2>/dev/null
rc=$?
assert_exit_code 1 "$rc" "read: stale entry returns 1"

# =========================================================================
# Test: cleanup removes old files
# =========================================================================

# Write a fresh entry and a stale entry
echo "keep me" | bash "$CM" write "$PROJECT_ROOT" "cleanup-cat" "fresh" 2>/dev/null
echo "remove me" | bash "$CM" write "$PROJECT_ROOT" "cleanup-cat" "old" 2>/dev/null

# Make the "old" entry stale
cleanup_ts_dir="$FAKE_PLUGIN/cache/$hash_output/cleanup-cat"
echo "1000" > "$cleanup_ts_dir/old.timestamp"

bash "$CM" cleanup "$PROJECT_ROOT" --max-age 1 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "cleanup: exits 0"

# Fresh entry should still be readable
bash "$CM" check "$PROJECT_ROOT" "cleanup-cat" "fresh" --ttl 1 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "cleanup: fresh entry survives cleanup"

# Old entry should be gone
if [ -f "$cleanup_ts_dir/old" ]; then
  fail "cleanup: old entry should be removed"
  TEST_TOTAL=$((TEST_TOTAL + 1))
  TEST_FAIL=$((TEST_FAIL + 1))
else
  test_start "cleanup: old entry removed"
  pass "cleanup: old entry removed"
fi

# =========================================================================
# Test: hash generation is deterministic
# =========================================================================

hash1=$(bash "$CM" hash "/test/path" 2>/dev/null)
hash2=$(bash "$CM" hash "/test/path" 2>/dev/null)
assert_eq "$hash1" "$hash2" "hash: deterministic for same path"

hash3=$(bash "$CM" hash "/other/path" 2>/dev/null)
assert_not_eq "$hash1" "$hash3" "hash: different for different paths"

# =========================================================================
# Test: list command
# =========================================================================

echo "list data" | bash "$CM" write "$PROJECT_ROOT" "list-cat" "item1" 2>/dev/null

result=$(bash "$CM" list "$PROJECT_ROOT" 2>/dev/null)
assert_json_valid "$result" "list: output is valid JSON"
assert_contains "$result" "list-cat" "list: contains category name"
assert_contains "$result" "item1" "list: contains key name"

print_summary
