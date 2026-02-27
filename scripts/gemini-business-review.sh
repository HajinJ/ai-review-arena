#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Gemini CLI Business Review Wrapper (Dual-Mode)
#
# Usage: echo "$CONTENT" | ./gemini-business-review.sh <config_file> --mode round1|round2 [--category accuracy|audience|positioning|clarity|evidence]
#   config_file - Path to JSON config (for timeout, model settings)
#   --mode      - "round1" (independent review) or "round2" (cross-review)
#   --category  - (round1 only) Review category: accuracy|audience|positioning|clarity|evidence
#
# Reads business content from stdin (round1) or findings JSON from stdin (round2).
# Outputs valid JSON to stdout.
# =============================================================================

set -euo pipefail

# --- Parse arguments ---
CONFIG_FILE="${1:?Usage: gemini-business-review.sh <config_file> --mode round1|round2 [--category ...]}"
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
    echo "{\"model\":\"gemini\",\"mode\":\"round1\",\"error\":\"--category is required for round1. Must be one of: accuracy, audience, positioning, clarity, evidence\",\"findings\":[]}"
    exit 0
  fi

  case "$CATEGORY" in
    accuracy|audience|positioning|clarity|evidence) ;;
    *)
      echo "{\"model\":\"gemini\",\"mode\":\"round1\",\"category\":\"$CATEGORY\",\"error\":\"Invalid category: $CATEGORY. Must be one of: accuracy, audience, positioning, clarity, evidence\",\"findings\":[]}"
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
  # Round 1: Independent business review
  # Map category to role name
  case "$CATEGORY" in
    accuracy)
      ROLE="domain-accuracy"
      ;;
    audience)
      ROLE="audience-fit"
      ;;
    positioning)
      ROLE="competitive-positioning"
      ;;
    clarity)
      ROLE="communication-clarity"
      ;;
    evidence)
      ROLE="data-evidence"
      ;;
  esac

  # Build criteria based on category
  CRITERIA=""
  case "$CATEGORY" in
    accuracy)
      CRITERIA="- Factual correctness: Are all claims accurate and verifiable?
- Domain expertise: Does content demonstrate proper understanding of the domain?
- Technical precision: Are technical terms and concepts used correctly?
- Citation quality: Are sources credible and properly attributed?"
      ;;
    audience)
      CRITERIA="- Audience alignment: Does the content match the target audience's knowledge level and interests?
- Tone appropriateness: Is the tone suitable for the audience (formal/casual/technical/etc)?
- Jargon usage: Is jargon appropriate for the audience? Too much or too little?
- Accessibility: Can the target audience understand and act on this content?"
      ;;
    positioning)
      CRITERIA="- Competitive differentiation: Does content clearly articulate unique value vs competitors?
- Market positioning: Is the positioning aligned with market realities?
- Strategic messaging: Does content support the strategic positioning goals?
- Value proposition clarity: Is the value proposition clear and compelling?"
      ;;
    clarity)
      CRITERIA="- Message clarity: Is the core message clear and easy to understand?
- Structure: Is content well-organized with logical flow?
- Language quality: Is writing clear, concise, and free of ambiguity?
- Call-to-action: Are desired actions clear and actionable?"
      ;;
    evidence)
      CRITERIA="- Data quality: Are statistics and data points accurate and current?
- Evidence strength: Is evidence sufficient to support claims?
- Source credibility: Are data sources credible and authoritative?
- Quantification: Are claims backed by quantitative evidence where possible?"
      ;;
  esac

  FULL_PROMPT=$(cat <<PROMPT_EOF
You are a business content reviewer specializing in ${ROLE}.

Your task is to perform an independent review of the following business content and identify issues related to your specialty.

**Review Category: ${CATEGORY}**

**Category-Specific Criteria:**

${CRITERIA}

**Output Format:**

Return a JSON object with this structure:
{
  "model": "gemini",
  "role": "${CATEGORY}",
  "mode": "round1",
  "findings": [
    {
      "severity": "critical|high|medium|low",
      "confidence": 0-100,
      "section": "section name or line reference",
      "title": "Brief title",
      "category": "${CATEGORY}",
      "description": "Detailed description of the issue",
      "suggestion": "Specific recommendation to fix"
    }
  ],
  "summary": "Brief overall assessment (2-3 sentences)"
}

**Content to Review:**

${INPUT_CONTENT}

Return only valid JSON. No markdown formatting.

---
[CORE INSTRUCTION REPEAT]
Review the business content above for ${CATEGORY} issues. Return findings as structured JSON with fields: severity (critical|high|medium|low), confidence (0-100), section, title, category, description, and suggestion. Output must be valid JSON only.
PROMPT_EOF
)

else
  # Round 2: Cross-review of other models' findings
  FULL_PROMPT=$(cat <<PROMPT_EOF
You are a business content reviewer performing cross-examination of other models' findings.

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
  "role": "business-cross-review",
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
    REVIEW_ERROR="Gemini business review timed out after ${TIMEOUT}s"
  else
    REVIEW_ERROR="Gemini exited with code ${exit_code}"
  fi
}
log_stderr_file "gemini-business-review" "$_cli_err"

# --- Handle errors (always exit 0 for graceful degradation) ---
if [ -n "$REVIEW_ERROR" ]; then
  if [ "$MODE" = "round1" ]; then
    echo "{\"model\":\"gemini\",\"role\":\"$CATEGORY\",\"mode\":\"round1\",\"error\":$(echo "$REVIEW_ERROR" | jq -Rs .),\"findings\":[],\"summary\":\"Review failed\"}"
  else
    echo "{\"model\":\"gemini\",\"role\":\"business-cross-review\",\"mode\":\"round2\",\"error\":$(echo "$REVIEW_ERROR" | jq -Rs .),\"responses\":[]}"
  fi
  exit 0
fi

if [ -z "$RAW_OUTPUT" ]; then
  if [ "$MODE" = "round1" ]; then
    echo "{\"model\":\"gemini\",\"role\":\"$CATEGORY\",\"mode\":\"round1\",\"error\":\"Gemini returned empty response\",\"findings\":[],\"summary\":\"No output\"}"
  else
    echo "{\"model\":\"gemini\",\"role\":\"business-cross-review\",\"mode\":\"round2\",\"error\":\"Gemini returned empty response\",\"responses\":[]}"
  fi
  exit 0
fi

# --- Extract JSON from response (uses shared extract_json from utils.sh) ---
PARSED_JSON=""
PARSED_JSON=$(extract_json "$RAW_OUTPUT") || {
  # Could not parse JSON at all -- wrap raw output as error (always exit 0)
  if [ "$MODE" = "round1" ]; then
    echo "{\"model\":\"gemini\",\"role\":\"$CATEGORY\",\"mode\":\"round1\",\"error\":\"Failed to parse JSON from gemini response\",\"raw_output\":$(echo "$RAW_OUTPUT" | head -c 2000 | jq -Rs .),\"findings\":[],\"summary\":\"Parse error\"}"
  else
    echo "{\"model\":\"gemini\",\"role\":\"business-cross-review\",\"mode\":\"round2\",\"error\":\"Failed to parse JSON from gemini response\",\"raw_output\":$(echo "$RAW_OUTPUT" | head -c 2000 | jq -Rs .),\"responses\":[]}"
  fi
  exit 0
}

# --- Normalize output with jq ---
if [ "$MODE" = "round1" ]; then
  NORMALIZED=$(echo "$PARSED_JSON" | jq --arg model "gemini" --arg role "$CATEGORY" --arg mode "round1" '{
    model: $model,
    role: $role,
    mode: $mode,
    findings: (if .findings then .findings else [] end),
    summary: (if .summary then .summary else "No summary provided" end)
  }')
else
  NORMALIZED=$(echo "$PARSED_JSON" | jq --arg model "gemini" --arg mode "round2" '{
    model: $model,
    role: "business-cross-review",
    mode: $mode,
    responses: (if .responses then .responses else [] end)
  }')
fi

echo "$NORMALIZED"
exit 0
