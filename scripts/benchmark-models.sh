#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Model Benchmarking
#
# Usage: benchmark-models.sh [--category security|bugs|architecture|performance|all]
#                            [--models claude,codex,gemini]
#                            [--config <config>]
#
# Reads test cases from $PLUGIN_DIR/config/benchmarks/*.json.
# Runs each enabled model against test cases, compares against ground_truth.
# Computes precision, recall, F1 per model per category.
#
# IMPORTANT: Claude cannot be called via CLI from within this script.
#   For Claude benchmarks, outputs a marker for arena.md to handle via Task tool.
#
# Output: JSON with model scores per category. Saved to cache.
#
# Exit codes:
#   0 - Always (informational tool)
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/utils.sh"

ensure_jq

# --- Arguments ---
CATEGORY="all"
MODELS="codex,gemini,claude"
CONFIG_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --category) CATEGORY="${2:-all}"; shift 2 ;;
    --models) MODELS="${2:-codex,gemini,claude}"; shift 2 ;;
    --config) CONFIG_FILE="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

# --- Resolve config ---
if [ -z "$CONFIG_FILE" ]; then
  CONFIG_FILE=$(load_config "$(find_project_root)") || CONFIG_FILE=""
fi

# --- Parse models list ---
IFS=',' read -ra MODEL_LIST <<< "$MODELS"

has_model() {
  local target="$1"
  local m
  for m in "${MODEL_LIST[@]}"; do
    if [ "$m" = "$target" ]; then
      return 0
    fi
  done
  return 1
}

# --- Locate benchmark files ---
BENCHMARKS_DIR="${PLUGIN_DIR}/config/benchmarks"

if [ ! -d "$BENCHMARKS_DIR" ]; then
  log_warn "Benchmarks directory not found: $BENCHMARKS_DIR"
  jq -n '{"error": "No benchmark directory found", "scores": {}}'
  exit 0
fi

# Collect benchmark files
BENCHMARK_FILES=()
if [ "$CATEGORY" = "all" ]; then
  for f in "$BENCHMARKS_DIR"/*.json; do
    [ -f "$f" ] && BENCHMARK_FILES+=("$f")
  done
else
  if [ -f "$BENCHMARKS_DIR/${CATEGORY}.json" ]; then
    BENCHMARK_FILES+=("$BENCHMARKS_DIR/${CATEGORY}.json")
  fi
fi

if [ ${#BENCHMARK_FILES[@]} -eq 0 ]; then
  log_warn "No benchmark files found for category: $CATEGORY"
  jq -n --arg cat "$CATEGORY" '{"error": "No benchmark files for category", "category": $cat, "scores": {}}'
  exit 0
fi

# --- Helper: check ground truth match ---
# Returns number of matched keywords out of total
check_ground_truth() {
  local response="$1"
  local description_contains_json="$2"

  local total
  total=$(echo "$description_contains_json" | jq 'length' 2>/dev/null || echo "0")
  if [ "$total" -eq 0 ]; then
    echo "0 0"
    return
  fi

  local matched=0
  local i=0
  while [ "$i" -lt "$total" ]; do
    local keyword
    keyword=$(echo "$description_contains_json" | jq -r ".[$i]" 2>/dev/null)
    if echo "$response" | grep -qi "$keyword" 2>/dev/null; then
      matched=$((matched + 1))
    fi
    i=$((i + 1))
  done

  echo "$matched $total"
}

# --- Run benchmarks ---
# Accumulate results: { model: { category: { tp, fp, fn } } }
RESULTS="{}"
CLAUDE_TEST_CASES="[]"
TIMEOUT=120

if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
  cfg_timeout=$(jq -r '.timeout // empty' "$CONFIG_FILE" 2>/dev/null || true)
  if [ -n "$cfg_timeout" ]; then
    TIMEOUT="$cfg_timeout"
  fi
fi

for benchmark_file in "${BENCHMARK_FILES[@]}"; do
  BENCH_CATEGORY=$(basename "$benchmark_file" .json)
  log_info "Benchmarking category: $BENCH_CATEGORY"

  # Read test cases
  TEST_CASES=$(jq '.test_cases // []' "$benchmark_file" 2>/dev/null || echo "[]")
  TEST_COUNT=$(echo "$TEST_CASES" | jq 'length' 2>/dev/null || echo "0")

  if [ "$TEST_COUNT" -eq 0 ]; then
    log_warn "No test cases in $benchmark_file"
    continue
  fi

  tc_idx=0
  while [ "$tc_idx" -lt "$TEST_COUNT" ]; do
    TEST_CASE=$(echo "$TEST_CASES" | jq ".[$tc_idx]" 2>/dev/null)
    CODE=$(echo "$TEST_CASE" | jq -r '.code // ""' 2>/dev/null)
    GROUND_TRUTH=$(echo "$TEST_CASE" | jq '.ground_truth // {}' 2>/dev/null)
    DESCRIPTION_CONTAINS=$(echo "$GROUND_TRUTH" | jq '.description_contains // []' 2>/dev/null)
    TEST_FILE=$(echo "$TEST_CASE" | jq -r '.file // "benchmark_test.tmp"' 2>/dev/null)
    TEST_ROLE=$(echo "$TEST_CASE" | jq -r '.role // "bugs"' 2>/dev/null)

    if [ -z "$CODE" ]; then
      tc_idx=$((tc_idx + 1))
      continue
    fi

    # --- Codex ---
    if has_model "codex" && command -v codex &>/dev/null; then
      CODEX_RESPONSE=$(echo "$CODE" | "$SCRIPT_DIR/codex-review.sh" "$TEST_FILE" "${CONFIG_FILE:-/dev/null}" "$TEST_ROLE" 2>/dev/null || echo "{}")
      CODEX_TEXT=$(echo "$CODEX_RESPONSE" | jq -r 'tostring' 2>/dev/null || echo "")

      read -r matched total <<< "$(check_ground_truth "$CODEX_TEXT" "$DESCRIPTION_CONTAINS")"

      # Update results for codex
      RESULTS=$(echo "$RESULTS" | jq \
        --arg model "codex" \
        --arg cat "$BENCH_CATEGORY" \
        --argjson matched "$matched" \
        --argjson total "$total" \
        '
        .[$model] //= {} |
        .[$model][$cat] //= {"tp": 0, "total_expected": 0, "total_found": 0} |
        .[$model][$cat].tp += $matched |
        .[$model][$cat].total_expected += $total |
        .[$model][$cat].total_found += (if $matched > 0 then 1 else 0 end)
        ')
    fi

    # --- Gemini ---
    if has_model "gemini" && command -v gemini &>/dev/null; then
      GEMINI_RESPONSE=$(echo "$CODE" | "$SCRIPT_DIR/gemini-review.sh" "$TEST_FILE" "${CONFIG_FILE:-/dev/null}" "$TEST_ROLE" 2>/dev/null || echo "{}")
      GEMINI_TEXT=$(echo "$GEMINI_RESPONSE" | jq -r 'tostring' 2>/dev/null || echo "")

      read -r matched total <<< "$(check_ground_truth "$GEMINI_TEXT" "$DESCRIPTION_CONTAINS")"

      RESULTS=$(echo "$RESULTS" | jq \
        --arg model "gemini" \
        --arg cat "$BENCH_CATEGORY" \
        --argjson matched "$matched" \
        --argjson total "$total" \
        '
        .[$model] //= {} |
        .[$model][$cat] //= {"tp": 0, "total_expected": 0, "total_found": 0} |
        .[$model][$cat].tp += $matched |
        .[$model][$cat].total_expected += $total |
        .[$model][$cat].total_found += (if $matched > 0 then 1 else 0 end)
        ')
    fi

    # --- Claude (marker for external processing) ---
    if has_model "claude"; then
      CLAUDE_TEST_CASES=$(echo "$CLAUDE_TEST_CASES" | jq \
        --arg cat "$BENCH_CATEGORY" \
        --arg code "$CODE" \
        --arg file "$TEST_FILE" \
        --arg role "$TEST_ROLE" \
        --argjson ground_truth "$GROUND_TRUTH" \
        '. + [{
          "category": $cat,
          "code": $code,
          "file": $file,
          "role": $role,
          "ground_truth": $ground_truth
        }]')
    fi

    tc_idx=$((tc_idx + 1))
  done
done

# =============================================================================
# Compute Scores (Precision, Recall, F1)
# =============================================================================

SCORES=$(echo "$RESULTS" | jq '
  to_entries | map(
    .key as $model |
    .value | to_entries | map(
      .key as $cat |
      .value |
      {
        category: $cat,
        true_positives: .tp,
        total_expected: .total_expected,
        total_found: .total_found,
        precision: (if .total_found > 0 then (.tp / .total_found * 100 | floor) else 0 end),
        recall: (if .total_expected > 0 then (.tp / .total_expected * 100 | floor) else 0 end),
        f1: (
          if .total_found > 0 and .total_expected > 0 then
            ((.tp / .total_found) * (.tp / .total_expected)) as $pr |
            ((.tp / .total_found) + (.tp / .total_expected)) as $sum |
            if $sum > 0 then (2 * $pr / $sum * 100 | floor) else 0 end
          else 0 end
        )
      }
    ) | {($model): .}
  ) | add // {}
')

# =============================================================================
# Output
# =============================================================================

CLAUDE_COUNT=$(echo "$CLAUDE_TEST_CASES" | jq 'length' 2>/dev/null || echo "0")

OUTPUT=""
if [ "$CLAUDE_COUNT" -gt 0 ] && has_model "claude"; then
  OUTPUT=$(jq -n \
    --argjson scores "$SCORES" \
    --argjson claude_test_cases "$CLAUDE_TEST_CASES" \
    '{
      scores: $scores,
      claude_benchmark_needed: true,
      test_cases: $claude_test_cases
    }')
else
  OUTPUT=$(jq -n \
    --argjson scores "$SCORES" \
    '{
      scores: $scores,
      claude_benchmark_needed: false
    }')
fi

echo "$OUTPUT"

# --- Save to cache ---
PROJECT_ROOT=$(find_project_root)
echo "$OUTPUT" | "$SCRIPT_DIR/cache-manager.sh" write "$PROJECT_ROOT" "benchmarks" "model-scores" 2>/dev/null || true

exit 0
