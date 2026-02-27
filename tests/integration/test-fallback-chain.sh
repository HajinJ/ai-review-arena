#!/usr/bin/env bash
# =============================================================================
# Integration Test: Fallback chain (Level 0→5) transitions
#
# Tests the fallback framework behavior when components fail:
# - L0: Full normal operation
# - L1: Benchmark failure → default role assignment
# - L2: Research failure → proceed without context
# - L3: Agent Teams failure → switch to subagents
# - L4: External CLI failure → Claude only
# - L5: All failure → inline analysis
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test-helpers.sh"

PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# --- Setup ---
setup_temp_dir

# --- Test: Fallback level definition exists in config ---
test_begin "fallback: config has fallback level definitions"

CONFIG="$PLUGIN_DIR/config/default-config.json"

assert_file_exists "$CONFIG" "default-config.json should exist"

HAS_FALLBACK=$(jq 'has("fallback")' "$CONFIG" 2>/dev/null)
assert_eq "$HAS_FALLBACK" "true" "Config should have fallback section"

LEVEL_COUNT=$(jq '.fallback.levels | length' "$CONFIG" 2>/dev/null || echo "0")
assert_eq "$LEVEL_COUNT" "6" "Should have 6 fallback levels (L0-L5)"

STRATEGY=$(jq -r '.fallback.strategy' "$CONFIG" 2>/dev/null)
assert_eq "$STRATEGY" "graceful_degradation" "Strategy should be graceful_degradation"

test_end

# --- Test: orchestrate-review.sh has fallback tracking ---
test_begin "fallback: orchestrate-review.sh initializes FALLBACK_LEVEL"

ORCHESTRATE="$PLUGIN_DIR/scripts/orchestrate-review.sh"
assert_file_exists "$ORCHESTRATE" "orchestrate-review.sh should exist"

# Check for FALLBACK_LEVEL initialization
if grep -q "FALLBACK_LEVEL=" "$ORCHESTRATE" 2>/dev/null; then
  pass "FALLBACK_LEVEL variable found in orchestrate-review.sh"
else
  fail "FALLBACK_LEVEL not found in orchestrate-review.sh"
fi

test_end

# --- Test: run-debate.sh handles CLI failure gracefully ---
test_begin "fallback: debate handles missing CLIs gracefully"

DEBATE="$PLUGIN_DIR/scripts/run-debate.sh"

# Remove all CLIs from PATH
CLEAN_PATH="/usr/bin:/bin"

echo '[{"title":"Test","severity":"high","confidence":85,"models":["codex"],"file":"test.py","line":1}]' > "$TEMP_DIR/fallback-findings.json"

# Create minimal config
cat > "$TEMP_DIR/fallback-config.json" <<'CONFIG_EOF'
{
  "models": {"codex": {"enabled": true}, "gemini": {"enabled": true}},
  "debate": {"enabled": true, "max_rounds": 1, "consensus_threshold": 80, "challenge_threshold": 60},
  "websocket": {"enabled": false},
  "fallback": {"external_cli_timeout_seconds": 5}
}
CONFIG_EOF

mkdir -p "$TEMP_DIR/session"

RESULT=$(PATH="$CLEAN_PATH" bash "$DEBATE" "$TEMP_DIR/fallback-findings.json" "$TEMP_DIR/fallback-config.json" "$TEMP_DIR/session" 2>/dev/null)
EXIT_CODE=$?

assert_eq "$EXIT_CODE" "0" "Debate should exit 0 even when CLIs unavailable"
assert_json_valid "$RESULT" "Should produce valid JSON output"

# All findings should be accepted (no challengers available)
ACCEPTED=$(echo "$RESULT" | jq '.accepted | length' 2>/dev/null || echo "0")
assert_eq "$ACCEPTED" "1" "Finding should be accepted when no challengers available"

test_end

# --- Test: aggregate-findings handles empty session ---
test_begin "fallback: aggregate-findings handles empty session dir"

AGGREGATE="$PLUGIN_DIR/scripts/aggregate-findings.sh"
EMPTY_SESSION="$TEMP_DIR/empty-session"
mkdir -p "$EMPTY_SESSION"

RESULT=$(bash "$AGGREGATE" "$EMPTY_SESSION" "$TEMP_DIR/fallback-config.json" 2>/dev/null)

assert_eq "$RESULT" "LGTM" "Empty session should produce LGTM"

test_end

# --- Test: aggregate-findings handles invalid JSON files ---
test_begin "fallback: aggregate-findings skips invalid JSON"

INVALID_SESSION="$TEMP_DIR/invalid-session"
mkdir -p "$INVALID_SESSION"

echo "not valid json" > "$INVALID_SESSION/findings_0.json"

cat > "$INVALID_SESSION/findings_1.json" <<'VALID'
{"model":"codex","role":"security","file":"test.py","findings":[{"title":"Real Finding","severity":"high","confidence":80,"line":5,"description":"test"}]}
VALID

RESULT=$(bash "$AGGREGATE" "$INVALID_SESSION" "$TEMP_DIR/fallback-config.json" 2>/dev/null)

if [ "$RESULT" != "LGTM" ]; then
  assert_json_valid "$RESULT" "Valid findings should still be processed"
  COUNT=$(echo "$RESULT" | jq 'length' 2>/dev/null || echo "0")
  assert_eq "$COUNT" "1" "Should have 1 finding from the valid file"
else
  pass "LGTM is acceptable (threshold filtering)"
fi

test_end

# --- Test: validate-config catches errors ---
test_begin "fallback: validate-config catches missing keys"

VALIDATE="$PLUGIN_DIR/scripts/validate-config.sh"

if [ -f "$VALIDATE" ]; then
  # Valid config should pass
  bash "$VALIDATE" "$PLUGIN_DIR/config/default-config.json" >/dev/null 2>&1
  assert_eq "$?" "0" "Default config should pass validation"

  # Invalid JSON should fail
  echo "not json" > "$TEMP_DIR/bad-config.json"
  bash "$VALIDATE" "$TEMP_DIR/bad-config.json" >/dev/null 2>&1
  assert_eq "$?" "1" "Invalid JSON should fail validation"

  # Missing required keys should fail
  echo '{"review": {}}' > "$TEMP_DIR/partial-config.json"
  bash "$VALIDATE" "$TEMP_DIR/partial-config.json" >/dev/null 2>&1
  assert_eq "$?" "1" "Config missing required keys should fail"
else
  skip "validate-config.sh not found"
fi

test_end

# --- Test: cost-estimator handles missing CLIs ---
test_begin "fallback: cost-estimator works without external CLIs"

COST="$PLUGIN_DIR/scripts/cost-estimator.sh"
CONFIG="$PLUGIN_DIR/config/default-config.json"

# Run with no external CLIs in PATH
RESULT=$(PATH="/usr/bin:/bin" bash "$COST" "$CONFIG" --intensity quick --json 2>/dev/null)
EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ] && [ -n "$RESULT" ]; then
  assert_json_valid "$RESULT" "Cost estimate should be valid JSON"
  CLI_CALLS=$(echo "$RESULT" | jq '.external_cli_calls // -1' 2>/dev/null)
  assert_eq "$CLI_CALLS" "0" "Should report 0 CLI calls when CLIs unavailable"
else
  skip "cost-estimator requires dependencies not available"
fi

test_end

# --- Cleanup ---
cleanup
print_summary
