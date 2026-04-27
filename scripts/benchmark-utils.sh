#!/usr/bin/env bash
# ai-review-arena: source-compatible benchmark utility shim.
# Implementations live in arena_runtime.support_runtime.

if [ "${_ARENA_BENCHMARK_UTILS_LOADED:-}" = "true" ]; then
  return 0 2>/dev/null || true
fi
_ARENA_BENCHMARK_UTILS_LOADED="true"

BENCH_UTILS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$BENCH_UTILS_SCRIPT_DIR/utils.sh"

_arena_benchmark_utils() {
  ARENA_UTILS_PLUGIN_DIR="$UTILS_PLUGIN_DIR" python3 "$(_arena_runtime_py)" benchmark-utils "$@"
}

extract_text() { _arena_benchmark_utils extract-text "$1"; }
count_matches() { _arena_benchmark_utils count-matches "$1" "$2" "$3" "${4:-false}"; }
compute_metrics() { _arena_benchmark_utils compute-metrics "$1" "$2" "$3"; }
severity_weight() { _arena_benchmark_utils severity-weight "$1"; }
compute_weighted_f1() { _arena_benchmark_utils compute-weighted-f1 "$1" "$2" "$3" "$4"; }
