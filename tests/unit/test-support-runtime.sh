#!/usr/bin/env bash
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/test-helpers.sh"

echo "=== test-support-runtime.sh ==="
setup_temp_dir

hash1=$(python3 "$REPO_DIR/scripts/arena-runtime.py" support-utils project-hash /tmp/example)
hash2=$(python3 "$REPO_DIR/scripts/arena-runtime.py" support-utils project-hash /tmp/example)
assert_eq "$hash1" "$hash2" "support-utils: project hash is deterministic"

json=$(python3 "$REPO_DIR/scripts/arena-runtime.py" support-utils extract-json 'prefix {"ok":true} suffix')
assert_eq "$(echo "$json" | jq -r '.ok')" "true" "support-utils: extracts embedded JSON"

metrics=$(python3 "$REPO_DIR/scripts/arena-runtime.py" benchmark-utils compute-metrics 3 1 1)
assert_eq "$metrics" ".750 .750 .750" "benchmark-utils: computes bc-compatible metrics"

setup_output=$(python3 "$REPO_DIR/scripts/arena-runtime.py" setup-arena --verbose)
assert_contains "$setup_output" "Extended Setup Check" "setup-arena: reports setup status"
assert_contains "$setup_output" "Plugin dir" "setup-arena: verbose includes paths"

source "$REPO_DIR/scripts/utils.sh"
shim_hash1=$(project_hash /tmp/example)
assert_eq "$shim_hash1" "$hash1" "utils.sh shim: delegates project_hash"

source "$REPO_DIR/scripts/benchmark-utils.sh"
shim_metrics=$(compute_metrics 3 1 1)
assert_eq "$shim_metrics" ".750 .750 .750" "benchmark-utils.sh shim: delegates compute_metrics"

print_summary
