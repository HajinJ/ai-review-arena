#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Stream Orchestrator
#
# Launches parallel streaming reviews with proper process group management.
# Falls back to sync review scripts if streaming fails.
#
# Usage: stream-orchestrator.sh <session-dir> <file-path> <config-file> <roles...>
# Exit: 0 always (non-blocking)
#
# Output: Findings files in session-dir (findings_stream_*.json)
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh" || true

# --- Arguments ---
SESSION_DIR="${1:?Usage: stream-orchestrator.sh <session-dir> <file-path> <config-file> <roles...>}"
FILE_PATH="${2:?Missing file path}"
CONFIG_FILE="${3:?Missing config file}"
shift 3

ROLES=("$@")
if [ ${#ROLES[@]} -eq 0 ]; then
  log_warn "No roles specified for streaming review."
  exit 0
fi

# --- Load streaming config ---
STREAMING_ENABLED=true
if [ -f "$CONFIG_FILE" ] && command -v jq &>/dev/null; then
  STREAMING_ENABLED=$(jq -r '.streaming.enabled // true' "$CONFIG_FILE")
fi

if [ "$STREAMING_ENABLED" != "true" ]; then
  log_info "Streaming disabled in config."
  exit 0
fi

# --- Check Python availability ---
if ! command -v python3 &>/dev/null; then
  log_warn "python3 not found. Falling back to sync review."
  exit 0
fi

# --- Check stream-review.py can import required packages ---
_can_stream_codex=false
_can_stream_gemini=false

if python3 -c "from openai import OpenAI" 2>/dev/null; then
  _can_stream_codex=true
fi

if python3 -c "import google.genai" 2>/dev/null || python3 -c "import google.generativeai" 2>/dev/null; then
  _can_stream_gemini=true
fi

# --- Read model config ---
codex_enabled=$(jq -r '.models.codex.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
gemini_enabled=$(jq -r '.models.gemini.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
codex_roles=$(jq -r '.models.codex.roles[]? // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
gemini_roles=$(jq -r '.models.gemini.roles[]? // empty' "$CONFIG_FILE" 2>/dev/null || echo "")

# --- Prepare signal log ---
SIGNAL_LOG="${SESSION_DIR}/signals.jsonl"
touch "$SIGNAL_LOG"

# --- Start monitor ---
"$SCRIPT_DIR/stream-monitor.sh" "$SESSION_DIR" --timeout 300 &
MONITOR_PID=$!

# --- Process group cleanup ---
STREAM_PIDS=()

cleanup_streams() {
  for pid in "${STREAM_PIDS[@]+${STREAM_PIDS[@]}}"; do
    # Kill process and all its children
    kill -- "-$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')" 2>/dev/null || \
      kill "$pid" 2>/dev/null || true
  done
  # Kill monitor and its children
  if [ -n "${MONITOR_PID:-}" ]; then
    kill -- "-$(ps -o pgid= -p "$MONITOR_PID" 2>/dev/null | tr -d ' ')" 2>/dev/null || \
      kill "$MONITOR_PID" 2>/dev/null || true
  fi
}
trap cleanup_streams EXIT INT TERM

# --- Launch streaming reviews ---
FINDINGS_INDEX=0

for role in "${ROLES[@]}"; do
  [ -z "$role" ] && continue

  # Determine which models to use for this role
  _use_codex=false
  _use_gemini=false

  if [ "$codex_enabled" = "true" ] && echo "$codex_roles" | grep -q "$role"; then
    _use_codex=true
  fi
  if [ "$gemini_enabled" = "true" ] && echo "$gemini_roles" | grep -q "$role"; then
    _use_gemini=true
  fi

  # Launch Codex streaming
  if [ "$_use_codex" = "true" ] && [ "$_can_stream_codex" = "true" ]; then
    FINDINGS_FILE="${SESSION_DIR}/findings_stream_${FINDINGS_INDEX}.json"
    FINDINGS_INDEX=$((FINDINGS_INDEX + 1))
    (
      python3 "$SCRIPT_DIR/stream-review.py" codex "$FILE_PATH" "$role" \
        --config "$CONFIG_FILE" --session-dir "$SESSION_DIR" \
        > "$FINDINGS_FILE" 2>/dev/null
    ) &
    STREAM_PIDS+=($!)
  elif [ "$_use_codex" = "true" ]; then
    # Fallback to sync Codex
    FINDINGS_FILE="${SESSION_DIR}/findings_stream_${FINDINGS_INDEX}.json"
    FINDINGS_INDEX=$((FINDINGS_INDEX + 1))
    (
      cat "$FILE_PATH" | "$SCRIPT_DIR/codex-review.sh" "$FILE_PATH" "$CONFIG_FILE" "$role" \
        > "$FINDINGS_FILE" 2>/dev/null
    ) &
    STREAM_PIDS+=($!)
    log_info "Codex streaming unavailable for $role, using sync fallback."
  fi

  # Launch Gemini streaming
  if [ "$_use_gemini" = "true" ] && [ "$_can_stream_gemini" = "true" ]; then
    FINDINGS_FILE="${SESSION_DIR}/findings_stream_${FINDINGS_INDEX}.json"
    FINDINGS_INDEX=$((FINDINGS_INDEX + 1))
    (
      python3 "$SCRIPT_DIR/stream-review.py" gemini "$FILE_PATH" "$role" \
        --config "$CONFIG_FILE" --session-dir "$SESSION_DIR" \
        > "$FINDINGS_FILE" 2>/dev/null
    ) &
    STREAM_PIDS+=($!)
  elif [ "$_use_gemini" = "true" ]; then
    # Fallback to sync Gemini
    FINDINGS_FILE="${SESSION_DIR}/findings_stream_${FINDINGS_INDEX}.json"
    FINDINGS_INDEX=$((FINDINGS_INDEX + 1))
    (
      cat "$FILE_PATH" | "$SCRIPT_DIR/gemini-review.sh" "$FILE_PATH" "$CONFIG_FILE" "$role" \
        > "$FINDINGS_FILE" 2>/dev/null
    ) &
    STREAM_PIDS+=($!)
    log_info "Gemini streaming unavailable for $role, using sync fallback."
  fi
done

# --- Wait for all reviews ---
STREAM_FAILURES=0
for pid in "${STREAM_PIDS[@]+${STREAM_PIDS[@]}}"; do
  if ! wait "$pid" 2>/dev/null; then
    STREAM_FAILURES=$((STREAM_FAILURES + 1))
  fi
done

# --- Stop monitor ---
kill "$MONITOR_PID" 2>/dev/null || true
wait "$MONITOR_PID" 2>/dev/null || true

# --- Report conflicts ---
if [ -f "${SESSION_DIR}/conflicts.jsonl" ] && [ -s "${SESSION_DIR}/conflicts.jsonl" ]; then
  CONFLICT_COUNT=$(wc -l < "${SESSION_DIR}/conflicts.jsonl" | tr -d ' ')
  log_info "Streaming review completed with $CONFLICT_COUNT severity conflicts detected."
else
  log_info "Streaming review completed. No conflicts detected."
fi

if [ "$STREAM_FAILURES" -gt 0 ]; then
  log_warn "Streaming: ${STREAM_FAILURES}/${#STREAM_PIDS[@]} reviews failed."
fi

exit 0
