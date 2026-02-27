#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Run Actual Benchmark
#
# Usage: run-benchmark.sh [config_file] [--test-ids id1,id2,...] [--verbose]
#
# Runs benchmark test cases through actual Codex/Gemini CLIs and measures
# precision/recall/F1 against ground truth.
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/utils.sh"
source "$SCRIPT_DIR/benchmark-utils.sh"

CONFIG_FILE="${1:-$PLUGIN_DIR/config/default-config.json}"
shift || true

VERBOSE=false
TEST_IDS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --verbose) VERBOSE=true; shift ;;
    --test-ids) TEST_IDS="$2"; shift 2 ;;
    *) shift ;;
  esac
done

ensure_jq

BENCHMARK_DIR="$PLUGIN_DIR/config/benchmarks"
RESULTS_DIR="$PLUGIN_DIR/cache/evaluation-reports"
mkdir -p "$RESULTS_DIR"

# --- Check CLI availability ---
HAS_CODEX=false
HAS_GEMINI=false
command -v codex &>/dev/null && HAS_CODEX=true
command -v gemini &>/dev/null && HAS_GEMINI=true

if [ "$HAS_CODEX" != "true" ] && [ "$HAS_GEMINI" != "true" ]; then
  log_error "Neither Codex nor Gemini CLI found. Cannot run benchmark."
  exit 1
fi

log_info "CLIs available: codex=$HAS_CODEX, gemini=$HAS_GEMINI"

# --- Discover code benchmark test cases ---
CODE_TESTS=()
for f in "$BENCHMARK_DIR"/security-test-*.json "$BENCHMARK_DIR"/bugs-test-*.json \
         "$BENCHMARK_DIR"/architecture-test-*.json "$BENCHMARK_DIR"/performance-test-*.json; do
  [ -f "$f" ] || continue
  test_id=$(jq -r '.id // ""' "$f" 2>/dev/null)
  if [ -n "$TEST_IDS" ]; then
    echo "$TEST_IDS" | grep -q "$test_id" || continue
  fi
  CODE_TESTS+=("$f")
done

log_info "Found ${#CODE_TESTS[@]} code benchmark test case(s)"

# --- Run benchmarks ---
TOTAL_TP=0
TOTAL_FP=0
TOTAL_FN=0
RESULTS=()

for test_file in "${CODE_TESTS[@]}"; do
  test_id=$(jq -r '.id' "$test_file")
  test_cat=$(jq -r '.category' "$test_file")
  test_lang=$(jq -r '.language // "javascript"' "$test_file")
  test_desc=$(jq -r '.description' "$test_file")

  log_info "=== Benchmark: $test_id ($test_cat) ==="
  log_info "  $test_desc"

  # Write code to temp file
  BENCH_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/arena-bench-XXXXXX")
  SESSION_DIR="$BENCH_TEMP/session"
  mkdir -p "$SESSION_DIR"

  # Determine file extension
  case "$test_lang" in
    javascript) EXT="js" ;;
    typescript) EXT="ts" ;;
    python) EXT="py" ;;
    *) EXT="js" ;;
  esac

  CODE_FILE="$BENCH_TEMP/test-code.$EXT"
  jq -r '.code' "$test_file" > "$CODE_FILE"

  # Determine review role based on category
  REVIEW_ROLE="$test_cat"

  # shellcheck disable=SC2034 # used by review indexing
  REVIEW_IDX=0
  PIDS=()

  # Usage: cat file | codex-review.sh <file_path> <config_file> <role>
  # Run Codex review
  if [ "$HAS_CODEX" = "true" ]; then
    log_info "  Running Codex review..."
    (
      _cli_err=$(mktemp)
      CODEX_RESULT=$(cat "$CODE_FILE" | "$SCRIPT_DIR/codex-review.sh" "$CODE_FILE" "$CONFIG_FILE" "$REVIEW_ROLE" 2>"$_cli_err") || true
      log_stderr_file "run-benchmark(codex)" "$_cli_err"
      if [ -n "$CODEX_RESULT" ] && echo "$CODEX_RESULT" | jq . &>/dev/null; then
        echo "$CODEX_RESULT" > "$SESSION_DIR/findings_0.json"
      fi
    ) &
    PIDS+=($!)
  fi

  # Run Gemini review
  if [ "$HAS_GEMINI" = "true" ]; then
    log_info "  Running Gemini review..."
    (
      _cli_err=$(mktemp)
      GEMINI_RESULT=$(cat "$CODE_FILE" | "$SCRIPT_DIR/gemini-review.sh" "$CODE_FILE" "$CONFIG_FILE" "$REVIEW_ROLE" 2>"$_cli_err") || true
      log_stderr_file "run-benchmark(gemini)" "$_cli_err"
      if [ -n "$GEMINI_RESULT" ] && echo "$GEMINI_RESULT" | jq . &>/dev/null; then
        echo "$GEMINI_RESULT" > "$SESSION_DIR/findings_1.json"
      fi
    ) &
    PIDS+=($!)
  fi

  # Wait for reviews to complete
  for pid in "${PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  # Check what findings we got
  FINDINGS_COUNT=$(find "$SESSION_DIR" -name "findings_*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
  log_info "  Got $FINDINGS_COUNT findings file(s)"

  if [ "$FINDINGS_COUNT" -eq 0 ]; then
    log_warn "  No findings files produced for $test_id"
    rm -rf "$BENCH_TEMP"
    continue
  fi

  # Aggregate findings
  AGG_RESULT=$("$SCRIPT_DIR/aggregate-findings.sh" "$SESSION_DIR" "$CONFIG_FILE") || AGG_RESULT="[]"
  [ "$AGG_RESULT" = "LGTM" ] && AGG_RESULT="[]"

  # Save aggregated findings
  echo "$AGG_RESULT" > "$BENCH_TEMP/aggregated.json"

  if [ "$VERBOSE" = "true" ]; then
    AGG_COUNT=$(echo "$AGG_RESULT" | jq 'if type == "array" then length else 0 end' || echo 0)
    log_info "  Aggregated findings: $AGG_COUNT"
  fi

  # --- Calculate metrics against ground truth ---
  expected_count=$(jq '.ground_truth | length' "$test_file")
  actual_count=$(echo "$AGG_RESULT" | jq 'if type == "array" then length else 0 end' || echo 0)

  # Extract all text from aggregated findings for keyword matching
  AGG_TEXT=$(extract_text "$AGG_RESULT")

  read -r tp fn <<< "$(count_matches "$AGG_TEXT" "$test_file" "$expected_count" "$VERBOSE")"

  fp=0
  [ "$actual_count" -gt "$tp" ] && fp=$((actual_count - tp))

  # Calculate rates
  read -r precision recall f1 <<< "$(compute_metrics "$tp" "$fp" "$fn")"

  TOTAL_TP=$((TOTAL_TP + tp))
  TOTAL_FP=$((TOTAL_FP + fp))
  TOTAL_FN=$((TOTAL_FN + fn))

  log_info "  Results: TP=$tp FP=$fp FN=$fn P=$precision R=$recall F1=$f1"

  RESULTS+=("{\"test_id\":\"$test_id\",\"category\":\"$test_cat\",\"expected\":$expected_count,\"actual\":$actual_count,\"tp\":$tp,\"fp\":$fp,\"fn\":$fn,\"precision\":$precision,\"recall\":$recall,\"f1\":$f1}")

  rm -rf "$BENCH_TEMP"
done

# --- Aggregate metrics ---
read -r AGG_P AGG_R AGG_F1 <<< "$(compute_metrics "$TOTAL_TP" "$TOTAL_FP" "$TOTAL_FN")"

# --- Build JSON report ---
RESULTS_JSON="["
for i in "${!RESULTS[@]}"; do
  [ "$i" -gt 0 ] && RESULTS_JSON+=","
  RESULTS_JSON+="${RESULTS[$i]}"
done
RESULTS_JSON+="]"

REPORT_FILE="$RESULTS_DIR/benchmark-$(date +%Y%m%d-%H%M%S).json"
cat > "$REPORT_FILE" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "cli_available": {"codex": $HAS_CODEX, "gemini": $HAS_GEMINI},
  "test_cases": ${#CODE_TESTS[@]},
  "aggregate": {
    "true_positives": $TOTAL_TP,
    "false_positives": $TOTAL_FP,
    "false_negatives": $TOTAL_FN,
    "precision": $AGG_P,
    "recall": $AGG_R,
    "f1_score": $AGG_F1
  },
  "per_test": $RESULTS_JSON
}
EOF

# --- Print summary ---
echo ""
echo "## Benchmark Results (Arena Multi-AI)"
echo ""
echo "| Test Case | Category | Expected | Found | TP | FP | FN | Precision | Recall | F1 |"
echo "|-----------|----------|----------|-------|----|----|----|-----------|---------|----|"
for r in "${RESULTS[@]}"; do
  r_id=$(echo "$r" | jq -r '.test_id')
  r_cat=$(echo "$r" | jq -r '.category')
  r_exp=$(echo "$r" | jq '.expected')
  r_act=$(echo "$r" | jq '.actual')
  r_tp=$(echo "$r" | jq '.tp')
  r_fp=$(echo "$r" | jq '.fp')
  r_fn=$(echo "$r" | jq '.fn')
  r_p=$(echo "$r" | jq '.precision')
  r_r=$(echo "$r" | jq '.recall')
  r_f1=$(echo "$r" | jq '.f1')
  echo "| $r_id | $r_cat | $r_exp | $r_act | $r_tp | $r_fp | $r_fn | $r_p | $r_r | $r_f1 |"
done
echo "|-----------|----------|----------|-------|----|----|----|-----------|---------|----|"
echo "| **Total** | | | | **$TOTAL_TP** | **$TOTAL_FP** | **$TOTAL_FN** | **$AGG_P** | **$AGG_R** | **$AGG_F1** |"
echo ""
echo "Report saved: $REPORT_FILE"
