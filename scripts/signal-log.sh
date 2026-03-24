#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Cross-Agent Signal Log
#
# Usage:
#   signal-log.sh write <project-root> <agent-id> <signal-type> <data-json>
#   signal-log.sh read  <project-root> [--agent <id>] [--type <type>] [--since <epoch>]
#   signal-log.sh stats <project-root>
#   signal-log.sh learn <project-root>
#   signal-log.sh gotcha-suggest <project-root> [--save]
#
# Maintains a JSONL append-only log of cross-agent signals during review.
# Inspired by Ralph's progress.txt pattern and Agent-Skills-for-Context-Engineering.
#
# Signal types:
#   finding     - A new finding was identified
#   challenge   - A finding was challenged by another agent
#   support     - A finding was supported by another agent
#   escalation  - An escalation trigger was matched
#   consensus   - Debate reached consensus on a finding
#   pattern     - A recurring pattern was detected
#   learning    - A post-review learning for future sessions
#
# Exit codes:
#   0 - Success
#   1 - Error
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# --- Constants ---
SIGNAL_LOG_DIR="signal-log"

# =============================================================================
# Helpers
# =============================================================================

signal_log_file() {
  local project_root="$1"
  local base
  base=$(cache_base_dir "$project_root")
  local dir="${base}/${SIGNAL_LOG_DIR}"
  mkdir -p "$dir"
  echo "${dir}/signals.jsonl"
}

learnings_file() {
  local project_root="$1"
  local base
  base=$(cache_base_dir "$project_root")
  local dir="${base}/${SIGNAL_LOG_DIR}"
  mkdir -p "$dir"
  echo "${dir}/learnings.jsonl"
}

# =============================================================================
# Commands
# =============================================================================

cmd_write() {
  local project_root="${1:?Usage: signal-log.sh write <project-root> <agent-id> <signal-type> <data-json>}"
  local agent_id="${2:?Missing agent-id}"
  local signal_type="${3:?Missing signal-type}"
  local data_json="${4:-"{}"}"

  ensure_jq

  local log_file
  log_file=$(signal_log_file "$project_root")

  # Validate signal type
  case "$signal_type" in
    finding|challenge|support|escalation|consensus|pattern|learning) ;;
    *) log_error "Invalid signal type: $signal_type"; return 1 ;;
  esac

  # Validate data is valid JSON
  if ! echo "$data_json" | jq empty 2>/dev/null; then
    log_error "Invalid JSON data: $data_json"
    return 1
  fi

  # Scan for prompt injection in signal data
  if ! validate_cache_content "$data_json"; then
    log_warn "Signal write rejected for agent $agent_id: injection pattern detected in data"
    return 1
  fi

  # Build signal entry
  local now_epoch
  now_epoch=$(date +%s)
  local now_iso
  now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local entry
  entry=$(jq -cn \
    --arg agent "$agent_id" \
    --arg type "$signal_type" \
    --argjson ts "$now_epoch" \
    --arg ts_iso "$now_iso" \
    --argjson data "$data_json" \
    '{agent_id: $agent, signal_type: $type, timestamp: $ts, timestamp_iso: $ts_iso, data: $data}')

  # Atomic append: write to temp file then append with lock
  # Uses flock if available, direct append as fallback
  if command -v flock &>/dev/null; then
    (flock -x 200; echo "$entry" >> "$log_file") 200>"${log_file}.lock"
  else
    echo "$entry" >> "$log_file"
  fi

  return 0
}

cmd_read() {
  local project_root="${1:?Usage: signal-log.sh read <project-root>}"
  shift 1

  ensure_jq

  local agent_filter=""
  local type_filter=""
  local since_epoch="0"

  while [ $# -gt 0 ]; do
    case "$1" in
      --agent) agent_filter="${2:?--agent requires a value}"; shift 2 ;;
      --type)  type_filter="${2:?--type requires a value}"; shift 2 ;;
      --since) since_epoch="${2:?--since requires epoch value}"; shift 2 ;;
      *) shift ;;
    esac
  done

  local log_file
  log_file=$(signal_log_file "$project_root")

  if [ ! -f "$log_file" ]; then
    echo "[]"
    return 0
  fi

  # Build jq filter
  local jq_filter="select(.timestamp >= $since_epoch)"
  if [ -n "$agent_filter" ]; then
    jq_filter="${jq_filter} | select(.agent_id == \"$agent_filter\")"
  fi
  if [ -n "$type_filter" ]; then
    jq_filter="${jq_filter} | select(.signal_type == \"$type_filter\")"
  fi

  jq -s "[.[] | $jq_filter]" "$log_file" 2>/dev/null || echo "[]"
  return 0
}

cmd_stats() {
  local project_root="${1:?Usage: signal-log.sh stats <project-root>}"

  ensure_jq

  local log_file
  log_file=$(signal_log_file "$project_root")

  if [ ! -f "$log_file" ]; then
    echo '{"total_signals": 0}'
    return 0
  fi

  jq -s '{
    total_signals: length,
    by_type: (group_by(.signal_type) | map({key: .[0].signal_type, value: length}) | from_entries),
    by_agent: (group_by(.agent_id) | map({key: .[0].agent_id, value: length}) | from_entries),
    time_range: {
      first: (sort_by(.timestamp) | first.timestamp_iso // "N/A"),
      last: (sort_by(.timestamp) | last.timestamp_iso // "N/A")
    }
  }' "$log_file" 2>/dev/null || echo '{"total_signals": 0, "error": "parse_failed"}'
  return 0
}

cmd_learn() {
  # Extract learnings from the signal log for future reviews.
  # Identifies:
  #   - Patterns that were frequently challenged then accepted (model weakness)
  #   - Patterns that were frequently challenged then rejected (false positive patterns)
  #   - Agent pairs that frequently disagree (domain boundary issues)
  #   - Escalation patterns (what triggers intensity escalation)

  local project_root="${1:?Usage: signal-log.sh learn <project-root>}"

  ensure_jq

  local log_file
  log_file=$(signal_log_file "$project_root")
  local learn_file
  learn_file=$(learnings_file "$project_root")

  if [ ! -f "$log_file" ]; then
    echo '{"learnings": []}'
    return 0
  fi

  local now_iso
  now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Extract learnings
  local learnings
  learnings=$(jq -s '
    # Find frequently challenged-then-rejected patterns (false positives)
    [
      [.[] | select(.signal_type == "challenge")] |
      group_by(.data.finding_type // "unknown") |
      .[] |
      select(length >= 2) |
      {
        learning_type: "false_positive_pattern",
        pattern: .[0].data.finding_type,
        occurrences: length,
        agents_involved: [.[].agent_id] | unique,
        recommendation: "Consider adding to Recognized Secure Patterns for \(.[0].agent_id)"
      }
    ] +
    # Find escalation patterns
    [
      [.[] | select(.signal_type == "escalation")] |
      group_by(.data.trigger // "unknown") |
      .[] |
      {
        learning_type: "escalation_pattern",
        trigger: .[0].data.trigger,
        occurrences: length,
        recommendation: "This trigger consistently escalates intensity"
      }
    ] +
    # Find consensus patterns (what gets agreed on quickly)
    [
      [.[] | select(.signal_type == "consensus")] |
      group_by(.data.finding_type // "unknown") |
      .[] |
      select(length >= 3) |
      {
        learning_type: "quick_consensus",
        pattern: .[0].data.finding_type,
        occurrences: length,
        recommendation: "This finding type reaches consensus quickly — consider auto-accepting in Phase 6"
      }
    ]
  ' "$log_file" 2>/dev/null || echo '[]')

  # Append new learnings
  echo "$learnings" | jq -c --arg ts "$now_iso" '.[] + {extracted_at: $ts}' >> "$learn_file" 2>/dev/null

  # Output learnings
  echo "$learnings" | jq '.'
  return 0
}

cmd_gotcha_suggest() {
  # Converts accumulated learnings into Gotcha suggestions for agent definitions.
  # Reads from learnings.jsonl and produces markdown-formatted Gotcha entries
  # that can be appended to agent files or stored in short-term memory for
  # next pipeline run. Inspired by Hermes Agent's skill self-improvement pattern.
  #
  # Usage: signal-log.sh gotcha-suggest <project-root> [--save]
  #   --save: write suggestions to short-term memory for next pipeline run

  local project_root="${1:?Usage: signal-log.sh gotcha-suggest <project-root> [--save]}"
  shift 1

  local save_to_memory="false"
  while [ $# -gt 0 ]; do
    case "$1" in
      --save) save_to_memory="true"; shift ;;
      *) shift ;;
    esac
  done

  ensure_jq

  local learn_file
  learn_file=$(learnings_file "$project_root")

  if [ ! -f "$learn_file" ] || [ ! -s "$learn_file" ]; then
    echo "No learnings found. Run 'signal-log.sh learn' first."
    return 0
  fi

  # Generate Gotcha suggestions from false_positive_pattern learnings
  local suggestions
  suggestions=$(jq -s '
    [.[] | select(.learning_type == "false_positive_pattern" and .occurrences >= 2)] |
    group_by(.pattern) |
    map({
      agent: (.[0].agents_involved[0] // "unknown"),
      pattern: .[0].pattern,
      total_occurrences: ([.[].occurrences] | add),
      suggestion: "- **\(.[0].pattern)**: This pattern was challenged \([.[].occurrences] | add) times across reviews and frequently dismissed — likely a false positive that should be added to Gotchas"
    }) |
    sort_by(-.total_occurrences)
  ' "$learn_file" 2>/dev/null || echo "[]")

  local count
  count=$(echo "$suggestions" | jq 'length')

  if [ "$count" = "0" ]; then
    echo "No Gotcha suggestions found (need patterns with 2+ occurrences)."
    return 0
  fi

  # Output as markdown
  echo "## Auto-Generated Gotcha Suggestions"
  echo ""
  echo "Based on $count false-positive patterns detected across reviews:"
  echo ""
  echo "$suggestions" | jq -r '.[] | "### Agent: \(.agent)\n\(.suggestion)\n  (seen \(.total_occurrences) times)\n"'

  # Optionally save to memory for next pipeline run
  if [ "$save_to_memory" = "true" ]; then
    local gotcha_md
    gotcha_md=$(echo "$suggestions" | jq -r '[.[].suggestion] | join("\n")')
    echo "$gotcha_md" | "$SCRIPT_DIR/cache-manager.sh" memory-write "$project_root" short-term "gotcha-suggestions"
    log_info "Gotcha suggestions saved to short-term memory (key: gotcha-suggestions)"
  fi

  return 0
}

# =============================================================================
# Main Dispatch
# =============================================================================

COMMAND="${1:-}"

if [ -z "$COMMAND" ]; then
  log_error "Usage: signal-log.sh <write|read|stats|learn|gotcha-suggest> ..."
  exit 0
fi

shift 1

case "$COMMAND" in
  write) cmd_write "$@" ;;
  read)  cmd_read "$@" ;;
  stats) cmd_stats "$@" ;;
  learn) cmd_learn "$@" ;;
  gotcha-suggest) cmd_gotcha_suggest "$@" ;;
  *)
    log_error "Unknown command: $COMMAND"
    exit 0
    ;;
esac
