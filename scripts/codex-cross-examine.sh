#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Codex CLI Cross-Examination Wrapper
#
# Usage: echo <context_json> | ./codex-cross-examine.sh <config_file> <round>
#   config_file - Path to JSON config (for timeout, model settings)
#   round       - "cross-examine" (Round 2) or "defend" (Round 3)
#
# Reads cross-examination context from stdin as JSON.
# Outputs valid JSON to stdout.
# =============================================================================

set -euo pipefail

# --- Arguments ---
CONFIG_FILE="${1:?Usage: codex-cross-examine.sh <config_file> <round>}"
ROUND="${2:?Usage: codex-cross-examine.sh <config_file> <round>}"

# --- Validate round ---
case "$ROUND" in
  cross-examine|defend) ;;
  *)
    echo "{\"model\":\"codex\",\"round\":\"$ROUND\",\"error\":\"Invalid round: $ROUND. Must be: cross-examine or defend\",\"responses\":[]}"
    exit 1
    ;;
esac

# --- Resolve paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

if [ "$ROUND" = "cross-examine" ]; then
  PROMPT_FILE="${PLUGIN_DIR}/config/review-prompts/cross-examine.txt"
else
  PROMPT_FILE="${PLUGIN_DIR}/config/review-prompts/defend.txt"
fi

# --- Check dependencies ---
if ! command -v codex &>/dev/null; then
  echo "{\"model\":\"codex\",\"round\":\"$ROUND\",\"error\":\"codex CLI not found. Install: npm install -g @openai/codex\",\"responses\":[]}"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "{\"model\":\"codex\",\"round\":\"$ROUND\",\"error\":\"jq not found. Install: brew install jq\",\"responses\":[]}"
  exit 1
fi

if [ ! -f "$PROMPT_FILE" ]; then
  echo "{\"model\":\"codex\",\"round\":\"$ROUND\",\"error\":\"Prompt template not found: $PROMPT_FILE\",\"responses\":[]}"
  exit 1
fi

# --- Read config ---
TIMEOUT=180
CODEX_MODEL="gpt-5.3-codex-spark"
if [ -f "$CONFIG_FILE" ]; then
  if [ "$ROUND" = "cross-examine" ]; then
    cfg_timeout=$(jq -r '.debate.round2_timeout_seconds // empty' "$CONFIG_FILE" 2>/dev/null || true)
  else
    cfg_timeout=$(jq -r '.debate.round3_timeout_seconds // empty' "$CONFIG_FILE" 2>/dev/null || true)
  fi
  if [ -n "$cfg_timeout" ]; then
    TIMEOUT="$cfg_timeout"
  fi

  cfg_model=$(jq -r '.models.codex.model_variant // empty' "$CONFIG_FILE" 2>/dev/null || true)
  if [ -n "$cfg_model" ]; then
    CODEX_MODEL="$cfg_model"
  fi
fi

# --- Read context from stdin ---
CONTEXT_JSON=$(cat)

if [ -z "$CONTEXT_JSON" ]; then
  echo "{\"model\":\"codex\",\"round\":\"$ROUND\",\"error\":\"No context provided on stdin\",\"responses\":[]}"
  exit 1
fi

# --- Load prompt template ---
PROMPT_TEMPLATE=$(cat "$PROMPT_FILE")

# --- Build full prompt ---
if [ "$ROUND" = "cross-examine" ]; then
  FINDINGS_JSON=$(echo "$CONTEXT_JSON" | jq -r '.findings_from // empty' 2>/dev/null || echo "{}")
  CODE_CONTEXT=$(echo "$CONTEXT_JSON" | jq -r '.code_context // empty' 2>/dev/null || echo "{}")

  FULL_PROMPT=$(echo "$PROMPT_TEMPLATE" \
    | sed "s|{FINDINGS_JSON}|${FINDINGS_JSON}|g" \
    | sed "s|{CODE_CONTEXT}|${CODE_CONTEXT}|g")
else
  CHALLENGES_JSON=$(echo "$CONTEXT_JSON" | jq -r 'to_entries | map(select(.key | startswith("challenges_against"))) | from_entries // empty' 2>/dev/null || echo "{}")
  ORIGINAL_JSON=$(echo "$CONTEXT_JSON" | jq -r '.original_findings // empty' 2>/dev/null || echo "[]")
  CODE_CONTEXT=$(echo "$CONTEXT_JSON" | jq -r '.code_context // empty' 2>/dev/null || echo "{}")

  FULL_PROMPT=$(echo "$PROMPT_TEMPLATE" \
    | sed "s|{ORIGINAL_FINDINGS_JSON}|${ORIGINAL_JSON}|g" \
    | sed "s|{CHALLENGES_JSON}|${CHALLENGES_JSON}|g" \
    | sed "s|{CODE_CONTEXT}|${CODE_CONTEXT}|g")
fi

# --- Execute codex cross-examination ---
RAW_OUTPUT=""
REVIEW_ERROR=""

RAW_OUTPUT=$(
  timeout "${TIMEOUT}s" codex exec --full-auto -m "$CODEX_MODEL" "$FULL_PROMPT" 2>/dev/null
) || {
  exit_code=$?
  if [ "$exit_code" -eq 124 ]; then
    REVIEW_ERROR="Codex cross-examination timed out after ${TIMEOUT}s"
  else
    REVIEW_ERROR="Codex exited with code ${exit_code}"
  fi
}

# --- Handle errors ---
if [ -n "$REVIEW_ERROR" ]; then
  echo "{\"model\":\"codex\",\"round\":\"$ROUND\",\"error\":$(echo "$REVIEW_ERROR" | jq -Rs .),\"responses\":[],\"defenses\":[]}"
  exit 0
fi

if [ -z "$RAW_OUTPUT" ]; then
  echo "{\"model\":\"codex\",\"round\":\"$ROUND\",\"error\":\"Codex returned empty response\",\"responses\":[],\"defenses\":[]}"
  exit 0
fi

# --- Extract JSON from response ---
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

  # Try 4: Find first { to last }
  extracted=$(echo "$input" | sed -n '/^[[:space:]]*{/,/}[[:space:]]*$/p')
  if [ -n "$extracted" ] && echo "$extracted" | jq . &>/dev/null 2>&1; then
    echo "$extracted"
    return 0
  fi

  return 1
}

PARSED_JSON=""
PARSED_JSON=$(extract_json "$RAW_OUTPUT") || {
  echo "{\"model\":\"codex\",\"round\":\"$ROUND\",\"error\":\"Failed to parse JSON from codex response\",\"raw_output\":$(echo "$RAW_OUTPUT" | head -c 2000 | jq -Rs .),\"responses\":[],\"defenses\":[]}"
  exit 0
}

# --- Normalize output ---
if [ "$ROUND" = "cross-examine" ]; then
  NORMALIZED=$(echo "$PARSED_JSON" | jq --arg model "codex" --arg round "2" --arg phase "cross-examine" '{
    model: $model,
    round: ($round | tonumber),
    phase: $phase,
    responses: (if .responses then .responses else [] end)
  }')
else
  NORMALIZED=$(echo "$PARSED_JSON" | jq --arg model "codex" --arg round "3" --arg phase "defend" '{
    model: $model,
    round: ($round | tonumber),
    phase: $phase,
    defenses: (if .defenses then .defenses else [] end)
  }')
fi

echo "$NORMALIZED"
