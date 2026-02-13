#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Extended Dependency Checker
#
# Usage: setup-arena.sh [--verbose]
#
# Checks availability of all dependencies, config files, benchmark data,
# and cache writability. Reports a summary table.
#
# Exit codes:
#   0 - Always (informational)
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# --- Arguments ---
VERBOSE=false
if [ "${1:-}" = "--verbose" ]; then
  VERBOSE=true
fi

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# --- Counters ---
total_checks=0
available=0
missing=0
optional_missing=0

# =============================================================================
# Check Functions
# =============================================================================

check_item() {
  local name="$1"
  local status="$2"  # ok|missing|optional
  local detail="$3"

  total_checks=$((total_checks + 1))
  printf "  %-28s" "$name"

  case "$status" in
    ok)
      echo -e "${GREEN}[OK]${RESET}  ${DIM}${detail}${RESET}"
      available=$((available + 1))
      ;;
    missing)
      echo -e "${RED}[MISSING]${RESET}  ${YELLOW}${detail}${RESET}"
      missing=$((missing + 1))
      ;;
    optional)
      echo -e "${YELLOW}[OPTIONAL]${RESET}  ${DIM}${detail}${RESET}"
      optional_missing=$((optional_missing + 1))
      ;;
  esac
}

check_command() {
  local name="$1"
  local cmd="$2"
  local required="$3"  # required|optional
  local install_hint="$4"

  if command -v "$cmd" &>/dev/null; then
    local version
    version=$("$cmd" --version 2>/dev/null | head -1 || echo "installed")
    check_item "$name" "ok" "$version"
  else
    if [ "$required" = "required" ]; then
      check_item "$name" "missing" "Install: $install_hint"
    else
      check_item "$name" "optional" "Install: $install_hint"
    fi
  fi
}

check_file() {
  local name="$1"
  local path="$2"
  local required="$3"

  if [ -f "$path" ]; then
    local size
    size=$(wc -c < "$path" 2>/dev/null | tr -d ' ')
    check_item "$name" "ok" "${size} bytes"
  else
    if [ "$required" = "required" ]; then
      check_item "$name" "missing" "Expected at: $path"
    else
      check_item "$name" "optional" "Expected at: $path"
    fi
  fi
}

check_dir_writable() {
  local name="$1"
  local path="$2"

  mkdir -p "$path" 2>/dev/null
  if [ -d "$path" ] && [ -w "$path" ]; then
    check_item "$name" "ok" "$path"
  else
    check_item "$name" "missing" "Cannot write to: $path"
  fi
}

# =============================================================================
# Report
# =============================================================================

echo ""
echo -e "${BOLD}${CYAN}=============================================${RESET}"
echo -e "${BOLD}${CYAN}  ai-review-arena  -  Extended Setup Check${RESET}"
echo -e "${BOLD}${CYAN}=============================================${RESET}"
echo ""

# --- Required Tools ---
echo -e "${BOLD}Required Tools:${RESET}"
check_command "jq" "jq" "required" "brew install jq"
echo ""

# --- Optional AI CLI Tools ---
echo -e "${BOLD}AI Model CLIs (optional):${RESET}"
check_command "codex CLI" "codex" "optional" "npm install -g @openai/codex"
check_command "gemini CLI" "gemini" "optional" "npm install -g @google/gemini-cli"
echo ""

# --- Cache Directory ---
echo -e "${BOLD}Cache:${RESET}"
CACHE_DIR="${PLUGIN_DIR}/cache"
check_dir_writable "Cache directory" "$CACHE_DIR"
echo ""

# --- Config Files ---
echo -e "${BOLD}Configuration Files:${RESET}"
check_file "default-config.json" "${PLUGIN_DIR}/config/default-config.json" "required"
check_file "compliance-rules.json" "${PLUGIN_DIR}/config/compliance-rules.json" "optional"
check_file "tech-queries.json" "${PLUGIN_DIR}/config/tech-queries.json" "optional"
echo ""

# --- Benchmark Test Cases ---
echo -e "${BOLD}Benchmark Data:${RESET}"
BENCHMARKS_DIR="${PLUGIN_DIR}/config/benchmarks"
if [ -d "$BENCHMARKS_DIR" ]; then
  bench_count=$(find "$BENCHMARKS_DIR" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [ "$bench_count" -gt 0 ]; then
    check_item "Benchmark test cases" "ok" "$bench_count files in $BENCHMARKS_DIR"
  else
    check_item "Benchmark test cases" "optional" "No .json files in $BENCHMARKS_DIR"
  fi
else
  check_item "Benchmark test cases" "optional" "Directory not found: $BENCHMARKS_DIR"
fi
echo ""

# --- Prompt Templates ---
echo -e "${BOLD}Prompt Templates:${RESET}"
PROMPTS_DIR="${PLUGIN_DIR}/config/review-prompts"
if [ -d "$PROMPTS_DIR" ]; then
  prompt_count=$(find "$PROMPTS_DIR" -name "*.txt" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [ "$prompt_count" -gt 0 ]; then
    check_item "Review prompt templates" "ok" "$prompt_count templates"
  else
    check_item "Review prompt templates" "missing" "No .txt files in $PROMPTS_DIR"
  fi
else
  check_item "Review prompt templates" "missing" "Directory not found: $PROMPTS_DIR"
fi
echo ""

# --- Integrations Note ---
echo -e "${BOLD}Integrations (informational):${RESET}"
echo -e "  ${DIM}Figma MCP tools are available when configured in Claude Code MCP settings.${RESET}"
echo -e "  ${DIM}No CLI check needed - Figma access is provided via MCP protocol.${RESET}"
echo ""

# --- Verbose: show paths ---
if [ "$VERBOSE" = true ]; then
  echo -e "${BOLD}Paths:${RESET}"
  echo -e "  Plugin dir:     ${PLUGIN_DIR}"
  echo -e "  Scripts dir:    ${SCRIPT_DIR}"
  echo -e "  Config dir:     ${PLUGIN_DIR}/config"
  echo -e "  Cache dir:      ${CACHE_DIR}"
  echo -e "  Benchmarks dir: ${BENCHMARKS_DIR}"
  echo ""
fi

# =============================================================================
# Summary
# =============================================================================

echo -e "${BOLD}${CYAN}---------------------------------------------${RESET}"
echo -e "${BOLD}  Summary${RESET}"
echo -e "${BOLD}${CYAN}---------------------------------------------${RESET}"
echo -e "  Total checks:  ${total_checks}"
echo -e "  Available:     ${GREEN}${available}${RESET}"
echo -e "  Missing:       ${RED}${missing}${RESET}"
echo -e "  Optional:      ${YELLOW}${optional_missing}${RESET}"
echo ""

if [ "$missing" -gt 0 ]; then
  echo -e "  ${RED}${BOLD}Some required items are missing.${RESET}"
  echo -e "  ${RED}Install required dependencies before using ai-review-arena.${RESET}"
  echo ""
elif [ "$available" -gt 0 ]; then
  echo -e "  ${GREEN}${BOLD}ai-review-arena is ready to use.${RESET}"
  if [ "$optional_missing" -gt 0 ]; then
    echo -e "  ${YELLOW}Install optional items for full functionality.${RESET}"
  fi
  echo ""
fi

exit 0
