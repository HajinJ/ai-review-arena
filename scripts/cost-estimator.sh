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
CLAUDE_INPUT_PRICE="3.00"
CLAUDE_OUTPUT_PRICE="15.00"
CODEX_INPUT_PRICE="2.50"
CODEX_OUTPUT_PRICE="10.00"
GEMINI_INPUT_PRICE="1.25"
GEMINI_OUTPUT_PRICE="10.00"

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

  awk -v it="$input_tokens" -v ot="$output_tokens" \
      -v ip="$input_price" -v op="$output_price" \
      'BEGIN { printf "%.4f", (it/1000000)*ip + (ot/1000000)*op }'
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

declare -A PHASE_INPUT PHASE_OUTPUT PHASE_LABEL_EN PHASE_LABEL_KO

if [ "$PIPELINE" = "code" ]; then
  # Phase 0.1: Intensity Decision (4 agents debate)
  PHASE_INPUT[intensity]=6000;   PHASE_OUTPUT[intensity]=4000
  PHASE_LABEL_EN[intensity]="Intensity Decision (4 agents)";  PHASE_LABEL_KO[intensity]="강도 결정 (4 에이전트)"

  # Phase 0.2: Cost Estimation
  PHASE_INPUT[cost]=2000;        PHASE_OUTPUT[cost]=1000
  PHASE_LABEL_EN[cost]="Cost Estimation";                     PHASE_LABEL_KO[cost]="비용 추정"

  # Phase 0.5: Codebase Analysis
  PHASE_INPUT[codebase]=5000;    PHASE_OUTPUT[codebase]=3000
  PHASE_LABEL_EN[codebase]="Codebase Analysis";               PHASE_LABEL_KO[codebase]="코드베이스 분석"

  # Phase 1: Stack Detection
  PHASE_INPUT[stack]=2000;       PHASE_OUTPUT[stack]=1000
  PHASE_LABEL_EN[stack]="Stack Detection";                    PHASE_LABEL_KO[stack]="스택 감지"

  # Phase 2: Research
  PHASE_INPUT[research]=10000;   PHASE_OUTPUT[research]=5000
  PHASE_LABEL_EN[research]="Pre-Implementation Research";     PHASE_LABEL_KO[research]="사전 리서치"

  # Phase 2 Research Direction Debate
  PHASE_INPUT[research_debate]=8000;  PHASE_OUTPUT[research_debate]=4000
  PHASE_LABEL_EN[research_debate]="Research Direction Debate"; PHASE_LABEL_KO[research_debate]="리서치 방향 토론"

  # Phase 3: Compliance
  PHASE_INPUT[compliance]=8000;  PHASE_OUTPUT[compliance]=4000
  PHASE_LABEL_EN[compliance]="Compliance Detection";          PHASE_LABEL_KO[compliance]="컴플라이언스 감지"

  # Phase 3 Compliance Scope Debate
  PHASE_INPUT[compliance_debate]=6000; PHASE_OUTPUT[compliance_debate]=3000
  PHASE_LABEL_EN[compliance_debate]="Compliance Scope Debate"; PHASE_LABEL_KO[compliance_debate]="컴플라이언스 범위 토론"

  # Phase 4: Model Benchmarking
  PHASE_INPUT[benchmark]=25000;  PHASE_OUTPUT[benchmark]=15000
  PHASE_LABEL_EN[benchmark]="Model Benchmarking";             PHASE_LABEL_KO[benchmark]="모델 벤치마킹"

  # Phase 5: Figma Analysis
  PHASE_INPUT[figma]=15000;      PHASE_OUTPUT[figma]=5000
  PHASE_LABEL_EN[figma]="Figma Analysis";                     PHASE_LABEL_KO[figma]="Figma 분석"

  # Phase 5.5: Implementation Strategy Debate
  PHASE_INPUT[strategy]=15000;   PHASE_OUTPUT[strategy]=10000
  PHASE_LABEL_EN[strategy]="Strategy Debate (4 agents)";      PHASE_LABEL_KO[strategy]="전략 토론 (4 에이전트)"

  # Phase 6: Review per Claude agent
  PHASE_INPUT[review_agent]=8000; PHASE_OUTPUT[review_agent]=4000
  PHASE_LABEL_EN[review_agent]="Review (per Claude agent)";   PHASE_LABEL_KO[review_agent]="리뷰 (Claude 에이전트당)"

  # Phase 6: External CLI per call
  PHASE_INPUT[review_cli]=6000;  PHASE_OUTPUT[review_cli]=2000
  PHASE_LABEL_EN[review_cli]="Review (per external CLI)";     PHASE_LABEL_KO[review_cli]="리뷰 (외부 CLI당)"

  # Phase 6: Debate Rounds 2+3
  PHASE_INPUT[debate]=40000;     PHASE_OUTPUT[debate]=20000
  PHASE_LABEL_EN[debate]="Adversarial Debate (rounds 2-3)";   PHASE_LABEL_KO[debate]="적대적 토론 (라운드 2-3)"

  # Phase 6.5: Auto-Fix
  PHASE_INPUT[autofix]=6000;     PHASE_OUTPUT[autofix]=4000
  PHASE_LABEL_EN[autofix]="Auto-Fix Loop";                    PHASE_LABEL_KO[autofix]="자동 수정"

  # Phase 7: Report
  PHASE_INPUT[report]=3000;      PHASE_OUTPUT[report]=2000
  PHASE_LABEL_EN[report]="Final Report";                      PHASE_LABEL_KO[report]="최종 리포트"

else
  # Business pipeline phases
  PHASE_INPUT[intensity]=6000;   PHASE_OUTPUT[intensity]=4000
  PHASE_LABEL_EN[intensity]="Intensity Decision (4 agents)";  PHASE_LABEL_KO[intensity]="강도 결정 (4 에이전트)"

  PHASE_INPUT[cost]=2000;        PHASE_OUTPUT[cost]=1000
  PHASE_LABEL_EN[cost]="Cost Estimation";                     PHASE_LABEL_KO[cost]="비용 추정"

  PHASE_INPUT[context]=7000;     PHASE_OUTPUT[context]=3000
  PHASE_LABEL_EN[context]="Business Context Analysis";        PHASE_LABEL_KO[context]="비즈니스 컨텍스트 분석"

  PHASE_INPUT[market]=10000;     PHASE_OUTPUT[market]=5000
  PHASE_LABEL_EN[market]="Market Research";                   PHASE_LABEL_KO[market]="시장 리서치"

  PHASE_INPUT[research]=12000;   PHASE_OUTPUT[research]=8000
  PHASE_LABEL_EN[research]="Best Practices Research";         PHASE_LABEL_KO[research]="베스트 프랙티스 리서치"

  PHASE_INPUT[research_debate]=8000; PHASE_OUTPUT[research_debate]=4000
  PHASE_LABEL_EN[research_debate]="Research Direction Debate"; PHASE_LABEL_KO[research_debate]="리서치 방향 토론"

  PHASE_INPUT[accuracy]=12000;   PHASE_OUTPUT[accuracy]=6000
  PHASE_LABEL_EN[accuracy]="Accuracy Audit";                  PHASE_LABEL_KO[accuracy]="정확성 감사"

  PHASE_INPUT[accuracy_debate]=6000; PHASE_OUTPUT[accuracy_debate]=3000
  PHASE_LABEL_EN[accuracy_debate]="Accuracy Scope Debate";    PHASE_LABEL_KO[accuracy_debate]="정확성 범위 토론"

  PHASE_INPUT[benchmark]=25000;  PHASE_OUTPUT[benchmark]=15000
  PHASE_LABEL_EN[benchmark]="Model Benchmarking";             PHASE_LABEL_KO[benchmark]="모델 벤치마킹"

  PHASE_INPUT[strategy]=15000;   PHASE_OUTPUT[strategy]=10000
  PHASE_LABEL_EN[strategy]="Content Strategy Debate";         PHASE_LABEL_KO[strategy]="콘텐츠 전략 토론"

  PHASE_INPUT[review_agent]=10000; PHASE_OUTPUT[review_agent]=5000
  PHASE_LABEL_EN[review_agent]="Review (per business agent)"; PHASE_LABEL_KO[review_agent]="리뷰 (비즈니스 에이전트당)"

  PHASE_INPUT[review_cli]=6000;  PHASE_OUTPUT[review_cli]=2000
  PHASE_LABEL_EN[review_cli]="Review (per external CLI)";     PHASE_LABEL_KO[review_cli]="리뷰 (외부 CLI당)"

  PHASE_INPUT[debate]=35000;     PHASE_OUTPUT[debate]=15000
  PHASE_LABEL_EN[debate]="Business Review Debate";            PHASE_LABEL_KO[debate]="비즈니스 리뷰 토론"

  PHASE_INPUT[autofix]=10000;    PHASE_OUTPUT[autofix]=5000
  PHASE_LABEL_EN[autofix]="Auto-Revision";                    PHASE_LABEL_KO[autofix]="자동 수정"

  PHASE_INPUT[report]=5000;      PHASE_OUTPUT[report]=3000
  PHASE_LABEL_EN[report]="Final Report";                      PHASE_LABEL_KO[report]="최종 리포트"
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
  input_t="${PHASE_INPUT[$phase]:-0}"
  output_t="${PHASE_OUTPUT[$phase]:-0}"

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
    label="${PHASE_LABEL_KO[$phase]:-$phase}"
  else
    label="${PHASE_LABEL_EN[$phase]:-$phase}"
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
    '{
      intensity: $intensity,
      pipeline: $pipeline,
      input_lines: $lines,
      claude_agents: $claude_agents,
      external_cli_calls: $cli_calls,
      total_tokens: $total_tokens,
      total_cost_usd: ($total_cost | tonumber),
      est_minutes: $est_minutes
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
  echo "Est. Time: ~${EST_MINUTES} min"
fi
