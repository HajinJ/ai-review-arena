#!/usr/bin/env bash
# =============================================================================
# Tests for scripts/cost-estimator.sh
# =============================================================================

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$TESTS_DIR/test-helpers.sh"

SCRIPT="$REPO_DIR/scripts/cost-estimator.sh"

echo "=== test-cost-estimator.sh ==="

setup_temp_dir

# Create a test config with English output and all models disabled
# (to test without external CLIs)
cat > "$TEMP_DIR/config-basic.json" <<'EOF'
{
  "output": {"language": "en"},
  "models": {
    "claude": {"enabled": true, "roles": ["security", "bugs", "architecture"]},
    "codex": {"enabled": false},
    "gemini": {"enabled": false}
  },
  "debate": {"enabled": true, "max_rounds": 3},
  "cost_estimation": {
    "token_cost_per_1k": {
      "claude_input": 0.003,
      "claude_output": 0.015,
      "codex_input": 0.003,
      "codex_output": 0.012,
      "gemini_input": 0.00125,
      "gemini_output": 0.005
    },
    "prompt_cache_discount": 0.0
  }
}
EOF

# =========================================================================
# Test: quick intensity cost (minimal phases)
# =========================================================================

result=$(bash "$SCRIPT" "$TEMP_DIR/config-basic.json" --intensity quick --json 2>/dev/null)
assert_json_valid "$result" "quick: --json output is valid JSON"

intensity=$(echo "$result" | jq -r '.intensity')
assert_eq "$intensity" "quick" "quick: intensity field correct"

tokens=$(echo "$result" | jq '.total_tokens')
assert_gt "$tokens" 0 "quick: total_tokens > 0"

agents=$(echo "$result" | jq '.claude_agents')
assert_eq "$agents" "0" "quick: no claude agents for quick"

cli=$(echo "$result" | jq '.external_cli_calls')
assert_eq "$cli" "0" "quick: no external CLI calls"

# =========================================================================
# Test: standard intensity cost
# =========================================================================

result=$(bash "$SCRIPT" "$TEMP_DIR/config-basic.json" --intensity standard --json 2>/dev/null)
assert_json_valid "$result" "standard: --json output is valid JSON"

intensity=$(echo "$result" | jq -r '.intensity')
assert_eq "$intensity" "standard" "standard: intensity field correct"

tokens=$(echo "$result" | jq '.total_tokens')
assert_gt "$tokens" 1000 "standard: total_tokens > 1000"

agents=$(echo "$result" | jq '.claude_agents')
assert_gt "$agents" 0 "standard: has claude agents"

cost=$(echo "$result" | jq '.total_cost_usd')
cost_int=$(echo "$cost" | awk '{printf "%d", $1 * 100}')
assert_gt "$cost_int" 0 "standard: cost > 0"

# =========================================================================
# Test: --json output format fields
# =========================================================================

result=$(bash "$SCRIPT" "$TEMP_DIR/config-basic.json" --intensity deep --pipeline code --lines 1000 --json 2>/dev/null)
assert_json_valid "$result" "json fields: output is valid JSON"

pipeline=$(echo "$result" | jq -r '.pipeline')
assert_eq "$pipeline" "code" "json fields: pipeline correct"

lines=$(echo "$result" | jq '.input_lines')
assert_eq "$lines" "1000" "json fields: input_lines correct"

# Check all required fields exist
for field in intensity pipeline input_lines claude_agents external_cli_calls total_tokens total_cost_usd est_minutes prompt_cache_discount; do
  has_field=$(echo "$result" | jq "has(\"$field\")")
  assert_eq "$has_field" "true" "json fields: has $field"
done

# =========================================================================
# Test: cache discount application
# =========================================================================

cat > "$TEMP_DIR/config-cache.json" <<'EOF'
{
  "output": {"language": "en"},
  "models": {
    "claude": {"enabled": true, "roles": ["security", "bugs"]},
    "codex": {"enabled": false},
    "gemini": {"enabled": false}
  },
  "debate": {"enabled": true, "max_rounds": 3},
  "cost_estimation": {
    "token_cost_per_1k": {
      "claude_input": 0.003,
      "claude_output": 0.015
    },
    "prompt_cache_discount": 0.5
  }
}
EOF

result_no_cache=$(bash "$SCRIPT" "$TEMP_DIR/config-basic.json" --intensity standard --json 2>/dev/null)
result_with_cache=$(bash "$SCRIPT" "$TEMP_DIR/config-cache.json" --intensity standard --json 2>/dev/null)

cost_no=$(echo "$result_no_cache" | jq '.total_cost_usd')
cost_with=$(echo "$result_with_cache" | jq '.total_cost_usd')

discount=$(echo "$result_with_cache" | jq '.prompt_cache_discount')
assert_eq "$discount" "0.5" "cache discount: discount value reported"

# cost_with should be less than cost_no (cache discount reduces input cost)
is_cheaper=$(awk -v a="$cost_with" -v b="$cost_no" 'BEGIN { print (a < b) ? "true" : "false" }')
assert_eq "$is_cheaper" "true" "cache discount: cost is lower with cache discount"

# =========================================================================
# Test: text output format (non-JSON)
# =========================================================================

result=$(bash "$SCRIPT" "$TEMP_DIR/config-basic.json" --intensity quick 2>/dev/null)
assert_contains "$result" "Cost & Time Estimate" "text output: has header"
assert_contains "$result" "Intensity: quick" "text output: shows intensity"
assert_contains "$result" "Est. Cost:" "text output: shows estimated cost"

# =========================================================================
# Test: business pipeline
# =========================================================================

result=$(bash "$SCRIPT" "$TEMP_DIR/config-basic.json" --intensity standard --pipeline business --json 2>/dev/null)
assert_json_valid "$result" "business pipeline: output is valid JSON"

pipeline=$(echo "$result" | jq -r '.pipeline')
assert_eq "$pipeline" "business" "business pipeline: pipeline field correct"

# =========================================================================
# Test: with no external CLIs available (mock them away)
# =========================================================================

# Save and hide external CLIs
ORIG_PATH="$PATH"
export PATH="$TEMP_DIR/empty-bin:$ORIG_PATH"
mkdir -p "$TEMP_DIR/empty-bin"

# Ensure codex and gemini are not found
hash -r 2>/dev/null || true

result=$(bash "$SCRIPT" "$TEMP_DIR/config-basic.json" --intensity standard --json 2>/dev/null)
cli_calls=$(echo "$result" | jq '.external_cli_calls')
assert_eq "$cli_calls" "0" "no CLIs: external_cli_calls is 0"

export PATH="$ORIG_PATH"

print_summary
