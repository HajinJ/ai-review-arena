#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Review Quality Feedback Tracker
#
# Usage:
#   feedback-tracker.sh record <session_id> <finding_id> <useful|not_useful|false_positive> \
#                        [--model <model>] [--category <cat>] [--severity <sev>]
#   feedback-tracker.sh report [--model <model>] [--category <cat>] [--days <N>]
#   feedback-tracker.sh stats
#
# Storage:
#   ~/.claude/plugins/ai-review-arena/cache/feedback/feedback-log.jsonl
#
# Each record is one JSONL line:
#   {"timestamp":"2026-02-17T12:00:00Z","session_id":"abc","finding_id":"f1",
#    "model":"codex","category":"security","severity":"high","verdict":"useful"}
#
# Exit codes:
#   0 - Always (informational tool)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/utils.sh"

ensure_jq

# --- Constants ---
FEEDBACK_DIR="${PLUGIN_DIR}/cache/feedback"
FEEDBACK_LOG="${FEEDBACK_DIR}/feedback-log.jsonl"
DEFAULT_REPORT_DAYS=30
VALID_VERDICTS="useful not_useful false_positive"

# =============================================================================
# Helpers
# =============================================================================

ensure_feedback_log() {
  if [ ! -d "$FEEDBACK_DIR" ]; then
    mkdir -p "$FEEDBACK_DIR"
  fi
  if [ ! -f "$FEEDBACK_LOG" ]; then
    touch "$FEEDBACK_LOG"
  fi
}

iso_timestamp() {
  # Produce ISO 8601 UTC timestamp
  if date -u +%Y-%m-%dT%H:%M:%SZ &>/dev/null 2>&1; then
    date -u +%Y-%m-%dT%H:%M:%SZ
  else
    date +%Y-%m-%dT%H:%M:%SZ
  fi
}

is_valid_verdict() {
  local verdict="$1"
  local v
  for v in $VALID_VERDICTS; do
    if [ "$v" = "$verdict" ]; then
      return 0
    fi
  done
  return 1
}

# =============================================================================
# Commands
# =============================================================================

cmd_record() {
  local session_id="${1:?Usage: feedback-tracker.sh record <session_id> <finding_id> <verdict> [--model <model>] [--category <cat>] [--severity <sev>]}"
  local finding_id="${2:?Usage: feedback-tracker.sh record <session_id> <finding_id> <verdict> [--model <model>] [--category <cat>] [--severity <sev>]}"
  local verdict="${3:?Usage: feedback-tracker.sh record <session_id> <finding_id> <verdict> [--model <model>] [--category <cat>] [--severity <sev>]}"

  # Validate verdict
  if ! is_valid_verdict "$verdict"; then
    log_error "Invalid verdict: $verdict (must be one of: $VALID_VERDICTS)"
    jq -n --arg v "$verdict" '{"status":"error","message":"Invalid verdict","verdict":$v}'
    exit 0
  fi

  shift 3

  # Parse optional flags
  local model=""
  local category=""
  local severity=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --model) model="${2:?--model requires a value}"; shift 2 ;;
      --category) category="${2:?--category requires a value}"; shift 2 ;;
      --severity) severity="${2:?--severity requires a value}"; shift 2 ;;
      *) shift ;;
    esac
  done

  ensure_feedback_log

  local ts
  ts=$(iso_timestamp)

  # Build and append JSONL record
  jq -cn \
    --arg ts "$ts" \
    --arg sid "$session_id" \
    --arg fid "$finding_id" \
    --arg model "$model" \
    --arg category "$category" \
    --arg severity "$severity" \
    --arg verdict "$verdict" \
    '{
      timestamp: $ts,
      session_id: $sid,
      finding_id: $fid,
      model: $model,
      category: $category,
      severity: $severity,
      verdict: $verdict
    }' >> "$FEEDBACK_LOG"

  # Confirmation output
  jq -n \
    --arg sid "$session_id" \
    --arg fid "$finding_id" \
    '{"status":"recorded","session_id":$sid,"finding_id":$fid}'
}

cmd_report() {
  local filter_model=""
  local filter_category=""
  local filter_days="$DEFAULT_REPORT_DAYS"

  while [ $# -gt 0 ]; do
    case "$1" in
      --model) filter_model="${2:?--model requires a value}"; shift 2 ;;
      --category) filter_category="${2:?--category requires a value}"; shift 2 ;;
      --days) filter_days="${2:?--days requires a value}"; shift 2 ;;
      *) shift ;;
    esac
  done

  ensure_feedback_log

  if [ ! -s "$FEEDBACK_LOG" ]; then
    jq -n --argjson days "$filter_days" '{"period_days":$days,"models":{},"categories":{}}'
    exit 0
  fi

  # Compute cutoff timestamp string for filtering
  local cutoff_epoch
  cutoff_epoch=$(( $(date +%s) - (filter_days * 86400) ))

  # macOS vs GNU date for cutoff ISO string
  local cutoff_ts
  if date -u -r 0 +%Y-%m-%dT%H:%M:%SZ &>/dev/null 2>&1; then
    # macOS / BSD
    cutoff_ts=$(date -u -r "$cutoff_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z")
  else
    # GNU/Linux
    cutoff_ts=$(date -u -d "@$cutoff_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z")
  fi

  # Use jq to slurp the JSONL, filter, and compute per-model and per-category stats
  jq -s \
    --arg cutoff "$cutoff_ts" \
    --arg fmodel "$filter_model" \
    --arg fcat "$filter_category" \
    --argjson days "$filter_days" \
    '
    # Filter by date range
    [ .[] | select(.timestamp >= $cutoff) ] |

    # Filter by model if specified
    (if $fmodel != "" then [ .[] | select(.model == $fmodel) ] else . end) |

    # Filter by category if specified
    (if $fcat != "" then [ .[] | select(.category == $fcat) ] else . end) |

    . as $filtered |

    # Per-model stats
    (
      [ $filtered[] | select(.model != "") | .model ] | unique | map(
        . as $m |
        [ $filtered[] | select(.model == $m) ] |
        {
          total: length,
          useful: [ .[] | select(.verdict == "useful") ] | length,
          not_useful: [ .[] | select(.verdict == "not_useful") ] | length,
          false_positive: [ .[] | select(.verdict == "false_positive") ] | length,
          accuracy: (
            if length > 0 then
              ([ .[] | select(.verdict == "useful") ] | length) / length * 100
              | . * 10 | round | . / 10
            else 0
            end
          )
        } | {($m): .}
      ) | add // {}
    ) as $models |

    # Per-category stats
    (
      [ $filtered[] | select(.category != "") | .category ] | unique | map(
        . as $c |
        [ $filtered[] | select(.category == $c) ] |
        {
          total: length,
          useful: [ .[] | select(.verdict == "useful") ] | length,
          accuracy: (
            if length > 0 then
              ([ .[] | select(.verdict == "useful") ] | length) / length * 100
              | . * 10 | round | . / 10
            else 0
            end
          )
        } | {($c): .}
      ) | add // {}
    ) as $categories |

    {
      period_days: $days,
      models: $models,
      categories: $categories
    }
    ' "$FEEDBACK_LOG"
}

cmd_stats() {
  ensure_feedback_log

  if [ ! -s "$FEEDBACK_LOG" ]; then
    jq -n '{"total_records":0,"models":[],"categories":[],"verdicts":{"useful":0,"not_useful":0,"false_positive":0}}'
    exit 0
  fi

  jq -s '
    {
      total_records: length,
      models: ([ .[].model | select(. != "") ] | unique),
      categories: ([ .[].category | select(. != "") ] | unique),
      verdicts: {
        useful: [ .[] | select(.verdict == "useful") ] | length,
        not_useful: [ .[] | select(.verdict == "not_useful") ] | length,
        false_positive: [ .[] | select(.verdict == "false_positive") ] | length
      },
      oldest: (sort_by(.timestamp) | first | .timestamp // null),
      newest: (sort_by(.timestamp) | last | .timestamp // null)
    }
  ' "$FEEDBACK_LOG"
}

# =============================================================================
# Main Dispatch
# =============================================================================

COMMAND="${1:-}"

if [ -z "$COMMAND" ]; then
  log_error "Usage: feedback-tracker.sh <record|report|stats> ..."
  exit 0
fi

shift 1

case "$COMMAND" in
  record) cmd_record "$@" ;;
  report) cmd_report "$@" ;;
  stats)  cmd_stats "$@" ;;
  *)
    log_error "Unknown command: $COMMAND"
    exit 0
    ;;
esac
