#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Dependency Checker
# Validates required and optional tools are available.
# =============================================================================

set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# --- Counters ---
required_ok=0
required_fail=0
optional_ok=0
optional_miss=0

# --- Helpers ---
print_header() {
  echo ""
  echo -e "${BOLD}${CYAN}=============================================${RESET}"
  echo -e "${BOLD}${CYAN}  ai-review-arena  -  Dependency Check${RESET}"
  echo -e "${BOLD}${CYAN}=============================================${RESET}"
  echo ""
}

check_required() {
  local name="$1"
  local cmd="$2"
  local install_hint="$3"

  printf "  %-18s" "$name"
  if command -v "$cmd" &>/dev/null; then
    local version
    version=$("$cmd" --version 2>/dev/null | head -1 || echo "installed")
    echo -e "${GREEN}[OK]${RESET}  ${DIM}${version}${RESET}"
    ((required_ok++))
  else
    echo -e "${RED}[MISSING]${RESET}  ${YELLOW}Install: ${install_hint}${RESET}"
    ((required_fail++))
  fi
}

check_optional() {
  local name="$1"
  local cmd="$2"
  local install_hint="$3"

  printf "  %-18s" "$name"
  if command -v "$cmd" &>/dev/null; then
    local version
    version=$("$cmd" --version 2>/dev/null | head -1 || echo "installed")
    echo -e "${GREEN}[OK]${RESET}  ${DIM}${version}${RESET}"
    ((optional_ok++))
  else
    echo -e "${YELLOW}[OPTIONAL]${RESET}  ${DIM}Install: ${install_hint}${RESET}"
    ((optional_miss++))
  fi
}

# --- Main ---
print_header

echo -e "${BOLD}Required:${RESET}"
check_required "jq" "jq" "brew install jq  OR  apt-get install jq"
echo ""

echo -e "${BOLD}Optional (AI Review Models):${RESET}"
check_optional "codex CLI" "codex" "npm install -g @openai/codex"
check_optional "gemini CLI" "gemini" "npm install -g @google/gemini-cli"
echo ""

echo -e "${BOLD}Optional (Integrations):${RESET}"
check_optional "gh CLI" "gh" "brew install gh  OR  https://cli.github.com"
echo ""

# --- Config directory check ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="${PLUGIN_DIR}/config/review-prompts"

printf "  %-18s" "prompt templates"
if [ -d "$CONFIG_DIR" ] && [ "$(ls -1 "$CONFIG_DIR"/*.txt 2>/dev/null | wc -l)" -gt 0 ]; then
  local_count=$(ls -1 "$CONFIG_DIR"/*.txt 2>/dev/null | wc -l | tr -d ' ')
  echo -e "${GREEN}[OK]${RESET}  ${DIM}${local_count} templates found${RESET}"
else
  echo -e "${RED}[MISSING]${RESET}  ${YELLOW}No prompt templates in ${CONFIG_DIR}${RESET}"
  ((required_fail++))
fi
echo ""

# --- Summary ---
echo -e "${BOLD}${CYAN}---------------------------------------------${RESET}"
echo -e "${BOLD}  Summary${RESET}"
echo -e "${BOLD}${CYAN}---------------------------------------------${RESET}"
echo -e "  Required:  ${GREEN}${required_ok} ok${RESET}  ${RED}${required_fail} missing${RESET}"
echo -e "  Optional:  ${GREEN}${optional_ok} ok${RESET}  ${YELLOW}${optional_miss} not installed${RESET}"
echo ""

if [ "$required_fail" -gt 0 ]; then
  echo -e "  ${RED}${BOLD}Some required dependencies are missing.${RESET}"
  echo -e "  ${RED}Please install them before using ai-review-arena.${RESET}"
  echo ""
  exit 1
fi

if [ "$optional_miss" -gt 0 ]; then
  echo -e "  ${YELLOW}Optional tools are not required but enable additional features.${RESET}"
  echo -e "  ${YELLOW}Install at least one AI CLI (codex or gemini) to run reviews.${RESET}"
  echo ""
fi

if [ "$optional_ok" -ge 1 ] && [ "$required_fail" -eq 0 ]; then
  echo -e "  ${GREEN}${BOLD}Ready to use ai-review-arena!${RESET}"
  echo ""
fi

exit 0
