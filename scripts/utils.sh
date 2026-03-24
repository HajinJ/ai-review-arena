#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Shared Utility Library
#
# Provides common functions for all arena scripts.
# Source this file: source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
#
# Functions:
#   log_info, log_warn, log_error  - structured logging to stderr
#   log_stderr_file                - log stderr from temp file, then cleanup
#   safe_jq                        - jq with error logging (not silent)
#   is_valid_json                  - check if string is valid JSON
#   ensure_jq                      - verify jq is available
#   project_hash                   - deterministic hash from path
#   find_project_root              - git root or pwd
#   cache_base_dir                 - per-project cache directory
#   load_config                    - find and merge configs (default → global → project)
#   load_config_file               - find single highest-priority config file
#   merge_configs                  - deep merge multiple JSON config files
#   get_config_value               - jq wrapper for config values
#   get_current_year               - current year string
#   format_timestamp               - human readable from epoch
#   pipeline_memory_snapshot       - frozen memory read for pipeline consistency
#   pipeline_memory_reset          - reset snapshot between pipeline runs
#   validate_cache_content         - injection scanning for cache/memory writes
#   atomic_write                   - atomic file write via temp+mv
#   atomic_write_stdin             - atomic file write from stdin
#
# Error Handling Convention:
#   - External CLI calls: capture stderr via log_stderr_file(), never 2>/dev/null
#   - jq on validated input: no 2>/dev/null (errors indicate real bugs)
#   - jq on external/optional input: 2>/dev/null OK (input may be absent)
#   - Conditional validity checks (if ... | jq . &>/dev/null): OK
#   - System commands (kill, wait, rm): 2>/dev/null OK (noise suppression)
#   - Always prefer `|| fallback` over `2>/dev/null` when possible
# =============================================================================

# Guard against double-sourcing
if [ "${_ARENA_UTILS_LOADED:-}" = "true" ]; then
  return 0 2>/dev/null || true
fi
_ARENA_UTILS_LOADED="true"

# --- Resolve paths ---
UTILS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_PLUGIN_DIR="$(dirname "$UTILS_SCRIPT_DIR")"

# =============================================================================
# Logging (all output to stderr)
# =============================================================================

log_info() {
  echo "[arena:info] $*" >&2
}

log_warn() {
  echo "[arena:warn] $*" >&2
}

log_error() {
  echo "[arena:error] $*" >&2
}

# =============================================================================
# Stderr Logging (for replacing dangerous 2>/dev/null)
# =============================================================================

# Log stderr from a temp file if non-empty, then clean up.
# Usage: some_command 2>"$errfile" || true; log_stderr_file "label" "$errfile"
log_stderr_file() {
  local label="$1" logfile="$2"
  if [ -f "$logfile" ] && [ -s "$logfile" ]; then
    log_warn "${label}: $(head -c 500 "$logfile")"
    rm -f "$logfile"
  elif [ -f "$logfile" ]; then
    rm -f "$logfile"
  fi
}

# =============================================================================
# Safe JSON Helpers
# =============================================================================

# Safe jq: run jq with error logging instead of silent suppression.
# Usage: safe_jq '.field' "$file"           → stdout result, log on error
# Usage: safe_jq '.field' <<< "$json_var"   → same with stdin
# Returns: jq output on success, empty string on failure (exit 0 always)
safe_jq() {
  local filter="$1"
  shift
  local result
  if result=$(jq -r "$filter" "$@" 2>&1); then
    echo "$result"
  else
    log_warn "jq parse error (filter: $filter): ${result:0:200}"
    echo ""
  fi
}

# Validate JSON string. Returns 0 if valid, 1 if not.
# Usage: is_valid_json "$var" && echo "ok"
is_valid_json() {
  [ -n "$1" ] && echo "$1" | jq . &>/dev/null
}

# =============================================================================
# Dependency Checks
# =============================================================================

ensure_jq() {
  if ! command -v jq &>/dev/null; then
    log_error "jq is required but not found. Install: brew install jq"
    exit 1
  fi
}

# macOS-compatible timeout wrapper
# Usage: arena_timeout <seconds> <command> [args...]
arena_timeout() {
  local secs="$1"
  shift
  if command -v timeout &>/dev/null; then
    timeout "${secs}s" "$@"
  elif command -v gtimeout &>/dev/null; then
    gtimeout "${secs}s" "$@"
  else
    # Pure bash fallback using background process + kill
    "$@" &
    local pid=$!
    (
      sleep "$secs"
      kill "$pid" 2>/dev/null
    ) &
    local watchdog=$!
    wait "$pid" 2>/dev/null
    local ret=$?
    kill "$watchdog" 2>/dev/null || true
    wait "$watchdog" 2>/dev/null
    return $ret
  fi
}

# =============================================================================
# Project Identification
# =============================================================================

project_hash() {
  local path="${1:?Usage: project_hash <path>}"
  echo -n "$path" | shasum -a 256 | cut -c1-20
}

find_project_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

# =============================================================================
# Cache Management
# =============================================================================

cache_base_dir() {
  local project_root="${1:?Usage: cache_base_dir <project_root>}"
  local hash
  hash=$(project_hash "$project_root")
  echo "${UTILS_PLUGIN_DIR}/cache/${hash}"
}

# =============================================================================
# Configuration
# =============================================================================

merge_configs() {
  # Deep-merge multiple JSON config files using jq.
  # Usage: merge_configs file1 [file2] [file3]
  # Later files override earlier ones (deep merge).
  local files=()
  local f
  for f in "$@"; do
    if [ -f "$f" ]; then
      files+=("$f")
    fi
  done

  if [ ${#files[@]} -eq 0 ]; then
    echo "{}"
    return 1
  fi

  if [ ${#files[@]} -eq 1 ]; then
    cat "${files[0]}"
    return 0
  fi

  # jq -s deep merge: .[0] * .[1] * .[2] ...
  local merge_expr=".[0]"
  local i=1
  while [ "$i" -lt "${#files[@]}" ]; do
    merge_expr="${merge_expr} * .[$i]"
    i=$((i + 1))
  done

  jq -s "$merge_expr" "${files[@]}" 2>/dev/null || cat "${files[0]}"
}

load_config() {
  # Returns path to a merged config temp file.
  # Merge order: default → global → project (later overrides earlier).
  # Caller should use the output path directly.
  local project_root="${1:-}"

  local default_config="${UTILS_PLUGIN_DIR}/config/default-config.json"
  local global_config="$HOME/.claude/.ai-review-arena.json"
  local project_config=""
  if [ -n "$project_root" ]; then
    project_config="$project_root/.ai-review-arena.json"
  fi

  local configs_to_merge=()

  # 1. Default config (base)
  if [ -f "$default_config" ]; then
    configs_to_merge+=("$default_config")
  fi

  # 2. Global user config (overrides default)
  if [ -f "$global_config" ]; then
    configs_to_merge+=("$global_config")
  fi

  # 3. Project config (overrides global)
  if [ -n "$project_config" ] && [ -f "$project_config" ]; then
    configs_to_merge+=("$project_config")
  fi

  if [ ${#configs_to_merge[@]} -eq 0 ]; then
    return 1
  fi

  # If only default config exists, return it directly (no merge needed)
  if [ ${#configs_to_merge[@]} -eq 1 ]; then
    echo "${configs_to_merge[0]}"
    return 0
  fi

  # Merge into a deterministic temp file keyed by project hash (avoids orphan accumulation)
  # Use $TMPDIR (per-user on macOS /var/folders/...) to avoid /tmp symlink attacks
  local config_hash
  config_hash=$(echo -n "${configs_to_merge[*]}" | shasum -a 256 | cut -c1-12)
  local merged_tmp="${TMPDIR:-/tmp}/arena-config-merged.${config_hash}.json"

  # Only regenerate if missing or source configs are newer
  local needs_regen=false
  if [ ! -f "$merged_tmp" ]; then
    needs_regen=true
  else
    for cfg_src in "${configs_to_merge[@]}"; do
      if [ "$cfg_src" -nt "$merged_tmp" ] 2>/dev/null; then
        needs_regen=true
        break
      fi
    done
  fi

  if [ "$needs_regen" = "true" ]; then
    # Safety: refuse to write through symlinks (prevents symlink attack)
    [ -L "$merged_tmp" ] && rm -f "$merged_tmp"
    merge_configs "${configs_to_merge[@]}" > "$merged_tmp"
  fi

  echo "$merged_tmp"
  return 0
}

load_config_file() {
  # Legacy: returns the single highest-priority config file path (no merge).
  # Use load_config() for merged config instead.
  local project_root="${1:-}"

  if [ -n "$project_root" ] && [ -f "$project_root/.ai-review-arena.json" ]; then
    echo "$project_root/.ai-review-arena.json"
    return 0
  fi

  if [ -f "$HOME/.claude/.ai-review-arena.json" ]; then
    echo "$HOME/.claude/.ai-review-arena.json"
    return 0
  fi

  if [ -f "${UTILS_PLUGIN_DIR}/config/default-config.json" ]; then
    echo "${UTILS_PLUGIN_DIR}/config/default-config.json"
    return 0
  fi

  return 1
}

get_config_value() {
  local config_file="${1:?Usage: get_config_value <config_file> <jq_path>}"
  local jq_path="${2:?Usage: get_config_value <config_file> <jq_path>}"

  if [ ! -f "$config_file" ]; then
    return 1
  fi

  jq -r "$jq_path // empty" "$config_file" 2>/dev/null
}

# =============================================================================
# JSON Extraction (shared — replaces 6 duplicated copies)
# =============================================================================

extract_json() {
  local input="$1"

  # Try 1: Input is already valid JSON
  if echo "$input" | jq . &>/dev/null 2>&1; then
    echo "$input"
    return 0
  fi

  # Try 2: Extract from markdown code blocks (```json or ```)
  local extracted
  local pattern
  for pattern in '/^```json/,/^```$/p' '/^```/,/^```$/p'; do
    extracted=$(echo "$input" | sed -n "$pattern" | sed '1d;$d')
    if [ -n "$extracted" ] && echo "$extracted" | jq . &>/dev/null 2>&1; then
      echo "$extracted"
      return 0
    fi
  done

  # Try 3: Fallback — extract first { to last }
  extracted=$(echo "$input" | sed -n '/^[[:space:]]*{/,/}[[:space:]]*$/p')
  if [ -n "$extracted" ] && echo "$extracted" | jq . &>/dev/null 2>&1; then
    echo "$extracted"
    return 0
  fi

  return 1
}

# =============================================================================
# Time Utilities
# =============================================================================

get_current_year() {
  date +%Y
}

format_timestamp() {
  local epoch="${1:?Usage: format_timestamp <epoch_seconds>}"

  # macOS date vs GNU date
  if date -r 0 &>/dev/null 2>&1; then
    # macOS / BSD
    date -r "$epoch" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$epoch"
  else
    # GNU/Linux
    date -d "@$epoch" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$epoch"
  fi
}

# =============================================================================
# Pipeline Memory Snapshot (Frozen Snapshot Pattern)
# =============================================================================
# Reads memory state once and stores it. All subsequent pipeline phases use the
# snapshot instead of live reads, preventing mid-pipeline memory mutations from
# creating inconsistent agent behavior.
# Inspired by Hermes Agent's frozen system prompt pattern.

_PIPELINE_MEMORY_SNAPSHOT=""
_PIPELINE_MEMORY_SNAPSHOT_LOADED="false"

# Capture a frozen snapshot of memory state for the current pipeline run.
# Call once at pipeline start (Phase 0). Subsequent calls are no-ops.
# Usage: pipeline_memory_snapshot <project-root>
pipeline_memory_snapshot() {
  local project_root="${1:?Usage: pipeline_memory_snapshot <project-root>}"

  if [ "$_PIPELINE_MEMORY_SNAPSHOT_LOADED" = "true" ]; then
    echo "$_PIPELINE_MEMORY_SNAPSHOT"
    return 0
  fi

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  # Collect all memory tiers into a single JSON snapshot
  local working short_term long_term permanent
  working=$("$script_dir/cache-manager.sh" memory-list "$project_root" working 2>/dev/null || echo "[]")
  short_term=$("$script_dir/cache-manager.sh" memory-list "$project_root" short-term 2>/dev/null || echo "[]")
  long_term=$("$script_dir/cache-manager.sh" memory-list "$project_root" long-term 2>/dev/null || echo "[]")
  permanent=$("$script_dir/cache-manager.sh" memory-list "$project_root" permanent 2>/dev/null || echo "[]")

  _PIPELINE_MEMORY_SNAPSHOT=$(jq -cn \
    --argjson w "$working" \
    --argjson s "$short_term" \
    --argjson l "$long_term" \
    --argjson p "$permanent" \
    '{working: $w, short_term: $s, long_term: $l, permanent: $p, snapshot_epoch: now | floor}' 2>/dev/null || echo '{}')

  _PIPELINE_MEMORY_SNAPSHOT_LOADED="true"
  echo "$_PIPELINE_MEMORY_SNAPSHOT"
}

# Reset snapshot (e.g., between pipeline runs in ralph-loop)
pipeline_memory_reset() {
  _PIPELINE_MEMORY_SNAPSHOT=""
  _PIPELINE_MEMORY_SNAPSHOT_LOADED="false"
}

# =============================================================================
# Content Injection Scanning
# =============================================================================
# Scans content before writing to cache/memory/signal-log to prevent prompt
# injection attacks that could influence agent behavior.
# Inspired by Hermes Agent's memory injection scanner.

# Returns 0 if content is safe, 1 if injection detected.
# Usage: validate_cache_content "$content" && echo "safe"
validate_cache_content() {
  local content="$1"

  if [ -z "$content" ]; then
    return 0
  fi

  # Prompt injection patterns
  if echo "$content" | grep -qiE 'ignore (previous|prior|above|all) (instructions|prompts|rules)'; then
    log_warn "Injection scan: prompt override pattern detected"
    return 1
  fi
  if echo "$content" | grep -qiE 'you are now|new (system|base) prompt|override (system|your)'; then
    log_warn "Injection scan: identity override pattern detected"
    return 1
  fi
  if echo "$content" | grep -qiE 'system prompt[:\s]|<\|im_start\|>system|<system>'; then
    log_warn "Injection scan: system prompt injection pattern detected"
    return 1
  fi

  # Data exfiltration patterns
  if echo "$content" | grep -qiE '(curl|wget|fetch|nc|ncat)\s+https?://[^ ]*\.(txt|log|env|key|pem|json)'; then
    log_warn "Injection scan: data exfiltration pattern detected"
    return 1
  fi

  # Invisible unicode (zero-width chars used to hide instructions)
  if echo "$content" | grep -qP '[\x{200B}\x{200C}\x{200D}\x{FEFF}\x{2060}]' 2>/dev/null; then
    log_warn "Injection scan: invisible unicode characters detected"
    return 1
  fi

  return 0
}

# =============================================================================
# Atomic File Write
# =============================================================================
# Writes content to a file atomically via temp file + mv.
# Prevents partial-write corruption from concurrent access.
# Inspired by Hermes Agent's tempfile.mkstemp() + os.replace() pattern.
#
# Usage: atomic_write <target-path> <content>
#    or: echo "content" | atomic_write_stdin <target-path>
atomic_write() {
  local target="${1:?Usage: atomic_write <target> <content>}"
  local content="$2"
  local dir
  dir=$(dirname "$target")
  mkdir -p "$dir"

  local tmp
  tmp=$(mktemp "${target}.XXXXXX") || return 1
  echo "$content" > "$tmp" && mv "$tmp" "$target"
}

# Atomic write from stdin (for piped content)
atomic_write_stdin() {
  local target="${1:?Usage: echo 'content' | atomic_write_stdin <target>}"
  local dir
  dir=$(dirname "$target")
  mkdir -p "$dir"

  local tmp
  tmp=$(mktemp "${target}.XXXXXX") || return 1
  cat > "$tmp" && mv "$tmp" "$target"
}
