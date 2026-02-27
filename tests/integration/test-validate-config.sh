#!/usr/bin/env bash
# =============================================================================
# Integration Test: Config file validation
#
# Tests that all configuration JSON files in the project are valid and
# contain the expected structure, and that validate-config.sh works correctly.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test-helpers.sh"

PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATE="$PLUGIN_DIR/scripts/validate-config.sh"
CONFIG="$PLUGIN_DIR/config/default-config.json"

# --- Setup ---
setup_temp_dir

# --- Prerequisite check ---
if ! command -v jq &>/dev/null; then
  skip "jq not available"
  print_summary
  exit 0
fi

# =============================================================================
# Test 1: default-config.json is valid JSON
# =============================================================================
test_begin "validate-config: default-config.json is valid JSON"

assert_file_exists "$CONFIG" "default-config.json should exist"

if jq . "$CONFIG" >/dev/null 2>&1; then
  pass "default-config.json is valid JSON"
else
  fail "default-config.json is not valid JSON"
fi

test_end

# =============================================================================
# Test 2: default-config.json has all required top-level keys
# =============================================================================
test_begin "validate-config: default-config.json has required top-level keys"

for key in models review debate arena cache; do
  HAS_KEY=$(jq "has(\"$key\")" "$CONFIG" 2>/dev/null)
  if [ "$HAS_KEY" != "true" ]; then
    fail "Missing required top-level key: $key"
  fi
done
pass "All required top-level keys present (models, review, debate, arena, cache)"

test_end

# =============================================================================
# Test 3: default-config.json has expected additional keys
# =============================================================================
test_begin "validate-config: default-config.json has expected additional keys"

for key in output fallback cost_estimation intensity_presets business routing feedback context_density memory_tiers pipeline_evaluation; do
  HAS_KEY=$(jq "has(\"$key\")" "$CONFIG" 2>/dev/null)
  if [ "$HAS_KEY" != "true" ]; then
    fail "Missing expected key: $key"
  fi
done
pass "All expected additional keys present"

test_end

# =============================================================================
# Test 4: compliance-rules.json is valid JSON
# =============================================================================
test_begin "validate-config: compliance-rules.json is valid JSON"

COMPLIANCE="$PLUGIN_DIR/config/compliance-rules.json"

assert_file_exists "$COMPLIANCE" "compliance-rules.json should exist"

if jq . "$COMPLIANCE" >/dev/null 2>&1; then
  pass "compliance-rules.json is valid JSON"
else
  fail "compliance-rules.json is not valid JSON"
fi

# Verify it has the feature_patterns key
HAS_PATTERNS=$(jq 'has("feature_patterns")' "$COMPLIANCE" 2>/dev/null)
assert_eq "$HAS_PATTERNS" "true" "compliance-rules.json should have 'feature_patterns' key"

test_end

# =============================================================================
# Test 5: tech-queries.json is valid JSON
# =============================================================================
test_begin "validate-config: tech-queries.json is valid JSON"

TECH_QUERIES="$PLUGIN_DIR/config/tech-queries.json"

assert_file_exists "$TECH_QUERIES" "tech-queries.json should exist"

if jq . "$TECH_QUERIES" >/dev/null 2>&1; then
  pass "tech-queries.json is valid JSON"
else
  fail "tech-queries.json is not valid JSON"
fi

# Verify it has entries (at least 10 technologies documented)
ENTRY_COUNT=$(jq 'keys | length' "$TECH_QUERIES" 2>/dev/null || echo "0")
if [ "$ENTRY_COUNT" -ge 10 ]; then
  pass "tech-queries.json has $ENTRY_COUNT technology entries (>= 10)"
else
  fail "tech-queries.json should have at least 10 entries, got: $ENTRY_COUNT"
fi

test_end

# =============================================================================
# Test 6: All benchmark test case files are valid JSON
# =============================================================================
test_begin "validate-config: all benchmark files are valid JSON"

BENCHMARKS_DIR="$PLUGIN_DIR/config/benchmarks"
INVALID_COUNT=0
TOTAL_BENCHMARKS=0

if [ -d "$BENCHMARKS_DIR" ]; then
  for benchmark_file in "$BENCHMARKS_DIR"/*.json "$BENCHMARKS_DIR"/**/*.json; do
    [ -f "$benchmark_file" ] || continue
    TOTAL_BENCHMARKS=$((TOTAL_BENCHMARKS + 1))

    if ! jq . "$benchmark_file" >/dev/null 2>&1; then
      fail "Invalid JSON: $(basename "$benchmark_file")"
      INVALID_COUNT=$((INVALID_COUNT + 1))
    fi
  done

  if [ "$INVALID_COUNT" -eq 0 ] && [ "$TOTAL_BENCHMARKS" -gt 0 ]; then
    pass "All $TOTAL_BENCHMARKS benchmark files are valid JSON"
  elif [ "$TOTAL_BENCHMARKS" -eq 0 ]; then
    skip "No benchmark JSON files found"
  fi
else
  skip "Benchmarks directory not found"
fi

test_end

# =============================================================================
# Test 7: All Codex schema files are valid JSON
# =============================================================================
test_begin "validate-config: all schema files are valid JSON"

SCHEMAS_DIR="$PLUGIN_DIR/config/schemas"
SCHEMA_COUNT=0

if [ -d "$SCHEMAS_DIR" ]; then
  for schema_file in "$SCHEMAS_DIR"/*.json; do
    [ -f "$schema_file" ] || continue
    SCHEMA_COUNT=$((SCHEMA_COUNT + 1))

    if ! jq . "$schema_file" >/dev/null 2>&1; then
      fail "Invalid JSON schema: $(basename "$schema_file")"
    fi
  done

  if [ "$SCHEMA_COUNT" -gt 0 ]; then
    pass "All $SCHEMA_COUNT schema files are valid JSON"
  else
    skip "No schema JSON files found"
  fi
else
  skip "Schemas directory not found"
fi

test_end

# =============================================================================
# Test 8: validate-config.sh passes on default config
# =============================================================================
test_begin "validate-config: validate-config.sh passes on default config"

if [ -f "$VALIDATE" ]; then
  bash "$VALIDATE" "$CONFIG" >/dev/null 2>&1
  EXIT_CODE=$?
  assert_eq "$EXIT_CODE" "0" "validate-config.sh should pass on default config"
else
  skip "validate-config.sh not found"
fi

test_end

# =============================================================================
# Test 9: validate-config.sh fails on invalid JSON
# =============================================================================
test_begin "validate-config: validate-config.sh rejects invalid JSON"

if [ -f "$VALIDATE" ]; then
  echo "this is not json" > "$TEMP_DIR/bad-json.json"
  bash "$VALIDATE" "$TEMP_DIR/bad-json.json" >/dev/null 2>&1
  EXIT_CODE=$?
  assert_eq "$EXIT_CODE" "1" "Should reject invalid JSON"
else
  skip "validate-config.sh not found"
fi

test_end

# =============================================================================
# Test 10: validate-config.sh fails on missing required keys
# =============================================================================
test_begin "validate-config: validate-config.sh rejects missing keys"

if [ -f "$VALIDATE" ]; then
  # Config with only some required keys (missing models, debate, output)
  echo '{"review": {"intensity": "standard"}}' > "$TEMP_DIR/partial-config.json"
  bash "$VALIDATE" "$TEMP_DIR/partial-config.json" >/dev/null 2>&1
  EXIT_CODE=$?
  assert_eq "$EXIT_CODE" "1" "Should reject config missing required keys"
else
  skip "validate-config.sh not found"
fi

test_end

# =============================================================================
# Test 11: validate-config.sh passes on a fully valid custom config
# =============================================================================
test_begin "validate-config: validate-config.sh passes on valid custom config"

if [ -f "$VALIDATE" ]; then
  cat > "$TEMP_DIR/valid-custom.json" <<'CONFIG_EOF'
{
  "models": {
    "claude": {"enabled": true, "roles": ["security"]},
    "codex": {"enabled": false},
    "gemini": {"enabled": false}
  },
  "review": {
    "intensity": "standard",
    "confidence_threshold": 80
  },
  "debate": {
    "enabled": true,
    "max_rounds": 2
  },
  "output": {
    "language": "en"
  }
}
CONFIG_EOF
  bash "$VALIDATE" "$TEMP_DIR/valid-custom.json" >/dev/null 2>&1
  EXIT_CODE=$?
  assert_eq "$EXIT_CODE" "0" "Should accept valid custom config"
else
  skip "validate-config.sh not found"
fi

test_end

# =============================================================================
# Test 12: Config model structure validation
# =============================================================================
test_begin "validate-config: model configuration has expected structure"

# Verify each model has expected fields
for model in claude codex gemini; do
  ENABLED=$(jq ".models.${model}.enabled" "$CONFIG" 2>/dev/null)
  if [ "$ENABLED" != "true" ] && [ "$ENABLED" != "false" ]; then
    fail "models.$model.enabled should be boolean, got: $ENABLED"
  fi
done
pass "All model configurations have valid 'enabled' field"

# Verify Claude has roles array
ROLES_LEN=$(jq '.models.claude.roles | length' "$CONFIG" 2>/dev/null || echo "0")
if [ "$ROLES_LEN" -gt 0 ]; then
  pass "Claude model has $ROLES_LEN roles configured"
else
  fail "Claude model should have at least 1 role"
fi

test_end

# =============================================================================
# Test 13: Intensity presets have valid structure
# =============================================================================
test_begin "validate-config: intensity presets have valid structure"

for preset in quick standard deep comprehensive; do
  HAS_PRESET=$(jq ".intensity_presets | has(\"$preset\")" "$CONFIG" 2>/dev/null)
  if [ "$HAS_PRESET" != "true" ]; then
    fail "Missing intensity preset: $preset"
  fi
done
pass "All intensity presets (quick, standard, deep, comprehensive) present"

# Verify standard preset has reviewer_roles
STANDARD_ROLES=$(jq '.intensity_presets.standard.reviewer_roles | length' "$CONFIG" 2>/dev/null || echo "0")
if [ "$STANDARD_ROLES" -gt 0 ]; then
  pass "Standard preset has $STANDARD_ROLES reviewer roles"
else
  fail "Standard preset should have reviewer roles"
fi

test_end

# --- Cleanup ---
cleanup
print_summary
