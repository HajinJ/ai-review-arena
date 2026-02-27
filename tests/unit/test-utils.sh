#!/usr/bin/env bash
# =============================================================================
# Tests for scripts/utils.sh
# =============================================================================

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$TESTS_DIR/test-helpers.sh"

# Reset double-source guard so we can source utils.sh
unset _ARENA_UTILS_LOADED

source "$REPO_DIR/scripts/utils.sh"

echo "=== test-utils.sh ==="

# =========================================================================
# Test: load_config with default only
# =========================================================================

setup_temp_dir

# Create a fake plugin dir structure with just default config
FAKE_PLUGIN="$TEMP_DIR/plugin"
mkdir -p "$FAKE_PLUGIN/config" "$FAKE_PLUGIN/scripts"

cat > "$FAKE_PLUGIN/config/default-config.json" <<'EOF'
{"models": {"claude": {"enabled": true}}, "output": {"language": "ko"}}
EOF

# Override UTILS_PLUGIN_DIR so load_config uses our fake structure
ORIG_PLUGIN_DIR="$UTILS_PLUGIN_DIR"
UTILS_PLUGIN_DIR="$FAKE_PLUGIN"

# Remove global config if test creates one
ORIG_HOME="$HOME"

# Use a temp HOME to avoid reading real global config
export HOME="$TEMP_DIR/fakehome"
mkdir -p "$HOME/.claude"

result=$(load_config "/nonexistent/project")
# With only default config, load_config returns the default file path directly
assert_contains "$result" "default-config.json" "load_config: default only returns default path"

config_content=$(cat "$result" 2>/dev/null)
assert_json_valid "$config_content" "load_config: default config is valid JSON"

# =========================================================================
# Test: load_config with default + global
# =========================================================================

cat > "$HOME/.claude/.ai-review-arena.json" <<'EOF'
{"output": {"language": "en"}}
EOF

# Force regeneration of merged config
rm -f "${TMPDIR:-/tmp}"/arena-config-merged.*.json 2>/dev/null

result=$(load_config "/nonexistent/project")
config_content=$(cat "$result" 2>/dev/null)
assert_json_valid "$config_content" "load_config: default+global merged config is valid JSON"

lang=$(echo "$config_content" | jq -r '.output.language')
assert_eq "$lang" "en" "load_config: global overrides default language"

claude_enabled=$(echo "$config_content" | jq -r '.models.claude.enabled')
assert_eq "$claude_enabled" "true" "load_config: default value preserved after merge"

# =========================================================================
# Test: load_config with default + global + project
# =========================================================================

PROJECT_DIR="$TEMP_DIR/myproject"
mkdir -p "$PROJECT_DIR"

cat > "$PROJECT_DIR/.ai-review-arena.json" <<'EOF'
{"output": {"language": "ja"}, "review": {"intensity": "deep"}}
EOF

# Force regeneration
rm -f "${TMPDIR:-/tmp}"/arena-config-merged.*.json 2>/dev/null

result=$(load_config "$PROJECT_DIR")
config_content=$(cat "$result" 2>/dev/null)
assert_json_valid "$config_content" "load_config: 3-level merged config is valid JSON"

lang=$(echo "$config_content" | jq -r '.output.language')
assert_eq "$lang" "ja" "load_config: project overrides global language"

intensity=$(echo "$config_content" | jq -r '.review.intensity')
assert_eq "$intensity" "deep" "load_config: project-level review.intensity present"

claude_enabled=$(echo "$config_content" | jq -r '.models.claude.enabled')
assert_eq "$claude_enabled" "true" "load_config: base default value still present in 3-level merge"

# =========================================================================
# Test: get_config_value with valid path
# =========================================================================

cat > "$TEMP_DIR/test-config.json" <<'EOF'
{"models": {"claude": {"enabled": true, "roles": ["security", "bugs"]}}, "output": {"language": "ko"}}
EOF

val=$(get_config_value "$TEMP_DIR/test-config.json" '.output.language')
assert_eq "$val" "ko" "get_config_value: valid path returns value"

val=$(get_config_value "$TEMP_DIR/test-config.json" '.models.claude.enabled')
assert_eq "$val" "true" "get_config_value: nested boolean path"

# =========================================================================
# Test: get_config_value with missing path
# =========================================================================

val=$(get_config_value "$TEMP_DIR/test-config.json" '.nonexistent.path')
assert_eq "$val" "" "get_config_value: missing path returns empty"

# =========================================================================
# Test: get_config_value with missing file
# =========================================================================

get_config_value "/nonexistent/file.json" '.anything'
rc=$?
assert_exit_code 1 "$rc" "get_config_value: missing file returns exit 1"

# =========================================================================
# Test: extract_json with plain JSON
# =========================================================================

input='{"findings": [{"title": "bug"}]}'
result=$(extract_json "$input")
assert_json_valid "$result" "extract_json: plain JSON is valid"
title=$(echo "$result" | jq -r '.findings[0].title')
assert_eq "$title" "bug" "extract_json: plain JSON content preserved"

# =========================================================================
# Test: extract_json with ```json block
# =========================================================================

input='Here is the result:
```json
{"score": 85, "items": ["a", "b"]}
```
Done.'

result=$(extract_json "$input")
assert_json_valid "$result" "extract_json: json code block extracted"
score=$(echo "$result" | jq -r '.score')
assert_eq "$score" "85" "extract_json: json code block value correct"

# =========================================================================
# Test: extract_json with ``` block (no language tag)
# =========================================================================

input='Output:
```
{"key": "value"}
```'

result=$(extract_json "$input")
assert_json_valid "$result" "extract_json: generic code block extracted"
val=$(echo "$result" | jq -r '.key')
assert_eq "$val" "value" "extract_json: generic code block value correct"

# =========================================================================
# Test: extract_json with embedded JSON in text
# =========================================================================

input='The analysis shows: {"severity": "high", "confidence": 90} which means critical.'
result=$(extract_json "$input")
assert_json_valid "$result" "extract_json: embedded JSON extracted"

# =========================================================================
# Test: extract_json with invalid input
# =========================================================================

input='This is just plain text with no JSON at all'
extract_json "$input"
rc=$?
assert_exit_code 1 "$rc" "extract_json: invalid input returns exit 1"

# =========================================================================
# Test: project_hash determinism
# =========================================================================

hash1=$(project_hash "/some/path")
hash2=$(project_hash "/some/path")
assert_eq "$hash1" "$hash2" "project_hash: same path produces same hash"

hash3=$(project_hash "/other/path")
assert_not_eq "$hash1" "$hash3" "project_hash: different path produces different hash"

# =========================================================================
# Test: format_timestamp
# =========================================================================

result=$(format_timestamp 0)
assert_contains "$result" "1970" "format_timestamp: epoch 0 gives 1970"

# Restore
UTILS_PLUGIN_DIR="$ORIG_PLUGIN_DIR"
export HOME="$ORIG_HOME"

# Cleanup merged temp files we created
rm -f "${TMPDIR:-/tmp}"/arena-config-merged.*.json 2>/dev/null

print_summary
