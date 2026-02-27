#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Gemini CLI Review Wrapper
#
# Usage: cat file.py | ./gemini-review.sh <file_path> <config_file> <role>
#   file_path   - Path to the file being reviewed
#   config_file - Path to JSON config (for timeout, model settings)
#   role        - Review role: security|bugs|performance|architecture|testing
#
# Reads file content from stdin.
# Outputs valid JSON to stdout.
# =============================================================================

set -euo pipefail

# --- Arguments ---
FILE_PATH="${1:?Usage: gemini-review.sh <file_path> <config_file> <role>}"
CONFIG_FILE="${2:?Usage: gemini-review.sh <file_path> <config_file> <role>}"
ROLE="${3:?Usage: gemini-review.sh <file_path> <config_file> <role>}"

# --- Validate role ---
case "$ROLE" in
  security|bugs|performance|architecture|testing) ;;
  *)
    echo "{\"model\":\"gemini\",\"role\":\"$ROLE\",\"error\":\"Invalid role: $ROLE. Must be one of: security, bugs, performance, architecture, testing\",\"findings\":[]}"
    exit 1
    ;;
esac

# --- Resolve paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/utils.sh"
PROMPT_FILE="${PLUGIN_DIR}/config/review-prompts/${ROLE}.txt"

# --- Check dependencies ---
if ! command -v gemini &>/dev/null; then
  echo "{\"model\":\"gemini\",\"role\":\"$ROLE\",\"error\":\"gemini CLI not found. Install: npm install -g @google/gemini-cli\",\"findings\":[]}"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "{\"model\":\"gemini\",\"role\":\"$ROLE\",\"error\":\"jq not found. Install: brew install jq\",\"findings\":[]}"
  exit 1
fi

if [ ! -f "$PROMPT_FILE" ]; then
  echo "{\"model\":\"gemini\",\"role\":\"$ROLE\",\"error\":\"Prompt template not found: $PROMPT_FILE\",\"findings\":[]}"
  exit 1
fi

# --- Read config ---
TIMEOUT=120
MODEL_VARIANT=""

if [ -f "$CONFIG_FILE" ]; then
  cfg_timeout=$(jq -r '.timeout // empty' "$CONFIG_FILE" || true)
  if [ -n "$cfg_timeout" ]; then
    TIMEOUT="$cfg_timeout"
  fi

  cfg_model=$(jq -r '.models.gemini.model_variant // .gemini.model_variant // empty' "$CONFIG_FILE" || true)
  if [ -n "$cfg_model" ]; then
    MODEL_VARIANT="$cfg_model"
  fi
fi

# Build model flag: only pass --model if model is set
GEMINI_MODEL_ARGS=()
if [ -n "$MODEL_VARIANT" ]; then
  GEMINI_MODEL_ARGS=(--model "$MODEL_VARIANT")
fi

# --- Read file content from stdin ---
FILE_CONTENT=$(cat)

if [ -z "$FILE_CONTENT" ]; then
  echo "{\"model\":\"gemini\",\"role\":\"$ROLE\",\"error\":\"No file content provided on stdin\",\"findings\":[]}"
  exit 1
fi

# --- Load prompt template ---
PROMPT_TEMPLATE=$(cat "$PROMPT_FILE")

# --- Build full prompt ---
FULL_PROMPT=$(cat <<PROMPT_EOF
${PROMPT_TEMPLATE}

--- FILE: ${FILE_PATH} ---
${FILE_CONTENT}
--- END FILE ---

---
[CORE INSTRUCTION REPEAT]
Review the code above for ${ROLE} issues in file ${FILE_PATH}. Return findings as structured JSON with fields: severity (critical|high|medium|low), description, file, line, and suggestion. Output must be valid JSON only.
PROMPT_EOF
)

# --- Execute gemini review ---
RAW_OUTPUT=""
REVIEW_ERROR=""

_cli_err=$(mktemp)
RAW_OUTPUT=$(
  arena_timeout "${TIMEOUT}" gemini "${GEMINI_MODEL_ARGS[@]}" "$FULL_PROMPT" 2>"$_cli_err"
) || {
  exit_code=$?
  if [ "$exit_code" -eq 124 ]; then
    REVIEW_ERROR="Gemini review timed out after ${TIMEOUT}s"
  else
    REVIEW_ERROR="Gemini exited with code ${exit_code}"
  fi
}
log_stderr_file "gemini-review" "$_cli_err"

# --- Handle errors ---
if [ -n "$REVIEW_ERROR" ]; then
  echo "{\"model\":\"gemini\",\"role\":\"$ROLE\",\"error\":$(echo "$REVIEW_ERROR" | jq -Rs .),\"findings\":[]}"
  exit 0
fi

if [ -z "$RAW_OUTPUT" ]; then
  echo "{\"model\":\"gemini\",\"role\":\"$ROLE\",\"error\":\"Gemini returned empty response\",\"findings\":[]}"
  exit 0
fi

# --- Extract JSON from response (uses shared extract_json from utils.sh) ---
PARSED_JSON=""
PARSED_JSON=$(extract_json "$RAW_OUTPUT") || {
  # Could not parse JSON at all -- wrap raw output as error
  echo "{\"model\":\"gemini\",\"role\":\"$ROLE\",\"error\":\"Failed to parse JSON from gemini response\",\"raw_output\":$(echo "$RAW_OUTPUT" | head -c 2000 | jq -Rs .),\"findings\":[]}"
  exit 0
}

# --- Normalize output ---
# Ensure required fields are present in the output
NORMALIZED=$(echo "$PARSED_JSON" | jq --arg model "gemini" --arg role "$ROLE" --arg file "$FILE_PATH" '{
  model: $model,
  role: $role,
  file: $file,
  findings: (if .findings then .findings else [] end),
  summary: (if .summary then .summary else "No summary provided" end)
}')

echo "$NORMALIZED"
