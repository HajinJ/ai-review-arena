#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/test-helpers.sh"
setup_temp_dir

provider_output="$(cd "$ROOT_DIR" && python3 scripts/arena-runtime.py provider-smoke --models codex,gemini,claude --timeout 1)"
assert_json_valid "$provider_output" "provider-smoke emits valid JSON"
assert_contains "$provider_output" "non_interactive_ready" "provider-smoke reports non-interactive readiness"

cat > "$TEMP_DIR/mcp-secure.json" <<'JSON'
{
  "mcp": {
    "allowed_tools": ["local.echo", "local.env"],
    "side_effect_tools": [],
    "security": {
      "env_allowlist": ["PATH", "ARENA_TEST_SECRET"],
      "redact_env_patterns": ["*SECRET*"],
      "allowed_commands": ["cat", "printenv"],
      "allowed_cwd_roots": ["."],
      "stdout_limit_bytes": 32,
      "stderr_limit_bytes": 32
    },
    "servers": {
      "local": {
        "tools": {
          "echo": {"command": ["cat"], "side_effect": false},
          "env": {"command": ["printenv", "ARENA_TEST_SECRET"], "side_effect": false}
        }
      }
    }
  }
}
JSON
mcp_blocked="$(cd "$ROOT_DIR" && python3 scripts/arena-runtime.py mcp-tool-call --config "$TEMP_DIR/mcp-secure.json" --server local --tool missing --input-json '{}')"
assert_json_valid "$mcp_blocked" "mcp blocked output is valid JSON"
assert_contains "$mcp_blocked" "not allowlisted" "mcp blocks unlisted tool"
ARENA_TEST_SECRET="super-secret-value" mcp_redacted="$(cd "$ROOT_DIR" && python3 scripts/arena-runtime.py mcp-tool-call --config "$TEMP_DIR/mcp-secure.json" --server local --tool env --input-json '{}')"
assert_not_contains "$mcp_redacted" "super-secret-value" "mcp redacts secret stdout"
assert_contains "$mcp_redacted" '"stdout": ""' "mcp does not pass secret env into tool"

PROJECT="$TEMP_DIR/project"
mkdir -p "$PROJECT/src"
cat > "$PROJECT/src/auth.py" <<'PY'
def validate_token(token):
    if token == "unsafe":
        return True
    return token.startswith("tok_")
PY
cat > "$TEMP_DIR/rag-semantic.json" <<'JSON'
{
  "rag": {
    "enabled": true,
    "semantic_backend": "local-hash-v1",
    "semantic_dims": 64,
    "semantic_weight": 0.5,
    "index_extensions": [".py"]
  }
}
JSON
(cd "$ROOT_DIR" && python3 scripts/arena-runtime.py rag-indexer "$PROJECT" --config "$TEMP_DIR/rag-semantic.json" >/dev/null)
evidence="$(cd "$ROOT_DIR" && python3 scripts/arena-runtime.py rag-evidence "$PROJECT" security "validate token" --config "$TEMP_DIR/rag-semantic.json" --top-k 1)"
assert_json_valid "$evidence" "semantic rag evidence emits JSON"
assert_contains "$evidence" "semantic" "semantic ranking metadata is present"

dashboard_output="$(cd "$ROOT_DIR" && python3 scripts/arena-runtime.py dashboard-build --runs-dir cache/runs --output "$TEMP_DIR/dashboard/index.html")"
assert_json_valid "$dashboard_output" "dashboard-build emits valid JSON"
assert_file_exists "$TEMP_DIR/dashboard/index.html" "dashboard-build writes HTML"
assert_file_exists "$TEMP_DIR/dashboard/summary.json" "dashboard-build writes summary JSON"

print_summary "$(basename "$0")"
