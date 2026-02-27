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
source "$SCRIPT_DIR/benchmark-utils.sh"

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
  for f in "$BENCHMARKS_DIR"/${CATEGORY}*.json "$BENCHMARKS_DIR"/${CATEGORY}-*.json; do
    [ -f "$f" ] && BENCHMARK_FILES+=("$f")
  done
fi

if [ ${#BENCHMARK_FILES[@]} -eq 0 ]; then
  log_warn "No benchmark files found for category: $CATEGORY"
  jq -n --arg cat "$CATEGORY" '{"error": "No benchmark files for category", "category": $cat, "scores": {}}'
  exit 0
fi

# --- Negation patterns for context-aware keyword matching ---
NEGATION_PATTERNS="not a|no .* found|no .* detected|no .* issue|not vulnerable|false positive|doesn.t have|isn.t|is not|are not|was not|were not|cannot find|could not find|don.t see|didn.t find|absence of|without any|free from|no evidence of|does not contain|not present"

# --- Helper: context-aware keyword match ---
# Checks if keyword appears in a positive (affirming) context, not negated.
# Returns 0 if keyword is positively present, 1 if absent or negated.
keyword_match_positive() {
  local response="$1"
  local keyword="$2"

  # First check if keyword exists at all
  if ! echo "$response" | grep -qi "$keyword" 2>/dev/null; then
    return 1
  fi

  # Extract lines containing the keyword
  local matching_lines
  matching_lines=$(echo "$response" | grep -i "$keyword" || echo "")

  # Check if ALL matching lines are negated
  local positive_found=false
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    # Check if the line contains negation near the keyword
    local is_negated=false
    if echo "$line" | grep -qiE "(${NEGATION_PATTERNS}).*${keyword}" 2>/dev/null; then
      is_negated=true
    fi
    if [ "$is_negated" = "false" ]; then
      positive_found=true
      break
    fi
  done <<< "$matching_lines"

  if [ "$positive_found" = "true" ]; then
    return 0
  fi
  return 1
}

# --- Helper: check ground truth match against a single finding ---
# Supports both array-of-objects ground_truth and flat description_contains.
# Returns: "matched total" counts.
check_ground_truth() {
  local response="$1"
  local ground_truth_json="$2"

  # Detect ground_truth format:
  # 1. Array of objects with description_contains (e.g., security-test-01.json)
  # 2. Single object with description_contains
  # 3. Flat array of strings

  local gt_type
  gt_type=$(echo "$ground_truth_json" | jq -r 'type' || echo "null")

  local all_keywords="[]"

  if [ "$gt_type" = "array" ]; then
    # Check if array of objects (each with description_contains) or flat strings
    local first_type
    first_type=$(echo "$ground_truth_json" | jq -r '.[0] | type' || echo "null")

    if [ "$first_type" = "object" ]; then
      # Array of finding objects: merge all description_contains + check severity/type fields
      all_keywords=$(echo "$ground_truth_json" | jq '[.[] | .description_contains // [] | .[]] | unique' || echo "[]")

      # Also try structured matching: check if response mentions severity+type
      local struct_matched=0
      local struct_total
      struct_total=$(echo "$ground_truth_json" | jq 'length' || echo "0")

      local si=0
      while [ "$si" -lt "$struct_total" ]; do
        local sev type_val
        sev=$(echo "$ground_truth_json" | jq -r ".[$si].severity // empty" 2>/dev/null)
        type_val=$(echo "$ground_truth_json" | jq -r ".[$si].type // empty" 2>/dev/null)

        # A finding is "structurally matched" if the response mentions both severity and type
        local sev_found=false type_found=false
        if [ -n "$sev" ] && keyword_match_positive "$response" "$sev"; then
          sev_found=true
        fi
        if [ -n "$type_val" ]; then
          # Convert underscores to spaces for matching (e.g., sql_injection -> sql injection)
          local type_readable
          type_readable=$(echo "$type_val" | tr '_' ' ')
          if keyword_match_positive "$response" "$type_val" || keyword_match_positive "$response" "$type_readable"; then
            type_found=true
          fi
        fi

        if [ "$sev_found" = "true" ] && [ "$type_found" = "true" ]; then
          struct_matched=$((struct_matched + 1))
        fi
        si=$((si + 1))
      done

      # Use the better of keyword matching or structural matching
      # Structural matching counts per-finding, keyword matching counts per-keyword
    else
      # Flat array of strings
      all_keywords="$ground_truth_json"
    fi
  elif [ "$gt_type" = "object" ]; then
    # Single object with description_contains
    all_keywords=$(echo "$ground_truth_json" | jq '.description_contains // []' || echo "[]")
  fi

  local total
  total=$(echo "$all_keywords" | jq 'length' || echo "0")
  if [ "$total" -eq 0 ]; then
    echo "0 0"
    return
  fi

  local matched=0
  local i=0
  while [ "$i" -lt "$total" ]; do
    local keyword
    keyword=$(echo "$all_keywords" | jq -r ".[$i]" 2>/dev/null)
    if keyword_match_positive "$response" "$keyword"; then
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
# shellcheck disable=SC2034 # TIMEOUT used by arena_timeout wrapper in CLI calls
TIMEOUT=120

# shellcheck disable=SC2034 # TIMEOUT used by arena_timeout wrapper
if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
  cfg_timeout=$(jq -r '.timeout // empty' "$CONFIG_FILE" || true)
  if [ -n "$cfg_timeout" ]; then
    TIMEOUT="$cfg_timeout"
  fi
fi

for benchmark_file in "${BENCHMARK_FILES[@]}"; do
  BENCH_CATEGORY=$(basename "$benchmark_file" .json)
  log_info "Benchmarking category: $BENCH_CATEGORY"

  # Read test cases: support both {test_cases: [...]} and single-object format
  TEST_CASES=$(jq 'if .test_cases then .test_cases elif type == "array" then . else [.] end' "$benchmark_file" || echo "[]")
  TEST_COUNT=$(echo "$TEST_CASES" | jq 'length' || echo "0")

  if [ "$TEST_COUNT" -eq 0 ]; then
    log_warn "No test cases in $benchmark_file"
    continue
  fi

  tc_idx=0
  while [ "$tc_idx" -lt "$TEST_COUNT" ]; do
    TEST_CASE=$(echo "$TEST_CASES" | jq ".[$tc_idx]" 2>/dev/null)
    CODE=$(echo "$TEST_CASE" | jq -r '.code // ""' 2>/dev/null)
    # ground_truth can be array of finding objects or single object
    GROUND_TRUTH=$(echo "$TEST_CASE" | jq '.ground_truth // []' 2>/dev/null)
    TEST_FILE=$(echo "$TEST_CASE" | jq -r '.file // "benchmark_test.tmp"' 2>/dev/null)
    TEST_ROLE=$(echo "$TEST_CASE" | jq -r '.role // "bugs"' 2>/dev/null)

    if [ -z "$CODE" ]; then
      tc_idx=$((tc_idx + 1))
      continue
    fi

    # --- Launch Codex + Gemini in parallel ---
    CODEX_TMP="" GEMINI_TMP=""
    CODEX_PID="" GEMINI_PID=""

    if has_model "codex" && command -v codex &>/dev/null; then
      CODEX_TMP=$(mktemp)
      ( _cli_err=$(mktemp); echo "$CODE" | "$SCRIPT_DIR/codex-review.sh" "$TEST_FILE" "${CONFIG_FILE:-/dev/null}" "$TEST_ROLE" > "$CODEX_TMP" 2>"$_cli_err"; log_stderr_file "benchmark(codex)" "$_cli_err" ) &
      CODEX_PID=$!
    fi

    if has_model "gemini" && command -v gemini &>/dev/null; then
      GEMINI_TMP=$(mktemp)
      ( _cli_err=$(mktemp); echo "$CODE" | "$SCRIPT_DIR/gemini-review.sh" "$TEST_FILE" "${CONFIG_FILE:-/dev/null}" "$TEST_ROLE" > "$GEMINI_TMP" 2>"$_cli_err"; log_stderr_file "benchmark(gemini)" "$_cli_err" ) &
      GEMINI_PID=$!
    fi

    # Wait for parallel benchmarks
    [ -n "$CODEX_PID" ] && wait "$CODEX_PID" 2>/dev/null || true
    [ -n "$GEMINI_PID" ] && wait "$GEMINI_PID" 2>/dev/null || true

    # --- Process Codex results ---
    if [ -n "$CODEX_TMP" ] && [ -f "$CODEX_TMP" ]; then
      CODEX_TEXT=$(jq -r 'tostring' "$CODEX_TMP" || cat "$CODEX_TMP")
      read -r matched total <<< "$(check_ground_truth "$CODEX_TEXT" "$GROUND_TRUTH")"
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
      rm -f "$CODEX_TMP"
    fi

    # --- Process Gemini results ---
    if [ -n "$GEMINI_TMP" ] && [ -f "$GEMINI_TMP" ]; then
      GEMINI_TEXT=$(jq -r 'tostring' "$GEMINI_TMP" || cat "$GEMINI_TMP")
      read -r matched total <<< "$(check_ground_truth "$GEMINI_TEXT" "$GROUND_TRUTH")"
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
      rm -f "$GEMINI_TMP"
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

CLAUDE_COUNT=$(echo "$CLAUDE_TEST_CASES" | jq 'length' || echo "0")

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
echo "$OUTPUT" | "$SCRIPT_DIR/cache-manager.sh" write "$PROJECT_ROOT" "benchmarks" "model-scores" || true

exit 0
