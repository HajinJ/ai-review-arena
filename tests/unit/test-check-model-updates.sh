#!/usr/bin/env bash
# =============================================================================
# Tests for scripts/check-model-updates.sh
# =============================================================================

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$TESTS_DIR/test-helpers.sh"

SCRIPT="$REPO_DIR/scripts/check-model-updates.sh"

echo "=== test-check-model-updates.sh ==="

setup_temp_dir

# --- Setup fake plugin structure ---
FAKE_PLUGIN="$TEMP_DIR/plugin"
mkdir -p "$FAKE_PLUGIN/scripts" "$FAKE_PLUGIN/cache" "$FAKE_PLUGIN/config"

cp "$REPO_DIR/scripts/utils.sh" "$FAKE_PLUGIN/scripts/"
cp "$REPO_DIR/scripts/cache-manager.sh" "$FAKE_PLUGIN/scripts/"
cp "$REPO_DIR/scripts/check-model-updates.sh" "$FAKE_PLUGIN/scripts/"

SCRIPT="$FAKE_PLUGIN/scripts/check-model-updates.sh"

# --- Create test config ---
create_config() {
  local enabled="${1:-true}"
  cat > "$TEMP_DIR/config.json" <<EOF
{
  "models": {
    "codex": { "model_variant": "gpt-5.4" },
    "gemini": { "model_variant": "gemini-3-pro-preview" }
  },
  "output": { "language": "ko" },
  "model_updates": {
    "enabled": $enabled,
    "ttl_days": 7,
    "api_timeout_seconds": 5,
    "providers": {
      "openai": {
        "enabled": true,
        "family_pattern": "^gpt-5",
        "api_endpoint": "https://api.openai.com/v1/models"
      },
      "gemini": {
        "enabled": true,
        "family_pattern": "gemini-3",
        "api_endpoint": "https://generativelanguage.googleapis.com/v1beta/models"
      },
      "anthropic": {
        "enabled": true,
        "family_pattern": "^claude-",
        "api_endpoint": "https://api.anthropic.com/v1/models"
      }
    }
  }
}
EOF
}

# --- Mock curl for different provider responses ---
MOCK_BIN="$TEMP_DIR/bin"
mkdir -p "$MOCK_BIN"

create_curl_mock() {
  local openai_response="$1"
  local gemini_response="$2"
  local anthropic_response="$3"

  cat > "$MOCK_BIN/curl" <<MOCK_EOF
#!/usr/bin/env bash
# Determine which API is being called from the URL
for arg in "\$@"; do
  case "\$arg" in
    *openai.com*)
      cat <<'OPENAI_JSON'
$openai_response
OPENAI_JSON
      exit 0
      ;;
    *generativelanguage.googleapis.com*)
      cat <<'GEMINI_JSON'
$gemini_response
GEMINI_JSON
      exit 0
      ;;
    *anthropic.com*)
      cat <<'ANTHROPIC_JSON'
$anthropic_response
ANTHROPIC_JSON
      exit 0
      ;;
  esac
done
echo '{"error":"unknown endpoint"}'
exit 1
MOCK_EOF
  chmod +x "$MOCK_BIN/curl"
}

# =========================================================================
# Test: parse_openai_response — filter gpt-5.* models
# =========================================================================

create_config
create_curl_mock \
  '{"data":[{"id":"gpt-5.5","created":1709600000},{"id":"gpt-5.4","created":1709500000},{"id":"gpt-4o","created":1709400000}]}' \
  '{"models":[]}' \
  '{"data":[]}'

export OPENAI_API_KEY="test-key"
export GEMINI_API_KEY=""
export ANTHROPIC_API_KEY=""
export PATH="$MOCK_BIN:$PATH"

result=$(bash "$SCRIPT" "$TEMP_DIR/config.json" --force --json 2>/dev/null)
rc=$?
assert_exit_code 0 "$rc" "parse_openai_response: exits 0"

# Check that gpt-5.5 is detected as latest
openai_latest=$(echo "$result" | jq -r '.results[] | select(.provider == "openai") | .latest' 2>/dev/null)
assert_eq "$openai_latest" "gpt-5.5" "parse_openai_response: detects gpt-5.5 as latest"

openai_update=$(echo "$result" | jq -r '.results[] | select(.provider == "openai") | .update_available' 2>/dev/null)
assert_eq "$openai_update" "true" "parse_openai_response: update_available is true"

# =========================================================================
# Test: parse_gemini_response — filter gemini-3.* models
# =========================================================================

create_config
create_curl_mock \
  '{"data":[]}' \
  '{"models":[{"name":"models/gemini-3.1-pro-preview","displayName":"Gemini 3.1 Pro Preview"},{"name":"models/gemini-3-pro-preview","displayName":"Gemini 3 Pro Preview"},{"name":"models/gemini-2.0-flash","displayName":"Gemini 2.0 Flash"}]}' \
  '{"data":[]}'

export OPENAI_API_KEY=""
export GEMINI_API_KEY="test-key"
export ANTHROPIC_API_KEY=""

result=$(bash "$SCRIPT" "$TEMP_DIR/config.json" --force --json 2>/dev/null)

gemini_latest=$(echo "$result" | jq -r '.results[] | select(.provider == "gemini") | .latest' 2>/dev/null)
assert_eq "$gemini_latest" "gemini-3.1-pro-preview" "parse_gemini_response: detects gemini-3.1-pro-preview (models/ prefix removed)"

gemini_update=$(echo "$result" | jq -r '.results[] | select(.provider == "gemini") | .update_available' 2>/dev/null)
assert_eq "$gemini_update" "true" "parse_gemini_response: update_available is true"

# =========================================================================
# Test: parse_anthropic_response — filter claude-* models
# =========================================================================

create_config
create_curl_mock \
  '{"data":[]}' \
  '{"models":[]}' \
  '{"data":[{"id":"claude-sonnet-4-6-20260301","created_at":"2026-03-01T00:00:00Z"},{"id":"claude-opus-4-6-20260301","created_at":"2026-03-01T00:00:00Z"},{"id":"claude-haiku-4-5-20251001","created_at":"2025-10-01T00:00:00Z"}]}'

export OPENAI_API_KEY=""
export GEMINI_API_KEY=""
export ANTHROPIC_API_KEY="test-key"

result=$(bash "$SCRIPT" "$TEMP_DIR/config.json" --force --json 2>/dev/null)

anthropic_count=$(echo "$result" | jq -r '.results[] | select(.provider == "anthropic") | .update_available' 2>/dev/null)
# Since no current anthropic model is set in config, update_available should be false (no_data)
assert_eq "$anthropic_count" "false" "parse_anthropic_response: no current model set → no update flagged"

# =========================================================================
# Test: compare_same_version — no update when versions match
# =========================================================================

create_config
create_curl_mock \
  '{"data":[{"id":"gpt-5.4","created":1709500000}]}' \
  '{"models":[{"name":"models/gemini-3-pro-preview","displayName":"Gemini 3 Pro Preview"}]}' \
  '{"data":[]}'

export OPENAI_API_KEY="test-key"
export GEMINI_API_KEY="test-key"
export ANTHROPIC_API_KEY=""

result=$(bash "$SCRIPT" "$TEMP_DIR/config.json" --force --json 2>/dev/null)

openai_update=$(echo "$result" | jq -r '.results[] | select(.provider == "openai") | .update_available' 2>/dev/null)
assert_eq "$openai_update" "false" "compare_same_version: openai gpt-5.4 == gpt-5.4 → no update"

gemini_update=$(echo "$result" | jq -r '.results[] | select(.provider == "gemini") | .update_available' 2>/dev/null)
assert_eq "$gemini_update" "false" "compare_same_version: gemini matches → no update"

# =========================================================================
# Test: compare_newer_version — update detected
# =========================================================================

create_config
create_curl_mock \
  '{"data":[{"id":"gpt-5.5","created":1709600000},{"id":"gpt-5.4","created":1709500000}]}' \
  '{"models":[{"name":"models/gemini-3.1-pro-preview","displayName":"Gemini 3.1 Pro Preview"}]}' \
  '{"data":[]}'

export OPENAI_API_KEY="test-key"
export GEMINI_API_KEY="test-key"
export ANTHROPIC_API_KEY=""

result=$(bash "$SCRIPT" "$TEMP_DIR/config.json" --force --json 2>/dev/null)

openai_update=$(echo "$result" | jq -r '.results[] | select(.provider == "openai") | .update_available' 2>/dev/null)
assert_eq "$openai_update" "true" "compare_newer_version: gpt-5.5 > gpt-5.4 → update available"

openai_current=$(echo "$result" | jq -r '.results[] | select(.provider == "openai") | .current' 2>/dev/null)
assert_eq "$openai_current" "gpt-5.4" "compare_newer_version: current is gpt-5.4"

# =========================================================================
# Test: missing_api_key — graceful skip (exit 0)
# =========================================================================

create_config

export OPENAI_API_KEY=""
export GEMINI_API_KEY=""
export ANTHROPIC_API_KEY=""

result=$(bash "$SCRIPT" "$TEMP_DIR/config.json" --force --json 2>/dev/null)
rc=$?
assert_exit_code 0 "$rc" "missing_api_key: exits 0 even with no API keys"
assert_json_valid "$result" "missing_api_key: output is valid JSON"

# All providers should have no update available
no_updates=$(echo "$result" | jq -r '[.results[] | select(.update_available == true)] | length' 2>/dev/null)
assert_eq "$no_updates" "0" "missing_api_key: no updates when all keys missing"

# =========================================================================
# Test: invalid_json_response — graceful handling
# =========================================================================

create_config

# Create a curl mock that returns invalid JSON for OpenAI
cat > "$MOCK_BIN/curl" <<'MOCK_EOF'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in
    *openai.com*)
      echo "NOT VALID JSON {{{{"
      exit 0
      ;;
    *) ;;
  esac
done
echo '{"data":[]}'
exit 0
MOCK_EOF
chmod +x "$MOCK_BIN/curl"

export OPENAI_API_KEY="test-key"
export GEMINI_API_KEY=""
export ANTHROPIC_API_KEY=""

result=$(bash "$SCRIPT" "$TEMP_DIR/config.json" --force --json 2>/dev/null)
rc=$?
assert_exit_code 0 "$rc" "invalid_json_response: exits 0"
assert_json_valid "$result" "invalid_json_response: output is still valid JSON"

# OpenAI should have no update (invalid response was skipped)
openai_update=$(echo "$result" | jq -r '.results[] | select(.provider == "openai") | .update_available' 2>/dev/null)
assert_eq "$openai_update" "false" "invalid_json_response: no update from invalid response"

# =========================================================================
# Test: config_disabled — immediate exit
# =========================================================================

create_config false

result=$(bash "$SCRIPT" "$TEMP_DIR/config.json" --force --json 2>/dev/null)
rc=$?
assert_exit_code 0 "$rc" "config_disabled: exits 0"

# Should produce no output when disabled (no --json output since exit before main logic)
test_start "config_disabled: no JSON output when disabled"
if [ -z "$result" ]; then
  pass "config_disabled: no JSON output when disabled"
else
  fail "config_disabled: no JSON output when disabled" "got: $result"
fi

# =========================================================================
# Test: cache_hit — does not call API when cache is fresh
# =========================================================================

create_config

# Restore working curl mock
create_curl_mock \
  '{"data":[{"id":"gpt-5.5","created":1709600000}]}' \
  '{"models":[]}' \
  '{"data":[]}'

export OPENAI_API_KEY="test-key"
export GEMINI_API_KEY=""
export ANTHROPIC_API_KEY=""

# First run: populates cache
bash "$SCRIPT" "$TEMP_DIR/config.json" --force --json 2>/dev/null > /dev/null

# Create a curl that records if it's called
cat > "$MOCK_BIN/curl" <<'MOCK_EOF'
#!/usr/bin/env bash
echo "CURL_WAS_CALLED" > /tmp/arena-curl-called-marker
echo '{"data":[]}'
exit 0
MOCK_EOF
chmod +x "$MOCK_BIN/curl"
rm -f /tmp/arena-curl-called-marker

# Second run: should use cache (no --force)
result2=$(bash "$SCRIPT" "$TEMP_DIR/config.json" --json 2>/dev/null)
rc=$?
assert_exit_code 0 "$rc" "cache_hit: exits 0"

test_start "cache_hit: curl not called on cache hit"
if [ -f /tmp/arena-curl-called-marker ]; then
  fail "cache_hit: curl not called on cache hit" "curl was called despite cache being fresh"
  rm -f /tmp/arena-curl-called-marker
else
  pass "cache_hit: curl not called on cache hit"
fi

# =========================================================================
# Test: force_bypasses_cache — --force always calls API
# =========================================================================

# curl marker mock is still in place from previous test
rm -f /tmp/arena-curl-called-marker

# Re-create a useful curl mock that also sets the marker
create_curl_mock \
  '{"data":[{"id":"gpt-5.5","created":1709600000}]}' \
  '{"models":[]}' \
  '{"data":[]}'

# Wrap the mock to also set marker
cat > "$MOCK_BIN/curl" <<'MOCK_EOF'
#!/usr/bin/env bash
touch /tmp/arena-curl-called-marker
for arg in "$@"; do
  case "$arg" in
    *openai.com*)
      echo '{"data":[{"id":"gpt-5.5","created":1709600000}]}'
      exit 0
      ;;
  esac
done
echo '{"data":[]}'
exit 0
MOCK_EOF
chmod +x "$MOCK_BIN/curl"

result3=$(bash "$SCRIPT" "$TEMP_DIR/config.json" --force --json 2>/dev/null)
rc=$?
assert_exit_code 0 "$rc" "force_bypasses_cache: exits 0"

test_start "force_bypasses_cache: curl called with --force"
if [ -f /tmp/arena-curl-called-marker ]; then
  pass "force_bypasses_cache: curl called with --force"
  rm -f /tmp/arena-curl-called-marker
else
  fail "force_bypasses_cache: curl called with --force" "curl was not called despite --force"
fi

# =========================================================================
# Cleanup
# =========================================================================

rm -f /tmp/arena-curl-called-marker

print_summary "test-check-model-updates.sh"
