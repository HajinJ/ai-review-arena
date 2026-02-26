#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Business Model Benchmarking
#
# Usage: benchmark-business-models.sh [--category all|accuracy|audience|positioning|evidence]
#                                     [--models claude,codex,gemini]
#                                     [--config <config>]
#
# Reads test cases from $PLUGIN_DIR/config/benchmarks/business-*.json.
# Runs each enabled model against test cases, compares against ground_truth.
# Computes precision, recall, F1 per test case, then averages per category.
#
# KEY DIFFERENCE FROM CODE BENCHMARKING:
#   Multiple test cases per category, so scores are averaged F1 across test cases.
#
# IMPORTANT: Claude cannot be called via CLI from within this script.
#   For Claude benchmarks, outputs a marker for orchestrator to handle via Task tool.
#
# Output: JSON with model scores per category. Saved to cache.
#
# Exit codes:
#   0 - Always (informational tool)
# =============================================================================

set -euo pipefail

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

# =============================================================================
# SCORING ALGORITHM
# =============================================================================
# For each test case:
#   1. Run model's business review on the content
#   2. For each ground_truth item, check if any model finding matches:
#      - Section match: finding section contains ground_truth section (case-insensitive)
#      - Keyword match: finding description contains majority of ground_truth keywords
#   3. Calculate per-test-case scores:
#      - correct_findings = number of ground_truth items matched by at least one finding
#      - precision = correct_findings / total_findings_reported
#      - recall = correct_findings / total_ground_truth_items
#      - F1 = 2 * precision * recall / (precision + recall)
#
# For each category:
#   - Average F1 scores across all test cases in that category
#   - This is the final category score for the model
#
# Example:
#   Category "accuracy" has 3 test cases with F1 scores: 85, 90, 80
#   Model's accuracy score = (85 + 90 + 80) / 3 = 85
# =============================================================================

# Collect business benchmark files
BENCHMARK_FILES=()
if [ "$CATEGORY" = "all" ]; then
  for f in "$BENCHMARKS_DIR"/business-*.json; do
    [ -f "$f" ] && BENCHMARK_FILES+=("$f")
  done
else
  # For specific category, look for business-<category>-*.json files
  for f in "$BENCHMARKS_DIR"/business-${CATEGORY}-*.json; do
    [ -f "$f" ] && BENCHMARK_FILES+=("$f")
  done
fi

if [ ${#BENCHMARK_FILES[@]} -eq 0 ]; then
  log_warn "No business benchmark files found for category: $CATEGORY"
  jq -n --arg cat "$CATEGORY" '{"error": "No business benchmark files for category", "category": $cat, "scores": {}}'
  exit 0
fi

# --- Helper: check if finding matches ground truth item ---
# Returns 1 if match, 0 if no match
# Matching criteria:
#   1. Section contains ground_truth.section (case-insensitive)
#   2. Finding description contains majority of ground_truth.description_contains keywords
check_finding_match() {
  local finding_section="$1"
  local finding_desc="$2"
  local gt_section="$3"
  local gt_keywords_json="$4"

  # Check section match
  if ! echo "$finding_section" | grep -qi "$gt_section" 2>/dev/null; then
    echo "0"
    return
  fi

  # Count keyword matches
  local total_keywords
  total_keywords=$(echo "$gt_keywords_json" | jq 'length' 2>/dev/null || echo "0")
  if [ "$total_keywords" -eq 0 ]; then
    echo "0"
    return
  fi

  local matched_keywords=0
  local i=0
  while [ "$i" -lt "$total_keywords" ]; do
    local keyword
    keyword=$(echo "$gt_keywords_json" | jq -r ".[$i]" 2>/dev/null)
    if echo "$finding_desc" | grep -qi "$keyword" 2>/dev/null; then
      matched_keywords=$((matched_keywords + 1))
    fi
    i=$((i + 1))
  done

  # Require majority of keywords to match
  local half=$((total_keywords / 2))
  if [ "$matched_keywords" -gt "$half" ]; then
    echo "1"
  else
    echo "0"
  fi
}

# --- Helper: score findings against ground truth ---
# Returns: "correct_findings total_findings total_expected"
score_findings() {
  local findings_json="$1"
  local ground_truth_json="$2"

  local total_findings
  total_findings=$(echo "$findings_json" | jq 'length' 2>/dev/null || echo "0")

  local total_expected
  total_expected=$(echo "$ground_truth_json" | jq 'length' 2>/dev/null || echo "0")

  if [ "$total_expected" -eq 0 ]; then
    echo "0 $total_findings 0"
    return
  fi

  # For each ground truth item, check if any finding matches
  local correct_findings=0
  local gt_idx=0
  while [ "$gt_idx" -lt "$total_expected" ]; do
    local gt_item
    gt_item=$(echo "$ground_truth_json" | jq ".[$gt_idx]" 2>/dev/null)

    local gt_section
    gt_section=$(echo "$gt_item" | jq -r '.section // ""' 2>/dev/null)

    local gt_keywords
    gt_keywords=$(echo "$gt_item" | jq '.description_contains // []' 2>/dev/null)

    # Check if any finding matches this ground truth item
    local found_match=0
    local f_idx=0
    while [ "$f_idx" -lt "$total_findings" ]; do
      local finding
      finding=$(echo "$findings_json" | jq ".[$f_idx]" 2>/dev/null)

      local finding_section
      finding_section=$(echo "$finding" | jq -r '.section // ""' 2>/dev/null)

      local finding_desc
      finding_desc=$(echo "$finding" | jq -r '.description // .message // ""' 2>/dev/null)

      local is_match
      is_match=$(check_finding_match "$finding_section" "$finding_desc" "$gt_section" "$gt_keywords")

      if [ "$is_match" = "1" ]; then
        found_match=1
        break
      fi

      f_idx=$((f_idx + 1))
    done

    if [ "$found_match" = "1" ]; then
      correct_findings=$((correct_findings + 1))
    fi

    gt_idx=$((gt_idx + 1))
  done

  echo "$correct_findings $total_findings $total_expected"
}

# --- Helper: compute F1 score ---
# Returns F1 score (0-100)
compute_f1() {
  local correct="$1"
  local total_found="$2"
  local total_expected="$3"

  if [ "$total_found" -eq 0 ] || [ "$total_expected" -eq 0 ]; then
    echo "0"
    return
  fi

  # Use bc for floating point arithmetic
  if ! command -v bc &>/dev/null; then
    # Fallback to integer arithmetic
    local precision=$((correct * 100 / total_found))
    local recall=$((correct * 100 / total_expected))

    if [ "$precision" -eq 0 ] && [ "$recall" -eq 0 ]; then
      echo "0"
      return
    fi

    if [ "$correct" -eq 0 ]; then
      echo "0"
      return
    fi
    local f1=$((200 * correct * correct / (total_found * correct + total_expected * correct)))
    echo "$f1"
  else
    # Use bc for accurate calculation
    local precision=$(echo "scale=4; $correct / $total_found" | bc)
    local recall=$(echo "scale=4; $correct / $total_expected" | bc)

    local sum=$(echo "scale=4; $precision + $recall" | bc)
    if [ "$(echo "$sum == 0" | bc)" = "1" ]; then
      echo "0"
      return
    fi

    local f1=$(echo "scale=2; 2 * $precision * $recall / $sum * 100" | bc | cut -d. -f1)
    echo "$f1"
  fi
}

# --- Run benchmarks ---
# Accumulate results: { model: { category: [ { test_id, f1, precision, recall, correct, found, expected } ] } }
RESULTS="{}"
CLAUDE_TEST_CASES="[]"
TIMEOUT=120

if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
  cfg_timeout=$(jq -r '.timeout // empty' "$CONFIG_FILE" 2>/dev/null || true)
  if [ -n "$cfg_timeout" ]; then
    TIMEOUT="$cfg_timeout"
  fi
fi

log_info "Starting business model benchmarking..."

for benchmark_file in "${BENCHMARK_FILES[@]}"; do
  # Extract category from filename: business-accuracy-test-01.json -> accuracy
  BENCH_FILENAME=$(basename "$benchmark_file" .json)
  # Remove "business-" prefix and "-test-NN" suffix
  BENCH_CATEGORY=$(echo "$BENCH_FILENAME" | sed -E 's/^business-//; s/-test-[0-9]+$//')

  log_info "Benchmarking test case: $BENCH_FILENAME (category: $BENCH_CATEGORY)"

  # Read test case
  TEST_ID=$(jq -r '.id // "unknown"' "$benchmark_file" 2>/dev/null)
  CONTENT=$(jq -r '.content // ""' "$benchmark_file" 2>/dev/null)
  GROUND_TRUTH=$(jq '.ground_truth // []' "$benchmark_file" 2>/dev/null)
  CONTENT_TYPE=$(jq -r '.content_type // "unknown"' "$benchmark_file" 2>/dev/null)

  if [ -z "$CONTENT" ]; then
    log_warn "No content in $benchmark_file"
    continue
  fi

  # --- Codex & Gemini (parallel) ---
  CODEX_RESULT_FILE="${SESSION_DIR:-/tmp}/bench-codex-${TEST_ID}.json"
  GEMINI_RESULT_FILE="${SESSION_DIR:-/tmp}/bench-gemini-${TEST_ID}.json"
  _bench_pids=()

  if has_model "codex" && [ -x "$SCRIPT_DIR/codex-business-review.sh" ]; then
    log_info "  Running Codex for $TEST_ID..."
    (
      echo "$CONTENT" | timeout "$TIMEOUT" "$SCRIPT_DIR/codex-business-review.sh" "${CONFIG_FILE:-/dev/null}" --mode round1 --category "$BENCH_CATEGORY" > "$CODEX_RESULT_FILE" 2>/dev/null || echo '{"findings":[]}' > "$CODEX_RESULT_FILE"
    ) &
    _bench_pids+=($!)
  fi

  if has_model "gemini" && [ -x "$SCRIPT_DIR/gemini-business-review.sh" ]; then
    log_info "  Running Gemini for $TEST_ID..."
    (
      echo "$CONTENT" | timeout "$TIMEOUT" "$SCRIPT_DIR/gemini-business-review.sh" "${CONFIG_FILE:-/dev/null}" --mode round1 --category "$BENCH_CATEGORY" > "$GEMINI_RESULT_FILE" 2>/dev/null || echo '{"findings":[]}' > "$GEMINI_RESULT_FILE"
    ) &
    _bench_pids+=($!)
  fi

  # Wait for both models to finish
  for _bpid in "${_bench_pids[@]+${_bench_pids[@]}}"; do
    wait "$_bpid" 2>/dev/null || true
  done

  # Process Codex results
  if [ -f "$CODEX_RESULT_FILE" ]; then
    CODEX_RESPONSE=$(cat "$CODEX_RESULT_FILE" 2>/dev/null || echo '{"findings":[]}')
    rm -f "$CODEX_RESULT_FILE"
    CODEX_FINDINGS=$(echo "$CODEX_RESPONSE" | jq '.findings // []' 2>/dev/null || echo "[]")

    read -r correct found expected <<< "$(score_findings "$CODEX_FINDINGS" "$GROUND_TRUTH")"
    f1=$(compute_f1 "$correct" "$found" "$expected")
    precision=0; [ "$found" -gt 0 ] && precision=$((correct * 100 / found))
    recall=0; [ "$expected" -gt 0 ] && recall=$((correct * 100 / expected))

    RESULTS=$(echo "$RESULTS" | jq \
      --arg model "codex" --arg cat "$BENCH_CATEGORY" --arg test_id "$TEST_ID" \
      --argjson f1 "$f1" --argjson precision "$precision" --argjson recall "$recall" \
      --argjson correct "$correct" --argjson found "$found" --argjson expected "$expected" \
      '.[$model] //= {} | .[$model][$cat] //= [] | .[$model][$cat] += [{
        test_id: $test_id, f1: $f1, precision: $precision, recall: $recall,
        correct: $correct, found: $found, expected: $expected
      }]')

    log_info "    Codex: F1=$f1, P=$precision, R=$recall ($correct/$found found, $expected expected)"
  fi

  # Process Gemini results
  if [ -f "$GEMINI_RESULT_FILE" ]; then
    GEMINI_RESPONSE=$(cat "$GEMINI_RESULT_FILE" 2>/dev/null || echo '{"findings":[]}')
    rm -f "$GEMINI_RESULT_FILE"
    GEMINI_FINDINGS=$(echo "$GEMINI_RESPONSE" | jq '.findings // []' 2>/dev/null || echo "[]")

    read -r correct found expected <<< "$(score_findings "$GEMINI_FINDINGS" "$GROUND_TRUTH")"
    f1=$(compute_f1 "$correct" "$found" "$expected")
    precision=0; [ "$found" -gt 0 ] && precision=$((correct * 100 / found))
    recall=0; [ "$expected" -gt 0 ] && recall=$((correct * 100 / expected))

    RESULTS=$(echo "$RESULTS" | jq \
      --arg model "gemini" --arg cat "$BENCH_CATEGORY" --arg test_id "$TEST_ID" \
      --argjson f1 "$f1" --argjson precision "$precision" --argjson recall "$recall" \
      --argjson correct "$correct" --argjson found "$found" --argjson expected "$expected" \
      '.[$model] //= {} | .[$model][$cat] //= [] | .[$model][$cat] += [{
        test_id: $test_id, f1: $f1, precision: $precision, recall: $recall,
        correct: $correct, found: $found, expected: $expected
      }]')

    log_info "    Gemini: F1=$f1, P=$precision, R=$recall ($correct/$found found, $expected expected)"
  fi

  # --- Claude (marker for external processing) ---
  if has_model "claude"; then
    CLAUDE_TEST_CASES=$(echo "$CLAUDE_TEST_CASES" | jq \
      --arg cat "$BENCH_CATEGORY" \
      --arg test_id "$TEST_ID" \
      --arg content "$CONTENT" \
      --arg content_type "$CONTENT_TYPE" \
      --argjson ground_truth "$GROUND_TRUTH" \
      '. + [{
        category: $cat,
        test_id: $test_id,
        content: $content,
        content_type: $content_type,
        ground_truth: $ground_truth
      }]')
  fi
done

# =============================================================================
# Compute Average Scores Per Category
# =============================================================================

log_info "Computing average scores per category..."

# Average F1 scores per category for each model
SCORES=$(echo "$RESULTS" | jq '
  to_entries | map(
    .key as $model |
    .value | to_entries | map(
      .key as $cat |
      .value | {
        category: $cat,
        test_cases: .,
        avg_f1: (
          if (. | length) > 0 then
            (map(.f1) | add / length | floor)
          else 0 end
        ),
        avg_precision: (
          if (. | length) > 0 then
            (map(.precision) | add / length | floor)
          else 0 end
        ),
        avg_recall: (
          if (. | length) > 0 then
            (map(.recall) | add / length | floor)
          else 0 end
        ),
        total_test_cases: (. | length)
      }
    ) | map({(.category): .avg_f1}) | add
  ) | map({(.[0].key): .[0].value}) | add // {}
' 2>/dev/null || echo "{}")

# =============================================================================
# Output
# =============================================================================

CLAUDE_COUNT=$(echo "$CLAUDE_TEST_CASES" | jq 'length' 2>/dev/null || echo "0")

OUTPUT=""
if [ "$CLAUDE_COUNT" -gt 0 ] && has_model "claude"; then
  log_info "Claude benchmarking required: $CLAUDE_COUNT test cases"

  OUTPUT=$(jq -n \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson scores "$SCORES" \
    --argjson details "$RESULTS" \
    --argjson claude_test_cases "$CLAUDE_TEST_CASES" \
    '{
      timestamp: $timestamp,
      scores: $scores,
      details: $details,
      claude_benchmark_needed: true,
      claude_test_cases: $claude_test_cases,
      note: "Claude scores are 0 (placeholder). Orchestrator must run Claude benchmarks via Task tool and fill in scores."
    }')
else
  OUTPUT=$(jq -n \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson scores "$SCORES" \
    --argjson details "$RESULTS" \
    '{
      timestamp: $timestamp,
      scores: $scores,
      details: $details,
      claude_benchmark_needed: false
    }')
fi

echo "$OUTPUT"

# --- Save to cache ---
PROJECT_ROOT=$(find_project_root)
echo "$OUTPUT" | "$SCRIPT_DIR/cache-manager.sh" write "$PROJECT_ROOT" "benchmarks" "business-model-scores" 2>/dev/null || true

log_info "Business model benchmarking complete."

exit 0
