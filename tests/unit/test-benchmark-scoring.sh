#!/usr/bin/env bash
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/test-helpers.sh"

echo "=== test-benchmark-scoring.sh ==="
setup_temp_dir

cat > "$TEMP_DIR/test-case.json" <<'JSON'
{
  "id": "scoring-01",
  "category": "security",
  "ground_truth": [
    {
      "type": "sql_injection",
      "severity": "critical",
      "file": "app.js",
      "line_range": [10, 12],
      "line_tolerance": 1,
      "description_contains": ["SQL injection", "parameterized"],
      "expected_suggestion_terms": ["parameterized"]
    },
    {
      "type": "xss",
      "severity": "high",
      "file": "app.js",
      "line": 20,
      "line_tolerance": 0,
      "description_contains": ["cross-site scripting", "sanitization"],
      "expected_suggestion_terms": ["sanitize", "escape"]
    }
  ]
}
JSON

cat > "$TEMP_DIR/findings.json" <<'JSON'
[
  {"title": "SQL Injection", "severity": "critical", "file": "app.js", "line": 11, "confidence": 90, "description": "SQL injection through string concatenation", "suggestion": "Use parameterized queries"},
  {"title": "SQL Injection Duplicate", "severity": "high", "file": "app.js", "line": 12, "confidence": 80, "description": "SQL injection through string concatenation", "suggestion": "Use prepared statements"},
  {"title": "Cross-site scripting", "severity": "medium", "file": "app.js", "line": 20, "confidence": 40, "description": "cross-site scripting via unsanitized HTML", "suggestion": "Sanitize output and escape HTML"},
  {"title": "Not XSS", "severity": "low", "file": "app.js", "line": 50, "confidence": 95, "description": "No cross-site scripting issue is present here", "suggestion": "No change"}
]
JSON

result=$(python3 "$REPO_DIR/scripts/arena-runtime.py" benchmark-score --findings "$TEMP_DIR/findings.json" --test-case "$TEMP_DIR/test-case.json" 2>/dev/null)
assert_json_valid "$result" "benchmark-score: output is valid JSON"

tp=$(echo "$result" | jq '.true_positives')
fp=$(echo "$result" | jq '.false_positives')
fn=$(echo "$result" | jq '.false_negatives')
line_rate=$(echo "$result" | jq '.line_level.match_rate')
duplicates=$(echo "$result" | jq '.duplicate_count')
sev_crit=$(echo "$result" | jq '.severity_confusion_matrix.critical.critical')
sev_high_medium=$(echo "$result" | jq '.severity_confusion_matrix.high.medium')
category=$(echo "$result" | jq -r '.category_policy.category')
brier=$(echo "$result" | jq '.confidence_calibration.brier_score')
partial=$(echo "$result" | jq '.partial_credit_score')
suggestion=$(echo "$result" | jq '.suggestion_quality_score')

assert_eq "$tp" "2" "benchmark-score: line-aware true positives counted"
assert_eq "$fn" "0" "benchmark-score: no missed truths"
assert_eq "$fp" "2" "benchmark-score: duplicate and negated extra are false positives"
assert_eq "$line_rate" "1.0" "benchmark-score: line-level match rate is exact"
assert_eq "$duplicates" "1" "benchmark-score: duplicate finding is counted"
assert_eq "$sev_crit" "1" "benchmark-score: severity matrix tracks critical to critical"
assert_eq "$sev_high_medium" "1" "benchmark-score: severity matrix tracks high to medium"
assert_eq "$category" "security" "benchmark-score: category policy selected"
assert_contains "$result" "category_weighted_score" "benchmark-score: category-specific weighted score reported"
assert_contains "$result" "confidence_calibration" "benchmark-score: confidence calibration reported"
assert_contains "$result" "passes_category_threshold" "benchmark-score: category threshold decision reported"

if awk "BEGIN { exit !($brier > 0) }"; then
  pass "benchmark-score: Brier score is non-zero"
else
  fail "benchmark-score: expected non-zero Brier score, got $brier"
fi

if awk "BEGIN { exit !($partial > 0.6 && $partial <= 1) }"; then
  pass "benchmark-score: partial credit is bounded and useful"
else
  fail "benchmark-score: partial credit out of expected range, got $partial"
fi

if awk "BEGIN { exit !($suggestion > 0.5) }"; then
  pass "benchmark-score: suggestion quality is scored"
else
  fail "benchmark-score: suggestion quality too low, got $suggestion"
fi

print_summary
