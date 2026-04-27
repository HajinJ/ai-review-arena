#!/usr/bin/env bash
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/test-helpers.sh"

echo "=== test-provider-runner.sh ==="
setup_temp_dir

MOCK_BIN="$TEMP_DIR/bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/codex" <<'MOCK'
#!/usr/bin/env bash
if [ "$1" = "exec" ]; then
  shift
fi
echo '{"findings":[{"title":"Mock issue","severity":"high","description":"mock desc","line":1}],"summary":"ok"}'
MOCK
chmod +x "$MOCK_BIN/codex"

cat > "$TEMP_DIR/config.json" <<'JSON'
{"timeout": 5, "models": {"codex": {"enabled": true, "use_user_default": true, "structured_output": false}}}
JSON

OLD_PATH="$PATH"
export PATH="$MOCK_BIN:$PATH"
result=$(printf 'const x = 1;' | python3 "$REPO_DIR/scripts/arena-runtime.py" codex-review test.js "$TEMP_DIR/config.json" security 2>/dev/null)
export PATH="$OLD_PATH"
assert_json_valid "$result" "provider-runner: output is valid JSON"
model=$(echo "$result" | jq -r '.model')
count=$(echo "$result" | jq '.findings | length')
assert_eq "$model" "codex" "provider-runner: model normalized"
assert_eq "$count" "1" "provider-runner: findings normalized"

print_summary
