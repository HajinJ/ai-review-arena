#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Stream Monitor
#
# Monitors the streaming signal log for real-time conflict detection.
# Detects when different models flag the same file+line with different severities.
# Alerts immediately on critical findings.
#
# Usage: stream-monitor.sh <session-dir> [--timeout <seconds>]
# Exit: 0 always (background utility)
#
# Process management:
#   Runs as a background monitor. Kill via saved PID file.
#   Uses process group for clean cleanup of all child processes.
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh" || true

# --- Arguments ---
SESSION_DIR="${1:?Usage: stream-monitor.sh <session-dir> [--timeout <seconds>]}"
shift 1

MONITOR_TIMEOUT=300  # 5 min default

while [ $# -gt 0 ]; do
  case "$1" in
    --timeout) MONITOR_TIMEOUT="${2:-300}"; shift 2 ;;
    *) shift ;;
  esac
done

SIGNAL_LOG="${SESSION_DIR}/signals.jsonl"
CONFLICT_LOG="${SESSION_DIR}/conflicts.jsonl"
MONITOR_PID_FILE="${SESSION_DIR}/.monitor.pid"

# Save PID for cleanup
echo $$ > "$MONITOR_PID_FILE"

# Cleanup on exit
cleanup() {
  rm -f "$MONITOR_PID_FILE" 2>/dev/null
}
trap cleanup EXIT INT TERM

# --- Wait for signal log to appear ---
_waited=0
while [ ! -f "$SIGNAL_LOG" ] && [ "$_waited" -lt 30 ]; do
  sleep 1
  _waited=$((_waited + 1))
done

if [ ! -f "$SIGNAL_LOG" ]; then
  exit 0
fi

# --- Monitor signal log with timeout ---
# Use a background timeout killer
(
  sleep "$MONITOR_TIMEOUT"
  kill $$ 2>/dev/null
) &
_timeout_pid=$!

# Track seen findings for conflict detection: file:line -> {source, severity}
# Using temp files since bash arrays can't do associative in a portable way
SEEN_DIR=$(mktemp -d)
trap "rm -rf '$SEEN_DIR'; rm -f '$MONITOR_PID_FILE' 2>/dev/null; kill '$_timeout_pid' 2>/dev/null" EXIT INT TERM

# Process new signals in real-time using tail -f
# Use --pid to auto-exit when parent dies (GNU tail)
tail -n +1 -f "$SIGNAL_LOG" 2>/dev/null | while IFS= read -r signal; do
  # Skip empty lines
  [ -z "$signal" ] && continue

  # Parse signal (validate JSON first)
  if ! echo "$signal" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    continue
  fi

  _parsed=$(echo "$signal" | python3 -c "
import sys, json
try:
    s = json.load(sys.stdin)
    d = s.get('data', {})
    print(f\"{s.get('source','')}\t{s.get('type','')}\t{d.get('severity','')}\t{d.get('file','')}\t{d.get('line',0)}\t{d.get('title','')}\")
except:
    print('\t\t\t\t0\t')
" 2>/dev/null) || continue

  IFS=$'\t' read -r _source _type _severity _file _line _title <<< "$_parsed"

  # Only process finding_stream signals
  [ "$_type" != "finding_stream" ] && continue
  [ -z "$_file" ] && continue

  # --- Critical alert ---
  if [ "$_severity" = "critical" ]; then
    log_warn "[STREAM ALERT] Critical finding from ${_source}: ${_title} (${_file}:${_line})"
  fi

  # --- Conflict detection ---
  # Normalize file+line to a key
  _key=$(echo "${_file}:${_line}" | tr '/' '_')
  _seen_file="${SEEN_DIR}/${_key}"

  if [ -f "$_seen_file" ]; then
    # Another model already flagged this location
    _prev=$(cat "$_seen_file")
    _prev_source=$(echo "$_prev" | cut -d'|' -f1)
    _prev_severity=$(echo "$_prev" | cut -d'|' -f2)
    _prev_title=$(echo "$_prev" | cut -d'|' -f3)

    # Conflict: different sources with different severities
    if [ "$_prev_source" != "$_source" ] && [ "$_prev_severity" != "$_severity" ]; then
      # Use env vars to pass data to Python (avoids shell injection via signal data)
      _conflict_entry=$(
        _CF_FILE="$_file" \
        _CF_LINE="$_line" \
        _CF_PREV_SRC="$_prev_source" \
        _CF_PREV_SEV="$_prev_severity" \
        _CF_PREV_TITLE="$_prev_title" \
        _CF_SRC="$_source" \
        _CF_SEV="$_severity" \
        _CF_TITLE="$_title" \
        python3 -c "
import json, os
conflict = {
    'type': 'severity_conflict',
    'file': os.environ.get('_CF_FILE', ''),
    'line': int(os.environ.get('_CF_LINE', '0')) if os.environ.get('_CF_LINE', '0').isdigit() else 0,
    'model_a': {'source': os.environ.get('_CF_PREV_SRC', ''), 'severity': os.environ.get('_CF_PREV_SEV', ''), 'title': os.environ.get('_CF_PREV_TITLE', '')},
    'model_b': {'source': os.environ.get('_CF_SRC', ''), 'severity': os.environ.get('_CF_SEV', ''), 'title': os.environ.get('_CF_TITLE', '')},
    'resolution': 'pending_debate',
}
print(json.dumps(conflict, ensure_ascii=False))
" 2>/dev/null)

      if [ -n "$_conflict_entry" ]; then
        # Atomic append to conflict log
        if command -v flock &>/dev/null; then
          (flock -x 201; echo "$_conflict_entry" >> "$CONFLICT_LOG") 201>"${CONFLICT_LOG}.lock"
        else
          echo "$_conflict_entry" >> "$CONFLICT_LOG"
        fi
        log_warn "[STREAM CONFLICT] ${_file}:${_line} — ${_prev_source}(${_prev_severity}) vs ${_source}(${_severity})"
      fi
    fi
  fi

  # Record this finding
  echo "${_source}|${_severity}|${_title}" > "$_seen_file"

done

# Cleanup timeout
kill "$_timeout_pid" 2>/dev/null || true

exit 0
