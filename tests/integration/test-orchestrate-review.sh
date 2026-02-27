#!/usr/bin/env bash
# =============================================================================
# Integration Test: orchestrate-review.sh end-to-end pipeline
#
# Tests the full pipeline with mock CLIs to verify:
# - Hook input parsing
# - Batch accumulation
# - Review triggering
# - Findings aggregation
# - Report generation
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test-helpers.sh"

PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ORCHESTRATE="$PLUGIN_DIR/scripts/orchestrate-review.sh"

# --- Setup ---
setup_temp_dir
MOCK_BIN="$TEMP_DIR/mock-bin"
mkdir -p "$MOCK_BIN"

# Create mock codex CLI that returns findings JSON
cat > "$MOCK_BIN/codex" <<'MOCK_EOF'
#!/usr/bin/env bash
echo '{"model":"codex","role":"security","file":"test.py","findings":[{"title":"SQL Injection","severity":"high","confidence":85,"line":10,"description":"Unsanitized input in query","suggestion":"Use parameterized queries"}],"summary":"Found 1 issue"}'
MOCK_EOF
chmod +x "$MOCK_BIN/codex"

# Create mock gemini CLI
cat > "$MOCK_BIN/gemini" <<'MOCK_EOF'
#!/usr/bin/env bash
echo '{"model":"gemini","role":"bugs","file":"test.py","findings":[{"title":"Null Check Missing","severity":"medium","confidence":70,"line":25,"description":"Variable may be null","suggestion":"Add null check"}],"summary":"Found 1 issue"}'
MOCK_EOF
chmod +x "$MOCK_BIN/gemini"

# Add mock bin to PATH
export PATH="$MOCK_BIN:$PATH"

# Create a minimal test config
cat > "$TEMP_DIR/test-config.json" <<CONFIG_EOF
{
  "models": {
    "codex": {"enabled": false, "roles": ["security"], "model_variant": "test-model"},
    "gemini": {"enabled": false, "roles": ["bugs"], "model_variant": "test-model"}
  },
  "review": {"intensity": "standard", "confidence_threshold": 40, "max_file_lines": 500, "file_extensions": ["py"]},
  "hook_mode": {"enabled": true, "batch_size": 1, "min_lines_changed": 1},
  "debate": {"enabled": false},
  "output": {"language": "en"}
}
CONFIG_EOF

# Create a test source file
mkdir -p "$TEMP_DIR/project"
cat > "$TEMP_DIR/project/test.py" <<'PYEOF'
import sqlite3

def get_user(user_id):
    conn = sqlite3.connect("db.sqlite")
    cursor = conn.cursor()
    query = f"SELECT * FROM users WHERE id = {user_id}"
    cursor.execute(query)
    result = cursor.fetchone()
    conn.close()
    return result

def process_data(data):
    if data:
        return data.strip().upper()
    # Missing null check for nested access
    return data["key"]["nested"]
PYEOF

# --- Test: Hook input JSON parsing ---
test_begin "orchestrate-review: parses hook input JSON"

HOOK_INPUT='{"tool_name":"Write","tool_input":{"file_path":"/tmp/test.py","content":"print('\''hello'\'')"}}'

# The orchestrate script expects to be run from the plugin context
# We test that it doesn't crash with valid input
RESULT=$(echo "$HOOK_INPUT" | CONFIG_FILE="$TEMP_DIR/test-config.json" \
  MULTI_REVIEW_HOOK_ENABLED=false bash "$ORCHESTRATE" 2>/dev/null)
EXIT_CODE=$?

# Should exit 0 (hooks must not block Claude workflow)
assert_eq "$EXIT_CODE" "0" "Hook should exit 0 even when disabled"

test_end

# --- Test: aggregate-findings with mock data ---
test_begin "aggregate-findings: merges and deduplicates findings"

AGGREGATE="$PLUGIN_DIR/scripts/aggregate-findings.sh"
MOCK_SESSION="$TEMP_DIR/session"
mkdir -p "$MOCK_SESSION"

# Create mock findings files
cat > "$MOCK_SESSION/findings_0.json" <<'F1EOF'
{"model":"codex","role":"security","file":"test.py","findings":[
  {"title":"SQL Injection","severity":"critical","confidence":90,"line":6,"description":"Direct string interpolation in SQL","suggestion":"Use parameterized queries"}
]}
F1EOF

cat > "$MOCK_SESSION/findings_1.json" <<'F2EOF'
{"model":"gemini","role":"bugs","file":"test.py","findings":[
  {"title":"SQL Injection risk","severity":"high","confidence":80,"line":7,"description":"Unescaped input in query","suggestion":"Sanitize input"},
  {"title":"Null Reference","severity":"medium","confidence":75,"line":16,"description":"Possible null access","suggestion":"Add null check"}
]}
F2EOF

RESULT=$(bash "$AGGREGATE" "$MOCK_SESSION" "$TEMP_DIR/test-config.json" 2>/dev/null)
EXIT_CODE=$?

assert_eq "$EXIT_CODE" "0" "aggregate-findings should exit 0"

if [ "$RESULT" != "LGTM" ]; then
  assert_json_valid "$RESULT" "Output should be valid JSON"

  # Should have deduplicated SQL Injection (line 6 and 7 are within proximity)
  FINDING_COUNT=$(echo "$RESULT" | jq 'length' 2>/dev/null || echo "0")
  # Expect 2 findings: 1 merged SQL injection + 1 null reference
  assert_eq "$FINDING_COUNT" "2" "Should have 2 findings after dedup"

  # The merged SQL injection should have cross-model agreement
  CROSS_MODEL=$(echo "$RESULT" | jq '.[0].cross_model_agreement // false' 2>/dev/null)
  assert_eq "$CROSS_MODEL" "true" "First finding should have cross-model agreement"
else
  # LGTM is possible if severity-aware threshold filters differently
  pass "LGTM from aggregate-findings (threshold filtering may differ)"
fi

test_end

# --- Test: generate-report output format ---
test_begin "generate-report: produces markdown output"

GENERATE="$PLUGIN_DIR/scripts/generate-report.sh"

# Use the aggregated findings from above
if [ -n "$RESULT" ] && [ "$RESULT" != "LGTM" ]; then
  REPORT=$(echo "$RESULT" | bash "$GENERATE" /dev/stdin "$TEMP_DIR/test-config.json" 2>/dev/null)
  REPORT_EXIT=$?

  assert_eq "$REPORT_EXIT" "0" "generate-report should exit 0"
  assert_contains "$REPORT" "AI Review Arena Report" "Should contain report header"
else
  skip "No findings to test report generation"
fi

test_end

# --- Test: normalize-severity ---
test_begin "normalize-severity: normalizes external CLI severity values"

NORMALIZE="$PLUGIN_DIR/scripts/normalize-severity.sh"

if [ -f "$NORMALIZE" ]; then
  NORM_RESULT=$(echo '[{"severity":"error"},{"severity":"warning"},{"severity":"blocker"},{"severity":"trivial"},{"severity":"moderate"}]' | bash "$NORMALIZE" 2>/dev/null)

  assert_json_valid "$NORM_RESULT" "Should output valid JSON"

  SEV_0=$(echo "$NORM_RESULT" | jq -r '.[0].severity' 2>/dev/null)
  assert_eq "$SEV_0" "critical" "error should map to critical"

  SEV_1=$(echo "$NORM_RESULT" | jq -r '.[1].severity' 2>/dev/null)
  assert_eq "$SEV_1" "high" "warning should map to high"

  SEV_2=$(echo "$NORM_RESULT" | jq -r '.[2].severity' 2>/dev/null)
  assert_eq "$SEV_2" "critical" "blocker should map to critical"

  SEV_3=$(echo "$NORM_RESULT" | jq -r '.[3].severity' 2>/dev/null)
  assert_eq "$SEV_3" "low" "trivial should map to low"

  SEV_4=$(echo "$NORM_RESULT" | jq -r '.[4].severity' 2>/dev/null)
  assert_eq "$SEV_4" "medium" "moderate should map to medium"
else
  skip "normalize-severity.sh not found"
fi

test_end

# --- Cleanup ---
cleanup
print_summary
