#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Review Gate (Stop Hook Handler)
#
# Triggered by Claude Code Stop hook when Claude finishes a coding task.
# Evaluates the scope of uncommitted changes and auto-triggers cross-model
# review if the change exceeds configured thresholds.
#
# Inspired by Codex Plugin's Review Gate pattern:
#   Claude modifies code → Stop hook fires → review-gate evaluates scope
#   → threshold exceeded → cross-model review → feedback returned to Claude
#   → Claude resolves issues before truly stopping
#
# Usage: Invoked automatically by hooks/hooks.json Stop hook.
#        Reads JSON from stdin (Claude Code hook format).
#
# Config: config.review_gate (see default-config.json)
#
# Exit codes:
#   0 - Always (hooks must not block Claude workflow)
# =============================================================================

set -uo pipefail

# --- Constants ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# Project-specific session directory
_PROJECT_TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
_PROJECT_HASH=$(echo -n "$_PROJECT_TOPLEVEL" | shasum -a 256 | cut -c1-12)
SESSION_DIR="/tmp/ai-review-arena-${_PROJECT_HASH}"
COOLDOWN_FILE="${SESSION_DIR}/.review_gate_last_run"

mkdir -p "$SESSION_DIR" && chmod 700 "$SESSION_DIR"

# --- Source utils ---
if [ -f "$PLUGIN_DIR/scripts/utils.sh" ]; then
  source "$PLUGIN_DIR/scripts/utils.sh"
fi

# =============================================================================
# Config Loading
# =============================================================================

if command -v load_config &>/dev/null; then
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  CONFIG_FILE=$(load_config "$PROJECT_ROOT" 2>/dev/null) || CONFIG_FILE="${PLUGIN_DIR}/config/default-config.json"
else
  CONFIG_FILE="${PLUGIN_DIR}/config/default-config.json"
  project_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$project_root" ] && [ -f "$project_root/.ai-review-arena.json" ]; then
    CONFIG_FILE="$project_root/.ai-review-arena.json"
  elif [ -f "$HOME/.claude/.ai-review-arena.json" ]; then
    CONFIG_FILE="$HOME/.claude/.ai-review-arena.json"
  fi
fi

# --- Verify dependencies ---
if ! command -v jq &>/dev/null; then
  exit 0
fi

if [ ! -f "$CONFIG_FILE" ]; then
  exit 0
fi

# =============================================================================
# Read Config
# =============================================================================

_GATE_VALUES=$(jq -r '[
  (.review_gate.enabled // false),
  (.review_gate.min_files_changed // 2),
  (.review_gate.min_lines_changed // 20),
  (.review_gate.block_on_critical // true),
  (.review_gate.cooldown_seconds // 120)
] | @tsv' "$CONFIG_FILE") || _GATE_VALUES=""

if [ -z "$_GATE_VALUES" ]; then
  exit 0
fi

IFS=$'\t' read -r gate_enabled min_files min_lines block_critical cooldown_secs <<< "$_GATE_VALUES"

if [ "$gate_enabled" != "true" ]; then
  exit 0
fi

# =============================================================================
# Cooldown Check
# =============================================================================

NOW=$(date +%s)
if [ -f "$COOLDOWN_FILE" ]; then
  LAST_RUN=$(cat "$COOLDOWN_FILE" 2>/dev/null || echo "0")
  ELAPSED=$((NOW - LAST_RUN))
  if [ "$ELAPSED" -lt "$cooldown_secs" ]; then
    exit 0
  fi
fi

# =============================================================================
# Evaluate Change Scope
# =============================================================================

# Count uncommitted changed files (staged + unstaged, tracked only)
CHANGED_FILES=$(git diff --name-only HEAD 2>/dev/null || true)
STAGED_FILES=$(git diff --cached --name-only 2>/dev/null || true)

# Merge and deduplicate
ALL_CHANGED=$(printf '%s\n%s' "$CHANGED_FILES" "$STAGED_FILES" | sort -u | grep -v '^$' || true)
FILE_COUNT=$(echo "$ALL_CHANGED" | grep -c -v '^$' 2>/dev/null || echo "0")

if [ "$FILE_COUNT" -lt "$min_files" ]; then
  exit 0
fi

# Count total lines changed
LINES_CHANGED=$(git diff --stat HEAD 2>/dev/null | tail -1 | grep -oE '[0-9]+ insertion|[0-9]+ deletion' | grep -oE '[0-9]+' | paste -sd+ - | bc 2>/dev/null || echo "0")
if [ -z "$LINES_CHANGED" ] || [ "$LINES_CHANGED" = "0" ]; then
  # Fallback: count diff lines
  LINES_CHANGED=$(git diff HEAD 2>/dev/null | grep -c '^[+-]' 2>/dev/null || echo "0")
fi

if [ "$LINES_CHANGED" -lt "$min_lines" ]; then
  exit 0
fi

# =============================================================================
# Filter to Reviewable Files
# =============================================================================

# Allowed extensions from config
RAW_EXTENSIONS=$(jq -r '(.review.file_extensions[]? // empty)' "$CONFIG_FILE")
if [ -z "$RAW_EXTENSIONS" ]; then
  RAW_EXTENSIONS="ts tsx js jsx py go rs java kt swift rb php c cpp cs"
fi

REVIEWABLE_FILES=""
while IFS= read -r file; do
  [ -z "$file" ] && continue
  [ ! -f "$file" ] && continue
  FILE_EXT="${file##*.}"
  for ext in $RAW_EXTENSIONS; do
    ext_clean="${ext#.}"
    if [ "$FILE_EXT" = "$ext_clean" ]; then
      REVIEWABLE_FILES="${REVIEWABLE_FILES}${file}\n"
      break
    fi
  done
done <<< "$ALL_CHANGED"

REVIEWABLE_COUNT=$(printf '%b' "$REVIEWABLE_FILES" | grep -c -v '^$' 2>/dev/null || echo "0")
if [ "$REVIEWABLE_COUNT" -eq 0 ]; then
  exit 0
fi

# =============================================================================
# Update Cooldown Timestamp
# =============================================================================

echo "$NOW" > "$COOLDOWN_FILE"

# =============================================================================
# Launch Cross-Model Review
# =============================================================================

log_info "Review Gate triggered: ${REVIEWABLE_COUNT} files, ~${LINES_CHANGED} lines changed"

GATE_MODELS=$(jq -r '.review_gate.models[]? // empty' "$CONFIG_FILE")
GATE_ROLES=$(jq -r '.review_gate.roles[]? // empty' "$CONFIG_FILE")

if [ -z "$GATE_MODELS" ]; then
  GATE_MODELS="codex gemini"
fi
if [ -z "$GATE_ROLES" ]; then
  GATE_ROLES="security bugs"
fi

REVIEW_PIDS=()
FINDINGS_INDEX=0
MAX_FILE_SIZE=1048576

cleanup_reviews() {
  for pid in "${REVIEW_PIDS[@]+${REVIEW_PIDS[@]}}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap cleanup_reviews EXIT INT TERM

# Review each file with each model+role
while IFS= read -r review_file; do
  [ -z "$review_file" ] && continue
  [ ! -f "$review_file" ] && continue

  FILE_SIZE=$(wc -c < "$review_file" 2>/dev/null | tr -d ' ')
  if [ "${FILE_SIZE:-0}" -gt "$MAX_FILE_SIZE" ]; then
    continue
  fi

  FILE_CONTENT=$(cat "$review_file" 2>/dev/null) || continue
  [ -z "$FILE_CONTENT" ] && continue

  for model in $GATE_MODELS; do
    for role in $GATE_ROLES; do
      REVIEW_SCRIPT=""
      case "$model" in
        codex)
          if command -v codex &>/dev/null; then
            REVIEW_SCRIPT="$SCRIPT_DIR/codex-review.sh"
          fi
          ;;
        gemini)
          if command -v gemini &>/dev/null; then
            REVIEW_SCRIPT="$SCRIPT_DIR/gemini-review.sh"
          fi
          ;;
      esac

      if [ -z "$REVIEW_SCRIPT" ] || [ ! -f "$REVIEW_SCRIPT" ]; then
        continue
      fi

      FINDINGS_FILE="${SESSION_DIR}/gate_findings_${FINDINGS_INDEX}.json"
      FINDINGS_INDEX=$((FINDINGS_INDEX + 1))
      (
        echo "$FILE_CONTENT" | "$REVIEW_SCRIPT" "$review_file" "$CONFIG_FILE" "$role" > "$FINDINGS_FILE" 2>/dev/null
      ) &
      REVIEW_PIDS+=($!)
    done
  done
done < <(printf '%b' "$REVIEWABLE_FILES")

# --- Wait for all reviews ---
REVIEW_FAILURES=0
for pid in "${REVIEW_PIDS[@]+${REVIEW_PIDS[@]}}"; do
  if ! wait "$pid" 2>/dev/null; then
    REVIEW_FAILURES=$((REVIEW_FAILURES + 1))
  fi
done

if [ "${#REVIEW_PIDS[@]}" -eq 0 ]; then
  exit 0
fi

# =============================================================================
# Aggregate & Report
# =============================================================================

AGGREGATE_RESULT=""
if [ -f "$SCRIPT_DIR/aggregate-findings.sh" ]; then
  AGGREGATE_RESULT=$("$SCRIPT_DIR/aggregate-findings.sh" "$SESSION_DIR" "$CONFIG_FILE" \
    --prefix "gate_findings_" 2>&1) || AGGREGATE_RESULT=""
fi

# Clean up gate findings
rm -f "${SESSION_DIR}"/gate_findings_*.json 2>/dev/null

if [ -z "$AGGREGATE_RESULT" ] || [ "$AGGREGATE_RESULT" = "LGTM" ]; then
  log_info "Review Gate: LGTM — no issues found"
  exit 0
fi

# Count critical findings
CRITICAL_COUNT=0
if echo "$AGGREGATE_RESULT" | jq . &>/dev/null 2>&1; then
  CRITICAL_COUNT=$(echo "$AGGREGATE_RESULT" | jq '[.[] | select(.severity == "critical")] | length' 2>/dev/null || echo "0")
fi

# --- Generate report ---
REPORT=""
if [ -f "$SCRIPT_DIR/generate-report.sh" ]; then
  REPORT=$("$SCRIPT_DIR/generate-report.sh" <(echo "$AGGREGATE_RESULT") "$CONFIG_FILE" 2>&1) || REPORT=""
fi
[ -z "$REPORT" ] && REPORT="$AGGREGATE_RESULT"

# --- Determine language ---
LANG_CFG=$(jq -r '.output.language // "ko"' "$CONFIG_FILE")

if [ "$LANG_CFG" = "ko" ]; then
  GATE_PREFIX="Review Gate (${REVIEWABLE_COUNT}개 파일, ~${LINES_CHANGED}줄 변경):"
  if [ "$block_critical" = "true" ] && [ "$CRITICAL_COUNT" -gt 0 ]; then
    GATE_SUFFIX="CRITICAL 이슈 ${CRITICAL_COUNT}건이 발견되었습니다. 해결 후 진행해주세요."
  else
    GATE_SUFFIX="위 피드백을 참고하여 필요한 부분만 수정하세요."
  fi
else
  GATE_PREFIX="Review Gate (${REVIEWABLE_COUNT} files, ~${LINES_CHANGED} lines changed):"
  if [ "$block_critical" = "true" ] && [ "$CRITICAL_COUNT" -gt 0 ]; then
    GATE_SUFFIX="Found ${CRITICAL_COUNT} CRITICAL issue(s). Please resolve before proceeding."
  else
    GATE_SUFFIX="Review the above feedback and address relevant issues."
  fi
fi

# --- Build hook feedback ---
SHOULD_BLOCK="false"
if [ "$block_critical" = "true" ] && [ "$CRITICAL_COUNT" -gt 0 ]; then
  SHOULD_BLOCK="true"
fi

jq -n \
  --arg prefix "$GATE_PREFIX" \
  --arg report "$REPORT" \
  --arg suffix "$GATE_SUFFIX" \
  --argjson critical "$CRITICAL_COUNT" \
  --argjson block "$SHOULD_BLOCK" \
  '{
    hookSpecificOutput: {
      hookEventName: "Stop",
      review_gate: true,
      critical_count: $critical,
      decision: (if $block then "block" else "report" end),
      additionalContext: ($prefix + "\n" + $report + "\n\n" + $suffix)
    }
  }'

exit 0
