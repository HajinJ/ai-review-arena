#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Codex CLI Review Wrapper
#
# Usage: cat file.py | ./codex-review.sh <file_path> <config_file> <role>
#   file_path   - Path to the file being reviewed
#   config_file - Path to JSON config (for timeout, model settings)
#   role        - Review role: security|bugs|performance|architecture|testing
#
# Reads file content from stdin.
# Outputs valid JSON to stdout.
# =============================================================================

set -euo pipefail

# --- Arguments ---
FILE_PATH="${1:?Usage: codex-review.sh <file_path> <config_file> <role>}"
CONFIG_FILE="${2:?Usage: codex-review.sh <file_path> <config_file> <role>}"
ROLE="${3:?Usage: codex-review.sh <file_path> <config_file> <role>}"

# --- Validate role ---
case "$ROLE" in
  security|bugs|performance|architecture|testing) ;;
  *)
    echo "{\"model\":\"codex\",\"role\":\"$ROLE\",\"error\":\"Invalid role: $ROLE. Must be one of: security, bugs, performance, architecture, testing\",\"findings\":[]}"
    exit 1
    ;;
esac

# --- Resolve paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
PROMPT_FILE="${PLUGIN_DIR}/config/review-prompts/${ROLE}.txt"

# --- Check dependencies ---
if ! command -v codex &>/dev/null; then
  echo "{\"model\":\"codex\",\"role\":\"$ROLE\",\"error\":\"codex CLI not found. Install: npm install -g @openai/codex\",\"findings\":[]}"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "{\"model\":\"codex\",\"role\":\"$ROLE\",\"error\":\"jq not found. Install: brew install jq\",\"findings\":[]}"
  exit 1
fi

if [ ! -f "$PROMPT_FILE" ]; then
  echo "{\"model\":\"codex\",\"role\":\"$ROLE\",\"error\":\"Prompt template not found: $PROMPT_FILE\",\"findings\":[]}"
  exit 1
fi

# --- Read config ---
TIMEOUT=120
CODEX_MODEL="gpt-5.3-codex-spark"
if [ -f "$CONFIG_FILE" ]; then
  cfg_timeout=$(jq -r '.timeout // empty' "$CONFIG_FILE" 2>/dev/null || true)
  if [ -n "$cfg_timeout" ]; then
    TIMEOUT="$cfg_timeout"
  fi

  cfg_model=$(jq -r '.codex.model_variant // .models.codex.model_variant // empty' "$CONFIG_FILE" 2>/dev/null || true)
  if [ -n "$cfg_model" ]; then
    CODEX_MODEL="$cfg_model"
  fi
fi

# --- Read file content from stdin ---
FILE_CONTENT=$(cat)

if [ -z "$FILE_CONTENT" ]; then
  echo "{\"model\":\"codex\",\"role\":\"$ROLE\",\"error\":\"No file content provided on stdin\",\"findings\":[]}"
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

# --- Execute codex review ---
RAW_OUTPUT=""
REVIEW_ERROR=""

RAW_OUTPUT=$(
  timeout "${TIMEOUT}s" codex exec --full-auto -m "$CODEX_MODEL" "$FULL_PROMPT" 2>/dev/null
) || {
  exit_code=$?
  if [ "$exit_code" -eq 124 ]; then
    REVIEW_ERROR="Codex review timed out after ${TIMEOUT}s"
  else
    REVIEW_ERROR="Codex exited with code ${exit_code}"
  fi
}

# --- Handle errors ---
if [ -n "$REVIEW_ERROR" ]; then
  echo "{\"model\":\"codex\",\"role\":\"$ROLE\",\"error\":$(echo "$REVIEW_ERROR" | jq -Rs .),\"findings\":[]}"
  exit 0
fi

if [ -z "$RAW_OUTPUT" ]; then
  echo "{\"model\":\"codex\",\"role\":\"$ROLE\",\"error\":\"Codex returned empty response\",\"findings\":[]}"
  exit 0
fi

# --- Extract JSON from response ---
# The model may wrap JSON in markdown code blocks. Strip them.
extract_json() {
  local input="$1"

  # Try 1: Input is already valid JSON
  if echo "$input" | jq . &>/dev/null 2>&1; then
    echo "$input"
    return 0
  fi

  # Try 2: Extract from ```json ... ``` blocks
  local extracted
  extracted=$(echo "$input" | sed -n '/^```json/,/^```$/p' | sed '1d;$d')
  if [ -n "$extracted" ] && echo "$extracted" | jq . &>/dev/null 2>&1; then
    echo "$extracted"
    return 0
  fi

  # Try 3: Extract from ``` ... ``` blocks (no language tag)
  extracted=$(echo "$input" | sed -n '/^```/,/^```$/p' | sed '1d;$d')
  if [ -n "$extracted" ] && echo "$extracted" | jq . &>/dev/null 2>&1; then
    echo "$extracted"
    return 0
  fi

  # Try 4: Find first { to last } on a best-effort basis
  extracted=$(echo "$input" | sed -n '/^[[:space:]]*{/,/}[[:space:]]*$/p')
  if [ -n "$extracted" ] && echo "$extracted" | jq . &>/dev/null 2>&1; then
    echo "$extracted"
    return 0
  fi

  return 1
}

PARSED_JSON=""
PARSED_JSON=$(extract_json "$RAW_OUTPUT") || {
  # Could not parse JSON at all -- wrap raw output as error
  echo "{\"model\":\"codex\",\"role\":\"$ROLE\",\"error\":\"Failed to parse JSON from codex response\",\"raw_output\":$(echo "$RAW_OUTPUT" | head -c 2000 | jq -Rs .),\"findings\":[]}"
  exit 0
}

# --- Normalize output ---
# Ensure required fields are present in the output
NORMALIZED=$(echo "$PARSED_JSON" | jq --arg model "codex" --arg role "$ROLE" --arg file "$FILE_PATH" '{
  model: $model,
  role: $role,
  file: $file,
  findings: (if .findings then .findings else [] end),
  summary: (if .summary then .summary else "No summary provided" end)
}')

echo "$NORMALIZED"
