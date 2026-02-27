#!/usr/bin/env bash
# =============================================================================
# Tests for scripts/generate-report.sh
# =============================================================================

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$TESTS_DIR/test-helpers.sh"

SCRIPT="$REPO_DIR/scripts/generate-report.sh"

echo "=== test-generate-report.sh ==="

setup_temp_dir

# =========================================================================
# Test: Korean language output
# =========================================================================

cat > "$TEMP_DIR/config-ko.json" <<'EOF'
{
  "output": {
    "language": "ko",
    "show_cost_estimate": false,
    "show_model_attribution": true,
    "show_confidence_scores": true
  },
  "review": {
    "intensity": "standard",
    "focus_areas": ["security", "bugs"]
  }
}
EOF

cat > "$TEMP_DIR/findings-ko.json" <<'EOF'
[
  {
    "file": "src/auth.ts",
    "line": 42,
    "title": "SQL Injection",
    "description": "Unsanitized input",
    "suggestion": "Use parameterized queries",
    "severity": "critical",
    "confidence": 95,
    "models": ["claude", "codex"],
    "role": "security-reviewer",
    "cross_model_agreement": true
  }
]
EOF

result=$(bash "$SCRIPT" "$TEMP_DIR/findings-ko.json" "$TEMP_DIR/config-ko.json" 2>/dev/null)
assert_contains "$result" "AI Review Arena Report" "korean: has report title"
assert_contains "$result" "accepted" "korean: has accepted count"
assert_contains "$result" "CRITICAL" "korean: has CRITICAL section"
assert_contains "$result" "SQL Injection" "korean: has finding title"
assert_contains "$result" "교차 모델 합의" "korean: has cross-model agreement in Korean"

# =========================================================================
# Test: English language output
# =========================================================================

cat > "$TEMP_DIR/config-en.json" <<'EOF'
{
  "output": {
    "language": "en",
    "show_cost_estimate": false,
    "show_model_attribution": true,
    "show_confidence_scores": true
  },
  "review": {
    "intensity": "deep",
    "focus_areas": ["security"]
  }
}
EOF

cat > "$TEMP_DIR/findings-en.json" <<'EOF'
[
  {
    "file": "src/api.ts",
    "line": 10,
    "title": "Missing auth check",
    "description": "Endpoint lacks authentication",
    "suggestion": "Add auth middleware",
    "severity": "high",
    "confidence": 85,
    "models": ["claude"],
    "role": "security-reviewer",
    "cross_model_agreement": false
  }
]
EOF

result=$(bash "$SCRIPT" "$TEMP_DIR/findings-en.json" "$TEMP_DIR/config-en.json" 2>/dev/null)
assert_contains "$result" "AI Review Arena Report" "english: has report title"
assert_contains "$result" "Confidence" "english: has Confidence label"
assert_contains "$result" "Suggestion" "english: has Suggestion label"
assert_contains "$result" "HIGH" "english: has HIGH section"
assert_contains "$result" "Missing auth check" "english: has finding title"

# =========================================================================
# Test: Consensus format {accepted, rejected, disputed}
# =========================================================================

cat > "$TEMP_DIR/consensus.json" <<'EOF'
{
  "accepted": [
    {
      "file": "src/db.ts",
      "line": 20,
      "title": "Connection leak",
      "description": "Database connection not closed",
      "severity": "high",
      "confidence": 88,
      "models": ["claude"],
      "role": "bug-detector",
      "cross_model_agreement": false
    }
  ],
  "rejected": [
    {
      "file": "src/utils.ts",
      "line": 5,
      "title": "Unused import",
      "severity": "low",
      "confidence": 40,
      "models": ["codex"],
      "role": "scope-reviewer"
    }
  ],
  "disputed": [
    {
      "file": "src/api.ts",
      "line": 30,
      "title": "Rate limiting needed",
      "description": "No rate limiting on public endpoint",
      "severity": "medium",
      "confidence": 65,
      "models": ["claude", "gemini"],
      "role": "security-reviewer",
      "cross_model_agreement": true
    }
  ]
}
EOF

result=$(bash "$SCRIPT" "$TEMP_DIR/consensus.json" "$TEMP_DIR/config-en.json" 2>/dev/null)
assert_contains "$result" "1 accepted" "consensus: shows accepted count"
assert_contains "$result" "1 rejected" "consensus: shows rejected count"
assert_contains "$result" "1 disputed" "consensus: shows disputed count"
assert_contains "$result" "Connection leak" "consensus: shows accepted finding"
assert_contains "$result" "DISPUTED" "consensus: has disputed section"
assert_contains "$result" "Rate limiting" "consensus: shows disputed finding"
# Rejected findings should NOT appear in the body
assert_not_contains "$result" "Unused import" "consensus: rejected finding not in body"

# =========================================================================
# Test: Plain array format (pre-debate)
# =========================================================================

cat > "$TEMP_DIR/findings-array.json" <<'EOF'
[
  {
    "file": "src/handler.ts",
    "line": 5,
    "title": "Error not caught",
    "severity": "medium",
    "confidence": 70,
    "models": ["claude"],
    "role": "bug-detector",
    "cross_model_agreement": false
  }
]
EOF

result=$(bash "$SCRIPT" "$TEMP_DIR/findings-array.json" "$TEMP_DIR/config-en.json" 2>/dev/null)
assert_contains "$result" "1 accepted" "plain array: treated as accepted"
assert_contains "$result" "0 rejected" "plain array: 0 rejected"
assert_contains "$result" "Error not caught" "plain array: finding rendered"

# =========================================================================
# Test: LGTM for empty findings
# =========================================================================

cat > "$TEMP_DIR/findings-empty.json" <<'EOF'
[]
EOF

result=$(bash "$SCRIPT" "$TEMP_DIR/findings-empty.json" "$TEMP_DIR/config-en.json" 2>/dev/null)
assert_eq "$result" "LGTM" "LGTM: empty array produces LGTM"

# Also test with null
echo "null" > "$TEMP_DIR/findings-null.json"
result=$(bash "$SCRIPT" "$TEMP_DIR/findings-null.json" "$TEMP_DIR/config-en.json" 2>/dev/null)
assert_eq "$result" "LGTM" "LGTM: null produces LGTM"

# Also test with empty consensus
cat > "$TEMP_DIR/findings-empty-consensus.json" <<'EOF'
{"accepted": [], "rejected": [], "disputed": []}
EOF

result=$(bash "$SCRIPT" "$TEMP_DIR/findings-empty-consensus.json" "$TEMP_DIR/config-en.json" 2>/dev/null)
assert_eq "$result" "LGTM" "LGTM: empty consensus produces LGTM"

# =========================================================================
# Test: severity section rendering order
# =========================================================================

cat > "$TEMP_DIR/findings-multi.json" <<'EOF'
[
  {"file": "a.ts", "line": 1, "title": "Low bug", "severity": "low", "confidence": 80, "models": ["claude"], "cross_model_agreement": false},
  {"file": "b.ts", "line": 1, "title": "Critical bug", "severity": "critical", "confidence": 90, "models": ["claude"], "cross_model_agreement": false},
  {"file": "c.ts", "line": 1, "title": "Medium bug", "severity": "medium", "confidence": 85, "models": ["claude"], "cross_model_agreement": false},
  {"file": "d.ts", "line": 1, "title": "High bug", "severity": "high", "confidence": 88, "models": ["claude"], "cross_model_agreement": false}
]
EOF

result=$(bash "$SCRIPT" "$TEMP_DIR/findings-multi.json" "$TEMP_DIR/config-en.json" 2>/dev/null)
assert_contains "$result" "CRITICAL" "severity sections: has CRITICAL"
assert_contains "$result" "HIGH" "severity sections: has HIGH"
assert_contains "$result" "MEDIUM" "severity sections: has MEDIUM"
assert_contains "$result" "LOW" "severity sections: has LOW"

# Check ordering: CRITICAL should appear before LOW
crit_pos=$(echo "$result" | grep -n "CRITICAL" | head -1 | cut -d: -f1)
low_pos=$(echo "$result" | grep -n "LOW" | head -1 | cut -d: -f1)
if [ -n "$crit_pos" ] && [ -n "$low_pos" ]; then
  test_start "severity sections: CRITICAL before LOW"
  if [ "$crit_pos" -lt "$low_pos" ]; then
    pass "severity sections: CRITICAL before LOW"
  else
    fail "severity sections: CRITICAL before LOW" "CRITICAL at line $crit_pos, LOW at line $low_pos"
  fi
else
  test_start "severity sections: positions found"
  fail "severity sections: positions found" "Could not find positions"
fi

print_summary
