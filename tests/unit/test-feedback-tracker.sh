#!/usr/bin/env bash
# =============================================================================
# Tests for scripts/feedback-tracker.sh
# =============================================================================

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$TESTS_DIR/test-helpers.sh"

echo "=== test-feedback-tracker.sh ==="

setup_temp_dir

# Create a fake plugin dir so feedback goes into temp dir
FAKE_PLUGIN="$TEMP_DIR/plugin"
mkdir -p "$FAKE_PLUGIN/scripts" "$FAKE_PLUGIN/cache/feedback" "$FAKE_PLUGIN/config"

# Copy scripts we need
cp "$REPO_DIR/scripts/utils.sh" "$FAKE_PLUGIN/scripts/"
cp "$REPO_DIR/scripts/feedback-tracker.sh" "$FAKE_PLUGIN/scripts/"

# Create minimal default config
cat > "$FAKE_PLUGIN/config/default-config.json" <<'EOF'
{}
EOF

FT="$FAKE_PLUGIN/scripts/feedback-tracker.sh"

# =========================================================================
# Test: record command creates JSONL entry
# =========================================================================

result=$(bash "$FT" record "session-1" "finding-1" "useful" --model "claude" --category "security" --severity "high" 2>/dev/null)
assert_json_valid "$result" "record: output is valid JSON"
assert_contains "$result" "recorded" "record: status is recorded"

# Verify the JSONL file was created and has content
FEEDBACK_LOG="$FAKE_PLUGIN/cache/feedback/feedback-log.jsonl"
assert_file_exists "$FEEDBACK_LOG" "record: feedback log file created"

line_count=$(wc -l < "$FEEDBACK_LOG" | tr -d ' ')
assert_eq "$line_count" "1" "record: one line in JSONL"

entry=$(cat "$FEEDBACK_LOG")
assert_json_valid "$entry" "record: JSONL entry is valid JSON"

verdict=$(echo "$entry" | jq -r '.verdict')
assert_eq "$verdict" "useful" "record: verdict is useful"

model=$(echo "$entry" | jq -r '.model')
assert_eq "$model" "claude" "record: model is claude"

category=$(echo "$entry" | jq -r '.category')
assert_eq "$category" "security" "record: category is security"

# =========================================================================
# Test: record multiple entries
# =========================================================================

bash "$FT" record "session-1" "finding-2" "not_useful" --model "codex" --category "bugs" --severity "medium" 2>/dev/null
bash "$FT" record "session-2" "finding-1" "false_positive" --model "claude" --category "security" --severity "low" 2>/dev/null
bash "$FT" record "session-2" "finding-2" "useful" --model "gemini" --category "architecture" --severity "high" 2>/dev/null

line_count=$(wc -l < "$FEEDBACK_LOG" | tr -d ' ')
assert_eq "$line_count" "4" "record multiple: 4 entries in JSONL"

# =========================================================================
# Test: record invalid verdict
# =========================================================================

result=$(bash "$FT" record "session-x" "finding-x" "invalid_verdict" 2>/dev/null)
assert_contains "$result" "error" "record invalid: returns error"

# =========================================================================
# Test: report command aggregates feedback
# =========================================================================

result=$(bash "$FT" report --days 365 2>/dev/null)
assert_json_valid "$result" "report: output is valid JSON"

# Check models section exists
has_models=$(echo "$result" | jq 'has("models")')
assert_eq "$has_models" "true" "report: has models section"

# Claude accuracy: 1 useful out of 2 records = 50%
claude_total=$(echo "$result" | jq '.models.claude.total // 0')
assert_eq "$claude_total" "2" "report: claude has 2 records"

claude_useful=$(echo "$result" | jq '.models.claude.useful // 0')
assert_eq "$claude_useful" "1" "report: claude has 1 useful"

claude_fp=$(echo "$result" | jq '.models.claude.false_positive // 0')
assert_eq "$claude_fp" "1" "report: claude has 1 false_positive"

# Check categories section
has_categories=$(echo "$result" | jq 'has("categories")')
assert_eq "$has_categories" "true" "report: has categories section"

security_total=$(echo "$result" | jq '.categories.security.total // 0')
assert_eq "$security_total" "2" "report: security category has 2 records"

# =========================================================================
# Test: report with model filter
# =========================================================================

result=$(bash "$FT" report --model codex --days 365 2>/dev/null)
assert_json_valid "$result" "report model filter: output is valid JSON"

# Only codex records
codex_total=$(echo "$result" | jq '.models.codex.total // 0')
assert_eq "$codex_total" "1" "report model filter: codex has 1 record"

# =========================================================================
# Test: report with category filter
# =========================================================================

result=$(bash "$FT" report --category security --days 365 2>/dev/null)
assert_json_valid "$result" "report category filter: output is valid JSON"

security_total=$(echo "$result" | jq '.categories.security.total // 0')
assert_eq "$security_total" "2" "report category filter: security has 2 records"

# =========================================================================
# Test: stats command
# =========================================================================

result=$(bash "$FT" stats 2>/dev/null)
assert_json_valid "$result" "stats: output is valid JSON"

total=$(echo "$result" | jq '.total_records')
assert_eq "$total" "4" "stats: total_records is 4"

models_count=$(echo "$result" | jq '.models | length')
assert_eq "$models_count" "3" "stats: 3 unique models (claude, codex, gemini)"

useful_count=$(echo "$result" | jq '.verdicts.useful')
assert_eq "$useful_count" "2" "stats: 2 useful verdicts"

not_useful_count=$(echo "$result" | jq '.verdicts.not_useful')
assert_eq "$not_useful_count" "1" "stats: 1 not_useful verdict"

fp_count=$(echo "$result" | jq '.verdicts.false_positive')
assert_eq "$fp_count" "1" "stats: 1 false_positive verdict"

has_oldest=$(echo "$result" | jq '.oldest != null')
assert_eq "$has_oldest" "true" "stats: has oldest timestamp"

has_newest=$(echo "$result" | jq '.newest != null')
assert_eq "$has_newest" "true" "stats: has newest timestamp"

# =========================================================================
# Test: stats on empty log
# =========================================================================

# Create a new empty feedback tracker
EMPTY_PLUGIN="$TEMP_DIR/empty-plugin"
mkdir -p "$EMPTY_PLUGIN/scripts" "$EMPTY_PLUGIN/cache/feedback" "$EMPTY_PLUGIN/config"
cp "$REPO_DIR/scripts/utils.sh" "$EMPTY_PLUGIN/scripts/"
cp "$REPO_DIR/scripts/feedback-tracker.sh" "$EMPTY_PLUGIN/scripts/"
cat > "$EMPTY_PLUGIN/config/default-config.json" <<'EOF'
{}
EOF

result=$(bash "$EMPTY_PLUGIN/scripts/feedback-tracker.sh" stats 2>/dev/null)
assert_json_valid "$result" "stats empty: output is valid JSON"

total=$(echo "$result" | jq '.total_records')
assert_eq "$total" "0" "stats empty: total_records is 0"

print_summary
