#!/usr/bin/env bash
# =============================================================================
# E2E Test: Solo vs Arena Comparison
#
# Runs 1 test case (security-test-01) through Solo Codex, Solo Gemini,
# and Arena (both + aggregation). Asserts Arena F1 >= max(Solo).
# Gracefully skips if no CLIs are available.
# =============================================================================

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$TESTS_DIR/../scripts" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/utils.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

PASSED=0; FAILED=0; SKIPPED=0
pass() { printf "  ${GREEN}PASS${NC} %s\n" "$1"; PASSED=$((PASSED + 1)); }
fail() { printf "  ${RED}FAIL${NC} %s\n" "$1"; FAILED=$((FAILED + 1)); }
skip() { printf "  ${YELLOW}SKIP${NC} %s\n" "$1"; SKIPPED=$((SKIPPED + 1)); }

HAS_CODEX=false; HAS_GEMINI=false
command -v codex &>/dev/null && HAS_CODEX=true
command -v gemini &>/dev/null && HAS_GEMINI=true

if [ "$HAS_CODEX" != "true" ] && [ "$HAS_GEMINI" != "true" ]; then
  skip "No external CLIs available. Skipping Solo vs Arena E2E."
  echo ""; printf "  Total: 0 passed, 0 failed, 1 skipped\n"; exit 0
fi

# Need both CLIs for a meaningful comparison
if [ "$HAS_CODEX" != "true" ] || [ "$HAS_GEMINI" != "true" ]; then
  skip "Need both Codex and Gemini for Solo vs Arena comparison."
  echo ""; printf "  Total: 0 passed, 0 failed, 1 skipped\n"; exit 0
fi

TEST_FILE="$PLUGIN_DIR/config/benchmarks/security-test-01.json"
CONFIG_FILE="$PLUGIN_DIR/config/default-config.json"

if [ ! -f "$TEST_FILE" ]; then
  skip "security-test-01.json not found"; echo ""; exit 0
fi

BENCH_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/arena-e2e-solo-XXXXXX")
SESSION_DIR="$BENCH_TEMP/session"
mkdir -p "$SESSION_DIR"

CODE_FILE="$BENCH_TEMP/test-code.js"
jq -r '.code' "$TEST_FILE" > "$CODE_FILE"

# --- Helper: count matches and compute F1 ---
compute_f1_for() {
  local text="$1" actual_count="$2"
  local expected_count
  expected_count=$(jq '.ground_truth | length' "$TEST_FILE")
  local tp=0
  for i in $(seq 0 $((expected_count - 1))); do
    local keywords
    keywords=$(jq -r ".ground_truth[$i].description_contains[]?" "$TEST_FILE" 2>/dev/null)
    local found=false
    for keyword in $keywords; do
      if echo "$text" | grep -qi "$keyword" 2>/dev/null; then found=true; break; fi
    done
    [ "$found" = "true" ] && tp=$((tp + 1))
  done
  local fn=$((expected_count - tp))
  local fp=0; [ "$actual_count" -gt "$tp" ] && fp=$((actual_count - tp))
  local precision=0 recall=0 f1=0
  [ $((tp + fp)) -gt 0 ] && precision=$(echo "scale=3; $tp / ($tp + $fp)" | bc)
  [ $((tp + fn)) -gt 0 ] && recall=$(echo "scale=3; $tp / ($tp + $fn)" | bc)
  if [ "$(echo "$precision + $recall > 0" | bc)" = "1" ]; then
    f1=$(echo "scale=3; 2 * $precision * $recall / ($precision + $recall)" | bc)
  fi
  echo "$f1"
}

extract_text() {
  echo "$1" | tr -d '\000-\011\013-\037' | jq -r '
    if type == "array" then
      [.[] | (.title // ""), (.description // ""), (.suggestion // "")] | join(" ")
    elif type == "object" then
      [(.title // ""), (.description // ""), (.suggestion // "")] | join(" ")
    else . // "" end
  ' 2>/dev/null || echo "$1"
}

# --- Run Solo Codex ---
CODEX_RESULT=$(cat "$CODE_FILE" | "$SCRIPT_DIR/codex-review.sh" "$CODE_FILE" "$CONFIG_FILE" "security" 2>/dev/null) || CODEX_RESULT=""

# --- Run Solo Gemini ---
GEMINI_RESULT=$(cat "$CODE_FILE" | "$SCRIPT_DIR/gemini-review.sh" "$CODE_FILE" "$CONFIG_FILE" "security" 2>/dev/null) || GEMINI_RESULT=""

# --- Solo Codex F1 ---
CODEX_F1="0"
if [ -n "$CODEX_RESULT" ] && echo "$CODEX_RESULT" | jq . &>/dev/null; then
  ct=$(extract_text "$CODEX_RESULT")
  cc=$(echo "$CODEX_RESULT" | jq 'if type == "array" then length else 0 end' 2>/dev/null || echo 0)
  CODEX_F1=$(compute_f1_for "$ct" "$cc")
fi

# --- Solo Gemini F1 ---
GEMINI_F1="0"
if [ -n "$GEMINI_RESULT" ] && echo "$GEMINI_RESULT" | jq . &>/dev/null; then
  gt=$(extract_text "$GEMINI_RESULT")
  gc=$(echo "$GEMINI_RESULT" | jq 'if type == "array" then length else 0 end' 2>/dev/null || echo 0)
  GEMINI_F1=$(compute_f1_for "$gt" "$gc")
fi

# --- Arena (both + aggregation) ---
if [ -n "$CODEX_RESULT" ] && echo "$CODEX_RESULT" | jq . &>/dev/null; then
  echo "$CODEX_RESULT" > "$SESSION_DIR/findings_0.json"
fi
if [ -n "$GEMINI_RESULT" ] && echo "$GEMINI_RESULT" | jq . &>/dev/null; then
  echo "$GEMINI_RESULT" > "$SESSION_DIR/findings_1.json"
fi

AGG_RESULT=$("$SCRIPT_DIR/aggregate-findings.sh" "$SESSION_DIR" "$CONFIG_FILE" 2>/dev/null) || AGG_RESULT="[]"
[ "$AGG_RESULT" = "LGTM" ] && AGG_RESULT="[]"

at=$(extract_text "$AGG_RESULT")
ac=$(echo "$AGG_RESULT" | jq 'if type == "array" then length else 0 end' 2>/dev/null || echo 0)
ARENA_F1=$(compute_f1_for "$at" "$ac")

# --- Results ---
echo "  Solo Codex F1:  $CODEX_F1"
echo "  Solo Gemini F1: $GEMINI_F1"
echo "  Arena F1:       $ARENA_F1"

# Max of solo
MAX_SOLO=$(echo "if ($CODEX_F1 > $GEMINI_F1) $CODEX_F1 else $GEMINI_F1" | bc 2>/dev/null || echo "0")

if [ "$(echo "$ARENA_F1 >= $MAX_SOLO" | bc 2>/dev/null)" = "1" ]; then
  pass "Arena F1 ($ARENA_F1) >= max Solo ($MAX_SOLO)"
else
  fail "Arena F1 ($ARENA_F1) < max Solo ($MAX_SOLO)"
fi

rm -rf "$BENCH_TEMP"

echo ""
printf "  Total: %d passed, %d failed, %d skipped\n" "$PASSED" "$FAILED" "$SKIPPED"
[ "$FAILED" -gt 0 ] && exit 1
exit 0
