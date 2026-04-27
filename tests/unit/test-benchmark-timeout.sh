#!/usr/bin/env bash
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/test-helpers.sh"

echo "=== test-benchmark-timeout.sh ==="
setup_temp_dir

MOCK_BIN="$TEMP_DIR/bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/codex" <<'MOCK'
#!/usr/bin/env bash
sleep 5
echo '{"findings":[{"title":"late","severity":"low"}]}'
MOCK
cat > "$MOCK_BIN/gemini" <<'MOCK'
#!/usr/bin/env bash
sleep 5
echo '{"findings":[{"title":"late","severity":"low"}]}'
MOCK
chmod +x "$MOCK_BIN/codex" "$MOCK_BIN/gemini"

OLD_PATH="$PATH"
export PATH="$MOCK_BIN:$PATH"
start=$(date +%s)
result=$(python3 "$REPO_DIR/scripts/arena-runtime.py" benchmark-models --category security --models codex,gemini --live --timeout 1 --max-cases 1 --max-parallel 2 --json 2>/dev/null)
rc=$?
end=$(date +%s)
elapsed=$((end - start))
export PATH="$OLD_PATH"

assert_exit_code 0 "$rc" "benchmark timeout: exits successfully"
assert_json_valid "$result" "benchmark timeout: output is valid JSON"
assert_eq "$(echo "$result" | jq '.runtime.timeout_seconds')" "1" "benchmark timeout: timeout is reported"
assert_eq "$(echo "$result" | jq '.runtime.cases_selected')" "1" "benchmark timeout: max-cases limits work"
assert_contains "$result" "timed out" "benchmark timeout: timed out provider is reported"

if [ "$elapsed" -lt 5 ]; then
  pass "benchmark timeout: slow providers are bounded (${elapsed}s)"
else
  fail "benchmark timeout: expected <5s, got ${elapsed}s"
fi

bounded_result=$(python3 "$REPO_DIR/scripts/arena-runtime.py" benchmark-models --category security --models claude --json 2>/dev/null)
assert_json_valid "$bounded_result" "benchmark default: output is valid JSON"
assert_eq "$(echo "$bounded_result" | jq '.runtime.max_cases')" "2" "benchmark default: bounded sample is the default"
assert_eq "$(echo "$bounded_result" | jq '.runtime.live')" "false" "benchmark default: live calls are explicit"
assert_eq "$(echo "$bounded_result" | jq '.runtime.full')" "false" "benchmark default: full mode is explicit"
assert_eq "$(echo "$bounded_result" | jq '.runtime.sampled')" "true" "benchmark default: sampled run is reported"

print_summary
