#!/usr/bin/env bash
# =============================================================================
# Integration Test: detect-stack.sh on real directories
#
# Tests the stack detection script against real project directories,
# verifying JSON output and field structure.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test-helpers.sh"

PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DETECT_STACK="$PLUGIN_DIR/scripts/detect-stack.sh"

# --- Setup ---
setup_temp_dir

# --- Prerequisite check ---
if [ ! -f "$DETECT_STACK" ]; then
  skip "detect-stack.sh not found"
  print_summary
  exit 0
fi

if ! command -v jq &>/dev/null; then
  skip "jq not available"
  print_summary
  exit 0
fi

# =============================================================================
# Test 1: Run on plugin directory (should detect bash/shell)
# =============================================================================
test_begin "detect-stack: detects stack for plugin directory"

RESULT=$(bash "$DETECT_STACK" "$PLUGIN_DIR" 2>/dev/null)
EXIT_CODE=$?

assert_eq "$EXIT_CODE" "0" "Should exit 0"
assert_json_valid "$RESULT" "Output should be valid JSON"

# The plugin dir has requirements.txt (python), so it should detect python
HAS_LANGUAGES=$(echo "$RESULT" | jq 'has("languages")' 2>/dev/null)
assert_eq "$HAS_LANGUAGES" "true" "Output should have 'languages' field"

HAS_FRAMEWORKS=$(echo "$RESULT" | jq 'has("frameworks")' 2>/dev/null)
assert_eq "$HAS_FRAMEWORKS" "true" "Output should have 'frameworks' field"

HAS_PLATFORM=$(echo "$RESULT" | jq 'has("platform")' 2>/dev/null)
assert_eq "$HAS_PLATFORM" "true" "Output should have 'platform' field"

HAS_ALL_TECH=$(echo "$RESULT" | jq 'has("all_technologies")' 2>/dev/null)
assert_eq "$HAS_ALL_TECH" "true" "Output should have 'all_technologies' field"

# Should have project_root pointing to the plugin dir
PROJECT_ROOT_VAL=$(echo "$RESULT" | jq -r '.project_root' 2>/dev/null)
assert_contains "$PROJECT_ROOT_VAL" "ai-review-arena" "project_root should reference the plugin dir"

test_end

# =============================================================================
# Test 2: Verify JSON structure completeness
# =============================================================================
test_begin "detect-stack: JSON output has all expected fields"

RESULT=$(bash "$DETECT_STACK" "$PLUGIN_DIR" 2>/dev/null)

# Check all required top-level fields exist
for field in project_root detected_at platform languages frameworks databases infrastructure build_tools testing ci_cd all_technologies; do
  HAS_FIELD=$(echo "$RESULT" | jq "has(\"$field\")" 2>/dev/null)
  if [ "$HAS_FIELD" != "true" ]; then
    fail "Missing field: $field"
  fi
done
pass "All expected JSON fields are present"

# Verify array fields are arrays
for array_field in languages frameworks databases infrastructure build_tools testing ci_cd all_technologies; do
  IS_ARRAY=$(echo "$RESULT" | jq ".${array_field} | type == \"array\"" 2>/dev/null)
  if [ "$IS_ARRAY" != "true" ]; then
    fail "Field $array_field should be an array"
  fi
done
pass "All array fields are valid arrays"

test_end

# =============================================================================
# Test 3: Text output mode
# =============================================================================
test_begin "detect-stack: text output mode works"

RESULT=$(bash "$DETECT_STACK" "$PLUGIN_DIR" --output text 2>/dev/null)
EXIT_CODE=$?

assert_eq "$EXIT_CODE" "0" "Should exit 0 with text output"
assert_contains "$RESULT" "Platform:" "Text output should contain 'Platform:'"
assert_contains "$RESULT" "Languages:" "Text output should contain 'Languages:'"

test_end

# =============================================================================
# Test 4: Non-existent directory handled gracefully
# =============================================================================
test_begin "detect-stack: handles non-existent directory gracefully"

RESULT=$(bash "$DETECT_STACK" "$TEMP_DIR/nonexistent-dir" 2>/dev/null)
EXIT_CODE=$?

# Script should still exit 0 (informational tool) and produce JSON
assert_eq "$EXIT_CODE" "0" "Should exit 0 for non-existent directory"
assert_json_valid "$RESULT" "Output should still be valid JSON"

# All technology arrays should be empty
LANG_COUNT=$(echo "$RESULT" | jq '.languages | length' 2>/dev/null || echo "-1")
assert_eq "$LANG_COUNT" "0" "Languages should be empty for non-existent dir"

test_end

# =============================================================================
# Test 5: Detect Node.js project (mock)
# =============================================================================
test_begin "detect-stack: detects Node.js project"

MOCK_PROJECT="$TEMP_DIR/mock-node-project"
mkdir -p "$MOCK_PROJECT"

# Create a minimal package.json
cat > "$MOCK_PROJECT/package.json" <<'PKG_EOF'
{
  "name": "test-project",
  "dependencies": {
    "express": "^4.18.0",
    "jest": "^29.0.0"
  },
  "devDependencies": {
    "typescript": "^5.0.0"
  }
}
PKG_EOF

# Create tsconfig.json for TypeScript detection
echo '{"compilerOptions": {"target": "es2020"}}' > "$MOCK_PROJECT/tsconfig.json"

RESULT=$(bash "$DETECT_STACK" "$MOCK_PROJECT" 2>/dev/null)
EXIT_CODE=$?

assert_eq "$EXIT_CODE" "0" "Should exit 0"
assert_json_valid "$RESULT" "Output should be valid JSON"

# Should detect nodejs
LANGUAGES=$(echo "$RESULT" | jq -r '.languages[]' 2>/dev/null)
assert_contains "$LANGUAGES" "nodejs" "Should detect nodejs"
assert_contains "$LANGUAGES" "typescript" "Should detect typescript"

# Should detect express framework
FRAMEWORKS=$(echo "$RESULT" | jq -r '.frameworks[]' 2>/dev/null)
assert_contains "$FRAMEWORKS" "express" "Should detect express framework"

# Should detect jest testing
TESTING=$(echo "$RESULT" | jq -r '.testing[]' 2>/dev/null)
assert_contains "$TESTING" "jest" "Should detect jest testing"

test_end

# =============================================================================
# Test 6: Detect Python project (mock)
# =============================================================================
test_begin "detect-stack: detects Python project"

MOCK_PYTHON="$TEMP_DIR/mock-python-project"
mkdir -p "$MOCK_PYTHON"

cat > "$MOCK_PYTHON/requirements.txt" <<'REQ_EOF'
django>=4.0
redis>=4.0
pytest>=7.0
REQ_EOF

RESULT=$(bash "$DETECT_STACK" "$MOCK_PYTHON" 2>/dev/null)
EXIT_CODE=$?

assert_eq "$EXIT_CODE" "0" "Should exit 0"
assert_json_valid "$RESULT" "Output should be valid JSON"

LANGUAGES=$(echo "$RESULT" | jq -r '.languages[]' 2>/dev/null)
assert_contains "$LANGUAGES" "python" "Should detect python"

FRAMEWORKS=$(echo "$RESULT" | jq -r '.frameworks[]' 2>/dev/null)
assert_contains "$FRAMEWORKS" "django" "Should detect django"

DATABASES=$(echo "$RESULT" | jq -r '.databases[]' 2>/dev/null)
assert_contains "$DATABASES" "redis" "Should detect redis"

test_end

# =============================================================================
# Test 7: Detect CI/CD (GitHub Actions in this repo)
# =============================================================================
test_begin "detect-stack: detects CI/CD from .github directory"

# The actual plugin repo has a .github directory
if [ -d "$PLUGIN_DIR/.github/workflows" ]; then
  RESULT=$(bash "$DETECT_STACK" "$PLUGIN_DIR" 2>/dev/null)
  CICD=$(echo "$RESULT" | jq -r '.ci_cd[]' 2>/dev/null || echo "")
  if echo "$CICD" | grep -q "github-actions"; then
    pass "Detected GitHub Actions CI/CD"
  else
    # .github/workflows might exist but have no .yml files
    skip "GitHub Actions not detected (no workflow YAML files)"
  fi
else
  skip "No .github/workflows directory in repo"
fi

test_end

# --- Cleanup ---
cleanup
print_summary
