#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Main Orchestration Hook Entry Point
#
# Triggered by PostToolUse hook on Write|Edit|MultiEdit.
# Reads JSON input from stdin, accumulates changes in batch, and triggers
# parallel multi-model review when batch_size is reached.
#
# Exit codes:
#   0 - Always (hooks must not block Claude workflow)
# =============================================================================

set -uo pipefail

# --- Constants ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# Project-specific session directory (prevents cross-project state leakage)
_PROJECT_TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
_PROJECT_HASH=$(echo -n "$_PROJECT_TOPLEVEL" | shasum -a 256 | cut -c1-12)
SESSION_DIR="/tmp/ai-review-arena-${_PROJECT_HASH}"
PENDING_FILE="${SESSION_DIR}/pending-changes.txt"
COUNTER_FILE="${SESSION_DIR}/change-counter"
LOCK_FILE="${SESSION_DIR}/.lock"

# --- Ensure session directory (restrictive permissions on shared systems) ---
mkdir -p "$SESSION_DIR" && chmod 700 "$SESSION_DIR"

# --- Store commit hash for stale review detection (Code Factory pattern) ---
git rev-parse HEAD > "${SESSION_DIR}/.review_commit_hash" 2>/dev/null || true

# =============================================================================
# Config Loading
# =============================================================================

# Source utils for load_config (deep-merges default → global → project)
if [ -f "$PLUGIN_DIR/scripts/utils.sh" ]; then
  source "$PLUGIN_DIR/scripts/utils.sh"
fi

# Use load_config for proper 3-level merge; fallback to find_config_file for single file
if command -v load_config &>/dev/null; then
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  CONFIG_FILE=$(load_config "$PROJECT_ROOT" 2>/dev/null) || CONFIG_FILE="${PLUGIN_DIR}/config/default-config.json"
else
  # Fallback: find single config file (no merge)
  CONFIG_FILE="${PLUGIN_DIR}/config/default-config.json"
  project_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$project_root" ] && [ -f "$project_root/.ai-review-arena.json" ]; then
    CONFIG_FILE="$project_root/.ai-review-arena.json"
  elif [ -f "$HOME/.claude/.ai-review-arena.json" ]; then
    CONFIG_FILE="$HOME/.claude/.ai-review-arena.json"
  fi
fi

# --- Verify jq is available ---
if ! command -v jq &>/dev/null; then
  exit 0
fi

# --- Check config exists ---
if [ ! -f "$CONFIG_FILE" ]; then
  exit 0
fi

# =============================================================================
# Read Config Values (with environment variable overrides)
# =============================================================================

# Batch all config reads into a single jq call (was 7 separate invocations)
_CFG_VALUES=$(jq -r '[
  (.hook_mode.enabled // true),
  (.hook_mode.batch_size // 5),
  (.review.intensity // "standard"),
  (.review.max_file_lines // 500),
  (.hook_mode.min_lines_changed // 10),
  (.review.confidence_threshold // 75)
] | @tsv' "$CONFIG_FILE") || _CFG_VALUES=""

if [ -n "$_CFG_VALUES" ]; then
  IFS=$'\t' read -r _cfg_hook_enabled _cfg_batch _cfg_intensity _cfg_max_lines _cfg_min_lines _cfg_conf_threshold <<< "$_CFG_VALUES"
fi

hook_enabled="${MULTI_REVIEW_HOOK_ENABLED:-${_cfg_hook_enabled:-true}}"
if [ "$hook_enabled" != "true" ]; then
  exit 0
fi

BATCH_SIZE="${MULTI_REVIEW_BATCH_SIZE:-${_cfg_batch:-5}}"
# shellcheck disable=SC2034 # INTENSITY used by sourced scripts and phase logic
INTENSITY="${MULTI_REVIEW_INTENSITY:-${_cfg_intensity:-standard}}"
MAX_LINES="${_cfg_max_lines:-500}"
MIN_LINES="${_cfg_min_lines:-10}"
# shellcheck disable=SC2034 # CONFIDENCE_THRESHOLD used by downstream filtering
CONFIDENCE_THRESHOLD="${_cfg_conf_threshold:-75}"

# Allowed extensions: config stores without dots (e.g., "ts"), we add dots for matching
RAW_EXTENSIONS=$(jq -r '(.review.file_extensions[]? // empty)' "$CONFIG_FILE")
if [ -z "$RAW_EXTENSIONS" ]; then
  RAW_EXTENSIONS=$(jq -r '(.hook_mode.allowed_extensions[]? // empty)' "$CONFIG_FILE")
fi
if [ -z "$RAW_EXTENSIONS" ]; then
  ALLOWED_EXTENSIONS=".ts .tsx .js .jsx .py .go .rs .java .kt .swift .rb .php .c .cpp .cs"
else
  # Normalize: add dot prefix if missing
  ALLOWED_EXTENSIONS=""
  while IFS= read -r ext; do
    [ -z "$ext" ] && continue
    case "$ext" in
      .*) ALLOWED_EXTENSIONS="$ALLOWED_EXTENSIONS $ext" ;;
      *)  ALLOWED_EXTENSIONS="$ALLOWED_EXTENSIONS .$ext" ;;
    esac
  done <<< "$RAW_EXTENSIONS"
fi

# =============================================================================
# Read Hook Input (JSON from stdin)
# =============================================================================

HOOK_INPUT=$(cat)

if [ -z "$HOOK_INPUT" ]; then
  exit 0
fi

# Parse tool_name + file_path in a single jq call (was 2-7 separate calls)
_HOOK_PARSED=$(echo "$HOOK_INPUT" | jq -r '[
  (.tool_name // ""),
  (.tool_input.file_path // "")
] | @tsv') || _HOOK_PARSED=""

IFS=$'\t' read -r TOOL_NAME _TOOL_FILE_PATH <<< "$_HOOK_PARSED"

if [ -z "$TOOL_NAME" ]; then
  exit 0
fi

# =============================================================================
# Extract File Path Based on Tool Type
# =============================================================================

FILE_PATH="$_TOOL_FILE_PATH"
CHANGE_TYPE=""
CHANGE_DETAIL=""

case "$TOOL_NAME" in
  Write)
    CHANGE_TYPE="write"
    CONTENT=$(echo "$HOOK_INPUT" | jq -r '.tool_input.content // empty')
    if [ -n "$CONTENT" ]; then
      LINE_COUNT=$(echo "$CONTENT" | wc -l | tr -d ' ')
      if [ "$LINE_COUNT" -lt "$MIN_LINES" ]; then
        exit 0
      fi
      CHANGE_DETAIL=$(echo "$CONTENT" | head -n "$MAX_LINES")
    fi
    ;;
  Edit)
    CHANGE_TYPE="edit"
    _EDIT_PARSED=$(echo "$HOOK_INPUT" | jq -r '[(.tool_input.old_string // ""), (.tool_input.new_string // "")] | @tsv')
    IFS=$'\t' read -r OLD_STR NEW_STR <<< "$_EDIT_PARSED"
    CHANGE_DETAIL=$(printf "--- OLD ---\n%s\n--- NEW ---\n%s" "$OLD_STR" "$NEW_STR")
    ;;
  MultiEdit)
    CHANGE_TYPE="multiedit"
    EDITS=$(echo "$HOOK_INPUT" | jq -r '.tool_input.edits[]? | "--- OLD ---\n" + .old_string + "\n--- NEW ---\n" + .new_string')
    CHANGE_DETAIL="$EDITS"
    ;;
  *)
    exit 0
    ;;
esac

# --- Validate file path ---
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

if [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# --- Check file extension ---
FILE_EXT=""
case "$FILE_PATH" in
  *.*) FILE_EXT=".${FILE_PATH##*.}" ;;
esac

if [ -z "$FILE_EXT" ]; then
  exit 0
fi

ext_allowed=false
for ext in $ALLOWED_EXTENSIONS; do
  if [ "$FILE_EXT" = "$ext" ]; then
    ext_allowed=true
    break
  fi
done

if [ "$ext_allowed" != "true" ]; then
  exit 0
fi

# =============================================================================
# Batch Accumulation
# =============================================================================

# Initialize counter if not exists
if [ ! -f "$COUNTER_FILE" ]; then
  echo "0" > "$COUNTER_FILE"
fi

# Atomic batch accumulation with flock (prevents race condition on rapid edits)
# Uses portable mkdir-based lock as fallback if flock unavailable
_arena_lock() {
  if command -v flock &>/dev/null; then
    exec 200>"$LOCK_FILE"
    flock -n 200 || return 1
  else
    mkdir "${LOCK_FILE}.d" 2>/dev/null || return 1
    trap 'rmdir "${LOCK_FILE}.d" 2>/dev/null' EXIT
  fi
}

_arena_unlock() {
  if command -v flock &>/dev/null; then
    exec 200>&-
  else
    rmdir "${LOCK_FILE}.d" 2>/dev/null || true
  fi
}

if ! _arena_lock; then
  # Another hook instance is running — skip this invocation
  exit 0
fi

# Append change to pending file
{
  echo "===CHANGE_START==="
  echo "FILE:${FILE_PATH}"
  echo "TYPE:${CHANGE_TYPE}"
  echo "TIMESTAMP:$(date +%s)"
  echo "---DETAIL---"
  echo "$CHANGE_DETAIL"
  echo "===CHANGE_END==="
} >> "$PENDING_FILE"

# Increment counter (now atomic under lock)
CURRENT_COUNT=$(cat "$COUNTER_FILE" || echo "0")
CURRENT_COUNT=$((CURRENT_COUNT + 1))
echo "$CURRENT_COUNT" > "$COUNTER_FILE"

# --- Check if batch is full ---
if [ "$CURRENT_COUNT" -lt "$BATCH_SIZE" ]; then
  _arena_unlock
  exit 0
fi

# =============================================================================
# Trigger Review (batch_size reached)
# =============================================================================

# Read all pending changes
PENDING_CHANGES=""
if [ -f "$PENDING_FILE" ]; then
  PENDING_CHANGES=$(cat "$PENDING_FILE")
fi

# Reset counter and pending file
echo "0" > "$COUNTER_FILE"
: > "$PENDING_FILE"

if [ -z "$PENDING_CHANGES" ]; then
  exit 0
fi

# --- Collect unique files from pending changes ---
CHANGED_FILES=$(echo "$PENDING_CHANGES" | grep '^FILE:' | sed 's/^FILE://' | sort -u)

if [ -z "$CHANGED_FILES" ]; then
  exit 0
fi

# =============================================================================
# Fallback Level Tracking
# =============================================================================
# L0: Full normal operation
# L1: Benchmark failure → default role assignment
# L2: Research failure → proceed without context
# L3: Agent Teams failure → switch to subagents
# L4: External CLI failure → Claude only
# L5: All failure → inline analysis
FALLBACK_LEVEL=0

# =============================================================================
# Model Configuration
# =============================================================================

# Codex
codex_enabled="${MULTI_REVIEW_CODEX_ENABLED:-$(jq -r '.models.codex.enabled // false' "$CONFIG_FILE")}"
codex_roles=""
if [ "$codex_enabled" = "true" ]; then
  codex_roles=$(jq -r '.models.codex.roles[]? // empty' "$CONFIG_FILE")
fi

# Gemini
gemini_enabled="${MULTI_REVIEW_GEMINI_ENABLED:-$(jq -r '.models.gemini.enabled // false' "$CONFIG_FILE")}"
gemini_roles=""
if [ "$gemini_enabled" = "true" ]; then
  gemini_roles=$(jq -r '.models.gemini.roles[]? // empty' "$CONFIG_FILE")
fi

# If no models enabled, skip
if [ "$codex_enabled" != "true" ] && [ "$gemini_enabled" != "true" ]; then
  exit 0
fi

# =============================================================================
# Launch Parallel Reviews
# =============================================================================

REVIEW_PIDS=()
FINDINGS_INDEX=0
MAX_FILE_SIZE=1048576  # 1MB — skip files larger than this
MAX_PARALLEL=8  # Cap concurrent review processes to prevent resource exhaustion

# Cleanup trap: kill background review processes on interruption
cleanup_reviews() {
  for pid in "${REVIEW_PIDS[@]+${REVIEW_PIDS[@]}}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap cleanup_reviews EXIT INT TERM

# Throttle: wait until running process count drops below MAX_PARALLEL
_throttle_parallel() {
  while [ ${#REVIEW_PIDS[@]} -ge "$MAX_PARALLEL" ]; do
    local new_pids=()
    for pid in "${REVIEW_PIDS[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        new_pids+=("$pid")
      fi
    done
    REVIEW_PIDS=("${new_pids[@]+${new_pids[@]}}")
    if [ ${#REVIEW_PIDS[@]} -ge "$MAX_PARALLEL" ]; then
      sleep 0.5
    fi
  done
}

# For each changed file, launch reviews with each enabled model+role
while IFS= read -r changed_file; do
  [ -z "$changed_file" ] && continue
  [ ! -f "$changed_file" ] && continue

  # Skip files exceeding size limit (prevents OOM on large files)
  FILE_SIZE=$(wc -c < "$changed_file" 2>/dev/null | tr -d ' ')
  if [ "${FILE_SIZE:-0}" -gt "$MAX_FILE_SIZE" ]; then
    continue
  fi

  FILE_CONTENT=$(cat "$changed_file" 2>/dev/null) || continue
  if [ -z "$FILE_CONTENT" ]; then
    continue
  fi

  # Launch codex reviews (throttled to MAX_PARALLEL)
  if [ "$codex_enabled" = "true" ] && [ -n "$codex_roles" ]; then
    while IFS= read -r role; do
      [ -z "$role" ] && continue
      _throttle_parallel
      FINDINGS_FILE="${SESSION_DIR}/findings_${FINDINGS_INDEX}.json"
      FINDINGS_INDEX=$((FINDINGS_INDEX + 1))
      (
        _cli_err=$(mktemp)
        echo "$FILE_CONTENT" | "$SCRIPT_DIR/codex-review.sh" "$changed_file" "$CONFIG_FILE" "$role" > "$FINDINGS_FILE" 2>"$_cli_err"
        log_stderr_file "orchestrate(codex:$role)" "$_cli_err"
      ) &
      REVIEW_PIDS+=($!)
    done <<< "$codex_roles"
  fi

  # Launch gemini reviews (throttled to MAX_PARALLEL)
  if [ "$gemini_enabled" = "true" ] && [ -n "$gemini_roles" ]; then
    while IFS= read -r role; do
      [ -z "$role" ] && continue
      _throttle_parallel
      FINDINGS_FILE="${SESSION_DIR}/findings_${FINDINGS_INDEX}.json"
      FINDINGS_INDEX=$((FINDINGS_INDEX + 1))
      (
        _cli_err=$(mktemp)
        echo "$FILE_CONTENT" | "$SCRIPT_DIR/gemini-review.sh" "$changed_file" "$CONFIG_FILE" "$role" > "$FINDINGS_FILE" 2>"$_cli_err"
        log_stderr_file "orchestrate(gemini:$role)" "$_cli_err"
      ) &
      REVIEW_PIDS+=($!)
    done <<< "$gemini_roles"
  fi
done <<< "$CHANGED_FILES"

# --- Wait for all reviews to complete ---
REVIEW_FAILURES=0
for pid in "${REVIEW_PIDS[@]}"; do
  if ! wait "$pid" 2>/dev/null; then
    REVIEW_FAILURES=$((REVIEW_FAILURES + 1))
  fi
done

# Track external CLI failures
if [ "$REVIEW_FAILURES" -gt 0 ] && [ "$REVIEW_FAILURES" -eq "${#REVIEW_PIDS[@]}" ]; then
  # All external CLI reviews failed
  FALLBACK_LEVEL=4
  log_warn "All external CLI reviews failed (${REVIEW_FAILURES}/${#REVIEW_PIDS[@]}), fallback level: L${FALLBACK_LEVEL}"
elif [ "$REVIEW_FAILURES" -gt 0 ]; then
  log_warn "Some external CLI reviews failed (${REVIEW_FAILURES}/${#REVIEW_PIDS[@]})"
fi

# =============================================================================
# Aggregate Findings
# =============================================================================

AGGREGATE_RESULT=""
if ! AGGREGATE_RESULT=$("$SCRIPT_DIR/aggregate-findings.sh" "$SESSION_DIR" "$CONFIG_FILE" 2>&1); then
  log_warn "Aggregation failed: ${AGGREGATE_RESULT:0:200}"
  AGGREGATE_RESULT=""
  [ "$FALLBACK_LEVEL" -lt 5 ] && FALLBACK_LEVEL=5
fi

# --- Clean up findings files ---
rm -f "${SESSION_DIR}"/findings_*.json 2>/dev/null

# --- Check if LGTM (no issues) ---
if [ -z "$AGGREGATE_RESULT" ] || [ "$AGGREGATE_RESULT" = "LGTM" ]; then
  exit 0
fi

# --- Count findings ---
FINDING_COUNT=0
if echo "$AGGREGATE_RESULT" | jq . &>/dev/null 2>&1; then
  FINDING_COUNT=$(echo "$AGGREGATE_RESULT" | jq 'length' || echo "0")
fi

if [ "$FINDING_COUNT" -eq 0 ]; then
  exit 0
fi

# =============================================================================
# Format Output for Hook Feedback
# =============================================================================

# Generate report
REPORT=""
if ! REPORT=$("$SCRIPT_DIR/generate-report.sh" <(echo "$AGGREGATE_RESULT") "$CONFIG_FILE" 2>&1); then
  log_warn "Report generation failed: ${REPORT:0:200}"
  REPORT=""
fi

if [ -z "$REPORT" ]; then
  REPORT="$AGGREGATE_RESULT"
fi

# Determine language for feedback message
LANG_CFG=$(jq -r '.output.language // "ko"' "$CONFIG_FILE")

if [ "$LANG_CFG" = "ko" ]; then
  FEEDBACK_PREFIX="AI Review Arena (${BATCH_SIZE}건 일괄 리뷰):"
  FEEDBACK_SUFFIX="위 피드백은 최근 코드 변경에 대한 리뷰입니다. 현재 작업과 직접 관련된 이슈만 반영하세요."
else
  FEEDBACK_PREFIX="AI Review Arena (batch of ${BATCH_SIZE} changes):"
  FEEDBACK_SUFFIX="The above feedback is a review of recent code changes. Only address issues directly related to your current task."
fi

# Build hook feedback JSON safely using jq (avoids string interpolation injection)
# Include fallback_level in output so consumers know degradation state
jq -n \
  --arg prefix "$FEEDBACK_PREFIX" \
  --arg report "$REPORT" \
  --arg suffix "$FEEDBACK_SUFFIX" \
  --argjson fallback_level "$FALLBACK_LEVEL" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", fallback_level: $fallback_level, additionalContext: ($prefix + "\n" + $report + "\n\n" + $suffix)}}'

exit 0
