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
SESSION_DIR="/tmp/ai-review-arena"
PENDING_FILE="${SESSION_DIR}/pending-changes.txt"
COUNTER_FILE="${SESSION_DIR}/change-counter"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# --- Ensure session directory ---
mkdir -p "$SESSION_DIR"

# --- Store commit hash for stale review detection (Code Factory pattern) ---
git rev-parse HEAD > "${SESSION_DIR}/.review_commit_hash" 2>/dev/null || true

# =============================================================================
# Config Loading
# =============================================================================

find_config() {
  # Check project root first
  local project_config
  project_config=$(git rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$project_config" ] && [ -f "$project_config/.ai-review-arena.json" ]; then
    echo "$project_config/.ai-review-arena.json"
    return
  fi
  # Check ~/.claude/
  if [ -f "$HOME/.claude/.ai-review-arena.json" ]; then
    echo "$HOME/.claude/.ai-review-arena.json"
    return
  fi
  # Use default
  echo "${PLUGIN_DIR}/config/default-config.json"
}

CONFIG_FILE="$(find_config)"

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

hook_enabled="${MULTI_REVIEW_HOOK_ENABLED:-$(jq -r '.hook_mode.enabled // true' "$CONFIG_FILE" 2>/dev/null)}"
if [ "$hook_enabled" != "true" ]; then
  exit 0
fi

BATCH_SIZE="${MULTI_REVIEW_BATCH_SIZE:-$(jq -r '.hook_mode.batch_size // 5' "$CONFIG_FILE" 2>/dev/null)}"
INTENSITY="${MULTI_REVIEW_INTENSITY:-$(jq -r '.review.intensity // "standard"' "$CONFIG_FILE" 2>/dev/null)}"
MAX_LINES=$(jq -r '.review.max_file_lines // 500' "$CONFIG_FILE" 2>/dev/null)
MIN_LINES=$(jq -r '.hook_mode.min_lines_changed // 10' "$CONFIG_FILE" 2>/dev/null)
CONFIDENCE_THRESHOLD=$(jq -r '.review.confidence_threshold // 75' "$CONFIG_FILE" 2>/dev/null)

# Allowed extensions: config stores without dots (e.g., "ts"), we add dots for matching
# Try review.file_extensions first, then hook_mode.allowed_extensions for backward compat
RAW_EXTENSIONS=$(jq -r '(.review.file_extensions[]? // empty)' "$CONFIG_FILE" 2>/dev/null)
if [ -z "$RAW_EXTENSIONS" ]; then
  RAW_EXTENSIONS=$(jq -r '(.hook_mode.allowed_extensions[]? // empty)' "$CONFIG_FILE" 2>/dev/null)
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

TOOL_NAME=$(echo "$HOOK_INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
TOOL_INPUT=$(echo "$HOOK_INPUT" | jq -r '.tool_input // empty' 2>/dev/null)

if [ -z "$TOOL_NAME" ] || [ -z "$TOOL_INPUT" ]; then
  exit 0
fi

# =============================================================================
# Extract File Path Based on Tool Type
# =============================================================================

FILE_PATH=""
CHANGE_TYPE=""
CHANGE_DETAIL=""

case "$TOOL_NAME" in
  Write)
    FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty' 2>/dev/null)
    CHANGE_TYPE="write"
    # Extract content (max MAX_LINES lines)
    CONTENT=$(echo "$TOOL_INPUT" | jq -r '.content // empty' 2>/dev/null)
    if [ -n "$CONTENT" ]; then
      LINE_COUNT=$(echo "$CONTENT" | wc -l | tr -d ' ')
      if [ "$LINE_COUNT" -lt "$MIN_LINES" ]; then
        exit 0
      fi
      CHANGE_DETAIL=$(echo "$CONTENT" | head -n "$MAX_LINES")
    fi
    ;;
  Edit)
    FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty' 2>/dev/null)
    CHANGE_TYPE="edit"
    OLD_STR=$(echo "$TOOL_INPUT" | jq -r '.old_string // empty' 2>/dev/null)
    NEW_STR=$(echo "$TOOL_INPUT" | jq -r '.new_string // empty' 2>/dev/null)
    CHANGE_DETAIL=$(printf "--- OLD ---\n%s\n--- NEW ---\n%s" "$OLD_STR" "$NEW_STR")
    ;;
  MultiEdit)
    FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty' 2>/dev/null)
    CHANGE_TYPE="multiedit"
    # Extract all edits
    EDITS=$(echo "$TOOL_INPUT" | jq -r '.edits[]? | "--- OLD ---\n" + .old_string + "\n--- NEW ---\n" + .new_string' 2>/dev/null)
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

# Increment counter
CURRENT_COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
CURRENT_COUNT=$((CURRENT_COUNT + 1))
echo "$CURRENT_COUNT" > "$COUNTER_FILE"

# --- Check if batch is full ---
if [ "$CURRENT_COUNT" -lt "$BATCH_SIZE" ]; then
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
# Model Configuration
# =============================================================================

# Codex
codex_enabled="${MULTI_REVIEW_CODEX_ENABLED:-$(jq -r '.models.codex.enabled // false' "$CONFIG_FILE" 2>/dev/null)}"
codex_roles=""
if [ "$codex_enabled" = "true" ]; then
  codex_roles=$(jq -r '.models.codex.roles[]? // empty' "$CONFIG_FILE" 2>/dev/null)
fi

# Gemini
gemini_enabled="${MULTI_REVIEW_GEMINI_ENABLED:-$(jq -r '.models.gemini.enabled // false' "$CONFIG_FILE" 2>/dev/null)}"
gemini_roles=""
if [ "$gemini_enabled" = "true" ]; then
  gemini_roles=$(jq -r '.models.gemini.roles[]? // empty' "$CONFIG_FILE" 2>/dev/null)
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

# For each changed file, launch reviews with each enabled model+role
while IFS= read -r changed_file; do
  [ -z "$changed_file" ] && continue
  [ ! -f "$changed_file" ] && continue

  FILE_CONTENT=$(cat "$changed_file" 2>/dev/null) || continue
  if [ -z "$FILE_CONTENT" ]; then
    continue
  fi

  # Launch codex reviews
  if [ "$codex_enabled" = "true" ] && [ -n "$codex_roles" ]; then
    while IFS= read -r role; do
      [ -z "$role" ] && continue
      FINDINGS_FILE="${SESSION_DIR}/findings_${FINDINGS_INDEX}.json"
      FINDINGS_INDEX=$((FINDINGS_INDEX + 1))
      (
        echo "$FILE_CONTENT" | "$SCRIPT_DIR/codex-review.sh" "$changed_file" "$CONFIG_FILE" "$role" > "$FINDINGS_FILE" 2>/dev/null
      ) &
      REVIEW_PIDS+=($!)
    done <<< "$codex_roles"
  fi

  # Launch gemini reviews
  if [ "$gemini_enabled" = "true" ] && [ -n "$gemini_roles" ]; then
    while IFS= read -r role; do
      [ -z "$role" ] && continue
      FINDINGS_FILE="${SESSION_DIR}/findings_${FINDINGS_INDEX}.json"
      FINDINGS_INDEX=$((FINDINGS_INDEX + 1))
      (
        echo "$FILE_CONTENT" | "$SCRIPT_DIR/gemini-review.sh" "$changed_file" "$CONFIG_FILE" "$role" > "$FINDINGS_FILE" 2>/dev/null
      ) &
      REVIEW_PIDS+=($!)
    done <<< "$gemini_roles"
  fi
done <<< "$CHANGED_FILES"

# --- Wait for all reviews to complete ---
for pid in "${REVIEW_PIDS[@]}"; do
  wait "$pid" 2>/dev/null || true
done

# =============================================================================
# Aggregate Findings
# =============================================================================

AGGREGATE_RESULT=""
AGGREGATE_RESULT=$("$SCRIPT_DIR/aggregate-findings.sh" "$SESSION_DIR" "$CONFIG_FILE" 2>/dev/null) || true

# --- Clean up findings files ---
rm -f "${SESSION_DIR}"/findings_*.json 2>/dev/null

# --- Check if LGTM (no issues) ---
if [ -z "$AGGREGATE_RESULT" ] || [ "$AGGREGATE_RESULT" = "LGTM" ]; then
  exit 0
fi

# --- Count findings ---
FINDING_COUNT=0
if echo "$AGGREGATE_RESULT" | jq . &>/dev/null 2>&1; then
  FINDING_COUNT=$(echo "$AGGREGATE_RESULT" | jq 'length' 2>/dev/null || echo "0")
fi

if [ "$FINDING_COUNT" -eq 0 ]; then
  exit 0
fi

# =============================================================================
# Format Output for Hook Feedback
# =============================================================================

# Generate report
REPORT=""
REPORT=$("$SCRIPT_DIR/generate-report.sh" <(echo "$AGGREGATE_RESULT") "$CONFIG_FILE" 2>/dev/null) || true

if [ -z "$REPORT" ]; then
  REPORT="$AGGREGATE_RESULT"
fi

# Determine language for feedback message
LANG_CFG=$(jq -r '.output.language // "ko"' "$CONFIG_FILE" 2>/dev/null)

if [ "$LANG_CFG" = "ko" ]; then
  FEEDBACK_PREFIX="AI Review Arena (${BATCH_SIZE}건 일괄 리뷰):"
  FEEDBACK_SUFFIX="위 피드백은 최근 코드 변경에 대한 리뷰입니다. 현재 작업과 직접 관련된 이슈만 반영하세요."
else
  FEEDBACK_PREFIX="AI Review Arena (batch of ${BATCH_SIZE} changes):"
  FEEDBACK_SUFFIX="The above feedback is a review of recent code changes. Only address issues directly related to your current task."
fi

# Escape the report for JSON embedding
ESCAPED_REPORT=$(echo "$REPORT" | jq -Rs . | sed 's/^"//;s/"$//')

# Output hook feedback JSON
cat <<HOOK_JSON
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "${FEEDBACK_PREFIX}\n${ESCAPED_REPORT}\n\n${FEEDBACK_SUFFIX}"
  }
}
HOOK_JSON

exit 0
