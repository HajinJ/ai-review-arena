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
source "$SCRIPT_DIR/utils.sh"
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
CODEX_MODEL=""
if [ -f "$CONFIG_FILE" ]; then
  cfg_timeout=$(jq -r '.timeout // empty' "$CONFIG_FILE" || true)
  if [ -n "$cfg_timeout" ]; then
    TIMEOUT="$cfg_timeout"
  fi

  cfg_model=$(jq -r '.codex.model_variant // .models.codex.model_variant // empty' "$CONFIG_FILE" || true)
  if [ -n "$cfg_model" ]; then
    CODEX_MODEL="$cfg_model"
  fi
fi

# Build model flag: only pass -m if model is set
CODEX_MODEL_ARGS=()
if [ -n "$CODEX_MODEL" ]; then
  CODEX_MODEL_ARGS=(-m "$CODEX_MODEL")
fi

# --- Read structured output config ---
STRUCTURED_OUTPUT=true
if [ -f "$CONFIG_FILE" ]; then
  cfg_structured=$(jq -r '.models.codex.structured_output // true' "$CONFIG_FILE" || true)
  if [ "$cfg_structured" = "false" ]; then
    STRUCTURED_OUTPUT=false
  fi
fi
SCHEMA_FILE="${PLUGIN_DIR}/config/schemas/codex-review.json"

# --- Read multi-agent config (experimental) ---
MULTI_AGENT=false
if [ -f "$CONFIG_FILE" ]; then
  cfg_multi_agent=$(jq -r '.models.codex.multi_agent.enabled // false' "$CONFIG_FILE" || true)
  if [ "$cfg_multi_agent" = "true" ]; then
    # Check if codex supports agents feature at runtime
    if codex exec --help 2>&1 | grep -q "agents" 2>/dev/null; then
      MULTI_AGENT=true
      AGENTS_DIR=$(jq -r '.models.codex.multi_agent.agents_dir // "config/codex-agents"' "$CONFIG_FILE" || echo "config/codex-agents")
      AGENT_CONFIG="${PLUGIN_DIR}/${AGENTS_DIR}/${ROLE}.toml"
    fi
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
PARSED_JSON=""

# Try multi-agent path first (experimental, feature-flagged)
if [ "$MULTI_AGENT" = "true" ] && [ -f "$AGENT_CONFIG" ]; then
  OUTPUT_FILE=$(mktemp)
  _cli_err=$(mktemp)
  RAW_OUTPUT=$(
    arena_timeout "${TIMEOUT}" codex exec --full-auto "${CODEX_MODEL_ARGS[@]}" \
      --config "agents.${ROLE}.config_file=${AGENT_CONFIG}" \
      --output-schema "$SCHEMA_FILE" -o "$OUTPUT_FILE" "$FULL_PROMPT" 2>"$_cli_err"
  ) || {
    exit_code=$?
    if [ "$exit_code" -eq 124 ]; then
      REVIEW_ERROR="Codex multi-agent review timed out after ${TIMEOUT}s"
    else
      # Multi-agent failed — reset error to allow fallback
      REVIEW_ERROR=""
    fi
  }
  log_stderr_file "codex-review(multi-agent)" "$_cli_err"

  if [ -z "$REVIEW_ERROR" ] && [ -f "$OUTPUT_FILE" ] && jq . "$OUTPUT_FILE" &>/dev/null; then
    PARSED_JSON=$(cat "$OUTPUT_FILE")
  fi
  rm -f "$OUTPUT_FILE"
fi

# Try structured output (skip if multi-agent already produced valid JSON)
if [ -z "$PARSED_JSON" ] && [ "$STRUCTURED_OUTPUT" = "true" ] && [ -f "$SCHEMA_FILE" ]; then
  OUTPUT_FILE=$(mktemp)
  _cli_err=$(mktemp)
  RAW_OUTPUT=$(
    arena_timeout "${TIMEOUT}" codex exec --full-auto "${CODEX_MODEL_ARGS[@]}" \
      --output-schema "$SCHEMA_FILE" -o "$OUTPUT_FILE" "$FULL_PROMPT" 2>"$_cli_err"
  ) || {
    exit_code=$?
    if [ "$exit_code" -eq 124 ]; then
      REVIEW_ERROR="Codex review timed out after ${TIMEOUT}s"
    else
      REVIEW_ERROR="Codex exited with code ${exit_code}"
    fi
  }
  log_stderr_file "codex-review(structured)" "$_cli_err"

  # Read structured output from -o file (clean JSON, no extraction needed)
  if [ -z "$REVIEW_ERROR" ] && [ -f "$OUTPUT_FILE" ] && jq . "$OUTPUT_FILE" &>/dev/null; then
    PARSED_JSON=$(cat "$OUTPUT_FILE")
  fi
  rm -f "$OUTPUT_FILE"
fi

# Fallback to standard execution if structured output didn't work
if [ -z "$PARSED_JSON" ] && [ -z "$REVIEW_ERROR" ]; then
  _cli_err=$(mktemp)
  RAW_OUTPUT=$(
    arena_timeout "${TIMEOUT}" codex exec --full-auto "${CODEX_MODEL_ARGS[@]}" "$FULL_PROMPT" 2>"$_cli_err"
  ) || {
    exit_code=$?
    if [ "$exit_code" -eq 124 ]; then
      REVIEW_ERROR="Codex review timed out after ${TIMEOUT}s"
    else
      REVIEW_ERROR="Codex exited with code ${exit_code}"
    fi
  }
  log_stderr_file "codex-review(fallback)" "$_cli_err"
fi

# --- Handle errors ---
if [ -n "$REVIEW_ERROR" ]; then
  echo "{\"model\":\"codex\",\"role\":\"$ROLE\",\"error\":$(echo "$REVIEW_ERROR" | jq -Rs .),\"findings\":[]}"
  exit 0
fi

if [ -z "$RAW_OUTPUT" ] && [ -z "$PARSED_JSON" ]; then
  echo "{\"model\":\"codex\",\"role\":\"$ROLE\",\"error\":\"Codex returned empty response\",\"findings\":[]}"
  exit 0
fi

# --- Extract JSON from response (uses shared extract_json from utils.sh) ---
# Skip extraction if structured output already provided clean JSON
if [ -z "$PARSED_JSON" ]; then
  PARSED_JSON=$(extract_json "$RAW_OUTPUT") || {
    # Could not parse JSON at all -- wrap raw output as error
    echo "{\"model\":\"codex\",\"role\":\"$ROLE\",\"error\":\"Failed to parse JSON from codex response\",\"raw_output\":$(echo "$RAW_OUTPUT" | head -c 2000 | jq -Rs .),\"findings\":[]}"
    exit 0
  }
fi

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
