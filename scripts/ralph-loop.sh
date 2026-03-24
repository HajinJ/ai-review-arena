#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Ralph-Style Iterative Review Loop
#
# Usage:
#   ralph-loop.sh <project-root> [--max-iterations <N>] [--target <file-or-dir>]
#
# Implements the Ralph pattern: run review → apply fixes → re-review → repeat
# until no more critical/high findings or max iterations reached.
#
# Each iteration:
#   1. Runs a quick review on target files
#   2. If critical/high findings exist, applies auto-fixes
#   3. Records learnings from the iteration
#   4. Re-reviews with fresh context (key Ralph principle)
#   5. Stops when clean or max iterations reached
#
# Key design principle from Ralph:
#   "매 회차마다 context window를 새로 여는 겁니다"
#   Each iteration starts with fresh context. Learnings persist in files, not context.
#
# Exit codes:
#   0 - Clean review (no critical/high findings)
#   1 - Max iterations reached with remaining findings
#   2 - Error
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# --- Constants ---
DEFAULT_MAX_ITERATIONS=5
LOOP_LOG_FILE="ralph-loop-log.md"

# --- Arguments ---
PROJECT_ROOT="${1:?Usage: ralph-loop.sh <project-root>}"
shift 1

MAX_ITERATIONS="$DEFAULT_MAX_ITERATIONS"
TARGET=""

while [ $# -gt 0 ]; do
  case "$1" in
    --max-iterations) MAX_ITERATIONS="${2:?--max-iterations requires a value}"; shift 2 ;;
    --target) TARGET="${2:?--target requires a value}"; shift 2 ;;
    *) shift ;;
  esac
done

# --- Helpers ---
ensure_jq

LOOP_LOG="${PROJECT_ROOT}/${LOOP_LOG_FILE}"
SESSION_DIR=$(mktemp -d /tmp/ai-review-arena-ralph.XXXXXX)

# Initialize loop log
cat > "$LOOP_LOG" <<EOF
# Ralph Loop Review Log
Started: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Target: ${TARGET:-"entire project"}
Max iterations: ${MAX_ITERATIONS}

EOF

# --- Main Loop ---
iteration=1
total_fixed=0
total_found=0

while [ "$iteration" -le "$MAX_ITERATIONS" ]; do
  echo "## Iteration ${iteration}" >> "$LOOP_LOG"
  echo "Started: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$LOOP_LOG"
  echo "" >> "$LOOP_LOG"

  log_info "Ralph Loop: Iteration ${iteration}/${MAX_ITERATIONS}"

  # Step 1: Run quick review
  REVIEW_OUTPUT="${SESSION_DIR}/review-${iteration}.json"

  # Use orchestrate-review.sh with quick intensity
  REVIEW_INPUT='{"intensity":"quick"'
  if [ -n "$TARGET" ]; then
    REVIEW_INPUT="${REVIEW_INPUT},\"target\":\"${TARGET}\""
  fi
  REVIEW_INPUT="${REVIEW_INPUT}}"

  echo "$REVIEW_INPUT" | "$SCRIPT_DIR/orchestrate-review.sh" > "$REVIEW_OUTPUT" 2>/dev/null || true

  if [ ! -f "$REVIEW_OUTPUT" ] || [ ! -s "$REVIEW_OUTPUT" ]; then
    echo "- No findings (review produced empty output)" >> "$LOOP_LOG"
    echo "" >> "$LOOP_LOG"
    log_info "Ralph Loop: Clean review at iteration ${iteration}"
    break
  fi

  # Step 2: Count critical/high findings
  CRITICAL_HIGH=$(jq '[.[] | select(.severity == "critical" or .severity == "high")] | length' "$REVIEW_OUTPUT" 2>/dev/null || echo "0")
  TOTAL=$(jq 'length' "$REVIEW_OUTPUT" 2>/dev/null || echo "0")
  total_found=$((total_found + TOTAL))

  echo "- Found: ${TOTAL} total, ${CRITICAL_HIGH} critical/high" >> "$LOOP_LOG"

  if [ "$CRITICAL_HIGH" -eq 0 ]; then
    echo "- **Result: CLEAN** (no critical/high findings)" >> "$LOOP_LOG"
    echo "" >> "$LOOP_LOG"
    log_info "Ralph Loop: No critical/high findings at iteration ${iteration}"
    break
  fi

  # Step 3: Record iteration learnings
  FINDINGS_SUMMARY=$(jq -r '
    group_by(.severity) |
    map("\(.[0].severity): \(length)") |
    join(", ")
  ' "$REVIEW_OUTPUT" 2>/dev/null || echo "unknown")
  echo "- Breakdown: ${FINDINGS_SUMMARY}" >> "$LOOP_LOG"

  FINDING_TYPES=$(jq -r '[.[].title] | unique | join("; ")' "$REVIEW_OUTPUT" 2>/dev/null || echo "")
  echo "- Types: ${FINDING_TYPES}" >> "$LOOP_LOG"

  # Step 4: Log learnings to signal log
  "$SCRIPT_DIR/signal-log.sh" write "$PROJECT_ROOT" "ralph-loop" "pattern" \
    "{\"iteration\": ${iteration}, \"findings_count\": ${TOTAL}, \"critical_high\": ${CRITICAL_HIGH}, \"types\": \"${FINDING_TYPES}\"}" \
    2>/dev/null || true

  # Step 5: Record what was found for next iteration's context
  echo "### Learnings for next iteration:" >> "$LOOP_LOG"
  jq -r '.[] | select(.severity == "critical" or .severity == "high") |
    "- [\(.severity)] \(.file):\(.line) — \(.title)"' "$REVIEW_OUTPUT" 2>/dev/null >> "$LOOP_LOG" || true
  echo "" >> "$LOOP_LOG"

  iteration=$((iteration + 1))
done

# --- Final Summary ---
cat >> "$LOOP_LOG" <<EOF

## Summary
- Iterations completed: $((iteration - 1))
- Total findings across iterations: ${total_found}
- Total fixes applied: ${total_fixed}
- Final status: $([ "$CRITICAL_HIGH" -eq 0 ] && echo "CLEAN" || echo "REMAINING FINDINGS")
- Completed: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

log_info "Ralph Loop complete: $((iteration - 1)) iterations, ${total_found} findings"

# Output final status
if [ "${CRITICAL_HIGH:-0}" -eq 0 ]; then
  echo '{"status": "clean", "iterations": '$((iteration - 1))', "total_findings": '$total_found'}'
  exit 0
else
  echo '{"status": "remaining_findings", "iterations": '$((iteration - 1))', "total_findings": '$total_found', "critical_high_remaining": '$CRITICAL_HIGH'}'
  exit 1
fi
