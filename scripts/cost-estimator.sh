#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Phase-Based Cost Estimator
#
# Usage: cost-estimator.sh <config_file> [--intensity <level>] [--pipeline code|business]
#                          [--lines <total_input_lines>] [--figma] [--json]
#
# Estimates the cost of running the arena pipeline based on:
#   - Intensity level (quick/standard/deep/comprehensive)
#   - Pipeline type (code or business)
#   - Per-phase token estimates and pricing
#   - Enabled models, Agent Team overhead, debate costs
#
# Output: Formatted cost estimate text (respects config language) or JSON.
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

ensure_jq

# --- Arguments ---
CONFIG_FILE="${1:?Usage: cost-estimator.sh <config_file> [--intensity <level>] [--pipeline code|business] [--lines <N>]}"
shift

INTENSITY="standard"
PIPELINE="code"
TOTAL_INPUT_LINES=500
HAS_FIGMA="false"
OUTPUT_JSON="false"

while [ $# -gt 0 ]; do
  case "$1" in
    --intensity) INTENSITY="${2:-standard}"; shift 2 ;;
    --pipeline) PIPELINE="${2:-code}"; shift 2 ;;
    --lines) TOTAL_INPUT_LINES="${2:-500}"; shift 2 ;;
    --figma) HAS_FIGMA="true"; shift ;;
    --json) OUTPUT_JSON="true"; shift ;;
    *) shift ;;
  esac
done

if [ ! -f "$CONFIG_FILE" ]; then
  log_error "Config file not found: $CONFIG_FILE"
  exit 1
fi

# --- Pricing (USD per 1M tokens) ---
# Defaults; overridden by config cost_estimation.token_cost_per_1k (per-1K → multiply by 1000)
CLAUDE_INPUT_PRICE="3.00"
CLAUDE_OUTPUT_PRICE="15.00"
CODEX_INPUT_PRICE="3.00"
CODEX_OUTPUT_PRICE="12.00"
GEMINI_INPUT_PRICE="1.25"
GEMINI_OUTPUT_PRICE="5.00"

# Read prices from config if available (config stores per-1K, we need per-1M)
if [ -f "$CONFIG_FILE" ]; then
  _read_price() {
    local key="$1" default="$2"
    local val
    val=$(jq -r ".cost_estimation.token_cost_per_1k.${key} // empty" "$CONFIG_FILE" 2>/dev/null || true)
    if [ -n "$val" ]; then
      awk -v v="$val" 'BEGIN { printf "%.2f", v * 1000 }'
    else
      echo "$default"
    fi
  }
  CLAUDE_INPUT_PRICE=$(_read_price "claude_input" "$CLAUDE_INPUT_PRICE")
  CLAUDE_OUTPUT_PRICE=$(_read_price "claude_output" "$CLAUDE_OUTPUT_PRICE")
  CODEX_INPUT_PRICE=$(_read_price "codex_input" "$CODEX_INPUT_PRICE")
  CODEX_OUTPUT_PRICE=$(_read_price "codex_output" "$CODEX_OUTPUT_PRICE")
  GEMINI_INPUT_PRICE=$(_read_price "gemini_input" "$GEMINI_INPUT_PRICE")
  GEMINI_OUTPUT_PRICE=$(_read_price "gemini_output" "$GEMINI_OUTPUT_PRICE")
fi

# --- Prompt cache awareness ---
# Claude prompt caching: cached input tokens billed at ~10% of base price (90% discount).
# cache_discount = overall expected input cost reduction ratio (0.0 = no caching, 0.5 = 50% input savings).
# Agent workflows with stable system prompts typically achieve 0.4-0.6 effective discount.
CACHE_DISCOUNT="0.0"
if [ -f "$CONFIG_FILE" ]; then
  cfg_cache=$(jq -r '.cost_estimation.prompt_cache_discount // empty' "$CONFIG_FILE" 2>/dev/null || true)
  if [ -n "$cfg_cache" ]; then
    CACHE_DISCOUNT="$cfg_cache"
  fi
fi

# --- Read config ---
OUTPUT_LANG=$(jq -r '.output.language // "ko"' "$CONFIG_FILE" 2>/dev/null)
claude_enabled=$(jq -r '.models.claude.enabled // false' "$CONFIG_FILE" 2>/dev/null)
codex_enabled=$(jq -r '.models.codex.enabled // false' "$CONFIG_FILE" 2>/dev/null)
gemini_enabled=$(jq -r '.models.gemini.enabled // false' "$CONFIG_FILE" 2>/dev/null)
debate_enabled=$(jq -r '.debate.enabled // false' "$CONFIG_FILE" 2>/dev/null)
debate_rounds=$(jq -r '.debate.max_rounds // 3' "$CONFIG_FILE" 2>/dev/null)

# Check external CLI availability
codex_available="false"
gemini_available="false"
command -v codex &>/dev/null && codex_available="true"
command -v gemini &>/dev/null && gemini_available="true"

# Effective model availability
codex_active="false"
gemini_active="false"
[ "$codex_enabled" = "true" ] && [ "$codex_available" = "true" ] && codex_active="true"
[ "$gemini_enabled" = "true" ] && [ "$gemini_available" = "true" ] && gemini_active="true"

# --- Helper ---
calc_cost() {
  local input_tokens="$1"
  local output_tokens="$2"
  local input_price="$3"
  local output_price="$4"
  local cache_disc="${5:-$CACHE_DISCOUNT}"

  # Apply prompt cache discount to input tokens:
  # Effective input price = base_price * (1 - cache_discount)
  awk -v it="$input_tokens" -v ot="$output_tokens" \
      -v ip="$input_price" -v op="$output_price" -v cd="$cache_disc" \
      'BEGIN { printf "%.4f", (it/1000000)*ip*(1-cd) + (ot/1000000)*op }'
}

format_cost() {
  local cost="$1"
  awk -v c="$cost" 'BEGIN { printf "$%.2f", c }'
}

# =============================================================================
# Phase Cost Table (token estimates per phase)
# =============================================================================

# Code pipeline phase costs: [input_tokens, output_tokens]
# Business pipeline phase costs: [input_tokens, output_tokens]

# Bash 3.2 compatible: use prefixed variables + indirect expansion instead of declare -A
# Prefixes: _pi_ (phase input), _po_ (phase output), _le_ (label EN), _lk_ (label KO)

if [ "$PIPELINE" = "code" ]; then
  _pi_intensity=6000;   _po_intensity=4000
  _le_intensity="Intensity Decision (4 agents)";  _lk_intensity="강도 결정 (4 에이전트)"

  _pi_cost=2000;        _po_cost=1000
  _le_cost="Cost Estimation";                     _lk_cost="비용 추정"

  _pi_codebase=5000;    _po_codebase=3000
  _le_codebase="Codebase Analysis";               _lk_codebase="코드베이스 분석"

  _pi_stack=2000;       _po_stack=1000
  _le_stack="Stack Detection";                    _lk_stack="스택 감지"

  _pi_research=10000;   _po_research=5000
  _le_research="Pre-Implementation Research";     _lk_research="사전 리서치"

  _pi_research_debate=8000;  _po_research_debate=4000
  _le_research_debate="Research Direction Debate"; _lk_research_debate="리서치 방향 토론"

  _pi_compliance=8000;  _po_compliance=4000
  _le_compliance="Compliance Detection";          _lk_compliance="컴플라이언스 감지"

  _pi_compliance_debate=6000; _po_compliance_debate=3000
  _le_compliance_debate="Compliance Scope Debate"; _lk_compliance_debate="컴플라이언스 범위 토론"

  _pi_benchmark=25000;  _po_benchmark=15000
  _le_benchmark="Model Benchmarking";             _lk_benchmark="모델 벤치마킹"

  _pi_figma=15000;      _po_figma=5000
  _le_figma="Figma Analysis";                     _lk_figma="Figma 분석"

  _pi_strategy=15000;   _po_strategy=10000
  _le_strategy="Strategy Debate (4 agents)";      _lk_strategy="전략 토론 (4 에이전트)"

  _pi_review_agent=8000; _po_review_agent=4000
  _le_review_agent="Review (per Claude agent)";   _lk_review_agent="리뷰 (Claude 에이전트당)"

  _pi_review_cli=6000;  _po_review_cli=2000
  _le_review_cli="Review (per external CLI)";     _lk_review_cli="리뷰 (외부 CLI당)"

  _pi_debate=40000;     _po_debate=20000
  _le_debate="Adversarial Debate (rounds 2-3)";   _lk_debate="적대적 토론 (라운드 2-3)"

  _pi_autofix=6000;     _po_autofix=4000
  _le_autofix="Auto-Fix Loop";                    _lk_autofix="자동 수정"

  _pi_report=3000;      _po_report=2000
  _le_report="Final Report";                      _lk_report="최종 리포트"

else
  # Business pipeline phases
  _pi_intensity=6000;   _po_intensity=4000
  _le_intensity="Intensity Decision (4 agents)";  _lk_intensity="강도 결정 (4 에이전트)"

  _pi_cost=2000;        _po_cost=1000
  _le_cost="Cost Estimation";                     _lk_cost="비용 추정"

  _pi_context=7000;     _po_context=3000
  _le_context="Business Context Analysis";        _lk_context="비즈니스 컨텍스트 분석"

  _pi_market=10000;     _po_market=5000
  _le_market="Market Research";                   _lk_market="시장 리서치"

  _pi_research=12000;   _po_research=8000
  _le_research="Best Practices Research";         _lk_research="베스트 프랙티스 리서치"

  _pi_research_debate=8000; _po_research_debate=4000
  _le_research_debate="Research Direction Debate"; _lk_research_debate="리서치 방향 토론"

  _pi_accuracy=12000;   _po_accuracy=6000
  _le_accuracy="Accuracy Audit";                  _lk_accuracy="정확성 감사"

  _pi_accuracy_debate=6000; _po_accuracy_debate=3000
  _le_accuracy_debate="Accuracy Scope Debate";    _lk_accuracy_debate="정확성 범위 토론"

  _pi_benchmark=25000;  _po_benchmark=15000
  _le_benchmark="Model Benchmarking";             _lk_benchmark="모델 벤치마킹"

  _pi_strategy=15000;   _po_strategy=10000
  _le_strategy="Content Strategy Debate";         _lk_strategy="콘텐츠 전략 토론"

  _pi_review_agent=10000; _po_review_agent=5000
  _le_review_agent="Review (per business agent)"; _lk_review_agent="리뷰 (비즈니스 에이전트당)"

  _pi_review_cli=6000;  _po_review_cli=2000
  _le_review_cli="Review (per external CLI)";     _lk_review_cli="리뷰 (외부 CLI당)"

  _pi_debate=35000;     _po_debate=15000
  _le_debate="Business Review Debate";            _lk_debate="비즈니스 리뷰 토론"

  _pi_autofix=10000;    _po_autofix=5000
  _le_autofix="Auto-Revision";                    _lk_autofix="자동 수정"

  _pi_report=5000;      _po_report=3000
  _le_report="Final Report";                      _lk_report="최종 리포트"
fi

# =============================================================================
# Build phase list by intensity
# =============================================================================

PHASES=()
case "$INTENSITY" in
  quick)
    PHASES=(intensity cost codebase)
    if [ "$PIPELINE" = "business" ]; then
      PHASES=(intensity cost context)
    fi
    ;;
  standard)
    if [ "$PIPELINE" = "code" ]; then
      PHASES=(intensity cost codebase stack strategy review_agent review_cli debate autofix report)
    else
      PHASES=(intensity cost context market strategy review_agent review_cli debate autofix report)
    fi
    ;;
  deep)
    if [ "$PIPELINE" = "code" ]; then
      PHASES=(intensity cost codebase stack research research_debate compliance compliance_debate strategy review_agent review_cli debate autofix report)
    else
      PHASES=(intensity cost context market research research_debate accuracy accuracy_debate strategy review_agent review_cli debate autofix report)
    fi
    ;;
  comprehensive)
    if [ "$PIPELINE" = "code" ]; then
      PHASES=(intensity cost codebase stack research research_debate compliance compliance_debate benchmark strategy review_agent review_cli debate autofix report)
      [ "$HAS_FIGMA" = "true" ] && PHASES=(intensity cost codebase stack research research_debate compliance compliance_debate benchmark figma strategy review_agent review_cli debate autofix report)
    else
      PHASES=(intensity cost context market research research_debate accuracy accuracy_debate benchmark strategy review_agent review_cli debate autofix report)
    fi
    ;;
esac

# =============================================================================
# Calculate costs per phase
# =============================================================================

TOTAL_TOKENS=0
TOTAL_COST_VAL="0.0000"
BREAKDOWN=""

# Determine review agent count and CLI call count
claude_agent_count=0
cli_call_count=0

if [ "$INTENSITY" != "quick" ]; then
  if [ "$PIPELINE" = "code" ]; then
    claude_agent_count=$(jq -r '.models.claude.roles | length' "$CONFIG_FILE" 2>/dev/null || echo "3")
    # +1 for debate-arbitrator
    claude_agent_count=$((claude_agent_count + 1))
  else
    claude_agent_count=6  # 5 business reviewers + arbitrator
  fi

  [ "$codex_active" = "true" ] && cli_call_count=$((cli_call_count + 1))
  [ "$gemini_active" = "true" ] && cli_call_count=$((cli_call_count + 1))
fi

for phase in "${PHASES[@]}"; do
  _pi_var="_pi_${phase}"; input_t="${!_pi_var:-0}"
  _po_var="_po_${phase}"; output_t="${!_po_var:-0}"

  # Scale review_agent by agent count
  if [ "$phase" = "review_agent" ]; then
    input_t=$((input_t * claude_agent_count))
    output_t=$((output_t * claude_agent_count))
  fi

  # Scale review_cli by CLI count
  if [ "$phase" = "review_cli" ]; then
    if [ "$cli_call_count" -eq 0 ]; then
      continue  # Skip if no external CLIs
    fi
    input_t=$((input_t * cli_call_count))
    output_t=$((output_t * cli_call_count))
  fi

  # Scale input tokens by actual code size for review phases
  if [ "$phase" = "review_agent" ] || [ "$phase" = "review_cli" ] || [ "$phase" = "codebase" ]; then
    local_lines_factor=$(awk -v lines="$TOTAL_INPUT_LINES" 'BEGIN { f = lines / 500; if (f < 1) f = 1; printf "%.1f", f }')
    input_t=$(awk -v t="$input_t" -v f="$local_lines_factor" 'BEGIN { printf "%d", t * f }')
  fi

  phase_tokens=$((input_t + output_t))
  TOTAL_TOKENS=$((TOTAL_TOKENS + phase_tokens))

  # Calculate cost using Claude pricing as default (Agent Team = Claude)
  phase_cost=$(calc_cost "$input_t" "$output_t" "$CLAUDE_INPUT_PRICE" "$CLAUDE_OUTPUT_PRICE")

  # Override for CLI-only phases
  if [ "$phase" = "review_cli" ]; then
    phase_cost=$(calc_cost "$input_t" "$output_t" "$CODEX_INPUT_PRICE" "$CODEX_OUTPUT_PRICE")
  fi

  TOTAL_COST_VAL=$(awk -v t="$TOTAL_COST_VAL" -v p="$phase_cost" 'BEGIN { printf "%.4f", t + p }')

  if [ "$OUTPUT_LANG" = "ko" ]; then
    _lk_var="_lk_${phase}"; label="${!_lk_var:-$phase}"
  else
    _le_var="_le_${phase}"; label="${!_le_var:-$phase}"
  fi

  BREAKDOWN="${BREAKDOWN}  ${label}: ~${phase_tokens} tokens, $(format_cost "$phase_cost")\n"
done

# Estimate time
EST_MINUTES=$(awk -v t="$TOTAL_TOKENS" 'BEGIN { m = t / 15000; if (m < 1) m = 1; printf "%d", m + 0.5 }')

# =============================================================================
# Output
# =============================================================================

if [ "$OUTPUT_JSON" = "true" ]; then
  jq -n \
    --arg intensity "$INTENSITY" \
    --arg pipeline "$PIPELINE" \
    --argjson total_tokens "$TOTAL_TOKENS" \
    --arg total_cost "$TOTAL_COST_VAL" \
    --argjson est_minutes "$EST_MINUTES" \
    --argjson claude_agents "$claude_agent_count" \
    --argjson cli_calls "$cli_call_count" \
    --argjson lines "$TOTAL_INPUT_LINES" \
    --arg cache_discount "$CACHE_DISCOUNT" \
    '{
      intensity: $intensity,
      pipeline: $pipeline,
      input_lines: $lines,
      claude_agents: $claude_agents,
      external_cli_calls: $cli_calls,
      total_tokens: $total_tokens,
      total_cost_usd: ($total_cost | tonumber),
      est_minutes: $est_minutes,
      prompt_cache_discount: ($cache_discount | tonumber)
    }'
  exit 0
fi

# Formatted text output
if [ "$OUTPUT_LANG" = "ko" ]; then
  echo "## 비용 & 시간 추정"
  echo ""
  echo "강도: ${INTENSITY}"
  echo "파이프라인: ${PIPELINE}"
  echo "입력: ~${TOTAL_INPUT_LINES}줄"
  echo "Claude 에이전트: ${claude_agent_count}개"
  echo "외부 CLI: ${cli_call_count}개"
  echo ""
  echo "### 단계별 비용"
  echo -e "$BREAKDOWN"
  echo "### 합계"
  echo "예상 토큰: ~${TOTAL_TOKENS}"
  echo "예상 비용: $(format_cost "$TOTAL_COST_VAL")"
  if [ "$(echo "$CACHE_DISCOUNT > 0" | bc 2>/dev/null)" = "1" ]; then
    echo "프롬프트 캐시 할인: $(awk -v d="$CACHE_DISCOUNT" 'BEGIN{printf "%d", d*100}')% (입력 토큰)"
  fi
  echo "예상 시간: ~${EST_MINUTES}분"
else
  echo "## Cost & Time Estimate"
  echo ""
  echo "Intensity: ${INTENSITY}"
  echo "Pipeline: ${PIPELINE}"
  echo "Input: ~${TOTAL_INPUT_LINES} lines"
  echo "Claude Agents: ${claude_agent_count}"
  echo "External CLIs: ${cli_call_count}"
  echo ""
  echo "### Per-Phase Breakdown"
  echo -e "$BREAKDOWN"
  echo "### Total"
  echo "Est. Tokens: ~${TOTAL_TOKENS}"
  echo "Est. Cost: $(format_cost "$TOTAL_COST_VAL")"
  if [ "$(echo "$CACHE_DISCOUNT > 0" | bc 2>/dev/null)" = "1" ]; then
    echo "Prompt Cache Discount: $(awk -v d="$CACHE_DISCOUNT" 'BEGIN{printf "%d", d*100}')% (input tokens)"
  fi
  echo "Est. Time: ~${EST_MINUTES} min"
fi
