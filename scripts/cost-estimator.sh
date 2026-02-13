#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Cost Estimator
#
# Usage: cost-estimator.sh <config_file> [total_input_lines]
#
# Estimates the cost of running multi-model reviews based on:
#   - Enabled models and their pricing
#   - Estimated token usage (lines * ~4 tokens/line)
#   - Number of enabled roles per model
#
# Output: Formatted cost estimate text (respects config language).
# =============================================================================

set -uo pipefail

# --- Arguments ---
CONFIG_FILE="${1:?Usage: cost-estimator.sh <config_file> [total_input_lines]}"
TOTAL_INPUT_LINES="${2:-500}"

# --- Dependencies ---
if ! command -v jq &>/dev/null; then
  echo "jq required for cost estimation"
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Config file not found: $CONFIG_FILE"
  exit 1
fi

# --- Pricing (USD per 1M tokens) ---
# Claude Sonnet: $3 input, $15 output
CLAUDE_INPUT_PRICE="3.00"
CLAUDE_OUTPUT_PRICE="15.00"

# Codex (approximate): $2.50 input, $10 output
CODEX_INPUT_PRICE="2.50"
CODEX_OUTPUT_PRICE="10.00"

# Gemini 2.5 Pro: $1.25 input, $10 output
GEMINI_INPUT_PRICE="1.25"
GEMINI_OUTPUT_PRICE="10.00"

# --- Token estimation ---
# Rough: ~4 tokens per line of code
TOKENS_PER_LINE=4
ESTIMATED_INPUT_TOKENS=$((TOTAL_INPUT_LINES * TOKENS_PER_LINE))

# Output estimation: ~200 tokens per finding, assume ~5 findings per role
ESTIMATED_OUTPUT_TOKENS_PER_ROLE=1000

# --- Read config ---
LANG=$(jq -r '.output.language // "ko"' "$CONFIG_FILE" 2>/dev/null)

# Model enablement and roles
claude_enabled=$(jq -r '.models.claude.enabled // false' "$CONFIG_FILE" 2>/dev/null)
claude_role_count=0
if [ "$claude_enabled" = "true" ]; then
  claude_role_count=$(jq -r '.models.claude.roles | length' "$CONFIG_FILE" 2>/dev/null || echo "0")
fi

codex_enabled=$(jq -r '.models.codex.enabled // false' "$CONFIG_FILE" 2>/dev/null)
codex_role_count=0
if [ "$codex_enabled" = "true" ]; then
  codex_role_count=$(jq -r '.models.codex.roles | length' "$CONFIG_FILE" 2>/dev/null || echo "0")
fi

gemini_enabled=$(jq -r '.models.gemini.enabled // false' "$CONFIG_FILE" 2>/dev/null)
gemini_role_count=0
if [ "$gemini_enabled" = "true" ]; then
  gemini_role_count=$(jq -r '.models.gemini.roles | length' "$CONFIG_FILE" 2>/dev/null || echo "0")
fi

# Debate rounds (additional calls)
debate_enabled=$(jq -r '.debate.enabled // false' "$CONFIG_FILE" 2>/dev/null)
debate_rounds=$(jq -r '.debate.max_rounds // 0' "$CONFIG_FILE" 2>/dev/null)

# --- Calculate costs ---
# Use awk for floating-point arithmetic

calc_model_cost() {
  local role_count="$1"
  local input_price="$2"
  local output_price="$3"
  local input_tokens="$4"
  local output_tokens="$5"

  awk -v roles="$role_count" \
      -v in_price="$input_price" \
      -v out_price="$output_price" \
      -v in_tokens="$input_tokens" \
      -v out_tokens="$output_tokens" \
      'BEGIN {
        in_cost = (in_tokens / 1000000) * in_price * roles
        out_cost = (out_tokens / 1000000) * out_price * roles
        printf "%.6f", in_cost + out_cost
      }'
}

CLAUDE_COST="0.000000"
CODEX_COST="0.000000"
GEMINI_COST="0.000000"
DEBATE_COST="0.000000"

if [ "$claude_enabled" = "true" ] && [ "$claude_role_count" -gt 0 ]; then
  CLAUDE_COST=$(calc_model_cost "$claude_role_count" "$CLAUDE_INPUT_PRICE" "$CLAUDE_OUTPUT_PRICE" "$ESTIMATED_INPUT_TOKENS" "$ESTIMATED_OUTPUT_TOKENS_PER_ROLE")
fi

if [ "$codex_enabled" = "true" ] && [ "$codex_role_count" -gt 0 ]; then
  CODEX_COST=$(calc_model_cost "$codex_role_count" "$CODEX_INPUT_PRICE" "$CODEX_OUTPUT_PRICE" "$ESTIMATED_INPUT_TOKENS" "$ESTIMATED_OUTPUT_TOKENS_PER_ROLE")
fi

if [ "$gemini_enabled" = "true" ] && [ "$gemini_role_count" -gt 0 ]; then
  GEMINI_COST=$(calc_model_cost "$gemini_role_count" "$GEMINI_INPUT_PRICE" "$GEMINI_OUTPUT_PRICE" "$ESTIMATED_INPUT_TOKENS" "$ESTIMATED_OUTPUT_TOKENS_PER_ROLE")
fi

# Debate cost: each round has ~2 additional API calls with smaller payloads
if [ "$debate_enabled" = "true" ] && [ "$debate_rounds" -gt 0 ]; then
  DEBATE_INPUT=$((ESTIMATED_INPUT_TOKENS / 2))  # Debates use shorter context
  DEBATE_OUTPUT=500  # Shorter responses

  # Use the cheapest enabled model for debate cost estimation
  if [ "$codex_enabled" = "true" ]; then
    DEBATE_COST=$(awk -v rounds="$debate_rounds" \
      -v in_price="$CODEX_INPUT_PRICE" \
      -v out_price="$CODEX_OUTPUT_PRICE" \
      -v in_tokens="$DEBATE_INPUT" \
      -v out_tokens="$DEBATE_OUTPUT" \
      'BEGIN {
        calls = rounds * 2
        in_cost = (in_tokens / 1000000) * in_price * calls
        out_cost = (out_tokens / 1000000) * out_price * calls
        printf "%.6f", in_cost + out_cost
      }')
  elif [ "$gemini_enabled" = "true" ]; then
    DEBATE_COST=$(awk -v rounds="$debate_rounds" \
      -v in_price="$GEMINI_INPUT_PRICE" \
      -v out_price="$GEMINI_OUTPUT_PRICE" \
      -v in_tokens="$DEBATE_INPUT" \
      -v out_tokens="$DEBATE_OUTPUT" \
      'BEGIN {
        calls = rounds * 2
        in_cost = (in_tokens / 1000000) * in_price * calls
        out_cost = (out_tokens / 1000000) * out_price * calls
        printf "%.6f", in_cost + out_cost
      }')
  fi
fi

TOTAL_COST=$(awk -v c="$CLAUDE_COST" -v co="$CODEX_COST" -v g="$GEMINI_COST" -v d="$DEBATE_COST" \
  'BEGIN { printf "%.4f", c + co + g + d }')

# --- Format output ---
format_cost() {
  local cost="$1"
  awk -v c="$cost" 'BEGIN {
    if (c < 0.0001) printf "$0.0000"
    else if (c < 0.01) printf "$%.4f", c
    else printf "$%.4f", c
  }'
}

TOTAL_FORMATTED=$(format_cost "$TOTAL_COST")

# Count enabled models
ENABLED_COUNT=0
[ "$claude_enabled" = "true" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
[ "$codex_enabled" = "true" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
[ "$gemini_enabled" = "true" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))

TOTAL_ROLES=$((claude_role_count + codex_role_count + gemini_role_count))

# --- Output ---
if [ "$LANG" = "ko" ]; then
  echo "입력: ~${TOTAL_INPUT_LINES}줄 (~${ESTIMATED_INPUT_TOKENS} 토큰)"
  echo "활성 모델: ${ENABLED_COUNT}개 (${TOTAL_ROLES}개 역할)"

  if [ "$claude_enabled" = "true" ] && [ "$claude_role_count" -gt 0 ]; then
    echo "  Claude Sonnet: ${claude_role_count}개 역할, $(format_cost "$CLAUDE_COST")"
  fi
  if [ "$codex_enabled" = "true" ] && [ "$codex_role_count" -gt 0 ]; then
    echo "  Codex: ${codex_role_count}개 역할, $(format_cost "$CODEX_COST")"
  fi
  if [ "$gemini_enabled" = "true" ] && [ "$gemini_role_count" -gt 0 ]; then
    echo "  Gemini 2.5 Pro: ${gemini_role_count}개 역할, $(format_cost "$GEMINI_COST")"
  fi
  if [ "$debate_enabled" = "true" ] && [ "$debate_rounds" -gt 0 ]; then
    echo "  토론 (${debate_rounds} 라운드): $(format_cost "$DEBATE_COST")"
  fi

  echo "예상 총 비용: ${TOTAL_FORMATTED}"
else
  echo "Input: ~${TOTAL_INPUT_LINES} lines (~${ESTIMATED_INPUT_TOKENS} tokens)"
  echo "Active models: ${ENABLED_COUNT} (${TOTAL_ROLES} roles)"

  if [ "$claude_enabled" = "true" ] && [ "$claude_role_count" -gt 0 ]; then
    echo "  Claude Sonnet: ${claude_role_count} roles, $(format_cost "$CLAUDE_COST")"
  fi
  if [ "$codex_enabled" = "true" ] && [ "$codex_role_count" -gt 0 ]; then
    echo "  Codex: ${codex_role_count} roles, $(format_cost "$CODEX_COST")"
  fi
  if [ "$gemini_enabled" = "true" ] && [ "$gemini_role_count" -gt 0 ]; then
    echo "  Gemini 2.5 Pro: ${gemini_role_count} roles, $(format_cost "$GEMINI_COST")"
  fi
  if [ "$debate_enabled" = "true" ] && [ "$debate_rounds" -gt 0 ]; then
    echo "  Debate (${debate_rounds} rounds): $(format_cost "$DEBATE_COST")"
  fi

  echo "Estimated total: ${TOTAL_FORMATTED}"
fi
