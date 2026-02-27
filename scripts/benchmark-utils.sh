#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Benchmark Utility Functions
#
# Shared scoring/matching logic used by benchmark scripts:
#   - run-benchmark.sh
#   - benchmark-models.sh
#   - benchmark-business-models.sh
#
# Source this file after utils.sh:
#   source "$SCRIPT_DIR/utils.sh"
#   source "$SCRIPT_DIR/benchmark-utils.sh"
#
# Functions:
#   extract_text       - Extract readable text from findings JSON
#   count_matches      - Count ground truth keyword matches in text
#   compute_metrics    - Calculate precision/recall/F1 from TP/FP/FN
# =============================================================================

# Guard against double-sourcing
if [ "${_ARENA_BENCHMARK_UTILS_LOADED:-}" = "true" ]; then
  return 0 2>/dev/null || true
fi
_ARENA_BENCHMARK_UTILS_LOADED="true"

BENCH_UTILS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$BENCH_UTILS_SCRIPT_DIR/utils.sh"

# =============================================================================
# extract_text - Extract readable text from findings JSON
#
# Reads a JSON array of finding objects and concatenates their title,
# description, and suggestion fields into a single searchable string.
# Control characters are stripped to avoid matching issues.
#
# Usage:
#   text=$(extract_text "$findings_json")
#
# Arguments:
#   $1 - JSON string (array of finding objects with title/description/suggestion)
#
# Output:
#   Concatenated text string on stdout
# =============================================================================
extract_text() {
  local findings_json="$1"
  echo "$findings_json" | tr -d '\000-\011\013-\037' | jq -r '
    if type == "array" then
      [.[] | (.title // ""), (.description // ""), (.suggestion // "")] | join(" ")
    else "" end
  ' || echo ""
}

# =============================================================================
# count_matches - Count ground truth keyword matches in text
#
# For each ground truth item in a test case, checks whether any of the
# keywords from description_contains appear in the provided text (case-
# insensitive grep). Returns the count of matched and missed ground truth
# items.
#
# Usage:
#   read -r tp fn <<< "$(count_matches "$text" "$test_file" "$expected_count" "$verbose")"
#
# Arguments:
#   $1 - Text to search (output of extract_text)
#   $2 - Path to the test case JSON file
#   $3 - Number of ground truth items (expected_count)
#   $4 - (optional) "true" for verbose output logging misses
#
# Output:
#   "tp fn" (space-separated) on stdout
# =============================================================================
count_matches() {
  local agg_text="$1"
  local test_file="$2"
  local expected_count="$3"
  local verbose="${4:-false}"

  local tp=0
  local fn=0

  local i
  for i in $(seq 0 $((expected_count - 1))); do
    local keywords
    keywords=$(jq -r ".ground_truth[$i].description_contains[]?" "$test_file" 2>/dev/null)
    local found=false
    if [ -n "$keywords" ]; then
      local keyword
      for keyword in $keywords; do
        if echo "$agg_text" | grep -qi "$keyword" 2>/dev/null; then
          found=true
          break
        fi
      done
    fi
    if [ "$found" = "true" ]; then
      tp=$((tp + 1))
    else
      fn=$((fn + 1))
      if [ "$verbose" = "true" ]; then
        local gt_type
        gt_type=$(jq -r ".ground_truth[$i].type" "$test_file")
        log_info "  MISS: $gt_type"
      fi
    fi
  done

  echo "$tp $fn"
}

# =============================================================================
# compute_metrics - Calculate precision, recall, and F1 from TP/FP/FN
#
# Uses bc for floating-point arithmetic. Falls back to integer arithmetic
# if bc is not available.
#
# Usage:
#   read -r precision recall f1 <<< "$(compute_metrics "$tp" "$fp" "$fn")"
#
# Arguments:
#   $1 - True positives (tp)
#   $2 - False positives (fp)
#   $3 - False negatives (fn)
#
# Output:
#   "precision recall f1" (space-separated) on stdout, scale=3
# =============================================================================
compute_metrics() {
  local tp="$1"
  local fp="$2"
  local fn="$3"

  local precision=0
  local recall=0
  local f1=0

  if command -v bc &>/dev/null; then
    [ $((tp + fp)) -gt 0 ] && precision=$(echo "scale=3; $tp / ($tp + $fp)" | bc)
    [ $((tp + fn)) -gt 0 ] && recall=$(echo "scale=3; $tp / ($tp + $fn)" | bc)
    if [ "$(echo "$precision + $recall > 0" | bc)" = "1" ]; then
      f1=$(echo "scale=3; 2 * $precision * $recall / ($precision + $recall)" | bc)
    fi
  else
    # Integer fallback (0-100 scale)
    [ $((tp + fp)) -gt 0 ] && precision=$((tp * 1000 / (tp + fp)))
    [ $((tp + fn)) -gt 0 ] && recall=$((tp * 1000 / (tp + fn)))
    if [ $((precision + recall)) -gt 0 ]; then
      f1=$((2 * precision * recall / (precision + recall)))
    fi
  fi

  echo "$precision $recall $f1"
}
