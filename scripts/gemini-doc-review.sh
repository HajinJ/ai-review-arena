#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Gemini CLI Documentation Review Wrapper (Dual-Mode)
#
# Usage: echo "$CONTENT" | ./gemini-doc-review.sh <config_file> --mode round1|round2 [--category accuracy|completeness|freshness|readability|examples|consistency]
#   config_file - Path to JSON config (for timeout, model settings)
#   --mode      - "round1" (independent review) or "round2" (cross-review)
#   --category  - (round1 only) Review category: accuracy|completeness|freshness|readability|examples|consistency
#
# Reads documentation content from stdin (round1) or findings JSON from stdin (round2).
# Outputs valid JSON to stdout.
# =============================================================================

set -euo pipefail

# --- Parse arguments ---
CONFIG_FILE="${1:?Usage: gemini-doc-review.sh <config_file> --mode round1|round2 [--category ...]}"
shift

MODE=""
CATEGORY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"
      shift 2
      ;;
    --category)
      CATEGORY="$2"
      shift 2
      ;;
    *)
      echo "{\"model\":\"gemini\",\"error\":\"Unknown argument: $1\",\"findings\":[],\"responses\":[]}"
      exit 0
      ;;
  esac
done

# --- Validate mode ---
if [ -z "$MODE" ]; then
  echo "{\"model\":\"gemini\",\"error\":\"--mode is required (round1 or round2)\",\"findings\":[],\"responses\":[]}"
  exit 0
fi

case "$MODE" in
  round1|round2) ;;
  *)
    echo "{\"model\":\"gemini\",\"mode\":\"$MODE\",\"error\":\"Invalid mode: $MODE. Must be: round1 or round2\",\"findings\":[],\"responses\":[]}"
    exit 0
    ;;
esac

# --- Validate category (required for round1) ---
if [ "$MODE" = "round1" ]; then
  if [ -z "$CATEGORY" ]; then
    echo "{\"model\":\"gemini\",\"mode\":\"round1\",\"error\":\"--category is required for round1. Must be one of: accuracy, completeness, freshness, readability, examples, consistency\",\"findings\":[]}"
    exit 0
  fi

  case "$CATEGORY" in
    accuracy|completeness|freshness|readability|examples|consistency) ;;
    *)
      echo "{\"model\":\"gemini\",\"mode\":\"round1\",\"category\":\"$CATEGORY\",\"error\":\"Invalid category: $CATEGORY. Must be one of: accuracy, completeness, freshness, readability, examples, consistency\",\"findings\":[]}"
      exit 0
      ;;
  esac
fi

# --- Resolve paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034 # PLUGIN_DIR used by sourced review prompts
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/utils.sh"

# --- Check dependencies ---
if ! command -v gemini &>/dev/null; then
  echo "{\"model\":\"gemini\",\"mode\":\"$MODE\",\"error\":\"gemini CLI not found. Install: npm install -g @google/gemini-cli\",\"findings\":[],\"responses\":[]}"
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo "{\"model\":\"gemini\",\"mode\":\"$MODE\",\"error\":\"jq not found. Install: brew install jq\",\"findings\":[],\"responses\":[]}"
  exit 0
fi

# --- Read config ---
TIMEOUT=120
MODEL_VARIANT=""

if [ -f "$CONFIG_FILE" ]; then
  # Read timeout based on mode
  if [ "$MODE" = "round1" ]; then
    cfg_timeout=$(jq -r '.fallback.external_cli_timeout_seconds // .timeout // empty' "$CONFIG_FILE" || true)
  else
    cfg_timeout=$(jq -r '.fallback.external_cli_debate_timeout_seconds // .debate.round2_timeout_seconds // empty' "$CONFIG_FILE" || true)
  fi
  if [ -n "$cfg_timeout" ]; then
    TIMEOUT="$cfg_timeout"
  fi

  # Read model variant
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

# --- Read input from stdin ---
INPUT_CONTENT=$(cat)

if [ -z "$INPUT_CONTENT" ]; then
  echo "{\"model\":\"gemini\",\"mode\":\"$MODE\",\"error\":\"No input provided on stdin\",\"findings\":[],\"responses\":[]}"
  exit 0
fi

# --- Build prompt based on mode ---
if [ "$MODE" = "round1" ]; then
  # Round 1: Independent documentation review
  # Map category to role name
  case "$CATEGORY" in
    accuracy)
      ROLE="doc-accuracy"
      ;;
    completeness)
      ROLE="doc-completeness"
      ;;
    freshness)
      ROLE="doc-freshness"
      ;;
    readability)
      ROLE="doc-readability"
      ;;
    examples)
      ROLE="doc-examples"
      ;;
    consistency)
      ROLE="doc-consistency"
      ;;
  esac

  # Build criteria based on category
  CRITERIA=""
  case "$CATEGORY" in
    accuracy)
      CRITERIA="- Code-documentation alignment: Do function signatures match the source code?
- API signature verification: Are parameter names, types, and return types correct?
- Configuration key accuracy: Are config key names, types, and defaults accurate?
- Behavioral description verification: Do descriptions match actual behavior?"
      ;;
    completeness)
      CRITERIA="- Undocumented public APIs: Are there exported functions/endpoints missing from docs?
- Missing sections: Are installation, configuration, error handling sections present?
- Missing parameter documentation: Are all params described with types and constraints?
- Missing error documentation: Are error codes, responses, and edge cases documented?"
      ;;
    freshness)
      CRITERIA="- Deprecated references: Does the doc reference deprecated APIs or removed features?
- Stale versions: Are version numbers and prerequisites current?
- Dead links: Do internal/external links point to valid targets?
- Technology drift: Have tools, frameworks, or databases changed since the doc was written?"
      ;;
    readability)
      CRITERIA="- Progressive disclosure: Are simple concepts introduced before complex ones?
- Audience fit: Does terminology match the target reader's expertise level?
- Heading hierarchy: Is the document well-structured and scannable?
- Cognitive load: Are sentences concise? Is jargon density appropriate?"
      ;;
    examples)
      CRITERIA="- Runnability: Do code examples actually work with the current API?
- Output accuracy: Do shown outputs match actual behavior?
- Import completeness: Are all required imports and dependencies shown?
- Security: Are there hardcoded secrets or insecure patterns in examples?
- Deprecated patterns: Do examples use old APIs or removed methods?"
      ;;
    consistency)
      CRITERIA="- Terminology consistency: Is the same term used for the same concept throughout?
- Cross-reference integrity: Do internal links point to correct sections?
- Naming conventions: Are casing, prefixes, and patterns used consistently?
- Tone and style: Is the tone consistent across sections?"
      ;;
  esac

  FULL_PROMPT=$(cat <<PROMPT_EOF
You are a documentation reviewer specializing in ${ROLE}.

Your task is to perform an independent review of the following documentation and identify issues related to your specialty.

**Review Category: ${CATEGORY}**

**Category-Specific Criteria:**

${CRITERIA}

**Output Format:**

Return a JSON object with this structure:
{
  "model": "gemini",
  "role": "doc-${CATEGORY}",
  "mode": "round1",
  "findings": [
    {
      "severity": "critical|high|medium|low",
      "confidence": 0-100,
      "location": {"file": "...", "section": "...", "line": null},
      "title": "Brief title",
      "doc_type": "api_reference|tutorial|readme|general",
      "category": "${CATEGORY}",
      "related_source": "source file path if applicable",
      "description": "Detailed description of the issue",
      "suggestion": "Specific recommendation to fix"
    }
  ],
  "summary": "Brief overall assessment (2-3 sentences)"
}

**Documentation to Review:**

${INPUT_CONTENT}

Return only valid JSON. No markdown formatting.

---
[CORE INSTRUCTION REPEAT]
Review the documentation above for ${CATEGORY} issues. Return findings as structured JSON with fields: severity (critical|high|medium|low), confidence (0-100), location (object with file/section/line), title, doc_type, category, related_source, description, and suggestion. Output must be valid JSON only.
PROMPT_EOF
)

else
  # Round 2: Cross-review of other models' findings
  FULL_PROMPT=$(cat <<PROMPT_EOF
You are a documentation reviewer performing cross-examination of other models' findings.

Your task is to review findings from other AI models and either:
- **Challenge** findings that appear incorrect, overstated, or not well-supported
- **Support** findings that are accurate and important

For each finding you review, provide:
1. Your action (challenge or support)
2. Confidence adjustment (if challenging: suggest lower confidence; if supporting: suggest higher confidence)
3. Clear reasoning for your position

**Other Models' Findings:**

${INPUT_CONTENT}

**Output Format:**

Return a JSON object with this structure:
{
  "model": "gemini",
  "role": "doc-cross-review",
  "mode": "round2",
  "responses": [
    {
      "finding_id": "reference to the finding (by title or section)",
      "action": "challenge|support",
      "confidence_adjustment": -30 to +30,
      "reasoning": "Detailed explanation of why you challenge or support this finding"
    }
  ]
}

Return only valid JSON. No markdown formatting.

---
[CORE INSTRUCTION REPEAT]
Cross-review the findings above. For each finding, provide action (challenge|support), confidence_adjustment (-30 to +30), and reasoning. Return structured JSON with a responses array. Output must be valid JSON only.
PROMPT_EOF
)

fi

# --- Execute gemini review ---
RAW_OUTPUT=""
REVIEW_ERROR=""

_cli_err=$(mktemp)
RAW_OUTPUT=$(
  arena_timeout "${TIMEOUT}" gemini "${GEMINI_MODEL_ARGS[@]}" "$FULL_PROMPT" 2>"$_cli_err"
) || {
  exit_code=$?
  if [ "$exit_code" -eq 124 ]; then
    REVIEW_ERROR="Gemini doc review timed out after ${TIMEOUT}s"
  else
    REVIEW_ERROR="Gemini exited with code ${exit_code}"
  fi
}
log_stderr_file "gemini-doc-review" "$_cli_err"

# --- Handle errors (always exit 0 for graceful degradation) ---
if [ -n "$REVIEW_ERROR" ]; then
  if [ "$MODE" = "round1" ]; then
    echo "{\"model\":\"gemini\",\"role\":\"doc-$CATEGORY\",\"mode\":\"round1\",\"error\":$(echo "$REVIEW_ERROR" | jq -Rs .),\"findings\":[],\"summary\":\"Review failed\"}"
  else
    echo "{\"model\":\"gemini\",\"role\":\"doc-cross-review\",\"mode\":\"round2\",\"error\":$(echo "$REVIEW_ERROR" | jq -Rs .),\"responses\":[]}"
  fi
  exit 0
fi

if [ -z "$RAW_OUTPUT" ]; then
  if [ "$MODE" = "round1" ]; then
    echo "{\"model\":\"gemini\",\"role\":\"doc-$CATEGORY\",\"mode\":\"round1\",\"error\":\"Gemini returned empty response\",\"findings\":[],\"summary\":\"No output\"}"
  else
    echo "{\"model\":\"gemini\",\"role\":\"doc-cross-review\",\"mode\":\"round2\",\"error\":\"Gemini returned empty response\",\"responses\":[]}"
  fi
  exit 0
fi

# --- Extract JSON from response (uses shared extract_json from utils.sh) ---
PARSED_JSON=""
PARSED_JSON=$(extract_json "$RAW_OUTPUT") || {
  # Could not parse JSON at all -- wrap raw output as error (always exit 0)
  if [ "$MODE" = "round1" ]; then
    echo "{\"model\":\"gemini\",\"role\":\"doc-$CATEGORY\",\"mode\":\"round1\",\"error\":\"Failed to parse JSON from gemini response\",\"raw_output\":$(echo "$RAW_OUTPUT" | head -c 2000 | jq -Rs .),\"findings\":[],\"summary\":\"Parse error\"}"
  else
    echo "{\"model\":\"gemini\",\"role\":\"doc-cross-review\",\"mode\":\"round2\",\"error\":\"Failed to parse JSON from gemini response\",\"raw_output\":$(echo "$RAW_OUTPUT" | head -c 2000 | jq -Rs .),\"responses\":[]}"
  fi
  exit 0
}

# --- Normalize output with jq ---
if [ "$MODE" = "round1" ]; then
  NORMALIZED=$(echo "$PARSED_JSON" | jq --arg model "gemini" --arg role "doc-$CATEGORY" --arg mode "round1" '{
    model: $model,
    role: $role,
    mode: $mode,
    findings: (if .findings then .findings else [] end),
    summary: (if .summary then .summary else "No summary provided" end)
  }')
else
  NORMALIZED=$(echo "$PARSED_JSON" | jq --arg model "gemini" --arg mode "round2" '{
    model: $model,
    role: "doc-cross-review",
    mode: $mode,
    responses: (if .responses then .responses else [] end)
  }')
fi

echo "$NORMALIZED"
exit 0
