#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Test Helper Library
#
# Source this file in every test:
#   source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
#
# Provides: assert_eq, assert_contains, assert_json_valid, assert_file_exists,
#           assert_exit_code, setup_temp_dir, cleanup, colored output, counters.
# =============================================================================

# --- Counters ---
TEST_PASS=0
TEST_FAIL=0
TEST_TOTAL=0
TEST_CURRENT_NAME=""

# --- Colors ---
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  NC=''
fi

# --- Test Lifecycle ---

test_start() {
  TEST_CURRENT_NAME="$1"
  TEST_TOTAL=$((TEST_TOTAL + 1))
}

# Aliases used by integration tests
test_begin() { test_start "$@"; }
test_end() { :; }

skip() {
  local msg="${1:-skipped}"
  TEST_PASS=$((TEST_PASS + 1))
  TEST_TOTAL=$((TEST_TOTAL + 1))
  printf "${YELLOW}  SKIP${NC} %s\n" "$msg"
}

log_info() {
  printf "  INFO %s\n" "$1"
}

pass() {
  local msg="${1:-$TEST_CURRENT_NAME}"
  TEST_PASS=$((TEST_PASS + 1))
  printf "${GREEN}  PASS${NC} %s\n" "$msg"
}

fail() {
  local msg="${1:-$TEST_CURRENT_NAME}"
  shift || true
  TEST_FAIL=$((TEST_FAIL + 1))
  printf "${RED}  FAIL${NC} %s\n" "$msg"
  if [ $# -gt 0 ]; then
    printf "       %s\n" "$@"
  fi
}

# --- Assertions ---

assert_eq() {
  local actual="$1"
  local expected="$2"
  local msg="${3:-assert_eq}"
  test_start "$msg"
  if [ "$actual" = "$expected" ]; then
    pass "$msg"
  else
    fail "$msg" "expected: '$expected'" "  actual: '$actual'"
  fi
}

assert_not_eq() {
  local actual="$1"
  local unexpected="$2"
  local msg="${3:-assert_not_eq}"
  test_start "$msg"
  if [ "$actual" != "$unexpected" ]; then
    pass "$msg"
  else
    fail "$msg" "should not equal: '$unexpected'"
  fi
}

assert_contains() {
  local string="$1"
  local substring="$2"
  local msg="${3:-assert_contains}"
  test_start "$msg"
  if echo "$string" | grep -qF "$substring"; then
    pass "$msg"
  else
    fail "$msg" "expected to contain: '$substring'" "  in: '$(echo "$string" | head -c 200)'"
  fi
}

assert_not_contains() {
  local string="$1"
  local substring="$2"
  local msg="${3:-assert_not_contains}"
  test_start "$msg"
  if ! echo "$string" | grep -qF "$substring"; then
    pass "$msg"
  else
    fail "$msg" "should not contain: '$substring'"
  fi
}

assert_json_valid() {
  local json_string="$1"
  local msg="${2:-assert_json_valid}"
  test_start "$msg"
  if echo "$json_string" | jq . &>/dev/null; then
    pass "$msg"
  else
    fail "$msg" "invalid JSON: '$(echo "$json_string" | head -c 200)'"
  fi
}

assert_file_exists() {
  local path="$1"
  local msg="${2:-assert_file_exists}"
  test_start "$msg"
  if [ -f "$path" ]; then
    pass "$msg"
  else
    fail "$msg" "file not found: '$path'"
  fi
}

assert_dir_exists() {
  local path="$1"
  local msg="${2:-assert_dir_exists}"
  test_start "$msg"
  if [ -d "$path" ]; then
    pass "$msg"
  else
    fail "$msg" "directory not found: '$path'"
  fi
}

assert_exit_code() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-assert_exit_code}"
  test_start "$msg"
  if [ "$actual" -eq "$expected" ]; then
    pass "$msg"
  else
    fail "$msg" "expected exit code: $expected" "  actual exit code: $actual"
  fi
}

assert_gt() {
  local actual="$1"
  local threshold="$2"
  local msg="${3:-assert_gt}"
  test_start "$msg"
  if [ "$actual" -gt "$threshold" ]; then
    pass "$msg"
  else
    fail "$msg" "expected > $threshold, got $actual"
  fi
}

# --- Temp Directory ---

TEMP_DIR=""

setup_temp_dir() {
  TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/arena-test.XXXXXX")
  export TEMP_DIR
}

cleanup() {
  if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
  fi
}

# Auto-cleanup on exit
trap cleanup EXIT

# --- Summary ---

print_summary() {
  local test_file="${1:-$(basename "${BASH_SOURCE[1]}" 2>/dev/null || echo "tests")}"
  echo ""
  echo "--- $test_file ---"
  printf "Total: %d  ${GREEN}Pass: %d${NC}  ${RED}Fail: %d${NC}\n" "$TEST_TOTAL" "$TEST_PASS" "$TEST_FAIL"
  if [ "$TEST_FAIL" -gt 0 ]; then
    return 1
  fi
  return 0
}

# --- Utility: create mock command in PATH ---

mock_command() {
  local name="$1"
  local output="${2:-}"
  local exit_code="${3:-0}"

  if [ -z "$TEMP_DIR" ]; then
    setup_temp_dir
  fi

  local mock_bin="$TEMP_DIR/bin"
  mkdir -p "$mock_bin"

  cat > "$mock_bin/$name" <<MOCK_EOF
#!/usr/bin/env bash
echo "$output"
exit $exit_code
MOCK_EOF
  chmod +x "$mock_bin/$name"

  # Prepend to PATH if not already there
  case ":$PATH:" in
    *":$mock_bin:"*) ;;
    *) export PATH="$mock_bin:$PATH" ;;
  esac
}

# --- Utility: remove mock command from PATH ---

unmock_command() {
  local name="$1"
  if [ -n "$TEMP_DIR" ] && [ -f "$TEMP_DIR/bin/$name" ]; then
    rm -f "$TEMP_DIR/bin/$name"
  fi
}
