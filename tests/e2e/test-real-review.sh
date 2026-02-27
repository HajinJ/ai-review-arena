#!/usr/bin/env bash
# =============================================================================
# E2E Test: Real CLI Review
#
# Runs security-test-01 through actual Codex/Gemini CLIs and asserts F1 > 0.5.
# Gracefully skips if no CLIs are available.
# =============================================================================

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$TESTS_DIR/../scripts" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/utils.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

PASSED=0
FAILED=0
SKIPPED=0

pass() { printf "  ${GREEN}PASS${NC} %s\n" "$1"; PASSED=$((PASSED + 1)); }
fail() { printf "  ${RED}FAIL${NC} %s\n" "$1"; FAILED=$((FAILED + 1)); }
skip() { printf "  ${YELLOW}SKIP${NC} %s\n" "$1"; SKIPPED=$((SKIPPED + 1)); }

# --- Check CLI availability ---
HAS_CODEX=false
HAS_GEMINI=false
command -v codex &>/dev/null && HAS_CODEX=true
command -v gemini &>/dev/null && HAS_GEMINI=true

if [ "$HAS_CODEX" != "true" ] && [ "$HAS_GEMINI" != "true" ]; then
  skip "No external CLIs available (codex/gemini). Skipping E2E tests."
  echo ""
  printf "  Total: 0 passed, 0 failed, 1 skipped\n"
  exit 0
fi

# --- Test: Real review on security-test-01 ---
TEST_FILE="$PLUGIN_DIR/config/benchmarks/security-test-01.json"
CONFIG_FILE="$PLUGIN_DIR/config/default-config.json"

if [ ! -f "$TEST_FILE" ]; then
  skip "security-test-01.json not found"
else
  BENCH_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/arena-e2e-XXXXXX")
  SESSION_DIR="$BENCH_TEMP/session"
  mkdir -p "$SESSION_DIR"

  CODE_FILE="$BENCH_TEMP/test-code.js"
  jq -r '.code' "$TEST_FILE" > "$CODE_FILE"

  # Run reviews
  PIDS=()
  if [ "$HAS_CODEX" = "true" ]; then
    (cat "$CODE_FILE" | "$SCRIPT_DIR/codex-review.sh" "$CODE_FILE" "$CONFIG_FILE" "security" > "$SESSION_DIR/findings_0.json" 2>/dev/null) &
    PIDS+=($!)
  fi
  if [ "$HAS_GEMINI" = "true" ]; then
    (cat "$CODE_FILE" | "$SCRIPT_DIR/gemini-review.sh" "$CODE_FILE" "$CONFIG_FILE" "security" > "$SESSION_DIR/findings_1.json" 2>/dev/null) &
    PIDS+=($!)
  fi

  for pid in "${PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  # Aggregate
  AGG_RESULT=$("$SCRIPT_DIR/aggregate-findings.sh" "$SESSION_DIR" "$CONFIG_FILE" 2>/dev/null) || AGG_RESULT="[]"
  [ "$AGG_RESULT" = "LGTM" ] && AGG_RESULT="[]"

  # Calculate F1
  expected_count=$(jq '.ground_truth | length' "$TEST_FILE")
  AGG_TEXT=$(echo "$AGG_RESULT" | tr -d '\000-\011\013-\037' | jq -r '
    if type == "array" then
      [.[] | (.title // ""), (.description // ""), (.suggestion // "")] | join(" ")
    else "" end
  ' 2>/dev/null || echo "")

  tp=0
  for i in $(seq 0 $((expected_count - 1))); do
    keywords=$(jq -r ".ground_truth[$i].description_contains[]?" "$TEST_FILE" 2>/dev/null)
    found=false
    for keyword in $keywords; do
      if echo "$AGG_TEXT" | grep -qi "$keyword" 2>/dev/null; then
        found=true; break
      fi
    done
    [ "$found" = "true" ] && tp=$((tp + 1))
  done
  fn=$((expected_count - tp))
  actual_count=$(echo "$AGG_RESULT" | jq 'if type == "array" then length else 0 end' 2>/dev/null || echo 0)
  fp=0; [ "$actual_count" -gt "$tp" ] && fp=$((actual_count - tp))

  precision=0; recall=0; f1=0
  [ $((tp + fp)) -gt 0 ] && precision=$(echo "scale=3; $tp / ($tp + $fp)" | bc)
  [ $((tp + fn)) -gt 0 ] && recall=$(echo "scale=3; $tp / ($tp + $fn)" | bc)
  if [ "$(echo "$precision + $recall > 0" | bc)" = "1" ]; then
    f1=$(echo "scale=3; 2 * $precision * $recall / ($precision + $recall)" | bc)
  fi

  # Assert F1 > 0.5
  if [ "$(echo "$f1 > 0.5" | bc)" = "1" ]; then
    pass "Real review F1=$f1 > 0.5 (TP=$tp, FP=$fp, FN=$fn)"
  else
    fail "Real review F1=$f1 <= 0.5 (TP=$tp, FP=$fp, FN=$fn)"
  fi

  rm -rf "$BENCH_TEMP"
fi

# --- Summary ---
echo ""
printf "  Total: %d passed, %d failed, %d skipped\n" "$PASSED" "$FAILED" "$SKIPPED"
[ "$FAILED" -gt 0 ] && exit 1
exit 0
