#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Gemini CLI Hook Adapter
#
# Translates Gemini CLI's AfterTool hook stdin JSON to the format expected
# by orchestrate-review.sh. Enables AI Review Arena to work with Gemini CLI
# in addition to Claude Code.
#
# Gemini AfterTool stdin format:
#   { "toolName": "write_file", "toolInput": { "path": "..." }, "toolOutput": "..." }
#
# Usage: Called automatically by Gemini CLI hooks system
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# Source utils if available
if [ -f "$PLUGIN_DIR/scripts/utils.sh" ]; then
  source "$PLUGIN_DIR/scripts/utils.sh"
fi

# --- Read Gemini hook JSON from stdin ---
HOOK_INPUT=""
if [ ! -t 0 ]; then
  HOOK_INPUT=$(cat)
fi

if [ -z "$HOOK_INPUT" ]; then
  exit 0
fi

# --- Check for jq ---
if ! command -v jq &>/dev/null; then
  echo "gemini-hook-adapter: jq not found, skipping review" >&2
  exit 0
fi

# --- Parse Gemini hook format ---
TOOL_NAME=$(echo "$HOOK_INPUT" | jq -r '.toolName // empty' 2>/dev/null)
FILE_PATH=$(echo "$HOOK_INPUT" | jq -r '.toolInput.path // .toolInput.file_path // empty' 2>/dev/null)

if [ -z "$TOOL_NAME" ] || [ -z "$FILE_PATH" ]; then
  exit 0
fi

# --- Check if file extension is reviewable ---
EXTENSION="${FILE_PATH##*.}"
case "$EXTENSION" in
  ts|tsx|js|jsx|py|go|rs|java|kt|swift|rb|php|c|cpp|cs)
    ;; # reviewable
  *)
    exit 0 # skip non-code files
    ;;
esac

# --- Translate to orchestrate-review.sh expected format ---
# Set environment variables that orchestrate-review.sh expects
export REVIEW_FILE_PATH="$FILE_PATH"
export REVIEW_TOOL_NAME="$TOOL_NAME"
export REVIEW_SOURCE="gemini"

# --- Load config ---
CONFIG_FILE=""
if [ -f ".ai-review-arena.json" ]; then
  CONFIG_FILE=".ai-review-arena.json"
elif [ -f "$HOME/.claude/.ai-review-arena.json" ]; then
  CONFIG_FILE="$HOME/.claude/.ai-review-arena.json"
fi

# Check if gemini hooks are enabled in config
if [ -n "$CONFIG_FILE" ]; then
  GEMINI_HOOKS_ENABLED=$(jq -r '.gemini_hooks.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
  if [ "$GEMINI_HOOKS_ENABLED" != "true" ]; then
    exit 0
  fi
fi

# --- Call orchestrate-review.sh ---
if [ -f "$PLUGIN_DIR/scripts/orchestrate-review.sh" ]; then
  "$PLUGIN_DIR/scripts/orchestrate-review.sh" "$FILE_PATH" "$CONFIG_FILE" 2>/dev/null || true
fi
