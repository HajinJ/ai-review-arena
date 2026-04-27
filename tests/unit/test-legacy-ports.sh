#!/usr/bin/env bash
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/test-helpers.sh"

echo "=== test-legacy-ports.sh ==="
setup_temp_dir

inventory=$(python3 "$REPO_DIR/scripts/arena-runtime.py" legacy-inventory --json)
assert_json_valid "$inventory" "legacy-inventory: output is valid JSON"
assert_eq "$(echo "$inventory" | jq '.counts.legacy_runtime_logic // 0')" "0" "legacy-inventory: no legacy runtime shell remains"
assert_eq "$(echo "$inventory" | jq '.counts.support_shell // 0')" "0" "legacy-inventory: no support shell remains"

docs=$(python3 "$REPO_DIR/scripts/arena-runtime.py" doc-inventory --root "$REPO_DIR" --config "$REPO_DIR/config/default-config.json")
assert_json_valid "$docs" "doc-inventory: output is valid JSON"
if [ "$(echo "$docs" | jq '.total_files')" -gt 0 ]; then pass "doc-inventory: finds documentation"; else fail "doc-inventory: expected docs"; fi

best=$(python3 "$REPO_DIR/scripts/arena-runtime.py" search-best-practices javascript --version 2026)
assert_json_valid "$best" "search-best-practices: output is valid JSON"
assert_eq "$(echo "$best" | jq '.search_queries | length')" "3" "search-best-practices: generic fallback queries generated"
assert_eq "$(echo "$best" | jq -r '.resolved_technology')" "null" "search-best-practices: does not overmatch javascript to java"

guidelines=$(python3 "$REPO_DIR/scripts/arena-runtime.py" search-guidelines auth web)
assert_json_valid "$guidelines" "search-guidelines: output is valid JSON"
if [ "$(echo "$guidelines" | jq '.guidelines | length')" -gt 0 ]; then pass "search-guidelines: finds matching guidelines"; else fail "search-guidelines: expected guidelines"; fi

monitor_dir="$TEMP_DIR/monitor"
mkdir -p "$monitor_dir"
printf '%s\n' \
  '{"source":"codex","type":"finding_stream","data":{"severity":"high","file":"a.js","line":1,"title":"A"}}' \
  '{"source":"gemini","type":"finding_stream","data":{"severity":"critical","file":"a.js","line":1,"title":"B"}}' \
  > "$monitor_dir/signals.jsonl"
python3 "$REPO_DIR/scripts/arena-runtime.py" stream-monitor "$monitor_dir" --timeout 1
assert_file_exists "$monitor_dir/conflicts.jsonl" "stream-monitor: conflict log created"
assert_eq "$(wc -l < "$monitor_dir/conflicts.jsonl" | tr -d ' ')" "1" "stream-monitor: detects one conflict"

daemon_root="$TEMP_DIR/project"
mkdir -p "$daemon_root"
ticket=$(python3 "$REPO_DIR/scripts/arena-runtime.py" review-daemon enqueue "$daemon_root" 42 --intensity quick)
status=$(python3 "$REPO_DIR/scripts/arena-runtime.py" review-daemon status "$daemon_root" "$ticket")
assert_eq "$(echo "$status" | jq -r '.status')" "queued" "review-daemon: enqueues ticket"
processed=$(python3 "$REPO_DIR/scripts/arena-runtime.py" review-daemon process "$daemon_root")
assert_eq "$(echo "$processed" | jq -r '.status')" "completed" "review-daemon: processes ticket"
listed=$(python3 "$REPO_DIR/scripts/arena-runtime.py" review-daemon list "$daemon_root")
assert_eq "$(echo "$listed" | jq 'length')" "1" "review-daemon: lists ticket"

ralph_root="$TEMP_DIR/ralph"
mkdir -p "$ralph_root"
ralph=$(python3 "$REPO_DIR/scripts/arena-runtime.py" ralph-loop "$ralph_root" --max-iterations 1)
assert_eq "$(echo "$ralph" | jq -r '.status')" "clean" "ralph-loop: returns clean deterministic status"
assert_file_exists "$ralph_root/ralph-loop-log.md" "ralph-loop: writes log"

harness=$(python3 "$REPO_DIR/scripts/arena-runtime.py" harness-stress-test --phase 5.8 --dry-run)
assert_contains "$harness" "DRY RUN" "harness-stress-test: dry run reports plan"

invalid=$(printf '{"findings_from":[],"code_context":{}}' | python3 "$REPO_DIR/scripts/arena-runtime.py" codex-cross-examine "$TEMP_DIR/no-config.json" invalid-round)
assert_eq "$(echo "$invalid" | jq -r '.model')" "codex" "codex-cross-examine: invalid round returns JSON"
assert_contains "$invalid" "Invalid round" "codex-cross-examine: invalid round error reported"

mock_bin="$TEMP_DIR/bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/codex" <<'MOCK'
#!/usr/bin/env bash
echo '{"findings":[{"title":"Mock issue","severity":"high","description":"mock","line":1}],"summary":"ok"}'
MOCK
chmod +x "$mock_bin/codex"
code_file="$TEMP_DIR/a.js"
printf 'const x = 1;\n' > "$code_file"
config_file="$TEMP_DIR/config.json"
printf '{"timeout":5,"models":{"codex":{"enabled":true,"use_user_default":true,"structured_output":false,"multi_agent":{"max_threads":2,"job_max_runtime_seconds":5}}}}\n' > "$config_file"
OLD_PATH="$PATH"
export PATH="$mock_bin:$PATH"
batch=$(python3 "$REPO_DIR/scripts/arena-runtime.py" codex-batch-review security "$config_file" "$code_file")
export PATH="$OLD_PATH"
assert_json_valid "$batch" "codex-batch-review: output is valid JSON"
assert_eq "$(echo "$batch" | jq 'length')" "1" "codex-batch-review: returns one result"

print_summary
