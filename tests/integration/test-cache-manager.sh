#!/usr/bin/env bash
# =============================================================================
# Integration Test: cache-manager.sh with real cache operations
#
# Tests write, read, list, check, cleanup, and memory tier commands
# using a temporary project root to avoid polluting real cache.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test-helpers.sh"

PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CACHE_MANAGER="$PLUGIN_DIR/scripts/cache-manager.sh"

# --- Setup ---
setup_temp_dir

# Use a unique temp directory as the fake project root so cache entries
# are stored under a unique hash and don't collide with real data.
FAKE_PROJECT="$TEMP_DIR/fake-project"
mkdir -p "$FAKE_PROJECT"

# --- Prerequisite check ---
if [ ! -f "$CACHE_MANAGER" ]; then
  skip "cache-manager.sh not found"
  print_summary
  exit 0
fi

if ! command -v jq &>/dev/null; then
  skip "jq not available"
  print_summary
  exit 0
fi

# =============================================================================
# Test 1: Write a cache entry
# =============================================================================
test_begin "cache-manager: write succeeds"

echo "test-value-hello" | bash "$CACHE_MANAGER" write "$FAKE_PROJECT" "test-category" "test-key-1" 2>/dev/null
EXIT_CODE=$?

assert_eq "$EXIT_CODE" "0" "Write should succeed"

test_end

# =============================================================================
# Test 2: Read the written cache entry
# =============================================================================
test_begin "cache-manager: read returns written value"

RESULT=$(bash "$CACHE_MANAGER" read "$FAKE_PROJECT" "test-category" "test-key-1" 2>/dev/null)
EXIT_CODE=$?

assert_eq "$EXIT_CODE" "0" "Read should succeed"
assert_eq "$RESULT" "test-value-hello" "Read should return the written value"

test_end

# =============================================================================
# Test 3: Check freshness of written entry
# =============================================================================
test_begin "cache-manager: check confirms fresh entry"

bash "$CACHE_MANAGER" check "$FAKE_PROJECT" "test-category" "test-key-1" --ttl 1 2>/dev/null
EXIT_CODE=$?

assert_eq "$EXIT_CODE" "0" "Check should return 0 for fresh entry"

test_end

# =============================================================================
# Test 4: List shows the written entry
# =============================================================================
test_begin "cache-manager: list includes written entry"

RESULT=$(bash "$CACHE_MANAGER" list "$FAKE_PROJECT" 2>/dev/null)
EXIT_CODE=$?

assert_eq "$EXIT_CODE" "0" "List should succeed"
assert_json_valid "$RESULT" "List output should be valid JSON"

# Should contain our test entry
FOUND=$(echo "$RESULT" | jq '[.[] | select(.category == "test-category" and .key == "test-key-1")] | length' 2>/dev/null)
assert_eq "$FOUND" "1" "List should contain our test entry"

test_end

# =============================================================================
# Test 5: Write multiple entries and verify list count
# =============================================================================
test_begin "cache-manager: multiple entries listed correctly"

echo "second-value" | bash "$CACHE_MANAGER" write "$FAKE_PROJECT" "test-category" "test-key-2" 2>/dev/null
echo "third-value" | bash "$CACHE_MANAGER" write "$FAKE_PROJECT" "another-category" "test-key-3" 2>/dev/null

RESULT=$(bash "$CACHE_MANAGER" list "$FAKE_PROJECT" 2>/dev/null)

TOTAL=$(echo "$RESULT" | jq 'length' 2>/dev/null)
if [ "$TOTAL" -ge 3 ]; then
  pass "List has at least 3 entries ($TOTAL)"
else
  fail "List should have at least 3 entries, got: $TOTAL"
fi

test_end

# =============================================================================
# Test 6: Read nonexistent key returns exit 1
# =============================================================================
test_begin "cache-manager: read nonexistent key fails gracefully"

bash "$CACHE_MANAGER" read "$FAKE_PROJECT" "test-category" "nonexistent-key" 2>/dev/null
EXIT_CODE=$?

if [ "$EXIT_CODE" -ne 0 ]; then
  pass "Read nonexistent key exits with non-zero ($EXIT_CODE)"
else
  fail "Read nonexistent key should exit non-zero"
fi

test_end

# =============================================================================
# Test 7: Cleanup does not error
# =============================================================================
test_begin "cache-manager: cleanup runs without error"

bash "$CACHE_MANAGER" cleanup "$FAKE_PROJECT" --max-age 365 2>/dev/null
EXIT_CODE=$?

assert_eq "$EXIT_CODE" "0" "Cleanup should exit 0"

# Entries should still exist (max-age is 365 days, entries are fresh)
RESULT=$(bash "$CACHE_MANAGER" read "$FAKE_PROJECT" "test-category" "test-key-1" 2>/dev/null)
assert_eq "$RESULT" "test-value-hello" "Fresh entries should survive cleanup"

test_end

# =============================================================================
# Test 8: Hash command produces consistent output
# =============================================================================
test_begin "cache-manager: hash produces consistent output"

HASH1=$(bash "$CACHE_MANAGER" hash "$FAKE_PROJECT" 2>/dev/null)
HASH2=$(bash "$CACHE_MANAGER" hash "$FAKE_PROJECT" 2>/dev/null)

assert_eq "$HASH1" "$HASH2" "Same project should produce same hash"
assert_not_eq "$HASH1" "" "Hash should not be empty"

# Different project should produce different hash
HASH3=$(bash "$CACHE_MANAGER" hash "$TEMP_DIR/other-project" 2>/dev/null)
assert_not_eq "$HASH1" "$HASH3" "Different project should produce different hash"

test_end

# =============================================================================
# Test 9: Memory tier write and read
# =============================================================================
test_begin "cache-manager: memory-write and memory-read work"

echo '{"pattern": "sql-injection", "count": 3}' | bash "$CACHE_MANAGER" memory-write "$FAKE_PROJECT" "short-term" "recurring-findings" 2>/dev/null
EXIT_CODE=$?
assert_eq "$EXIT_CODE" "0" "Memory write should succeed"

RESULT=$(bash "$CACHE_MANAGER" memory-read "$FAKE_PROJECT" "short-term" "recurring-findings" 2>/dev/null)
EXIT_CODE=$?
assert_eq "$EXIT_CODE" "0" "Memory read should succeed"
assert_json_valid "$RESULT" "Memory read output should be valid JSON"

PATTERN=$(echo "$RESULT" | jq -r '.pattern' 2>/dev/null)
assert_eq "$PATTERN" "sql-injection" "Memory read should return correct data"

test_end

# =============================================================================
# Test 10: Memory tier list
# =============================================================================
test_begin "cache-manager: memory-list returns entries"

RESULT=$(bash "$CACHE_MANAGER" memory-list "$FAKE_PROJECT" "short-term" 2>/dev/null)
EXIT_CODE=$?

assert_eq "$EXIT_CODE" "0" "Memory list should succeed"
assert_json_valid "$RESULT" "Memory list output should be valid JSON"

COUNT=$(echo "$RESULT" | jq 'length' 2>/dev/null)
if [ "$COUNT" -ge 1 ]; then
  pass "Memory list has entries ($COUNT)"
else
  fail "Memory list should have at least 1 entry, got: $COUNT"
fi

test_end

# =============================================================================
# Test 11: Cleanup with aggressive max-age removes entries
# =============================================================================
test_begin "cache-manager: cleanup with max-age 0 removes entries"

# Write a fresh entry to confirm it exists
echo "cleanup-test" | bash "$CACHE_MANAGER" write "$FAKE_PROJECT" "cleanup-cat" "cleanup-key" 2>/dev/null

# Wait briefly to ensure timestamp is in the past
sleep 1

# Cleanup with max-age 0 (should remove everything)
bash "$CACHE_MANAGER" cleanup "$FAKE_PROJECT" --max-age 0 2>/dev/null
EXIT_CODE=$?
assert_eq "$EXIT_CODE" "0" "Cleanup with max-age 0 should exit 0"

# The entry should be gone
bash "$CACHE_MANAGER" read "$FAKE_PROJECT" "cleanup-cat" "cleanup-key" 2>/dev/null
READ_EXIT=$?
if [ "$READ_EXIT" -ne 0 ]; then
  pass "Entry removed after cleanup with max-age 0"
else
  fail "Entry should have been removed by cleanup with max-age 0"
fi

test_end

# =============================================================================
# Cleanup: remove cache entries created during test
# =============================================================================
# The cache entries are stored under PLUGIN_DIR/cache/{hash}.
# Remove the hash directory for our fake project.
CACHE_HASH=$(bash "$CACHE_MANAGER" hash "$FAKE_PROJECT" 2>/dev/null)
if [ -n "$CACHE_HASH" ] && [ -d "$PLUGIN_DIR/cache/$CACHE_HASH" ]; then
  rm -rf "$PLUGIN_DIR/cache/$CACHE_HASH"
fi

# --- Cleanup ---
cleanup
print_summary
