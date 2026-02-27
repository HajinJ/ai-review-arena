#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Test Runner
#
# Usage: tests/run-tests.sh [--unit] [--integration] [pattern]
#
# Runs all test files in tests/unit/ and tests/integration/ sequentially.
# Prints colored pass/fail summary and exits 0 if all pass, 1 if any fail.
# =============================================================================

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Colors ---
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  BOLD=''
  NC=''
fi

# --- Arguments ---
RUN_UNIT=true
RUN_INTEGRATION=true
RUN_E2E=false
RUN_LINT=false
PATTERN=""

while [ $# -gt 0 ]; do
  case "$1" in
    --unit)
      RUN_UNIT=true
      RUN_INTEGRATION=false
      shift
      ;;
    --integration)
      RUN_UNIT=false
      RUN_INTEGRATION=true
      shift
      ;;
    --e2e)
      RUN_E2E=true
      RUN_UNIT=false
      RUN_INTEGRATION=false
      shift
      ;;
    --lint)
      RUN_LINT=true
      RUN_UNIT=false
      RUN_INTEGRATION=false
      shift
      ;;
    --all)
      RUN_UNIT=true
      RUN_INTEGRATION=true
      RUN_E2E=true
      RUN_LINT=true
      shift
      ;;
    *)
      PATTERN="$1"
      shift
      ;;
  esac
done

# --- Collect test files ---
TEST_FILES=()

if [ "$RUN_UNIT" = true ] && [ -d "$TESTS_DIR/unit" ]; then
  for f in "$TESTS_DIR"/unit/test-*.sh; do
    [ -f "$f" ] || continue
    if [ -n "$PATTERN" ]; then
      case "$(basename "$f")" in
        *"$PATTERN"*) TEST_FILES+=("$f") ;;
      esac
    else
      TEST_FILES+=("$f")
    fi
  done
fi

if [ "$RUN_INTEGRATION" = true ] && [ -d "$TESTS_DIR/integration" ]; then
  for f in "$TESTS_DIR"/integration/test-*.sh; do
    [ -f "$f" ] || continue
    if [ -n "$PATTERN" ]; then
      case "$(basename "$f")" in
        *"$PATTERN"*) TEST_FILES+=("$f") ;;
      esac
    else
      TEST_FILES+=("$f")
    fi
  done
fi

# Mock E2E tests (no external CLIs needed) always run with integration tests
if [ "$RUN_INTEGRATION" = true ] && [ -d "$TESTS_DIR/e2e" ]; then
  for f in "$TESTS_DIR"/e2e/test-mock-*.sh; do
    [ -f "$f" ] || continue
    if [ -n "$PATTERN" ]; then
      case "$(basename "$f")" in
        *"$PATTERN"*) TEST_FILES+=("$f") ;;
      esac
    else
      TEST_FILES+=("$f")
    fi
  done
fi

# Real E2E tests (require external CLIs) only with --e2e flag
if [ "$RUN_E2E" = true ] && [ -d "$TESTS_DIR/e2e" ]; then
  for f in "$TESTS_DIR"/e2e/test-*.sh; do
    [ -f "$f" ] || continue
    # Skip mock tests (already included above)
    case "$(basename "$f")" in test-mock-*) continue ;; esac
    if [ -n "$PATTERN" ]; then
      case "$(basename "$f")" in
        *"$PATTERN"*) TEST_FILES+=("$f") ;;
      esac
    else
      TEST_FILES+=("$f")
    fi
  done
fi

# --- Run shellcheck lint if requested ---
if [ "$RUN_LINT" = true ]; then
  if [ -f "$TESTS_DIR/run-shellcheck.sh" ]; then
    TEST_FILES+=("$TESTS_DIR/run-shellcheck.sh")
  else
    printf "${YELLOW}run-shellcheck.sh not found, skipping lint${NC}\n"
  fi
fi

if [ ${#TEST_FILES[@]} -eq 0 ]; then
  printf "${YELLOW}No test files found.${NC}\n"
  exit 0
fi

# --- Run tests ---
TOTAL_FILES=0
PASSED_FILES=0
FAILED_FILES=0
FAILED_NAMES=()

printf "\n${BOLD}AI Review Arena - Test Suite${NC}\n"
printf "Running %d test files...\n\n" "${#TEST_FILES[@]}"

for test_file in "${TEST_FILES[@]}"; do
  test_name=$(basename "$test_file")
  TOTAL_FILES=$((TOTAL_FILES + 1))

  printf "${BOLD}[%d/%d] %s${NC}\n" "$TOTAL_FILES" "${#TEST_FILES[@]}" "$test_name"

  # Run test in subshell to isolate failures
  # Integration/e2e tests get a 120s timeout to prevent hanging
  TEST_TIMEOUT=0
  case "$test_name" in
    *debate*|*orchestrate*|*fallback*|*mock-pipeline*) TEST_TIMEOUT=120 ;;
  esac

  if [ "$TEST_TIMEOUT" -gt 0 ]; then
    # Use timeout with fallback for macOS
    if command -v timeout &>/dev/null; then
      if timeout "${TEST_TIMEOUT}s" bash "$test_file"; then
        PASSED_FILES=$((PASSED_FILES + 1))
      else
        rc=$?
        if [ "$rc" -eq 124 ]; then
          printf "  ${YELLOW}TIMEOUT${NC} after ${TEST_TIMEOUT}s\n"
        fi
        FAILED_FILES=$((FAILED_FILES + 1))
        FAILED_NAMES+=("$test_name")
      fi
    elif command -v gtimeout &>/dev/null; then
      if gtimeout "${TEST_TIMEOUT}s" bash "$test_file"; then
        PASSED_FILES=$((PASSED_FILES + 1))
      else
        rc=$?
        if [ "$rc" -eq 124 ]; then
          printf "  ${YELLOW}TIMEOUT${NC} after ${TEST_TIMEOUT}s\n"
        fi
        FAILED_FILES=$((FAILED_FILES + 1))
        FAILED_NAMES+=("$test_name")
      fi
    else
      # Pure bash timeout fallback
      bash "$test_file" &
      local_pid=$!
      ( sleep "$TEST_TIMEOUT" && kill "$local_pid" 2>/dev/null ) &
      watchdog_pid=$!
      if wait "$local_pid" 2>/dev/null; then
        PASSED_FILES=$((PASSED_FILES + 1))
      else
        FAILED_FILES=$((FAILED_FILES + 1))
        FAILED_NAMES+=("$test_name")
      fi
      kill "$watchdog_pid" 2>/dev/null
      wait "$watchdog_pid" 2>/dev/null
    fi
  else
    if bash "$test_file"; then
      PASSED_FILES=$((PASSED_FILES + 1))
    else
      FAILED_FILES=$((FAILED_FILES + 1))
      FAILED_NAMES+=("$test_name")
    fi
  fi

  echo ""
done

# --- Summary ---
echo "================================================================"
printf "${BOLD}Test Suite Summary${NC}\n"
printf "  Files:  %d total, ${GREEN}%d passed${NC}, ${RED}%d failed${NC}\n" \
  "$TOTAL_FILES" "$PASSED_FILES" "$FAILED_FILES"

if [ "$FAILED_FILES" -gt 0 ]; then
  echo ""
  printf "${RED}Failed tests:${NC}\n"
  for name in "${FAILED_NAMES[@]}"; do
    printf "  - %s\n" "$name"
  done
  echo "================================================================"
  exit 1
fi

echo "================================================================"
printf "${GREEN}All tests passed.${NC}\n"
exit 0
