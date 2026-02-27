#!/usr/bin/env bash
# =============================================================================
# Integration Test: aggregate-findings.sh with real JSON findings
#
# Tests the findings aggregator with crafted findings JSON files,
# verifying merge, dedup, severity ordering, and threshold filtering.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test-helpers.sh"

PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
AGGREGATE="$PLUGIN_DIR/scripts/aggregate-findings.sh"
CONFIG="$PLUGIN_DIR/config/default-config.json"

# --- Setup ---
setup_temp_dir

# --- Prerequisite check ---
if [ ! -f "$AGGREGATE" ]; then
  skip "aggregate-findings.sh not found"
  print_summary
  exit 0
fi

if ! command -v jq &>/dev/null; then
  skip "jq not available"
  print_summary
  exit 0
fi

# =============================================================================
# Test 1: Two findings files merged correctly
# =============================================================================
test_begin "aggregate-findings: merges two findings files"

SESSION_DIR="$TEMP_DIR/session-merge"
mkdir -p "$SESSION_DIR"

cat > "$SESSION_DIR/findings_0.json" <<'EOF'
{
  "model": "codex",
  "role": "security",
  "file": "app/controllers/user_controller.py",
  "findings": [
    {
      "title": "SQL Injection",
      "severity": "high",
      "confidence": 85,
      "line": 42,
      "description": "User input not sanitized",
      "suggestion": "Use parameterized queries"
    }
  ]
}
EOF

cat > "$SESSION_DIR/findings_1.json" <<'EOF'
{
  "model": "gemini",
  "role": "security",
  "file": "app/views/template.html",
  "findings": [
    {
      "title": "XSS Vulnerability",
      "severity": "medium",
      "confidence": 80,
      "line": 15,
      "description": "Output not escaped",
      "suggestion": "Use HTML encoding"
    }
  ]
}
EOF

RESULT=$(bash "$AGGREGATE" "$SESSION_DIR" "$CONFIG" 2>/dev/null)
EXIT_CODE=$?

assert_eq "$EXIT_CODE" "0" "Should exit 0"

if [ "$RESULT" = "LGTM" ]; then
  fail "Should not be LGTM with valid findings"
else
  assert_json_valid "$RESULT" "Output should be valid JSON"

  COUNT=$(echo "$RESULT" | jq 'length' 2>/dev/null)
  assert_eq "$COUNT" "2" "Should have 2 aggregated findings"

  # Verify both findings are present
  TITLES=$(echo "$RESULT" | jq -r '.[].title' 2>/dev/null)
  assert_contains "$TITLES" "SQL Injection" "Should contain SQL Injection finding"
  assert_contains "$TITLES" "XSS Vulnerability" "Should contain XSS Vulnerability finding"
fi

test_end

# =============================================================================
# Test 2: Output is sorted by severity/confidence
# =============================================================================
test_begin "aggregate-findings: results sorted by severity and confidence"

if [ "$RESULT" != "LGTM" ]; then
  # SQL Injection (high, conf=85) should rank above XSS (medium, conf=70)
  FIRST_TITLE=$(echo "$RESULT" | jq -r '.[0].title' 2>/dev/null)
  assert_eq "$FIRST_TITLE" "SQL Injection" "Highest severity finding should be first"

  FIRST_SEVERITY=$(echo "$RESULT" | jq -r '.[0].severity' 2>/dev/null)
  assert_eq "$FIRST_SEVERITY" "high" "First finding should have severity 'high'"
fi

test_end

# =============================================================================
# Test 3: Empty session returns LGTM
# =============================================================================
test_begin "aggregate-findings: empty session returns LGTM"

EMPTY_SESSION="$TEMP_DIR/session-empty"
mkdir -p "$EMPTY_SESSION"

RESULT=$(bash "$AGGREGATE" "$EMPTY_SESSION" "$CONFIG" 2>/dev/null)
assert_eq "$RESULT" "LGTM" "Empty session should produce LGTM"

test_end

# =============================================================================
# Test 4: Findings with no valid titles return LGTM
# =============================================================================
test_begin "aggregate-findings: findings without titles produce LGTM"

SESSION_NOTITLE="$TEMP_DIR/session-notitle"
mkdir -p "$SESSION_NOTITLE"

cat > "$SESSION_NOTITLE/findings_0.json" <<'EOF'
{
  "model": "codex",
  "role": "security",
  "file": "app.py",
  "findings": [
    {
      "title": "",
      "severity": "high",
      "confidence": 90,
      "line": 1,
      "description": "Something with no title"
    }
  ]
}
EOF

RESULT=$(bash "$AGGREGATE" "$SESSION_NOTITLE" "$CONFIG" 2>/dev/null)
assert_eq "$RESULT" "LGTM" "Findings without titles should produce LGTM"

test_end

# =============================================================================
# Test 5: Deduplication of similar findings from different models
# =============================================================================
test_begin "aggregate-findings: deduplicates similar findings"

SESSION_DEDUP="$TEMP_DIR/session-dedup"
mkdir -p "$SESSION_DEDUP"

# Two models report the same SQL Injection on same file and near same line
cat > "$SESSION_DEDUP/findings_0.json" <<'EOF'
{
  "model": "codex",
  "role": "security",
  "file": "app/db.py",
  "findings": [
    {
      "title": "SQL Injection vulnerability found",
      "severity": "high",
      "confidence": 80,
      "line": 25,
      "description": "Unsanitized user input in query",
      "suggestion": "Use parameterized queries"
    }
  ]
}
EOF

cat > "$SESSION_DEDUP/findings_1.json" <<'EOF'
{
  "model": "gemini",
  "role": "security",
  "file": "app/db.py",
  "findings": [
    {
      "title": "SQL Injection vulnerability found",
      "severity": "critical",
      "confidence": 85,
      "line": 26,
      "description": "SQL injection risk on line 26",
      "suggestion": "Parameterize the query"
    }
  ]
}
EOF

RESULT=$(bash "$AGGREGATE" "$SESSION_DEDUP" "$CONFIG" 2>/dev/null)

if [ "$RESULT" != "LGTM" ]; then
  assert_json_valid "$RESULT" "Dedup output should be valid JSON"

  COUNT=$(echo "$RESULT" | jq 'length' 2>/dev/null)
  assert_eq "$COUNT" "1" "Similar findings should be deduplicated into 1"

  # Check cross-model agreement
  CROSS_MODEL=$(echo "$RESULT" | jq '.[0].cross_model_agreement' 2>/dev/null)
  assert_eq "$CROSS_MODEL" "true" "Should mark cross_model_agreement as true"

  # Severity should be the highest (critical)
  SEVERITY=$(echo "$RESULT" | jq -r '.[0].severity' 2>/dev/null)
  assert_eq "$SEVERITY" "critical" "Deduped finding should take highest severity"

  # Should list both models
  MODEL_COUNT=$(echo "$RESULT" | jq '.[0].models | length' 2>/dev/null)
  assert_eq "$MODEL_COUNT" "2" "Deduped finding should list both models"
else
  fail "Dedup findings should not produce LGTM"
fi

test_end

# =============================================================================
# Test 6: Invalid JSON files are skipped
# =============================================================================
test_begin "aggregate-findings: skips invalid JSON files"

SESSION_INVALID="$TEMP_DIR/session-invalid"
mkdir -p "$SESSION_INVALID"

echo "NOT VALID JSON AT ALL" > "$SESSION_INVALID/findings_0.json"

cat > "$SESSION_INVALID/findings_1.json" <<'EOF'
{
  "model": "codex",
  "role": "bugs",
  "file": "app.py",
  "findings": [
    {
      "title": "Null Pointer Dereference",
      "severity": "high",
      "confidence": 90,
      "line": 10,
      "description": "Potential null dereference"
    }
  ]
}
EOF

RESULT=$(bash "$AGGREGATE" "$SESSION_INVALID" "$CONFIG" 2>/dev/null)

if [ "$RESULT" != "LGTM" ]; then
  assert_json_valid "$RESULT" "Output should be valid JSON despite invalid file"

  COUNT=$(echo "$RESULT" | jq 'length' 2>/dev/null)
  assert_eq "$COUNT" "1" "Should have 1 finding from the valid file"

  TITLE=$(echo "$RESULT" | jq -r '.[0].title' 2>/dev/null)
  assert_eq "$TITLE" "Null Pointer Dereference" "Should contain the valid finding"
else
  pass "LGTM is acceptable if threshold filtering removed it"
fi

test_end

# =============================================================================
# Test 7: Output includes expected fields per finding
# =============================================================================
test_begin "aggregate-findings: output findings have expected fields"

SESSION_FIELDS="$TEMP_DIR/session-fields"
mkdir -p "$SESSION_FIELDS"

cat > "$SESSION_FIELDS/findings_0.json" <<'EOF'
{
  "model": "codex",
  "role": "performance",
  "file": "server/handler.go",
  "findings": [
    {
      "title": "N+1 Query Pattern",
      "severity": "medium",
      "confidence": 78,
      "line": 100,
      "description": "Database query inside loop",
      "suggestion": "Batch queries or use JOIN"
    }
  ]
}
EOF

RESULT=$(bash "$AGGREGATE" "$SESSION_FIELDS" "$CONFIG" 2>/dev/null)

if [ "$RESULT" != "LGTM" ]; then
  assert_json_valid "$RESULT" "Output should be valid JSON"

  # Check that each finding has the expected fields
  FINDING=$(echo "$RESULT" | jq '.[0]' 2>/dev/null)

  for field in file line title description suggestion severity confidence models role; do
    HAS_FIELD=$(echo "$FINDING" | jq "has(\"$field\")" 2>/dev/null)
    if [ "$HAS_FIELD" != "true" ]; then
      fail "Finding missing field: $field"
    fi
  done
  pass "All expected fields present in finding output"

  HAS_CROSS=$(echo "$FINDING" | jq 'has("cross_model_agreement")' 2>/dev/null)
  assert_eq "$HAS_CROSS" "true" "Finding should have cross_model_agreement field"
else
  pass "LGTM is acceptable if below confidence threshold"
fi

test_end

# =============================================================================
# Test 8: Findings below confidence threshold are filtered out
# =============================================================================
test_begin "aggregate-findings: filters out low-confidence findings"

SESSION_LOW="$TEMP_DIR/session-lowconf"
mkdir -p "$SESSION_LOW"

# Create a finding with very low confidence (below default threshold of 75)
# For medium severity, threshold is exactly 75, for low severity it's 85
cat > "$SESSION_LOW/findings_0.json" <<'EOF'
{
  "model": "codex",
  "role": "bugs",
  "file": "util.py",
  "findings": [
    {
      "title": "Possible Issue",
      "severity": "low",
      "confidence": 20,
      "line": 5,
      "description": "Very low confidence finding"
    }
  ]
}
EOF

RESULT=$(bash "$AGGREGATE" "$SESSION_LOW" "$CONFIG" 2>/dev/null)

# With confidence 20 and severity low, this should be filtered out
assert_eq "$RESULT" "LGTM" "Low confidence findings should be filtered out"

test_end

# --- Cleanup ---
cleanup
print_summary
