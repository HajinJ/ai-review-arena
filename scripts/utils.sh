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
#   load_config                    - find config with precedence
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
  echo -n "$path" | shasum -a 256 | cut -c1-12
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

load_config() {
  local project_root="${1:-}"

  # 1. Project-level config
  if [ -n "$project_root" ] && [ -f "$project_root/.ai-review-arena.json" ]; then
    echo "$project_root/.ai-review-arena.json"
    return 0
  fi

  # 2. Global user config
  if [ -f "$HOME/.claude/.ai-review-arena.json" ]; then
    echo "$HOME/.claude/.ai-review-arena.json"
    return 0
  fi

  # 3. Default config bundled with plugin
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
