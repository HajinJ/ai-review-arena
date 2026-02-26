#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Codex CLI Business Content Review Wrapper
#
# Usage: echo "$CONTENT" | ./codex-business-review.sh <config_file> --mode round1|round2 [--category accuracy|audience|positioning|clarity|evidence]
#   config_file - Path to JSON config (for timeout, model settings)
#   --mode      - round1 (independent review) or round2 (cross-review)
#   --category  - Review category (for round1): accuracy|audience|positioning|clarity|evidence
#
# Reads content from stdin.
# Outputs valid JSON to stdout.
# =============================================================================

set -euo pipefail

# --- Parse Arguments ---
CONFIG_FILE="${1:?Usage: codex-business-review.sh <config_file> --mode round1|round2 [--category <category>]}"
MODE=""
CATEGORY=""

shift
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
      echo "{\"model\":\"codex\",\"error\":\"Unknown argument: $1\",\"findings\":[]}" >&2
      exit 1
      ;;
  esac
done

# --- Validate mode ---
if [ -z "$MODE" ]; then
  echo "{\"model\":\"codex\",\"error\":\"--mode is required (round1 or round2)\",\"findings\":[]}"
  exit 1
fi

case "$MODE" in
  round1|round2) ;;
  *)
    echo "{\"model\":\"codex\",\"error\":\"Invalid mode: $MODE. Must be round1 or round2\",\"findings\":[]}"
    exit 1
    ;;
esac

# --- Validate category for round1 ---
if [ "$MODE" = "round1" ]; then
  if [ -z "$CATEGORY" ]; then
    echo "{\"model\":\"codex\",\"role\":\"\",\"mode\":\"round1\",\"error\":\"--category is required for round1. Must be one of: accuracy, audience, positioning, clarity, evidence\",\"findings\":[]}"
    exit 1
  fi

  case "$CATEGORY" in
    accuracy|audience|positioning|clarity|evidence) ;;
    *)
      echo "{\"model\":\"codex\",\"role\":\"$CATEGORY\",\"mode\":\"round1\",\"error\":\"Invalid category: $CATEGORY. Must be one of: accuracy, audience, positioning, clarity, evidence\",\"findings\":[]}"
      exit 1
      ;;
  esac
fi

# --- Check dependencies ---
if ! command -v codex &>/dev/null; then
  echo "{\"model\":\"codex\",\"role\":\"${CATEGORY:-business-cross-review}\",\"mode\":\"$MODE\",\"error\":\"codex CLI not found. Install: npm install -g @openai/codex\",\"findings\":[]}"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "{\"model\":\"codex\",\"role\":\"${CATEGORY:-business-cross-review}\",\"mode\":\"$MODE\",\"error\":\"jq not found. Install: brew install jq\",\"findings\":[]}"
  exit 1
fi

# --- Resolve paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# --- Read config for timeouts and model ---
TIMEOUT_ROUND1=120
TIMEOUT_ROUND2=180
CODEX_MODEL="gpt-5.3-codex-spark"

if [ -f "$CONFIG_FILE" ]; then
  cfg_timeout_r1=$(jq -r '.fallback.external_cli_timeout_seconds // empty' "$CONFIG_FILE" 2>/dev/null || true)
  cfg_timeout_r2=$(jq -r '.fallback.external_cli_debate_timeout_seconds // empty' "$CONFIG_FILE" 2>/dev/null || true)

  if [ -n "$cfg_timeout_r1" ]; then
    TIMEOUT_ROUND1="$cfg_timeout_r1"
  fi
  if [ -n "$cfg_timeout_r2" ]; then
    TIMEOUT_ROUND2="$cfg_timeout_r2"
  fi

  cfg_model=$(jq -r '.codex.model_variant // .models.codex.model_variant // empty' "$CONFIG_FILE" 2>/dev/null || true)
  if [ -n "$cfg_model" ]; then
    CODEX_MODEL="$cfg_model"
  fi
fi

TIMEOUT=$TIMEOUT_ROUND1
if [ "$MODE" = "round2" ]; then
  TIMEOUT=$TIMEOUT_ROUND2
fi

# --- Read structured output config ---
STRUCTURED_OUTPUT=true
if [ -f "$CONFIG_FILE" ]; then
  cfg_structured=$(jq -r '.models.codex.structured_output // true' "$CONFIG_FILE" 2>/dev/null || true)
  if [ "$cfg_structured" = "false" ]; then
    STRUCTURED_OUTPUT=false
  fi
fi

if [ "$MODE" = "round1" ]; then
  SCHEMA_FILE="${PLUGIN_DIR}/config/schemas/codex-business-review.json"
else
  SCHEMA_FILE="${PLUGIN_DIR}/config/schemas/codex-business-cross-review.json"
fi

# --- Read content from stdin ---
CONTENT=$(cat)

if [ -z "$CONTENT" ]; then
  echo "{\"model\":\"codex\",\"role\":\"${CATEGORY:-business-cross-review}\",\"mode\":\"$MODE\",\"error\":\"No content provided on stdin\",\"findings\":[]}"
  exit 1
fi

# --- Build prompt based on mode ---
if [ "$MODE" = "round1" ]; then
  # Round 1: Independent business content review
  FULL_PROMPT=$(cat <<'PROMPT_EOF'
You are a business content reviewer specializing in CATEGORY_PLACEHOLDER.

Review the following business content and provide findings in JSON format.

REVIEW CRITERIA BY CATEGORY:

**accuracy**: Factual correctness, data accuracy, claim validation
- Verify numerical data, statistics, market claims
- Check for factual errors or outdated information
- Validate sources and citations
- Flag unsubstantiated claims

**audience**: Target audience fit, tone, complexity
- Assess if content matches intended audience level
- Check if terminology is appropriate for readers
- Evaluate engagement and relevance
- Identify sections that may confuse or alienate readers

**positioning**: Competitive positioning, differentiation, value proposition
- Evaluate uniqueness of value proposition
- Check differentiation from competitors
- Assess market positioning clarity
- Identify weak or unconvincing positioning statements

**clarity**: Communication clarity, structure, flow
- Check for ambiguous or vague statements
- Evaluate logical flow and organization
- Identify confusing sections or jargon overuse
- Flag redundancy or verbosity

**evidence**: Data quality, source credibility, evidence strength
- Assess quality and credibility of cited sources
- Check if evidence supports claims effectively
- Identify missing evidence for key assertions
- Evaluate data presentation and visualization quality

OUTPUT FORMAT (JSON):
{
  "model": "codex",
  "role": "CATEGORY_PLACEHOLDER",
  "mode": "round1",
  "findings": [
    {
      "severity": "critical|high|medium|low",
      "confidence": 0.0-1.0,
      "section": "section name or line reference",
      "title": "brief title",
      "category": "CATEGORY_PLACEHOLDER",
      "description": "detailed description of the issue",
      "suggestion": "specific recommendation to fix"
    }
  ],
  "summary": "Overall assessment summary in 2-3 sentences"
}

Focus ONLY on CATEGORY_PLACEHOLDER issues. Be specific and constructive.

--- BUSINESS CONTENT ---
CONTENT_PLACEHOLDER
--- END CONTENT ---

---
[CORE INSTRUCTION REPEAT]
Review the business content above for CATEGORY_PLACEHOLDER issues. Return findings as structured JSON with fields: severity (critical|high|medium|low), confidence (0.0-1.0), section, title, category, description, and suggestion. Output must be valid JSON only.
PROMPT_EOF
)
  FULL_PROMPT="${FULL_PROMPT//CATEGORY_PLACEHOLDER/$CATEGORY}"
  FULL_PROMPT="${FULL_PROMPT//CONTENT_PLACEHOLDER/$CONTENT}"

else
  # Round 2: Cross-review of other models' findings
  FULL_PROMPT=$(cat <<'PROMPT_EOF'
You are a business content cross-reviewer. Your job is to review findings from other AI models (Round 1 reviews) and assess their accuracy and logical consistency.

You will receive:
1. Original business content
2. Findings from other models (Round 1)

Your task:
- Challenge findings that are incorrect, overstated, or lack evidence
- Support findings that are accurate and well-reasoned
- Provide confidence adjustments (+/- 0.1 to 0.3) based on your assessment
- Be specific about WHY you challenge or support each finding

OUTPUT FORMAT (JSON):
{
  "model": "codex",
  "role": "business-cross-review",
  "mode": "round2",
  "responses": [
    {
      "finding_id": "string (model-role-N format, e.g., claude-accuracy-1)",
      "action": "challenge|support",
      "confidence_adjustment": -0.3 to +0.3,
      "reasoning": "specific explanation of why you challenge or support this finding"
    }
  ]
}

Be rigorous and objective. Only challenge findings with clear reasoning.

--- INPUT DATA ---
CONTENT_PLACEHOLDER
--- END INPUT ---

---
[CORE INSTRUCTION REPEAT]
Cross-review the findings above. For each finding, provide action (challenge|support), confidence_adjustment (-0.3 to +0.3), and reasoning. Return structured JSON with a responses array. Output must be valid JSON only.
PROMPT_EOF
)
  FULL_PROMPT="${FULL_PROMPT//CONTENT_PLACEHOLDER/$CONTENT}"
fi

# --- Execute codex review ---
RAW_OUTPUT=""
REVIEW_ERROR=""
PARSED_JSON=""

# Try structured output first
if [ "$STRUCTURED_OUTPUT" = "true" ] && [ -f "$SCHEMA_FILE" ]; then
  OUTPUT_FILE=$(mktemp)
  RAW_OUTPUT=$(
    timeout "${TIMEOUT}s" codex exec --full-auto -m "$CODEX_MODEL" \
      --output-schema "$SCHEMA_FILE" -o "$OUTPUT_FILE" "$FULL_PROMPT" 2>/dev/null
  ) || {
    exit_code=$?
    if [ "$exit_code" -eq 124 ]; then
      REVIEW_ERROR="Codex review timed out after ${TIMEOUT}s"
    else
      REVIEW_ERROR="Codex exited with code ${exit_code}"
    fi
  }

  # Read structured output from -o file (clean JSON, no extraction needed)
  if [ -z "$REVIEW_ERROR" ] && [ -f "$OUTPUT_FILE" ] && jq . "$OUTPUT_FILE" &>/dev/null; then
    PARSED_JSON=$(cat "$OUTPUT_FILE")
  fi
  rm -f "$OUTPUT_FILE"
fi

# Fallback to standard execution if structured output didn't work
if [ -z "$PARSED_JSON" ] && [ -z "$REVIEW_ERROR" ]; then
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
fi

# --- Handle errors ---
if [ -n "$REVIEW_ERROR" ]; then
  if [ "$MODE" = "round1" ]; then
    echo "{\"model\":\"codex\",\"role\":\"$CATEGORY\",\"mode\":\"round1\",\"error\":$(echo "$REVIEW_ERROR" | jq -Rs .),\"findings\":[]}"
  else
    echo "{\"model\":\"codex\",\"role\":\"business-cross-review\",\"mode\":\"round2\",\"error\":$(echo "$REVIEW_ERROR" | jq -Rs .),\"responses\":[]}"
  fi
  exit 0
fi

if [ -z "$RAW_OUTPUT" ] && [ -z "$PARSED_JSON" ]; then
  if [ "$MODE" = "round1" ]; then
    echo "{\"model\":\"codex\",\"role\":\"$CATEGORY\",\"mode\":\"round1\",\"error\":\"Codex returned empty response\",\"findings\":[]}"
  else
    echo "{\"model\":\"codex\",\"role\":\"business-cross-review\",\"mode\":\"round2\",\"error\":\"Codex returned empty response\",\"responses\":[]}"
  fi
  exit 0
fi

# --- Extract JSON from response (4-layer extraction) ---
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

# Skip extraction if structured output already provided clean JSON
if [ -z "$PARSED_JSON" ]; then
  PARSED_JSON=$(extract_json "$RAW_OUTPUT") || {
    # Could not parse JSON at all -- wrap raw output as error
    if [ "$MODE" = "round1" ]; then
      echo "{\"model\":\"codex\",\"role\":\"$CATEGORY\",\"mode\":\"round1\",\"error\":\"Failed to parse JSON from codex response\",\"raw_output\":$(echo "$RAW_OUTPUT" | head -c 2000 | jq -Rs .),\"findings\":[]}"
    else
      echo "{\"model\":\"codex\",\"role\":\"business-cross-review\",\"mode\":\"round2\",\"error\":\"Failed to parse JSON from codex response\",\"raw_output\":$(echo "$RAW_OUTPUT" | head -c 2000 | jq -Rs .),\"responses\":[]}"
    fi
    exit 0
  }
fi

# --- Normalize output based on mode ---
if [ "$MODE" = "round1" ]; then
  NORMALIZED=$(echo "$PARSED_JSON" | jq --arg model "codex" --arg role "$CATEGORY" --arg mode "round1" '{
    model: $model,
    role: $role,
    mode: $mode,
    findings: (if .findings then .findings else [] end),
    summary: (if .summary then .summary else "No summary provided" end)
  }')
else
  NORMALIZED=$(echo "$PARSED_JSON" | jq --arg model "codex" --arg role "business-cross-review" --arg mode "round2" '{
    model: $model,
    role: $role,
    mode: $mode,
    responses: (if .responses then .responses else [] end)
  }')
fi

echo "$NORMALIZED"
