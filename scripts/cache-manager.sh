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
#   cache-manager.sh search  <project-root> <query> [--tier <tier>] [--limit <N>]
#   cache-manager.sh graph-add   <project-root> <subject> <predicate> <object> [--metadata <json>]
#   cache-manager.sh graph-query <project-root> [--subject <s>] [--predicate <p>] [--object <o>]
#   cache-manager.sh graph-stats <project-root>
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
  stored_epoch=$(cat "$ts_file" || echo "0")
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
        stored_epoch=$(cat "$ts_file" || echo "0")
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
    stored_epoch=$(cat "$ts_file" || echo "0")
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
        echo "$(cat "$ts_file" || echo 0) $ts_file"
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
      dir_mtime=$(stat -f %m "$session_dir" || echo "0")
    else
      # GNU/Linux
      dir_mtime=$(stat -c %Y "$session_dir" || echo "0")
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
      file_mtime=$(stat -f %m "$tmp_config" || echo "0")
    else
      file_mtime=$(stat -c %Y "$tmp_config" || echo "0")
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
      [ -f "$ts_file" ] && stored_epoch=$(cat "$ts_file" || echo "0")

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
        [ -f "$ts_file" ] && stored_epoch=$(cat "$ts_file" || echo "0")

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
# FTS5 Search (Full-Text Search with BM25 ranking)
# =============================================================================
# Enhanced search using SQLite FTS5 for finding patterns across review history.
# Falls back to grep-based search if SQLite is not available.

cmd_search() {
  local project_root="${1:?Usage: cache-manager.sh search <project-root> <query> [--tier <tier>] [--limit <N>]}"
  local query="${2:?Usage: cache-manager.sh search <project-root> <query>}"
  shift 2

  ensure_jq

  local tier=""
  local limit=10

  while [ $# -gt 0 ]; do
    case "$1" in
      --tier) tier="${2:?--tier requires a value}"; shift 2 ;;
      --limit) limit="${2:?--limit requires a value}"; shift 2 ;;
      *) shift ;;
    esac
  done

  local base
  base=$(cache_base_dir "$project_root")

  # Try FTS5 with SQLite first
  if command -v sqlite3 &>/dev/null; then
    _search_fts5 "$base" "$query" "$tier" "$limit"
  else
    _search_grep "$base" "$query" "$tier" "$limit"
  fi
}

_search_fts5() {
  local base="$1"
  local query="$2"
  local tier="$3"
  local limit="$4"

  local db_file="${base}/search-index.sqlite"

  # Build index if needed
  if [ ! -f "$db_file" ]; then
    _build_fts5_index "$base" "$db_file"
  fi

  # Check if index is stale (older than 1 hour)
  local db_mtime=0
  if stat -f %m "$db_file" &>/dev/null 2>&1; then
    db_mtime=$(stat -f %m "$db_file" || echo "0")
  else
    db_mtime=$(stat -c %Y "$db_file" || echo "0")
  fi
  local now_epoch
  now_epoch=$(date +%s)
  local age=$((now_epoch - db_mtime))
  if [ "$age" -gt 3600 ]; then
    _build_fts5_index "$base" "$db_file"
  fi

  # Search with BM25 ranking
  local tier_filter=""
  if [ -n "$tier" ]; then
    tier_filter="AND tier = '${tier}'"
  fi

  sqlite3 -json "$db_file" "
    SELECT tier, key, snippet(search_idx, 2, '>>>', '<<<', '...', 32) as snippet,
           rank as bm25_score
    FROM search_idx
    WHERE search_idx MATCH '${query}' ${tier_filter}
    ORDER BY rank
    LIMIT ${limit};
  " 2>/dev/null || echo "[]"
}

_build_fts5_index() {
  local base="$1"
  local db_file="$2"

  rm -f "$db_file" 2>/dev/null

  sqlite3 "$db_file" "
    CREATE VIRTUAL TABLE IF NOT EXISTS search_idx USING fts5(
      tier,
      key,
      content,
      tokenize='porter unicode61'
    );
  " 2>/dev/null || return 1

  # Index all memory tier entries
  for tier_name in short-term long-term permanent; do
    local dir="${base}/memory/${tier_name}"
    [ -d "$dir" ] || continue

    for entry in "$dir"/*; do
      [ -f "$entry" ] || continue
      case "$entry" in *.timestamp) continue ;; esac

      local key
      key=$(basename "$entry")
      local content
      content=$(cat "$entry" 2>/dev/null | head -c 10000 | sed "s/'/''/g")

      sqlite3 "$db_file" "
        INSERT INTO search_idx(tier, key, content) VALUES ('${tier_name}', '${key}', '${content}');
      " 2>/dev/null || true
    done
  done

  # Also index signal log entries
  local signal_file="${base}/signal-log/signals.jsonl"
  if [ -f "$signal_file" ]; then
    while IFS= read -r line; do
      local agent_id
      agent_id=$(echo "$line" | jq -r '.agent_id // "unknown"' 2>/dev/null)
      local signal_type
      signal_type=$(echo "$line" | jq -r '.signal_type // "unknown"' 2>/dev/null)
      local data
      data=$(echo "$line" | jq -r '.data | tostring' 2>/dev/null | head -c 5000 | sed "s/'/''/g")

      sqlite3 "$db_file" "
        INSERT INTO search_idx(tier, key, content) VALUES ('signal-log', '${agent_id}:${signal_type}', '${data}');
      " 2>/dev/null || true
    done < "$signal_file"
  fi
}

_search_grep() {
  local base="$1"
  local query="$2"
  local tier="$3"
  local limit="$4"

  # Fallback: grep-based search with simple BM25-like scoring
  local results_jsonl=""
  local count=0

  local search_dirs=()
  if [ -n "$tier" ]; then
    search_dirs=("${base}/memory/${tier}")
  else
    search_dirs=("${base}/memory/short-term" "${base}/memory/long-term" "${base}/memory/permanent")
  fi

  for dir in "${search_dirs[@]}"; do
    [ -d "$dir" ] || continue
    local tier_name
    tier_name=$(basename "$dir")

    for entry in "$dir"/*; do
      [ -f "$entry" ] || continue
      case "$entry" in *.timestamp) continue ;; esac
      [ "$count" -ge "$limit" ] && break 2

      local key
      key=$(basename "$entry")
      local match_count=0
      match_count=$(grep -ci "$query" "$entry" 2>/dev/null || echo "0")

      if [ "$match_count" -gt 0 ]; then
        local snippet
        snippet=$(grep -i "$query" "$entry" 2>/dev/null | head -1 | cut -c1-200)
        results_jsonl="${results_jsonl}$(jq -cn \
          --arg tier "$tier_name" \
          --arg key "$key" \
          --arg snippet "$snippet" \
          --argjson score "$match_count" \
          '{tier: $tier, key: $key, snippet: $snippet, bm25_score: $score}')
"
        count=$((count + 1))
      fi
    done
  done

  if [ -n "$results_jsonl" ]; then
    echo "$results_jsonl" | jq -s 'sort_by(-.bm25_score)'
  else
    echo "[]"
  fi
}

# =============================================================================
# Knowledge Graph Commands
# =============================================================================
# Lightweight knowledge graph using JSONL for tracking finding relationships,
# agent performance, and pattern evolution across reviews.

cmd_graph_add() {
  local project_root="${1:?Usage: cache-manager.sh graph-add <project-root> <subject> <predicate> <object> [--metadata <json>]}"
  local subject="${2:?Missing subject}"
  local predicate="${3:?Missing predicate}"
  local object="${4:?Missing object}"
  shift 4

  ensure_jq

  local metadata="{}"
  while [ $# -gt 0 ]; do
    case "$1" in
      --metadata) metadata="${2:?--metadata requires JSON}"; shift 2 ;;
      *) shift ;;
    esac
  done

  local base
  base=$(cache_base_dir "$project_root")
  local graph_dir="${base}/knowledge-graph"
  mkdir -p "$graph_dir"
  local graph_file="${graph_dir}/triples.jsonl"

  local now_iso
  now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  jq -cn \
    --arg s "$subject" \
    --arg p "$predicate" \
    --arg o "$object" \
    --arg ts "$now_iso" \
    --argjson meta "$metadata" \
    '{subject: $s, predicate: $p, object: $o, timestamp: $ts, metadata: $meta}' \
    >> "$graph_file"

  return 0
}

cmd_graph_query() {
  local project_root="${1:?Usage: cache-manager.sh graph-query <project-root> [--subject <s>] [--predicate <p>] [--object <o>]}"
  shift 1

  ensure_jq

  local subject=""
  local predicate=""
  local object=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --subject) subject="${2:?--subject requires a value}"; shift 2 ;;
      --predicate) predicate="${2:?--predicate requires a value}"; shift 2 ;;
      --object) object="${2:?--object requires a value}"; shift 2 ;;
      *) shift ;;
    esac
  done

  local base
  base=$(cache_base_dir "$project_root")
  local graph_file="${base}/knowledge-graph/triples.jsonl"

  if [ ! -f "$graph_file" ]; then
    echo "[]"
    return 0
  fi

  local jq_filter="."
  if [ -n "$subject" ]; then
    jq_filter="${jq_filter} | select(.subject == \"$subject\")"
  fi
  if [ -n "$predicate" ]; then
    jq_filter="${jq_filter} | select(.predicate == \"$predicate\")"
  fi
  if [ -n "$object" ]; then
    jq_filter="${jq_filter} | select(.object == \"$object\")"
  fi

  jq -s "[.[] | $jq_filter]" "$graph_file" 2>/dev/null || echo "[]"
  return 0
}

cmd_graph_stats() {
  local project_root="${1:?Usage: cache-manager.sh graph-stats <project-root>}"

  ensure_jq

  local base
  base=$(cache_base_dir "$project_root")
  local graph_file="${base}/knowledge-graph/triples.jsonl"

  if [ ! -f "$graph_file" ]; then
    echo '{"total_triples": 0}'
    return 0
  fi

  jq -s '{
    total_triples: length,
    subjects: ([.[].subject] | unique | length),
    predicates: ([.[].predicate] | unique | sort),
    objects: ([.[].object] | unique | length),
    latest: (sort_by(.timestamp) | last.timestamp // "N/A")
  }' "$graph_file" 2>/dev/null || echo '{"total_triples": 0, "error": "parse_failed"}'
  return 0
}

# =============================================================================
# Main Dispatch
# =============================================================================

COMMAND="${1:-}"

if [ -z "$COMMAND" ]; then
  log_error "Usage: cache-manager.sh <read|write|check|list|cleanup|cleanup-sessions|hash|memory-read|memory-write|memory-list|search|graph-add|graph-query|graph-stats> ..."
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
  search)           cmd_search "$@" ;;
  graph-add)        cmd_graph_add "$@" ;;
  graph-query)      cmd_graph_query "$@" ;;
  graph-stats)      cmd_graph_stats "$@" ;;
  *)
    log_error "Unknown command: $COMMAND"
    exit 0
    ;;
esac
