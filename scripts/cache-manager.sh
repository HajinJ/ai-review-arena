#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Knowledge Cache with TTL
#
# Usage:
#   cache-manager.sh read    <project-root> <category> <key>
#   cache-manager.sh write   <project-root> <category> <key> [--ttl <days>]
#   cache-manager.sh check   <project-root> <category> <key> [--ttl <days>]
#   cache-manager.sh list    <project-root>
#   cache-manager.sh cleanup <project-root> [--max-age <days>] [--max-size <mb>]
#   cache-manager.sh hash    <project-root>
#
# Cache location:
#   ~/.claude/plugins/ai-review-arena/cache/{project-hash}/{category}/{key}
#
# write: reads content from stdin, stores alongside a .timestamp file.
# read:  outputs cached content to stdout. Exit 1 if stale or missing.
# check: exit 0 if cache entry is fresh, exit 1 if stale or missing.
# list:  lists all cached entries for the project.
# cleanup: removes stale entries and enforces size limits.
# hash:  outputs the project hash.
#
# Exit codes:
#   0 - Success / cache hit / fresh
#   1 - Cache miss / stale / error
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# --- Constants ---
DEFAULT_TTL_DAYS=3
DEFAULT_MAX_AGE_DAYS=30
DEFAULT_MAX_SIZE_MB=100

# =============================================================================
# Helpers
# =============================================================================

cache_dir_for() {
  local project_root="$1"
  local category="$2"
  local base
  base=$(cache_base_dir "$project_root")
  echo "${base}/${category}"
}

cache_file_for() {
  local project_root="$1"
  local category="$2"
  local key="$3"
  local dir
  dir=$(cache_dir_for "$project_root" "$category")
  echo "${dir}/${key}"
}

timestamp_file_for() {
  local cache_file="$1"
  echo "${cache_file}.timestamp"
}

is_fresh() {
  local cache_file="$1"
  local ttl_days="$2"
  local ts_file
  ts_file=$(timestamp_file_for "$cache_file")

  if [ ! -f "$cache_file" ] || [ ! -f "$ts_file" ]; then
    return 1
  fi

  local stored_epoch
  stored_epoch=$(cat "$ts_file" 2>/dev/null || echo "0")
  local now_epoch
  now_epoch=$(date +%s)
  local ttl_seconds=$((ttl_days * 86400))
  local age=$((now_epoch - stored_epoch))

  if [ "$age" -gt "$ttl_seconds" ]; then
    return 1
  fi

  return 0
}

# =============================================================================
# Commands
# =============================================================================

cmd_read() {
  local project_root="${1:?Usage: cache-manager.sh read <project-root> <category> <key>}"
  local category="${2:?Usage: cache-manager.sh read <project-root> <category> <key>}"
  local key="${3:?Usage: cache-manager.sh read <project-root> <category> <key>}"
  local ttl_days="$DEFAULT_TTL_DAYS"

  # Parse optional --ttl
  shift 3
  while [ $# -gt 0 ]; do
    case "$1" in
      --ttl) ttl_days="${2:?--ttl requires a value}"; shift 2 ;;
      *) shift ;;
    esac
  done

  local cache_file
  cache_file=$(cache_file_for "$project_root" "$category" "$key")

  if ! is_fresh "$cache_file" "$ttl_days"; then
    return 1
  fi

  cat "$cache_file"
  return 0
}

cmd_write() {
  local project_root="${1:?Usage: cache-manager.sh write <project-root> <category> <key>}"
  local category="${2:?Usage: cache-manager.sh write <project-root> <category> <key>}"
  local key="${3:?Usage: cache-manager.sh write <project-root> <category> <key>}"

  shift 3
  # --ttl is accepted but only used for documentation; write always stores fresh
  while [ $# -gt 0 ]; do
    case "$1" in
      --ttl) shift 2 ;;
      *) shift ;;
    esac
  done

  local cache_file
  cache_file=$(cache_file_for "$project_root" "$category" "$key")
  local ts_file
  ts_file=$(timestamp_file_for "$cache_file")
  local dir
  dir=$(dirname "$cache_file")

  mkdir -p "$dir"

  # Read content from stdin
  cat > "$cache_file"

  # Write timestamp
  date +%s > "$ts_file"

  return 0
}

cmd_check() {
  local project_root="${1:?Usage: cache-manager.sh check <project-root> <category> <key>}"
  local category="${2:?Usage: cache-manager.sh check <project-root> <category> <key>}"
  local key="${3:?Usage: cache-manager.sh check <project-root> <category> <key>}"
  local ttl_days="$DEFAULT_TTL_DAYS"

  shift 3
  while [ $# -gt 0 ]; do
    case "$1" in
      --ttl) ttl_days="${2:?--ttl requires a value}"; shift 2 ;;
      *) shift ;;
    esac
  done

  local cache_file
  cache_file=$(cache_file_for "$project_root" "$category" "$key")

  if is_fresh "$cache_file" "$ttl_days"; then
    return 0
  fi
  return 1
}

cmd_list() {
  local project_root="${1:?Usage: cache-manager.sh list <project-root>}"
  local base
  base=$(cache_base_dir "$project_root")

  ensure_jq

  if [ ! -d "$base" ]; then
    echo "[]"
    return 0
  fi

  # Collect entries as JSONL (one per line), then combine with single jq -s
  local entries_jsonl=""
  # Walk cache directories
  for category_dir in "$base"/*/; do
    [ -d "$category_dir" ] || continue
    local category
    category=$(basename "$category_dir")

    for entry in "$category_dir"*; do
      [ -f "$entry" ] || continue
      # Skip .timestamp files
      case "$entry" in
        *.timestamp) continue ;;
      esac

      local key
      key=$(basename "$entry")
      local ts_file="${entry}.timestamp"
      local stored_epoch="0"
      local size_bytes=0

      if [ -f "$ts_file" ]; then
        stored_epoch=$(cat "$ts_file" 2>/dev/null || echo "0")
      fi
      size_bytes=$(wc -c < "$entry" 2>/dev/null | tr -d ' ')

      entries_jsonl="${entries_jsonl}$(jq -cn \
        --arg cat "$category" \
        --arg key "$key" \
        --argjson ts "$stored_epoch" \
        --argjson size "$size_bytes" \
        '{"category": $cat, "key": $key, "timestamp": $ts, "size_bytes": $size}')
"
    done
  done

  if [ -n "$entries_jsonl" ]; then
    echo "$entries_jsonl" | jq -s '.'
  else
    echo "[]"
  fi
  return 0
}

cmd_cleanup() {
  local project_root="${1:?Usage: cache-manager.sh cleanup <project-root>}"
  local max_age_days="$DEFAULT_MAX_AGE_DAYS"
  local max_size_mb="$DEFAULT_MAX_SIZE_MB"

  shift 1
  while [ $# -gt 0 ]; do
    case "$1" in
      --max-age) max_age_days="${2:?--max-age requires a value}"; shift 2 ;;
      --max-size) max_size_mb="${2:?--max-size requires a value}"; shift 2 ;;
      *) shift ;;
    esac
  done

  local base
  base=$(cache_base_dir "$project_root")

  if [ ! -d "$base" ]; then
    return 0
  fi

  local now_epoch
  now_epoch=$(date +%s)
  local max_age_seconds=$((max_age_days * 86400))
  local removed=0

  # Remove entries older than max-age
  for ts_file in "$base"/*/*.timestamp "$base"/*/*/*.timestamp; do
    [ -f "$ts_file" ] || continue
    local stored_epoch
    stored_epoch=$(cat "$ts_file" 2>/dev/null || echo "0")
    local age=$((now_epoch - stored_epoch))

    if [ "$age" -gt "$max_age_seconds" ]; then
      local data_file="${ts_file%.timestamp}"
      rm -f "$data_file" "$ts_file" 2>/dev/null
      removed=$((removed + 1))
    fi
  done

  # Enforce total size limit
  local max_size_bytes=$((max_size_mb * 1024 * 1024))
  local total_size=0

  # Calculate current size (excluding timestamp files)
  total_size=$(find "$base" -type f ! -name '*.timestamp' -exec wc -c {} + 2>/dev/null | tail -1 | awk '{print $1}')
  total_size=${total_size:-0}

  if [ "$total_size" -gt "$max_size_bytes" ]; then
    # Remove oldest entries until under limit
    # Use process substitution to keep while-loop in main shell (not subshell)
    while IFS=' ' read -r _ts ts_path; do
      [ -f "$ts_path" ] || continue
      local data_file="${ts_path%.timestamp}"
      if [ -f "$data_file" ]; then
        local file_size
        file_size=$(wc -c < "$data_file" 2>/dev/null | tr -d ' ')
        rm -f "$data_file" "$ts_path" 2>/dev/null
        total_size=$((total_size - file_size))
        removed=$((removed + 1))
        if [ "$total_size" -le "$max_size_bytes" ]; then
          break
        fi
      fi
    done < <(find "$base" -maxdepth 3 -name '*.timestamp' -type f -print0 2>/dev/null | \
      while IFS= read -r -d '' ts_file; do
        echo "$(cat "$ts_file" 2>/dev/null || echo 0) $ts_file"
      done | sort -n)
  fi

  # Remove empty directories
  find "$base" -type d -empty -delete 2>/dev/null || true

  log_info "Cleanup complete: removed $removed entries"
  return 0
}

cmd_hash() {
  local project_root="${1:?Usage: cache-manager.sh hash <project-root>}"
  project_hash "$project_root"
}

cmd_cleanup_sessions() {
  # Clean up stale session directories from /tmp.
  # Usage: cache-manager.sh cleanup-sessions [--max-age <hours>]
  local max_age_hours=24

  while [ $# -gt 0 ]; do
    case "$1" in
      --max-age) max_age_hours="${2:?--max-age requires a value in hours}"; shift 2 ;;
      *) shift ;;
    esac
  done

  local removed=0
  local now_epoch
  now_epoch=$(date +%s)
  local max_age_seconds=$((max_age_hours * 3600))

  # Clean /tmp/ai-review-arena* directories
  for session_dir in /tmp/ai-review-arena*/; do
    [ -d "$session_dir" ] || continue

    # Get directory modification time
    local dir_mtime
    if stat -f %m "$session_dir" &>/dev/null 2>&1; then
      # macOS / BSD
      dir_mtime=$(stat -f %m "$session_dir" 2>/dev/null || echo "0")
    else
      # GNU/Linux
      dir_mtime=$(stat -c %Y "$session_dir" 2>/dev/null || echo "0")
    fi

    local age=$((now_epoch - dir_mtime))

    if [ "$age" -gt "$max_age_seconds" ]; then
      rm -rf "$session_dir" 2>/dev/null
      removed=$((removed + 1))
    fi
  done

  # Also clean /tmp/arena-config-merged.* temp files
  for tmp_config in /tmp/arena-config-merged.*.json; do
    [ -f "$tmp_config" ] || continue

    local file_mtime
    if stat -f %m "$tmp_config" &>/dev/null 2>&1; then
      file_mtime=$(stat -f %m "$tmp_config" 2>/dev/null || echo "0")
    else
      file_mtime=$(stat -c %Y "$tmp_config" 2>/dev/null || echo "0")
    fi

    local age=$((now_epoch - file_mtime))

    if [ "$age" -gt "$max_age_seconds" ]; then
      rm -f "$tmp_config" 2>/dev/null
      removed=$((removed + 1))
    fi
  done

  log_info "Session cleanup complete: removed $removed items"
  return 0
}

# =============================================================================
# Memory Tier Commands
# =============================================================================

# Memory tiers map to specific cache categories with tier-specific TTLs:
#   short-term (7 days): recurring_findings, recent_review_patterns, session_decisions
#   long-term (90 days): model_accuracy_by_category, accepted_vs_rejected_findings, feedback_trends
#   permanent (-1/never): team_coding_standards, project_architecture_decisions, known_acceptable_patterns

_tier_ttl() {
  local tier="$1"
  case "$tier" in
    short-term) echo "7" ;;
    long-term)  echo "90" ;;
    permanent)  echo "36500" ;; # ~100 years = effectively permanent
    *) echo "$DEFAULT_TTL_DAYS" ;;
  esac
}

_tier_category() {
  local tier="$1"
  echo "memory/${tier}"
}

cmd_memory_read() {
  local project_root="${1:?Usage: cache-manager.sh memory-read <project-root> <tier> <key>}"
  local tier="${2:?Usage: cache-manager.sh memory-read <project-root> <tier> <key>}"
  local key="${3:?Usage: cache-manager.sh memory-read <project-root> <tier> <key>}"

  local ttl
  ttl=$(_tier_ttl "$tier")
  local category
  category=$(_tier_category "$tier")

  cmd_read "$project_root" "$category" "$key" --ttl "$ttl"
}

cmd_memory_write() {
  local project_root="${1:?Usage: cache-manager.sh memory-write <project-root> <tier> <key>}"
  local tier="${2:?Usage: cache-manager.sh memory-write <project-root> <tier> <key>}"
  local key="${3:?Usage: cache-manager.sh memory-write <project-root> <tier> <key>}"

  local category
  category=$(_tier_category "$tier")

  cmd_write "$project_root" "$category" "$key"
}

cmd_memory_list() {
  local project_root="${1:?Usage: cache-manager.sh memory-list <project-root> [<tier>]}"
  local tier="${2:-}"

  ensure_jq

  local base
  base=$(cache_base_dir "$project_root")

  if [ -n "$tier" ]; then
    local category
    category=$(_tier_category "$tier")
    local dir="${base}/${category}"

    if [ ! -d "$dir" ]; then
      echo "[]"
      return 0
    fi

    local entries_jsonl=""
    for entry in "$dir"/*; do
      [ -f "$entry" ] || continue
      case "$entry" in *.timestamp) continue ;; esac

      local key
      key=$(basename "$entry")
      local ts_file="${entry}.timestamp"
      local stored_epoch="0"
      [ -f "$ts_file" ] && stored_epoch=$(cat "$ts_file" 2>/dev/null || echo "0")

      entries_jsonl="${entries_jsonl}$(jq -cn \
        --arg tier "$tier" \
        --arg key "$key" \
        --argjson ts "$stored_epoch" \
        '{"tier": $tier, "key": $key, "timestamp": $ts}')
"
    done
    if [ -n "$entries_jsonl" ]; then
      echo "$entries_jsonl" | jq -s '.'
    else
      echo "[]"
    fi
  else
    # List all tiers — collect as JSONL, combine once
    local all_entries_jsonl=""
    for t in short-term long-term permanent; do
      local category
      category=$(_tier_category "$t")
      local dir="${base}/${category}"
      [ -d "$dir" ] || continue

      for entry in "$dir"/*; do
        [ -f "$entry" ] || continue
        case "$entry" in *.timestamp) continue ;; esac

        local key
        key=$(basename "$entry")
        local ts_file="${entry}.timestamp"
        local stored_epoch="0"
        [ -f "$ts_file" ] && stored_epoch=$(cat "$ts_file" 2>/dev/null || echo "0")

        all_entries_jsonl="${all_entries_jsonl}$(jq -cn \
          --arg tier "$t" \
          --arg key "$key" \
          --argjson ts "$stored_epoch" \
          '{"tier": $tier, "key": $key, "timestamp": $ts}')
"
      done
    done
    if [ -n "$all_entries_jsonl" ]; then
      echo "$all_entries_jsonl" | jq -s '.'
    else
      echo "[]"
    fi
  fi
  return 0
}

# =============================================================================
# Main Dispatch
# =============================================================================

COMMAND="${1:-}"

if [ -z "$COMMAND" ]; then
  log_error "Usage: cache-manager.sh <read|write|check|list|cleanup|cleanup-sessions|hash|memory-read|memory-write|memory-list> ..."
  exit 0
fi

shift 1

case "$COMMAND" in
  read)             cmd_read "$@" ;;
  write)            cmd_write "$@" ;;
  check)            cmd_check "$@" ;;
  list)             cmd_list "$@" ;;
  cleanup)          cmd_cleanup "$@" ;;
  cleanup-sessions) cmd_cleanup_sessions "$@" ;;
  hash)             cmd_hash "$@" ;;
  memory-read)      cmd_memory_read "$@" ;;
  memory-write)     cmd_memory_write "$@" ;;
  memory-list)      cmd_memory_list "$@" ;;
  *)
    log_error "Unknown command: $COMMAND"
    exit 0
    ;;
esac
