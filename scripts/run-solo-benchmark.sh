#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Solo vs Arena Benchmark
#
# Usage: run-solo-benchmark.sh [--verbose] [--test-ids id1,id2,...]
#
# Runs each code benchmark test case through:
#   1. Solo Codex (codex-review.sh alone)
#   2. Solo Gemini (gemini-review.sh alone)
#   3. Arena (both + aggregate-findings.sh)
# Compares F1 scores to demonstrate Arena value over individual models.
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/utils.sh"

VERBOSE=false
TEST_IDS=""
CONFIG_FILE="$PLUGIN_DIR/config/default-config.json"

while [ $# -gt 0 ]; do
  case "$1" in
    --verbose) VERBOSE=true; shift ;;
    --test-ids) TEST_IDS="$2"; shift 2 ;;
    --config) CONFIG_FILE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

ensure_jq

BENCHMARK_DIR="$PLUGIN_DIR/config/benchmarks"

# --- Check CLI availability ---
HAS_CODEX=false
HAS_GEMINI=false
command -v codex &>/dev/null && HAS_CODEX=true
command -v gemini &>/dev/null && HAS_GEMINI=true

if [ "$HAS_CODEX" != "true" ] && [ "$HAS_GEMINI" != "true" ]; then
  log_error "Neither Codex nor Gemini CLI found. Cannot run benchmark."
  exit 1
fi

log_info "Solo vs Arena Benchmark"
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

# --- Helper: extract text from findings JSON ---
extract_text() {
  local json="$1"
  echo "$json" | tr -d '\000-\011\013-\037' | jq -r '
    if type == "array" then
      [.[] | (.title // ""), (.description // ""), (.suggestion // "")] | join(" ")
    elif type == "object" then
      [(.title // ""), (.description // ""), (.suggestion // "")] | join(" ")
    else . // "" end
  ' || echo "$json"
}

# --- Helper: count ground truth matches ---
count_matches() {
  local text="$1"
  local test_file="$2"
  local expected_count
  expected_count=$(jq '.ground_truth | length' "$test_file")

  local tp=0
  local fn=0
  for i in $(seq 0 $((expected_count - 1))); do
    local keywords
    keywords=$(jq -r ".ground_truth[$i].description_contains[]?" "$test_file" 2>/dev/null)
    local found=false
    if [ -n "$keywords" ]; then
      for keyword in $keywords; do
        if echo "$text" | grep -qi "$keyword" 2>/dev/null; then
          found=true
          break
        fi
      done
    fi
    if [ "$found" = "true" ]; then
      tp=$((tp + 1))
    else
      fn=$((fn + 1))
    fi
  done

  echo "$tp $fn $expected_count"
}

# --- Helper: compute metrics ---
compute_metrics() {
  local tp="$1" fp="$2" fn="$3"
  local precision=0 recall=0 f1=0
  [ $((tp + fp)) -gt 0 ] && precision=$(echo "scale=3; $tp / ($tp + $fp)" | bc)
  [ $((tp + fn)) -gt 0 ] && recall=$(echo "scale=3; $tp / ($tp + $fn)" | bc)
  if [ "$(echo "$precision + $recall > 0" | bc)" = "1" ]; then
    f1=$(echo "scale=3; 2 * $precision * $recall / ($precision + $recall)" | bc)
  fi
  echo "$precision $recall $f1"
}

# --- Run benchmarks ---
# Accumulators: solo_codex, solo_gemini, arena
SC_TP=0; SC_FP=0; SC_FN=0
SG_TP=0; SG_FP=0; SG_FN=0
AR_TP=0; AR_FP=0; AR_FN=0

PER_TEST_RESULTS=()

for test_file in "${CODE_TESTS[@]}"; do
  test_id=$(jq -r '.id' "$test_file")
  test_cat=$(jq -r '.category' "$test_file")
  test_lang=$(jq -r '.language // "javascript"' "$test_file")

  log_info "=== $test_id ($test_cat) ==="

  BENCH_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/arena-solo-bench-XXXXXX")
  SESSION_DIR="$BENCH_TEMP/session"
  mkdir -p "$SESSION_DIR"

  case "$test_lang" in
    javascript) EXT="js" ;; typescript) EXT="ts" ;; python) EXT="py" ;; *) EXT="js" ;;
  esac

  CODE_FILE="$BENCH_TEMP/test-code.$EXT"
  jq -r '.code' "$test_file" > "$CODE_FILE"

  REVIEW_ROLE="$test_cat"
  CODEX_RESULT="" GEMINI_RESULT=""

  # --- Run Solo Codex ---
  if [ "$HAS_CODEX" = "true" ]; then
    _cli_err=$(mktemp)
    CODEX_RESULT=$(cat "$CODE_FILE" | "$SCRIPT_DIR/codex-review.sh" "$CODE_FILE" "$CONFIG_FILE" "$REVIEW_ROLE" 2>"$_cli_err") || CODEX_RESULT=""
    log_stderr_file "run-solo-benchmark(codex)" "$_cli_err"
  fi

  # --- Run Solo Gemini ---
  if [ "$HAS_GEMINI" = "true" ]; then
    _cli_err=$(mktemp)
    GEMINI_RESULT=$(cat "$CODE_FILE" | "$SCRIPT_DIR/gemini-review.sh" "$CODE_FILE" "$CONFIG_FILE" "$REVIEW_ROLE" 2>"$_cli_err") || GEMINI_RESULT=""
    log_stderr_file "run-solo-benchmark(gemini)" "$_cli_err"
  fi

  # --- Solo Codex metrics ---
  sc_tp=0; sc_fp=0; sc_fn=0
  if [ -n "$CODEX_RESULT" ] && echo "$CODEX_RESULT" | jq . &>/dev/null; then
    codex_text=$(extract_text "$CODEX_RESULT")
    codex_actual=$(echo "$CODEX_RESULT" | jq 'if type == "array" then length else 0 end' || echo 0)
    read -r sc_tp sc_fn _ <<< "$(count_matches "$codex_text" "$test_file")"
    [ "$codex_actual" -gt "$sc_tp" ] && sc_fp=$((codex_actual - sc_tp))
  fi

  # --- Solo Gemini metrics ---
  sg_tp=0; sg_fp=0; sg_fn=0
  if [ -n "$GEMINI_RESULT" ] && echo "$GEMINI_RESULT" | jq . &>/dev/null; then
    gemini_text=$(extract_text "$GEMINI_RESULT")
    gemini_actual=$(echo "$GEMINI_RESULT" | jq 'if type == "array" then length else 0 end' || echo 0)
    read -r sg_tp sg_fn _ <<< "$(count_matches "$gemini_text" "$test_file")"
    [ "$gemini_actual" -gt "$sg_tp" ] && sg_fp=$((gemini_actual - sg_tp))
  fi

  # --- Arena (both + aggregation) ---
  ar_tp=0; ar_fp=0; ar_fn=0
  # Save findings for aggregation
  if [ -n "$CODEX_RESULT" ] && echo "$CODEX_RESULT" | jq . &>/dev/null; then
    echo "$CODEX_RESULT" > "$SESSION_DIR/findings_0.json"
  fi
  if [ -n "$GEMINI_RESULT" ] && echo "$GEMINI_RESULT" | jq . &>/dev/null; then
    echo "$GEMINI_RESULT" > "$SESSION_DIR/findings_1.json"
  fi

  FINDINGS_COUNT=$(find "$SESSION_DIR" -name "findings_*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [ "$FINDINGS_COUNT" -gt 0 ]; then
    AGG_RESULT=$("$SCRIPT_DIR/aggregate-findings.sh" "$SESSION_DIR" "$CONFIG_FILE") || AGG_RESULT="[]"
    [ "$AGG_RESULT" = "LGTM" ] && AGG_RESULT="[]"

    agg_text=$(extract_text "$AGG_RESULT")
    agg_actual=$(echo "$AGG_RESULT" | jq 'if type == "array" then length else 0 end' || echo 0)
    read -r ar_tp ar_fn _ <<< "$(count_matches "$agg_text" "$test_file")"
    [ "$agg_actual" -gt "$ar_tp" ] && ar_fp=$((agg_actual - ar_tp))
  fi

  # Accumulate
  SC_TP=$((SC_TP + sc_tp)); SC_FP=$((SC_FP + sc_fp)); SC_FN=$((SC_FN + sc_fn))
  SG_TP=$((SG_TP + sg_tp)); SG_FP=$((SG_FP + sg_fp)); SG_FN=$((SG_FN + sg_fn))
  AR_TP=$((AR_TP + ar_tp)); AR_FP=$((AR_FP + ar_fp)); AR_FN=$((AR_FN + ar_fn))

  # Per-test metrics (precision/recall captured for verbose output, F1 used in results)
  # shellcheck disable=SC2034 # sc_p, sc_r, sg_p, sg_r, ar_p, ar_r used by read destructuring
  {
  read -r sc_p sc_r sc_f1 <<< "$(compute_metrics "$sc_tp" "$sc_fp" "$sc_fn")"
  read -r sg_p sg_r sg_f1 <<< "$(compute_metrics "$sg_tp" "$sg_fp" "$sg_fn")"
  read -r ar_p ar_r ar_f1 <<< "$(compute_metrics "$ar_tp" "$ar_fp" "$ar_fn")"
  }

  PER_TEST_RESULTS+=("$test_id|$test_cat|$sc_f1|$sg_f1|$ar_f1")

  if [ "$VERBOSE" = "true" ]; then
    log_info "  Solo Codex: TP=$sc_tp FP=$sc_fp FN=$sc_fn F1=$sc_f1"
    log_info "  Solo Gemini: TP=$sg_tp FP=$sg_fp FN=$sg_fn F1=$sg_f1"
    log_info "  Arena:       TP=$ar_tp FP=$ar_fp FN=$ar_fn F1=$ar_f1"
  fi

  rm -rf "$BENCH_TEMP"
done

# --- Compute aggregate metrics ---
read -r SC_P SC_R SC_F1 <<< "$(compute_metrics "$SC_TP" "$SC_FP" "$SC_FN")"
read -r SG_P SG_R SG_F1 <<< "$(compute_metrics "$SG_TP" "$SG_FP" "$SG_FN")"
read -r AR_P AR_R AR_F1 <<< "$(compute_metrics "$AR_TP" "$AR_FP" "$AR_FN")"

# --- Print summary ---
echo ""
echo "## Solo vs Arena Benchmark Results"
echo ""
echo "### Per-Test F1 Scores"
echo ""
echo "| Test Case | Category | Solo Codex F1 | Solo Gemini F1 | Arena F1 |"
echo "|-----------|----------|---------------|----------------|----------|"
for entry in "${PER_TEST_RESULTS[@]}"; do
  IFS='|' read -r tid tcat scf sgf arf <<< "$entry"
  echo "| $tid | $tcat | $scf | $sgf | $arf |"
done
echo ""
echo "### Aggregate Metrics"
echo ""
echo "| Model | TP | FP | FN | Precision | Recall | F1 |"
echo "|-------|----|----|----|-----------|---------|----|"
echo "| Solo Codex | $SC_TP | $SC_FP | $SC_FN | $SC_P | $SC_R | $SC_F1 |"
echo "| Solo Gemini | $SG_TP | $SG_FP | $SG_FN | $SG_P | $SG_R | $SG_F1 |"
echo "| **Arena** | **$AR_TP** | **$AR_FP** | **$AR_FN** | **$AR_P** | **$AR_R** | **$AR_F1** |"
echo ""

# --- Arena win count ---
ARENA_WINS=0
TOTAL_CATS=0
for entry in "${PER_TEST_RESULTS[@]}"; do
  IFS='|' read -r _ _ scf sgf arf <<< "$entry"
  TOTAL_CATS=$((TOTAL_CATS + 1))
  max_solo=$(echo "if ($scf > $sgf) $scf else $sgf" | bc || echo "0")
  if [ "$(echo "$arf >= $max_solo" | bc 2>/dev/null)" = "1" ]; then
    ARENA_WINS=$((ARENA_WINS + 1))
  fi
done

echo "Arena >= max(Solo) in $ARENA_WINS / $TOTAL_CATS test cases"
echo ""
echo "Results vary between runs due to LLM non-determinism."

# --- Save report ---
RESULTS_DIR="$PLUGIN_DIR/cache/evaluation-reports"
mkdir -p "$RESULTS_DIR"
REPORT_FILE="$RESULTS_DIR/solo-vs-arena-$(date +%Y%m%d-%H%M%S).json"

jq -n \
  --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson sc_tp "$SC_TP" --argjson sc_fp "$SC_FP" --argjson sc_fn "$SC_FN" --arg sc_f1 "$SC_F1" \
  --argjson sg_tp "$SG_TP" --argjson sg_fp "$SG_FP" --argjson sg_fn "$SG_FN" --arg sg_f1 "$SG_F1" \
  --argjson ar_tp "$AR_TP" --argjson ar_fp "$AR_FP" --argjson ar_fn "$AR_FN" --arg ar_f1 "$AR_F1" \
  '{
    timestamp: $timestamp,
    solo_codex: { tp: $sc_tp, fp: $sc_fp, fn: $sc_fn, f1: $sc_f1 },
    solo_gemini: { tp: $sg_tp, fp: $sg_fp, fn: $sg_fn, f1: $sg_f1 },
    arena: { tp: $ar_tp, fp: $ar_fp, fn: $ar_fn, f1: $ar_f1 }
  }' > "$REPORT_FILE"

log_info "Report saved: $REPORT_FILE"
exit 0
