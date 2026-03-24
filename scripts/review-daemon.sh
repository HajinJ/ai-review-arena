#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Review Daemon (Async Ticket Queue)
#
# Usage:
#   review-daemon.sh enqueue <project-root> <pr-number> [--intensity <level>]
#   review-daemon.sh process <project-root>
#   review-daemon.sh status  <project-root> [<ticket-id>]
#   review-daemon.sh list    <project-root>
#
# Implements an async ticket queue for background reviews.
# Inspired by AgentInc's event-driven pipeline and Symphony's issue-tracker integration.
#
# Tickets are stored as JSONL in the cache directory.
# Processing is sequential (one review at a time) to avoid resource contention.
#
# Exit codes:
#   0 - Success
#   1 - Error
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# --- Constants ---
QUEUE_CATEGORY="review-queue"
QUEUE_KEY="tickets.jsonl"
RESULTS_KEY="results.jsonl"

# =============================================================================
# Helpers
# =============================================================================

queue_file() {
  local project_root="$1"
  local base
  base=$(cache_base_dir "$project_root")
  local dir="${base}/${QUEUE_CATEGORY}"
  mkdir -p "$dir"
  echo "${dir}/${QUEUE_KEY}"
}

results_file() {
  local project_root="$1"
  local base
  base=$(cache_base_dir "$project_root")
  local dir="${base}/${QUEUE_CATEGORY}"
  mkdir -p "$dir"
  echo "${dir}/${RESULTS_KEY}"
}

generate_ticket_id() {
  # Generate a short unique ID
  if command -v uuidgen &>/dev/null; then
    uuidgen | tr '[:upper:]' '[:lower:]' | cut -d'-' -f1
  else
    date +%s%N | sha256sum | head -c 8
  fi
}

# =============================================================================
# Commands
# =============================================================================

cmd_enqueue() {
  local project_root="${1:?Usage: review-daemon.sh enqueue <project-root> <pr-number>}"
  local pr_number="${2:?Missing PR number}"
  shift 2

  ensure_jq

  local intensity="standard"
  local focus=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --intensity) intensity="${2:?--intensity requires a value}"; shift 2 ;;
      --focus) focus="${2:?--focus requires a value}"; shift 2 ;;
      *) shift ;;
    esac
  done

  local qfile
  qfile=$(queue_file "$project_root")
  local ticket_id
  ticket_id=$(generate_ticket_id)
  local now_iso
  now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  jq -cn \
    --arg id "$ticket_id" \
    --arg pr "$pr_number" \
    --arg int "$intensity" \
    --arg focus "$focus" \
    --arg ts "$now_iso" \
    '{
      ticket_id: $id,
      pr_number: ($pr | tonumber),
      intensity: $int,
      focus: $focus,
      status: "queued",
      created_at: $ts,
      started_at: null,
      completed_at: null,
      result: null
    }' >> "$qfile"

  # Output ticket info
  echo "{\"ticket_id\": \"${ticket_id}\", \"status\": \"queued\", \"pr\": ${pr_number}}" >&2
  echo "$ticket_id"
  return 0
}

cmd_process() {
  local project_root="${1:?Usage: review-daemon.sh process <project-root>}"

  ensure_jq

  local qfile
  qfile=$(queue_file "$project_root")
  local rfile
  rfile=$(results_file "$project_root")

  if [ ! -f "$qfile" ]; then
    log_info "No tickets in queue"
    return 0
  fi

  # Find first queued ticket
  local ticket
  ticket=$(jq -s '[.[] | select(.status == "queued")] | first // empty' "$qfile" 2>/dev/null)

  if [ -z "$ticket" ] || [ "$ticket" = "null" ]; then
    log_info "No queued tickets to process"
    return 0
  fi

  local ticket_id
  ticket_id=$(echo "$ticket" | jq -r '.ticket_id')
  local pr_number
  pr_number=$(echo "$ticket" | jq -r '.pr_number')
  local intensity
  intensity=$(echo "$ticket" | jq -r '.intensity')
  local focus
  focus=$(echo "$ticket" | jq -r '.focus // ""')

  log_info "Processing ticket ${ticket_id}: PR #${pr_number} (${intensity})"

  # Mark as in-progress
  local now_iso
  now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local temp_qfile="${qfile}.tmp"
  jq -s --arg id "$ticket_id" --arg ts "$now_iso" '
    map(if .ticket_id == $id then .status = "in_progress" | .started_at = $ts else . end)[]
  ' "$qfile" > "$temp_qfile" 2>/dev/null && mv "$temp_qfile" "$qfile"

  # Run review
  local review_result=""
  local review_exit=0

  REVIEW_INPUT="{\"pr\": ${pr_number}, \"intensity\": \"${intensity}\""
  if [ -n "$focus" ] && [ "$focus" != "null" ]; then
    REVIEW_INPUT="${REVIEW_INPUT}, \"focus\": \"${focus}\""
  fi
  REVIEW_INPUT="${REVIEW_INPUT}}"

  review_result=$(echo "$REVIEW_INPUT" | "$SCRIPT_DIR/orchestrate-review.sh" 2>/dev/null) || review_exit=$?

  # Mark as completed
  now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local status="completed"
  if [ "$review_exit" -ne 0 ]; then
    status="failed"
  fi

  jq -s --arg id "$ticket_id" --arg ts "$now_iso" --arg st "$status" '
    map(if .ticket_id == $id then .status = $st | .completed_at = $ts else . end)[]
  ' "$qfile" > "$temp_qfile" 2>/dev/null && mv "$temp_qfile" "$qfile"

  # Save result
  local finding_count=0
  if [ -n "$review_result" ]; then
    finding_count=$(echo "$review_result" | jq 'if type == "array" then length elif has("accepted") then (.accepted | length) + (.disputed | length) else 0 end' 2>/dev/null || echo "0")
  fi

  jq -cn \
    --arg id "$ticket_id" \
    --arg st "$status" \
    --arg ts "$now_iso" \
    --argjson findings "$finding_count" \
    '{ticket_id: $id, status: $st, completed_at: $ts, finding_count: $findings}' \
    >> "$rfile"

  log_info "Ticket ${ticket_id} ${status}: ${finding_count} findings"
  echo "{\"ticket_id\": \"${ticket_id}\", \"status\": \"${status}\", \"findings\": ${finding_count}}"
  return 0
}

cmd_status() {
  local project_root="${1:?Usage: review-daemon.sh status <project-root>}"
  local ticket_id="${2:-}"

  ensure_jq

  local qfile
  qfile=$(queue_file "$project_root")

  if [ ! -f "$qfile" ]; then
    echo '{"queued": 0, "in_progress": 0, "completed": 0, "failed": 0}'
    return 0
  fi

  if [ -n "$ticket_id" ]; then
    jq -s --arg id "$ticket_id" '[.[] | select(.ticket_id == $id)] | first // {"error": "not_found"}' "$qfile"
  else
    jq -s '{
      queued: [.[] | select(.status == "queued")] | length,
      in_progress: [.[] | select(.status == "in_progress")] | length,
      completed: [.[] | select(.status == "completed")] | length,
      failed: [.[] | select(.status == "failed")] | length,
      total: length
    }' "$qfile"
  fi
  return 0
}

cmd_list() {
  local project_root="${1:?Usage: review-daemon.sh list <project-root>}"

  ensure_jq

  local qfile
  qfile=$(queue_file "$project_root")

  if [ ! -f "$qfile" ]; then
    echo "[]"
    return 0
  fi

  jq -s '.' "$qfile"
  return 0
}

# =============================================================================
# Main Dispatch
# =============================================================================

COMMAND="${1:-}"

if [ -z "$COMMAND" ]; then
  log_error "Usage: review-daemon.sh <enqueue|process|status|list> ..."
  exit 0
fi

shift 1

case "$COMMAND" in
  enqueue) cmd_enqueue "$@" ;;
  process) cmd_process "$@" ;;
  status)  cmd_status "$@" ;;
  list)    cmd_list "$@" ;;
  *)
    log_error "Unknown command: $COMMAND"
    exit 0
    ;;
esac
