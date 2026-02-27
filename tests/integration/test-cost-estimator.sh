#!/usr/bin/env bash
# =============================================================================
# Integration Test: cost-estimator.sh with real arguments
#
# Tests the cost estimator script with various intensity/pipeline combinations
# using the actual default-config.json and verifying real output.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test-helpers.sh"

PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
COST_ESTIMATOR="$PLUGIN_DIR/scripts/cost-estimator.sh"
CONFIG="$PLUGIN_DIR/config/default-config.json"

# --- Setup ---
setup_temp_dir

# --- Prerequisite check ---
if [ ! -f "$COST_ESTIMATOR" ]; then
  skip "cost-estimator.sh not found"
  print_summary
  exit 0
fi

if [ ! -f "$CONFIG" ]; then
  skip "default-config.json not found"
  print_summary
  exit 0
fi

if ! command -v jq &>/dev/null; then
  skip "jq not available"
  print_summary
  exit 0
fi

# =============================================================================
# Test 1: --intensity quick --pipeline code --lines 100 --json
# =============================================================================
test_begin "cost-estimator: quick code JSON output"

RESULT=$(bash "$COST_ESTIMATOR" "$CONFIG" --intensity quick --pipeline code --lines 100 --json 2>/dev/null)
EXIT_CODE=$?

assert_eq "$EXIT_CODE" "0" "Should exit 0"
assert_json_valid "$RESULT" "Output should be valid JSON"

# Verify cost > 0
COST=$(echo "$RESULT" | jq '.total_cost_usd // 0' 2>/dev/null)
if [ "$(echo "$COST > 0" | bc 2>/dev/null || awk -v c="$COST" 'BEGIN{print (c>0)?"1":"0"}')" = "1" ]; then
  pass "Cost is greater than 0 ($COST)"
else
  fail "Cost should be > 0, got: $COST"
fi

# Verify expected JSON fields
INTENSITY_VAL=$(echo "$RESULT" | jq -r '.intensity' 2>/dev/null)
assert_eq "$INTENSITY_VAL" "quick" "Intensity should be 'quick'"

PIPELINE_VAL=$(echo "$RESULT" | jq -r '.pipeline' 2>/dev/null)
assert_eq "$PIPELINE_VAL" "code" "Pipeline should be 'code'"

LINES_VAL=$(echo "$RESULT" | jq '.input_lines' 2>/dev/null)
assert_eq "$LINES_VAL" "100" "Input lines should be 100"

TOKENS=$(echo "$RESULT" | jq '.total_tokens // 0' 2>/dev/null)
if [ "$TOKENS" -gt 0 ]; then
  pass "Total tokens is positive ($TOKENS)"
else
  fail "Total tokens should be > 0, got: $TOKENS"
fi

EST_MIN=$(echo "$RESULT" | jq '.est_minutes // 0' 2>/dev/null)
if [ "$EST_MIN" -ge 1 ]; then
  pass "Estimated minutes >= 1 ($EST_MIN)"
else
  fail "Estimated minutes should be >= 1, got: $EST_MIN"
fi

test_end

# =============================================================================
# Test 2: --intensity standard --pipeline code --lines 500 (text output)
# =============================================================================
test_begin "cost-estimator: standard code text output"

RESULT=$(bash "$COST_ESTIMATOR" "$CONFIG" --intensity standard --pipeline code --lines 500 2>/dev/null)
EXIT_CODE=$?

assert_eq "$EXIT_CODE" "0" "Should exit 0"

# Should contain dollar amounts (either $X.XX pattern)
if echo "$RESULT" | grep -q '\$[0-9]'; then
  pass "Text output contains dollar amounts"
else
  fail "Text output should contain dollar amounts" "got: $(echo "$RESULT" | head -20)"
fi

# Should contain intensity label
assert_contains "$RESULT" "standard" "Output should mention intensity 'standard'"

# Should contain pipeline type
assert_contains "$RESULT" "code" "Output should mention pipeline 'code'"

test_end

# =============================================================================
# Test 3: --intensity deep --pipeline business --lines 200 --json
# =============================================================================
test_begin "cost-estimator: deep business JSON output"

RESULT=$(bash "$COST_ESTIMATOR" "$CONFIG" --intensity deep --pipeline business --lines 200 --json 2>/dev/null)
EXIT_CODE=$?

assert_eq "$EXIT_CODE" "0" "Should exit 0"
assert_json_valid "$RESULT" "Output should be valid JSON"

INTENSITY_VAL=$(echo "$RESULT" | jq -r '.intensity' 2>/dev/null)
assert_eq "$INTENSITY_VAL" "deep" "Intensity should be 'deep'"

PIPELINE_VAL=$(echo "$RESULT" | jq -r '.pipeline' 2>/dev/null)
assert_eq "$PIPELINE_VAL" "business" "Pipeline should be 'business'"

# Deep business should have agents
AGENTS=$(echo "$RESULT" | jq '.claude_agents // 0' 2>/dev/null)
if [ "$AGENTS" -gt 0 ]; then
  pass "Deep business has Claude agents ($AGENTS)"
else
  fail "Deep business should have Claude agents, got: $AGENTS"
fi

# Verify cost caps are present
HAS_CAPS=$(echo "$RESULT" | jq 'has("cost_caps")' 2>/dev/null)
assert_eq "$HAS_CAPS" "true" "JSON should have cost_caps field"

test_end

# =============================================================================
# Test 4: --pipeline code without --intensity (should use default)
# =============================================================================
test_begin "cost-estimator: default intensity when not specified"

RESULT=$(bash "$COST_ESTIMATOR" "$CONFIG" --pipeline code --json 2>/dev/null)
EXIT_CODE=$?

assert_eq "$EXIT_CODE" "0" "Should exit 0"
assert_json_valid "$RESULT" "Output should be valid JSON"

# Default intensity is "standard" per the script
INTENSITY_VAL=$(echo "$RESULT" | jq -r '.intensity' 2>/dev/null)
assert_eq "$INTENSITY_VAL" "standard" "Default intensity should be 'standard'"

test_end

# =============================================================================
# Test 5: comprehensive intensity has higher cost than quick
# =============================================================================
test_begin "cost-estimator: comprehensive costs more than quick"

QUICK_RESULT=$(bash "$COST_ESTIMATOR" "$CONFIG" --intensity quick --pipeline code --lines 500 --json 2>/dev/null)
COMP_RESULT=$(bash "$COST_ESTIMATOR" "$CONFIG" --intensity comprehensive --pipeline code --lines 500 --json 2>/dev/null)

QUICK_COST=$(echo "$QUICK_RESULT" | jq '.total_cost_usd // 0' 2>/dev/null)
COMP_COST=$(echo "$COMP_RESULT" | jq '.total_cost_usd // 0' 2>/dev/null)

if [ "$(awk -v q="$QUICK_COST" -v c="$COMP_COST" 'BEGIN{print (c>q)?"1":"0"}')" = "1" ]; then
  pass "Comprehensive cost ($COMP_COST) > quick cost ($QUICK_COST)"
else
  fail "Comprehensive should cost more than quick" "comprehensive=$COMP_COST, quick=$QUICK_COST"
fi

test_end

# =============================================================================
# Test 6: Invalid config file is handled gracefully
# =============================================================================
test_begin "cost-estimator: handles missing config file"

bash "$COST_ESTIMATOR" "$TEMP_DIR/nonexistent-config.json" --intensity quick --json >/dev/null 2>&1
EXIT_CODE=$?

if [ "$EXIT_CODE" -ne 0 ]; then
  pass "Non-zero exit for missing config file (exit=$EXIT_CODE)"
else
  fail "Should exit non-zero for missing config file"
fi

test_end

# --- Cleanup ---
cleanup
print_summary
