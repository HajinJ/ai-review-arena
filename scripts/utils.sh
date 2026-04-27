#!/usr/bin/env bash
# ai-review-arena: source-compatible utility shim.
# Implementations live in arena_runtime.support_runtime.

if [ "${_ARENA_UTILS_LOADED:-}" = "true" ]; then
  return 0 2>/dev/null || true
fi
_ARENA_UTILS_LOADED="true"

UTILS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_PLUGIN_DIR="$(cd "$UTILS_SCRIPT_DIR/.." && pwd)"

_arena_runtime_py() {
  if [ -f "$UTILS_SCRIPT_DIR/arena-runtime.py" ]; then
    printf '%s\n' "$UTILS_SCRIPT_DIR/arena-runtime.py"
    return 0
  fi
  local search_dir="$PWD"
  while [ "$search_dir" != "/" ]; do
    if [ -f "$search_dir/scripts/arena-runtime.py" ] && [ -d "$search_dir/arena_runtime" ]; then
      printf '%s\n' "$search_dir/scripts/arena-runtime.py"
      return 0
    fi
    search_dir="$(dirname "$search_dir")"
  done
  printf '%s\n' "$UTILS_SCRIPT_DIR/arena-runtime.py"
}

_arena_support() {
  ARENA_UTILS_PLUGIN_DIR="$UTILS_PLUGIN_DIR" python3 "$(_arena_runtime_py)" support-utils "$@"
}

log_info() { echo "[arena:info] $*" >&2; }
log_warn() { echo "[arena:warn] $*" >&2; }
log_error() { echo "[arena:error] $*" >&2; }
log_stderr_file() {
  local label="$1" logfile="$2"
  if [ -f "$logfile" ] && [ -s "$logfile" ]; then
    log_warn "${label}: $(head -c 500 "$logfile")"
  fi
  rm -f "$logfile" 2>/dev/null || true
}
safe_jq() { _arena_support safe-jq "$@"; }
is_valid_json() { _arena_support is-valid-json "$1"; }
ensure_jq() { _arena_support ensure-jq; }
arena_timeout() { _arena_support timeout "$@"; }
project_hash() { _arena_support project-hash "$1"; }
find_project_root() { _arena_support find-project-root; }
cache_base_dir() { _arena_support cache-base-dir "$1"; }
merge_configs() { _arena_support merge-configs "$@"; }
load_config() { _arena_support load-config "${1:-}"; }
load_config_file() { _arena_support load-config-file "${1:-}"; }
get_config_value() { _arena_support get-config-value "$1" "$2"; }
extract_json() { _arena_support extract-json "$1"; }
get_current_year() { _arena_support get-current-year; }
format_timestamp() { _arena_support format-timestamp "$1"; }
pipeline_memory_snapshot() { _arena_support pipeline-memory-snapshot "$1"; }
pipeline_memory_reset() { _arena_support pipeline-memory-reset; }
validate_cache_content() { _arena_support validate-cache-content "$1"; }
atomic_write() { _arena_support atomic-write "$1" "$2"; }
atomic_write_stdin() { _arena_support atomic-write-stdin "$1"; }
