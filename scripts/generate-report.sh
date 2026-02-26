#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Report Generator
#
# Usage: generate-report.sh <consensus_json_file> <config_file>
#
# Generates a formatted markdown report from consensus/aggregated findings.
# Supports both Korean and English output based on config.
#
# Input: JSON file with either:
#   - {accepted: [...], rejected: [...], disputed: [...]}  (post-debate)
#   - [...] (plain findings array, pre-debate)
#
# Output: Markdown report to stdout.
# =============================================================================

set -uo pipefail

# --- Arguments ---
CONSENSUS_FILE="${1:?Usage: generate-report.sh <consensus_json_file> <config_file>}"
CONFIG_FILE="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Dependencies ---
if ! command -v jq &>/dev/null; then
  echo "Error: jq not found"
  exit 1
fi

# --- Read config ---
OUTPUT_LANG="ko"
SHOW_COST=true
SHOW_MODELS=true
SHOW_CONFIDENCE=true
INTENSITY="standard"

if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
  OUTPUT_LANG=$(jq -r '.output.language // "ko"' "$CONFIG_FILE" 2>/dev/null)
  SHOW_COST=$(jq -r '.output.show_cost_estimate // true' "$CONFIG_FILE" 2>/dev/null)
  SHOW_MODELS=$(jq -r '.output.show_model_attribution // true' "$CONFIG_FILE" 2>/dev/null)
  SHOW_CONFIDENCE=$(jq -r '.output.show_confidence_scores // true' "$CONFIG_FILE" 2>/dev/null)
  INTENSITY=$(jq -r '.review.intensity // "standard"' "$CONFIG_FILE" 2>/dev/null)
fi

# --- Read input ---
INPUT_JSON=""
if [ -f "$CONSENSUS_FILE" ]; then
  INPUT_JSON=$(cat "$CONSENSUS_FILE")
else
  # Might be a process substitution or stdin redirect
  INPUT_JSON=$(cat "$CONSENSUS_FILE" 2>/dev/null || echo "")
fi

if [ -z "$INPUT_JSON" ] || [ "$INPUT_JSON" = "null" ]; then
  echo "LGTM"
  exit 0
fi

# --- Detect input format ---
# Check if input is consensus format {accepted, rejected, disputed} or plain array
IS_CONSENSUS=$(echo "$INPUT_JSON" | jq 'has("accepted")' 2>/dev/null || echo "false")

ACCEPTED="[]"
REJECTED="[]"
DISPUTED="[]"
ALL_FINDINGS="[]"

if [ "$IS_CONSENSUS" = "true" ]; then
  ACCEPTED=$(echo "$INPUT_JSON" | jq '.accepted // []' 2>/dev/null)
  REJECTED=$(echo "$INPUT_JSON" | jq '.rejected // []' 2>/dev/null)
  DISPUTED=$(echo "$INPUT_JSON" | jq '.disputed // []' 2>/dev/null)
  ALL_FINDINGS=$(echo "$INPUT_JSON" | jq '[.accepted[], .disputed[]]' 2>/dev/null)
else
  # Plain array: treat all as accepted
  ALL_FINDINGS="$INPUT_JSON"
  ACCEPTED="$INPUT_JSON"
fi

# --- Counts ---
ACCEPTED_COUNT=$(echo "$ACCEPTED" | jq 'length' 2>/dev/null || echo "0")
REJECTED_COUNT=$(echo "$REJECTED" | jq 'length' 2>/dev/null || echo "0")
DISPUTED_COUNT=$(echo "$DISPUTED" | jq 'length' 2>/dev/null || echo "0")
TOTAL_FINDINGS=$((ACCEPTED_COUNT + DISPUTED_COUNT))

if [ "$TOTAL_FINDINGS" -eq 0 ]; then
  echo "LGTM"
  exit 0
fi

# --- Count by severity ---
count_severity() {
  local json_array="$1"
  local severity="$2"
  echo "$json_array" | jq --arg sev "$severity" '[.[] | select(.severity == $sev)] | length' 2>/dev/null || echo "0"
}

CRITICAL_COUNT=$(count_severity "$ALL_FINDINGS" "critical")
HIGH_COUNT=$(count_severity "$ALL_FINDINGS" "high")
MEDIUM_COUNT=$(count_severity "$ALL_FINDINGS" "medium")
LOW_COUNT=$(count_severity "$ALL_FINDINGS" "low")

# --- Collect models used ---
MODELS_USED=$(echo "$ALL_FINDINGS" | jq -r '[.[].models[]?] | unique | join(", ")' 2>/dev/null || echo "unknown")
FILE_COUNT=$(echo "$ALL_FINDINGS" | jq -r '[.[].file] | unique | length' 2>/dev/null || echo "0")

# --- Focus areas ---
FOCUS_AREAS=""
if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
  FOCUS_AREAS=$(jq -r '.review.focus_areas // [] | join(", ")' "$CONFIG_FILE" 2>/dev/null)
fi

# =============================================================================
# Localization Labels
# =============================================================================

if [ "$OUTPUT_LANG" = "ko" ]; then
  L_TITLE="## AI Review Arena Report"
  L_MODELS="Models"
  L_INTENSITY="Intensity"
  L_FOCUS="Focus"
  L_FILES="Files"
  L_FINDINGS="Findings"
  L_ACCEPTED="accepted"
  L_REJECTED="rejected"
  L_DISPUTED="disputed"
  L_CRITICAL="CRITICAL"
  L_HIGH="HIGH"
  L_MEDIUM="MEDIUM"
  L_LOW="LOW"
  L_DISPUTED_SECTION="DISPUTED (수동 검토 필요)"
  L_CONFIDENCE="신뢰도"
  L_MODELS_LABEL="모델"
  L_SUGGESTION="제안"
  L_CROSS_AGREE="교차 모델 합의"
  L_COST_TITLE="### 예상 비용"
  L_MANUAL_REVIEW="수동 검토가 필요합니다"
  L_FOR="찬성"
  L_AGAINST="반대"
  L_STALE="STALE"
  L_STALE_WARNING="리뷰 이후 코드가 변경됨 — findings 재검증 필요"
else
  L_TITLE="## AI Review Arena Report"
  L_MODELS="Models"
  L_INTENSITY="Intensity"
  L_FOCUS="Focus"
  L_FILES="Files"
  L_FINDINGS="Findings"
  L_ACCEPTED="accepted"
  L_REJECTED="rejected"
  L_DISPUTED="disputed"
  L_CRITICAL="CRITICAL"
  L_HIGH="HIGH"
  L_MEDIUM="MEDIUM"
  L_LOW="LOW"
  L_DISPUTED_SECTION="DISPUTED (manual review needed)"
  L_CONFIDENCE="Confidence"
  L_MODELS_LABEL="Models"
  L_SUGGESTION="Suggestion"
  L_CROSS_AGREE="Cross-model agreement"
  L_COST_TITLE="### Estimated Cost"
  L_MANUAL_REVIEW="Manual review required"
  L_FOR="For"
  L_AGAINST="Against"
  L_STALE="STALE"
  L_STALE_WARNING="Code changed after review — re-verify findings"
fi

# =============================================================================
# Generate Report
# =============================================================================

# Header
echo "$L_TITLE"
echo ""

# Stale review warning banner
HAS_STALE=$(echo "$ALL_FINDINGS" | jq '[.[] | select(.stale == true)] | length' 2>/dev/null || echo "0")
if [ "$HAS_STALE" -gt 0 ]; then
  echo "> **${L_STALE}**: ${L_STALE_WARNING}"
  echo ""
fi

echo "${L_MODELS}: ${MODELS_USED} | ${L_INTENSITY}: ${INTENSITY} | ${L_FOCUS}: ${FOCUS_AREAS:-all}"
echo "${L_FILES}: ${FILE_COUNT} | ${L_FINDINGS}: ${ACCEPTED_COUNT} ${L_ACCEPTED}, ${REJECTED_COUNT} ${L_REJECTED}, ${DISPUTED_COUNT} ${L_DISPUTED}"
echo ""

# --- Helper: render findings list ---
render_findings() {
  local findings_json="$1"
  local count
  count=$(echo "$findings_json" | jq 'length' 2>/dev/null || echo "0")

  if [ "$count" -eq 0 ]; then
    return
  fi

  # Batch-extract all finding fields in a single jq call (was 8 calls per finding)
  local rendered
  rendered=$(echo "$findings_json" | jq -r --arg show_conf "$SHOW_CONFIDENCE" --arg show_mod "$SHOW_MODELS" \
    --arg l_conf "$L_CONFIDENCE" --arg l_mod "$L_MODELS_LABEL" --arg l_sug "$L_SUGGESTION" --arg l_cross "$L_CROSS_AGREE" '
    to_entries[] |
    .key as $idx |
    .value |
    (.file // "?") as $file |
    (.line // "?") as $line |
    (.title // "Untitled") as $title |
    (.description // "") as $desc |
    (.suggestion // "") as $sug |
    (.confidence // "?") as $conf |
    ((.models // []) | join(", ")) as $models |
    (.cross_model_agreement // false) as $cross |
    ($file | split("/") | last) as $short_file |
    "\($idx + 1). **\($short_file):\($line)** - \($title)" +
    (if $show_conf == "true" then
      "\n   \($l_conf): \($conf)%" + (if $cross then " | \($l_cross)" else "" end)
    else "" end) +
    (if $show_mod == "true" and ($models | length) > 0 then "\n   \($l_mod): \($models)" else "" end) +
    (if $desc != "" then "\n   \($desc)" else "" end) +
    (if $sug != "" and $sug != "null" then "\n   \($l_sug): \($sug)" else "" end) +
    "\n"
  ' 2>/dev/null)

  if [ -n "$rendered" ]; then
    echo "$rendered"
  fi
}

# --- Render sections by severity ---
render_severity_section() {
  local severity="$1"
  local label="$2"
  local findings
  findings=$(echo "$ACCEPTED" | jq --arg sev "$severity" '[.[] | select(.severity == $sev)]' 2>/dev/null)
  local count
  count=$(echo "$findings" | jq 'length' 2>/dev/null || echo "0")

  if [ "$count" -gt 0 ]; then
    echo "### ${label} (${count})"
    echo ""
    render_findings "$findings"
  fi
}

# Render accepted findings by severity
render_severity_section "critical" "$L_CRITICAL"
render_severity_section "high" "$L_HIGH"
render_severity_section "medium" "$L_MEDIUM"
render_severity_section "low" "$L_LOW"

# --- Render disputed section ---
if [ "$DISPUTED_COUNT" -gt 0 ]; then
  echo "### ${L_DISPUTED_SECTION} (${DISPUTED_COUNT})"
  echo ""

  i=0
  while [ "$i" -lt "$DISPUTED_COUNT" ]; do
    finding=$(echo "$DISPUTED" | jq ".[$i]" 2>/dev/null)

    file=$(echo "$finding" | jq -r '.file // "?"' 2>/dev/null)
    line=$(echo "$finding" | jq -r '.line // "?"' 2>/dev/null)
    title=$(echo "$finding" | jq -r '.title // "Untitled"' 2>/dev/null)
    desc=$(echo "$finding" | jq -r '.description // ""' 2>/dev/null)
    confidence=$(echo "$finding" | jq -r '.confidence // "?"' 2>/dev/null)
    models=$(echo "$finding" | jq -r '(.models // []) | join(", ")' 2>/dev/null)
    challenger=$(echo "$finding" | jq -r '.challenger // ""' 2>/dev/null)
    debate_status=$(echo "$finding" | jq -r '.debate_status // ""' 2>/dev/null)

    short_file=$(basename "$file" 2>/dev/null || echo "$file")

    echo "$((i + 1)). **${short_file}:${line}** - ${title}"
    echo "   ${L_CONFIDENCE}: ${confidence}% | ${L_MANUAL_REVIEW}"

    if [ -n "$models" ]; then
      echo "   ${L_MODELS_LABEL}: ${models}"
    fi

    if [ -n "$desc" ]; then
      echo "   ${desc}"
    fi

    if [ -n "$challenger" ] && [ "$challenger" != "null" ]; then
      echo "   Challenger: ${challenger} (${debate_status})"
    fi

    echo ""
    i=$((i + 1))
  done
fi

# =============================================================================
# Cost Estimate
# =============================================================================

if [ "$SHOW_COST" = "true" ] && [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
  COST_ESTIMATE=$("$SCRIPT_DIR/cost-estimator.sh" "$CONFIG_FILE" 2>/dev/null) || true
  if [ -n "$COST_ESTIMATE" ]; then
    echo "$L_COST_TITLE"
    echo "$COST_ESTIMATE"
    echo ""
  fi
fi
