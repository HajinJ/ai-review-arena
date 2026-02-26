#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Shared Utility Library
#
# Provides common functions for all arena scripts.
# Source this file: source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
#
# Functions:
#   log_info, log_warn, log_error  - structured logging to stderr
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
# Dependency Checks
# =============================================================================

ensure_jq() {
  if ! command -v jq &>/dev/null; then
    log_error "jq is required but not found. Install: brew install jq"
    exit 1
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
  local config_hash
  config_hash=$(echo -n "${configs_to_merge[*]}" | shasum -a 256 | cut -c1-12)
  local merged_tmp="/tmp/arena-config-merged.${config_hash}.json"

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

  # Try 2: Extract from ```json ... ``` blocks
  local extracted
  extracted=$(echo "$input" | sed -n '/^```json/,/^```$/p' | sed '1d;$d')
  if [ -n "$extracted" ] && echo "$extracted" | jq . &>/dev/null 2>&1; then
    echo "$extracted"
    return 0
  fi

  # Try 3: Extract from ``` ... ``` blocks (no language tag)
  extracted=$(echo "$input" | sed -n '/^```/,/^```$/p' | sed '1d;$d')
  if [ -n "$extracted" ] && echo "$extracted" | jq . &>/dev/null 2>&1; then
    echo "$extracted"
    return 0
  fi

  # Try 4: Find outermost JSON object using jq -R (robust brace matching)
  extracted=$(echo "$input" | jq -Rsc '
    # Find first { and extract to end, let jq validate
    if test("\\{") then
      capture("(?<json>\\{.+)").json // empty
    else empty end
  ' 2>/dev/null)
  if [ -n "$extracted" ]; then
    # Try parsing the extracted substring
    local parsed
    parsed=$(echo "$extracted" | jq -r '.' 2>/dev/null)
    if [ -n "$parsed" ] && echo "$parsed" | jq . &>/dev/null 2>&1; then
      echo "$parsed"
      return 0
    fi
  fi

  # Try 5: Fallback — sed-based first { to last }
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
