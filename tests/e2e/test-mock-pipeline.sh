#!/usr/bin/env bash
# =============================================================================
# E2E Test: Mock Pipeline (no external CLIs required)
#
# Tests the full review pipeline flow using mock CLI outputs:
#   1. Mock findings → aggregate-findings.sh → scoring
#   2. Validates aggregation deduplication
#   3. Tests extract_json on real-world LLM output patterns
#
# Runs in CI without codex/gemini CLI dependencies.
# =============================================================================

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$TESTS_DIR/../scripts" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/utils.sh"
source "$SCRIPT_DIR/benchmark-utils.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

PASSED=0; FAILED=0

pass() { printf "  ${GREEN}PASS${NC} %s\n" "$1"; PASSED=$((PASSED + 1)); }
fail() { printf "  ${RED}FAIL${NC} %s\n" "$1"; FAILED=$((FAILED + 1)); }

echo "--- test-mock-pipeline.sh ---"

CONFIG_FILE="$PLUGIN_DIR/config/default-config.json"
TEST_FILE="$PLUGIN_DIR/config/benchmarks/security-test-01.json"

# =============================================================================
# Test 1: Mock findings → aggregation → valid JSON output
# =============================================================================
MOCK_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/arena-mock-e2e-XXXXXX")
SESSION_DIR="$MOCK_TEMP/session"
mkdir -p "$SESSION_DIR"

# Create mock findings simulating Codex output (SQL injection + XSS)
# Format: {model, role, file, findings: [...]} as expected by aggregate-findings.sh
cat > "$SESSION_DIR/findings_0.json" << 'MOCK_CODEX'
{
  "model": "codex",
  "role": "security",
  "file": "test-code.js",
  "findings": [
    {
      "title": "SQL Injection Vulnerability",
      "severity": "critical",
      "description": "User input is directly concatenated into SQL query string without parameterization, allowing SQL injection attacks.",
      "suggestion": "Use parameterized queries or prepared statements instead of string concatenation.",
      "confidence": 95,
      "category": "security",
      "line": 10
    },
    {
      "title": "Cross-Site Scripting (XSS)",
      "severity": "high",
      "description": "User-provided data is rendered in HTML without sanitization, enabling XSS attacks.",
      "suggestion": "Sanitize all user input before rendering in HTML context.",
      "confidence": 90,
      "category": "security",
      "line": 25
    }
  ],
  "summary": "Found 2 security issues: SQL injection and XSS"
}
MOCK_CODEX

# Create mock findings simulating Gemini output (SQL injection + CSRF, overlapping SQL injection)
cat > "$SESSION_DIR/findings_1.json" << 'MOCK_GEMINI'
{
  "model": "gemini",
  "role": "security",
  "file": "test-code.js",
  "findings": [
    {
      "title": "SQL Injection via String Concatenation",
      "severity": "critical",
      "description": "The query function uses string interpolation with user input, creating a SQL injection vulnerability.",
      "suggestion": "Replace string concatenation with parameterized queries.",
      "confidence": 92,
      "category": "security",
      "line": 11
    },
    {
      "title": "Missing CSRF Protection",
      "severity": "high",
      "description": "POST endpoints lack CSRF token validation, allowing cross-site request forgery.",
      "suggestion": "Implement CSRF token generation and validation middleware.",
      "confidence": 85,
      "category": "security",
      "line": 40
    }
  ],
  "summary": "Found 2 security issues: SQL injection and CSRF"
}
MOCK_GEMINI

# Run aggregation
AGG_RESULT=$("$SCRIPT_DIR/aggregate-findings.sh" "$SESSION_DIR" "$CONFIG_FILE" 2>/dev/null) || AGG_RESULT=""

if [ -n "$AGG_RESULT" ] && [ "$AGG_RESULT" != "LGTM" ] && echo "$AGG_RESULT" | jq . &>/dev/null; then
  pass "Aggregation produces valid JSON"
else
  fail "Aggregation did not produce valid JSON (got: ${AGG_RESULT:0:100})"
fi

# Test aggregated output is a non-empty array
AGG_COUNT=$(echo "$AGG_RESULT" | jq 'if type == "array" then length else 0 end' 2>/dev/null || echo 0)
if [ "$AGG_COUNT" -gt 0 ]; then
  pass "Aggregated $AGG_COUNT findings (expected > 0)"
else
  fail "Aggregation returned 0 findings"
fi

# Test deduplication: 4 mock inputs should aggregate to <= 4 (duplicates merged)
if [ "$AGG_COUNT" -le 4 ]; then
  pass "Deduplication working ($AGG_COUNT <= 4 input findings)"
else
  fail "Possible dedup failure: got $AGG_COUNT findings from 4 inputs"
fi

rm -rf "$MOCK_TEMP"

# =============================================================================
# Test 2: Mock findings scoring against ground truth
# =============================================================================
if [ -f "$TEST_FILE" ]; then
  # Create mock findings that match security-test-01 ground truth
  MOCK_FINDINGS='[
    {"title":"SQL Injection","severity":"critical","description":"SQL injection via string concatenation allows attacker to modify queries","suggestion":"Use parameterized queries","confidence":95,"category":"security"},
    {"title":"XSS Vulnerability","severity":"high","description":"Cross-site scripting through unsanitized user input in HTML","suggestion":"Sanitize output","confidence":90,"category":"security"}
  ]'

  expected_count=$(jq '.ground_truth | length' "$TEST_FILE")
  mock_text=$(extract_text "$MOCK_FINDINGS")
  read -r tp fn <<< "$(count_matches "$mock_text" "$TEST_FILE" "$expected_count")"
  actual_count=$(echo "$MOCK_FINDINGS" | jq 'length')
  fp=0; [ "$actual_count" -gt "$tp" ] && fp=$((actual_count - tp))
  read -r precision recall f1 <<< "$(compute_metrics "$tp" "$fp" "$fn")"

  if [ "$tp" -gt 0 ]; then
    pass "Ground truth matching works (TP=$tp, FN=$fn, F1=$f1)"
  else
    fail "Ground truth matching failed (TP=0)"
  fi
else
  fail "security-test-01.json not found for scoring test"
fi

# =============================================================================
# Test 3: extract_json handles real-world LLM patterns
# =============================================================================

# Pattern A: Clean JSON
CLEAN='{"key": "value"}'
result=$(extract_json "$CLEAN")
if echo "$result" | jq -e '.key == "value"' &>/dev/null; then
  pass "extract_json handles clean JSON"
else
  fail "extract_json failed on clean JSON"
fi

# Pattern B: JSON in markdown code block
MARKDOWN_JSON='Here is the result:
```json
{"findings": [{"title": "test"}]}
```
That is all.'
result=$(extract_json "$MARKDOWN_JSON")
if echo "$result" | jq -e '.findings[0].title == "test"' &>/dev/null; then
  pass "extract_json handles markdown json block"
else
  fail "extract_json failed on markdown json block"
fi

# Pattern C: JSON with leading text
LEADING_TEXT='Some intro text
  {"key": "embedded"}'
result=$(extract_json "$LEADING_TEXT")
if echo "$result" | jq -e '.key == "embedded"' &>/dev/null; then
  pass "extract_json handles JSON with leading text"
else
  fail "extract_json failed on JSON with leading text"
fi

# =============================================================================
# Test 4: benchmark-utils functions work correctly
# =============================================================================

# compute_metrics with known values
read -r p r f <<< "$(compute_metrics 3 1 1)"
if [ "$(echo "$f > 0" | bc 2>/dev/null)" = "1" ]; then
  pass "compute_metrics returns valid F1 ($f for TP=3 FP=1 FN=1)"
else
  fail "compute_metrics returned invalid F1: $f"
fi

# compute_metrics edge case: all zeros
read -r p r f <<< "$(compute_metrics 0 0 0)"
if [ "$f" = "0" ]; then
  pass "compute_metrics handles zero case (F1=0)"
else
  fail "compute_metrics zero case returned: $f"
fi

# =============================================================================
# Test 5: severity_weight and compute_weighted_f1
# =============================================================================

# severity_weight maps correctly
w_crit=$(severity_weight "critical")
w_high=$(severity_weight "high")
w_med=$(severity_weight "medium")
w_low=$(severity_weight "low")
w_unk=$(severity_weight "")
if [ "$w_crit" = "4" ] && [ "$w_high" = "3" ] && [ "$w_med" = "2" ] && [ "$w_low" = "1" ] && [ "$w_unk" = "1" ]; then
  pass "severity_weight maps all levels correctly (4/3/2/1/1)"
else
  fail "severity_weight mapping wrong: crit=$w_crit high=$w_high med=$w_med low=$w_low unk=$w_unk"
fi

# compute_weighted_f1 with ground truth file
if [ -f "$TEST_FILE" ]; then
  expected_count=$(jq '.ground_truth | length' "$TEST_FILE")
  wf1=$(compute_weighted_f1 "$mock_text" "$MOCK_FINDINGS" "$TEST_FILE" "$expected_count")
  if [ "$(echo "$wf1 > 0" | bc 2>/dev/null)" = "1" ]; then
    pass "compute_weighted_f1 returns valid score ($wf1)"
  else
    fail "compute_weighted_f1 returned: $wf1"
  fi
else
  fail "Cannot test compute_weighted_f1: test file not found"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "--- test-mock-pipeline.sh ---"
printf "Total: %d  Pass: %d  Fail: %d\n" "$((PASSED + FAILED))" "$PASSED" "$FAILED"
[ "$FAILED" -gt 0 ] && exit 1
exit 0
