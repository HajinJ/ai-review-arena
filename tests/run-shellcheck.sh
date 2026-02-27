#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: ShellCheck Runner
#
# Usage: tests/run-shellcheck.sh
#
# Runs shellcheck -S warning on all scripts/*.sh files with project-specific
# exclusions. Prints colored pass/fail per file and a summary.
#
# Excluded rules:
#   SC2086 - Word splitting (intentional in the codebase)
#   SC2046 - Word splitting in command substitution (intentional)
#   SC1091 - Can't follow sourced files (utils.sh sourced dynamically)
#
# Exit codes:
#   0 - All files pass (or shellcheck not installed)
#   1 - One or more files have warnings/errors
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPTS_DIR="$PROJECT_DIR/scripts"

# Shellcheck exclusions
EXCLUDED_RULES="SC2086,SC2046,SC1091"

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

# --- Check shellcheck installation ---
if ! command -v shellcheck &>/dev/null; then
  printf "${YELLOW}WARNING: shellcheck is not installed. Skipping lint checks.${NC}\n"
  printf "  Install with: brew install shellcheck (macOS) or apt-get install shellcheck (Ubuntu)\n"
  exit 0
fi

SHELLCHECK_VERSION=$(shellcheck --version | grep '^version:' | awk '{print $2}')
printf "${BOLD}ShellCheck Lint Runner${NC} (shellcheck %s)\n" "$SHELLCHECK_VERSION"
printf "Exclusions: %s\n" "$EXCLUDED_RULES"
printf "\n"

# --- Collect script files ---
SCRIPT_FILES=()
for f in "$SCRIPTS_DIR"/*.sh; do
  [ -f "$f" ] || continue
  SCRIPT_FILES+=("$f")
done

if [ ${#SCRIPT_FILES[@]} -eq 0 ]; then
  printf "${YELLOW}No shell scripts found in %s${NC}\n" "$SCRIPTS_DIR"
  exit 0
fi

printf "Checking %d files in scripts/...\n\n" "${#SCRIPT_FILES[@]}"

# --- Run shellcheck on each file ---
TOTAL=0
PASSED=0
FAILED=0
FAILED_NAMES=()

for script_file in "${SCRIPT_FILES[@]}"; do
  file_name=$(basename "$script_file")
  TOTAL=$((TOTAL + 1))

  if shellcheck -S warning -e "$EXCLUDED_RULES" "$script_file" 2>&1; then
    printf "  ${GREEN}PASS${NC}  %s\n" "$file_name"
    PASSED=$((PASSED + 1))
  else
    printf "  ${RED}FAIL${NC}  %s\n" "$file_name"
    FAILED=$((FAILED + 1))
    FAILED_NAMES+=("$file_name")
  fi
done

# --- Summary ---
printf "\n================================================================\n"
printf "${BOLD}ShellCheck Summary${NC}\n"
printf "  Files:  %d total, ${GREEN}%d passed${NC}, ${RED}%d failed${NC}\n" \
  "$TOTAL" "$PASSED" "$FAILED"

if [ "$FAILED" -gt 0 ]; then
  printf "\n"
  printf "${RED}Failed files:${NC}\n"
  for name in "${FAILED_NAMES[@]}"; do
    printf "  - %s\n" "$name"
  done
  printf "================================================================\n"
  printf "\nRun manually to see details:\n"
  printf "  shellcheck -S warning -e %s scripts/<file>.sh\n" "$EXCLUDED_RULES"
  exit 1
fi

printf "================================================================\n"
printf "${GREEN}All scripts passed shellcheck.${NC}\n"
exit 0
