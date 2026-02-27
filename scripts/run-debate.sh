#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Multi-Model Debate Engine
#
# Usage: run-debate.sh <findings_json_file> <config_file> <session_dir>
#
# Implements adversarial debate between AI models:
#   1. Identifies challengeable findings (single-model or low confidence)
#   2. Sends challenges to different models
#   3. Applies confidence adjustments
#   4. Runs consensus algorithm
#   5. Outputs final categorized results
#
# Output: JSON with {accepted, rejected, disputed} arrays
# =============================================================================

set -uo pipefail

# --- Arguments ---
FINDINGS_FILE="${1:?Usage: run-debate.sh <findings_json> <config_file> <session_dir> [code_context_json]}"
CONFIG_FILE="${2:?Usage: run-debate.sh <findings_json> <config_file> <session_dir> [code_context_json]}"
SESSION_DIR="${3:?Usage: run-debate.sh <findings_json> <config_file> <session_dir> [code_context_json]}"
CODE_CONTEXT="${4:-}"  # Optional 4th arg: JSON string with code context for WebSocket debate

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/utils.sh"

# Fallback level tracking for external CLI failures
DEBATE_FALLBACK_LEVEL=0

# --- Dependencies ---
if ! command -v jq &>/dev/null; then
  echo '{"accepted":[],"rejected":[],"disputed":[],"error":"jq not found"}'
  exit 0
fi

# --- Read config (batched into single jq call) ---
_DEBATE_CFG=$(jq -r '[
  (.debate.enabled // false),
  (.debate.max_rounds // 2),
  (.debate.consensus_threshold // 80),
  (.debate.challenge_threshold // 60),
  (.timeout // 120)
] | @tsv' "$CONFIG_FILE") || _DEBATE_CFG=""

if [ -n "$_DEBATE_CFG" ]; then
  IFS=$'\t' read -r DEBATE_ENABLED MAX_ROUNDS CONSENSUS_THRESHOLD CHALLENGE_THRESHOLD TIMEOUT <<< "$_DEBATE_CFG"
else
  DEBATE_ENABLED="false"; MAX_ROUNDS=2; CONSENSUS_THRESHOLD=80; CHALLENGE_THRESHOLD=60; TIMEOUT=120
fi

# Safety cap: prevent runaway debate loops from bad config
if ! [[ "$MAX_ROUNDS" =~ ^[0-9]+$ ]] || [ "$MAX_ROUNDS" -gt 10 ]; then MAX_ROUNDS=2; fi

# --- Check if debate is enabled ---
if [ "$DEBATE_ENABLED" != "true" ] || [ "$MAX_ROUNDS" -le 0 ] 2>/dev/null; then
  # No debate: accept all findings as-is
  if [ -f "$FINDINGS_FILE" ]; then
    FINDINGS=$(cat "$FINDINGS_FILE")
  else
    FINDINGS="$FINDINGS_FILE"
  fi
  echo "$FINDINGS" | jq '{accepted: ., rejected: [], disputed: []}'
  exit 0
fi

# --- Read findings ---
FINDINGS=""
if [ -f "$FINDINGS_FILE" ]; then
  FINDINGS=$(cat "$FINDINGS_FILE")
else
  FINDINGS="$FINDINGS_FILE"
fi

if [ -z "$FINDINGS" ] || [ "$FINDINGS" = "null" ] || [ "$FINDINGS" = "[]" ]; then
  echo '{"accepted":[],"rejected":[],"disputed":[]}'
  exit 0
fi

# Validate JSON
if ! echo "$FINDINGS" | jq . &>/dev/null 2>&1; then
  echo '{"accepted":[],"rejected":[],"disputed":[],"error":"Invalid findings JSON"}'
  exit 0
fi

# --- WebSocket fast path ---
WS_ENABLED=$(jq -r '.websocket.enabled // false' "$CONFIG_FILE" || echo "false")

if [ "$WS_ENABLED" = "true" ] && command -v python3 &>/dev/null; then
  # Check if openai package is available
  if python3 -c "import openai" &>/dev/null 2>&1; then
    WS_SCRIPT="${PLUGIN_DIR}/scripts/openai-ws-debate.py"
    if [ -f "$WS_SCRIPT" ]; then
      # Build input JSON for WebSocket client (include code_context)
      # Validate CODE_CONTEXT is valid JSON; default to empty object
      _ws_code_ctx="null"
      if [ -n "$CODE_CONTEXT" ] && echo "$CODE_CONTEXT" | jq . &>/dev/null; then
        _ws_code_ctx="$CODE_CONTEXT"
      fi
      WS_INPUT=$(jq -n \
        --argjson findings "$FINDINGS" \
        --argjson code_context "$_ws_code_ctx" \
        --slurpfile config "$CONFIG_FILE" \
        '{ findings: $findings, code_context: ($code_context // {}), config: $config[0] }')

      WS_TIMEOUT=$(jq -r '.fallback.external_cli_debate_timeout_seconds // 300' "$CONFIG_FILE" || echo "300")
      if ! WS_RESULT=$(echo "$WS_INPUT" | arena_timeout "${WS_TIMEOUT}" python3 "$WS_SCRIPT" 2>&1); then
        log_warn "WebSocket debate failed: ${WS_RESULT:0:200}"
        WS_RESULT=""
        DEBATE_FALLBACK_LEVEL=$((DEBATE_FALLBACK_LEVEL > 4 ? DEBATE_FALLBACK_LEVEL : 4))
      fi

      if [ -n "$WS_RESULT" ] && echo "$WS_RESULT" | jq -e '.accepted' &>/dev/null 2>&1; then
        # WebSocket debate succeeded — output result and exit
        echo "$WS_RESULT"
        exit 0
      fi
      # WebSocket failed — fall through to standard debate
    fi
  fi
fi

# --- Check available models for challenging ---
has_codex=false
has_gemini=false
if command -v codex &>/dev/null; then
  codex_enabled=$(jq -r '.models.codex.enabled // false' "$CONFIG_FILE" 2>/dev/null)
  [ "$codex_enabled" = "true" ] && has_codex=true
fi
if command -v gemini &>/dev/null; then
  gemini_enabled=$(jq -r '.models.gemini.enabled // false' "$CONFIG_FILE" 2>/dev/null)
  [ "$gemini_enabled" = "true" ] && has_gemini=true
fi

# Need at least one model to challenge
if [ "$has_codex" != "true" ] && [ "$has_gemini" != "true" ]; then
  echo "$FINDINGS" | jq '{accepted: ., rejected: [], disputed: []}'
  exit 0
fi

# --- Initialize debate log ---
DEBATE_LOG="${SESSION_DIR}/debate-log.json"
echo '[]' > "$DEBATE_LOG"

# --- Helper: pick challenger model ---
pick_challenger() {
  local finding_model="$1"
  # Pick a different model than the one that made the finding
  if [ "$finding_model" = "codex" ] && [ "$has_gemini" = "true" ]; then
    echo "gemini"
  elif [ "$finding_model" = "gemini" ] && [ "$has_codex" = "true" ]; then
    echo "codex"
  elif [ "$has_codex" = "true" ]; then
    echo "codex"
  elif [ "$has_gemini" = "true" ]; then
    echo "gemini"
  else
    echo ""
  fi
}

# --- Helper: run challenge ---
run_challenge() {
  local challenger="$1"
  local finding_json="$2"
  local code_snippet="$3"

  # Batch-extract all finding fields in a single jq call
  local _challenge_fields
  _challenge_fields=$(echo "$finding_json" | jq -r '[
    (.file // "unknown"),
    (.line // 0),
    (.title // "unknown"),
    (.description // ""),
    (.severity // "medium"),
    (.models[0] // "unknown")
  ] | @tsv') || _challenge_fields=""

  local file_path line title description severity original_model
  IFS=$'\t' read -r file_path line title description severity original_model <<< "$_challenge_fields"

  # Build challenge prompt
  local challenge_prompt
  challenge_prompt=$(cat <<CHALLENGE_EOF
You are reviewing a code review finding made by another AI model. Evaluate whether this finding is valid.

ORIGINAL FINDING:
- Model: ${original_model}
- File: ${file_path}
- Line: ${line}
- Severity: ${severity}
- Title: ${title}
- Description: ${description}

CODE CONTEXT:
${code_snippet}

INSTRUCTIONS:
Analyze this finding critically. Consider:
1. Is the issue real or a false positive?
2. Is the severity appropriate?
3. Is there sufficient evidence in the code?

Respond with ONLY valid JSON (no markdown, no explanation outside JSON):
{
  "agree": true or false,
  "confidence_adjustment": -20 to +20 (how much to adjust the original confidence),
  "evidence": "Brief explanation of your assessment"
}
CHALLENGE_EOF
)

  local result=""
  if [ "$challenger" = "codex" ]; then
    local codex_model
    codex_model=$(jq -r '.models.codex.model_variant // ""' "$CONFIG_FILE" 2>/dev/null)
    if [ -n "$codex_model" ]; then
      if ! result=$(echo "$challenge_prompt" | arena_timeout "${TIMEOUT}" codex exec --full-auto -m "$codex_model" 2>&1); then
        log_warn "Codex challenge failed: ${result:0:200}"
        result=""
      fi
    else
      if ! result=$(echo "$challenge_prompt" | arena_timeout "${TIMEOUT}" codex exec --full-auto 2>&1); then
        log_warn "Codex challenge failed: ${result:0:200}"
        result=""
      fi
    fi
  elif [ "$challenger" = "gemini" ]; then
    local model_variant
    model_variant=$(jq -r '.models.gemini.model_variant // ""' "$CONFIG_FILE" 2>/dev/null)
    if [ -n "$model_variant" ]; then
      if ! result=$(arena_timeout "${TIMEOUT}" gemini --model "$model_variant" "$challenge_prompt" 2>&1); then
        log_warn "Gemini challenge failed: ${result:0:200}"
        result=""
      fi
    else
      if ! result=$(arena_timeout "${TIMEOUT}" gemini "$challenge_prompt" 2>&1); then
        log_warn "Gemini challenge failed: ${result:0:200}"
        result=""
      fi
    fi
  fi

  if [ -z "$result" ]; then
    # Track CLI failure for fallback level
    DEBATE_FALLBACK_LEVEL=4
    echo '{"agree":true,"confidence_adjustment":0,"evidence":"Challenger did not respond"}'
    return
  fi

  # Extract JSON from result (uses shared extract_json from utils.sh)
  local parsed=""
  parsed=$(extract_json "$result") || true

  if [ -n "$parsed" ]; then
    # Validate and normalize
    echo "$parsed" | jq '{
      agree: (.agree // true),
      confidence_adjustment: ((.confidence_adjustment // 0) | if . > 20 then 20 elif . < -20 then -20 else . end),
      evidence: (.evidence // "No evidence provided")
    }'
  else
    echo '{"agree":true,"confidence_adjustment":0,"evidence":"Failed to parse challenger response"}'
  fi
}

# --- Debate Rounds ---
CURRENT_FINDINGS="$FINDINGS"

for round in $(seq 1 "$MAX_ROUNDS"); do
  ROUND_LOG="[]"
  FINDINGS_COUNT=$(echo "$CURRENT_FINDINGS" | jq 'length' || echo "0")

  if [ "$FINDINGS_COUNT" -eq 0 ]; then
    break
  fi

  # Iterate through findings and challenge those with low confidence or single-model
  UPDATED_FINDINGS="$CURRENT_FINDINGS"
  idx=0

  while [ "$idx" -lt "$FINDINGS_COUNT" ]; do
    # Batch-extract all needed fields from finding in a single jq call
    _FINDING_FIELDS=$(echo "$CURRENT_FINDINGS" | jq -r --argjson i "$idx" '
      .[$i] | [
        ((.models // []) | length),
        (.confidence // 50 | floor),
        (.models[0] // "unknown"),
        (.file // ""),
        (.line // 0)
      ] | @tsv
    ') || _FINDING_FIELDS=""

    if [ -z "$_FINDING_FIELDS" ]; then
      idx=$((idx + 1))
      continue
    fi

    IFS=$'\t' read -r MODEL_COUNT CONFIDENCE FINDING_MODEL FILE_TO_READ LINE_NUM <<< "$_FINDING_FIELDS"
    FINDING=$(echo "$CURRENT_FINDINGS" | jq ".[$idx]")
    if [ -z "$FINDING" ] || [ "$FINDING" = "null" ]; then
      idx=$((idx + 1))
      continue
    fi

    # Ensure integer values for arithmetic (handles float from Python WebSocket path)
    CONFIDENCE=${CONFIDENCE%%.*}
    MODEL_COUNT=${MODEL_COUNT%%.*}

    is_challengeable=false
    if [ "$MODEL_COUNT" -le 1 ] || [ "$CONFIDENCE" -lt "$CHALLENGE_THRESHOLD" ]; then
      is_challengeable=true
    fi

    if [ "$is_challengeable" != "true" ]; then
      idx=$((idx + 1))
      continue
    fi

    # FINDING_MODEL already extracted above in batch
    CHALLENGER=$(pick_challenger "$FINDING_MODEL")

    if [ -z "$CHALLENGER" ]; then
      idx=$((idx + 1))
      continue
    fi

    # FILE_TO_READ and LINE_NUM already extracted above in batch
    CODE_SNIPPET=""

    if [ -n "$FILE_TO_READ" ] && [ -f "$FILE_TO_READ" ] && [ "$LINE_NUM" -gt 0 ]; then
      START_LINE=$((LINE_NUM - 5))
      [ "$START_LINE" -lt 1 ] && START_LINE=1
      END_LINE=$((LINE_NUM + 15))
      CODE_SNIPPET=$(sed -n "${START_LINE},${END_LINE}p" "$FILE_TO_READ" || true)
    fi

    if [ -z "$CODE_SNIPPET" ] && [ -n "$FILE_TO_READ" ] && [ -f "$FILE_TO_READ" ]; then
      CODE_SNIPPET=$(head -n 50 "$FILE_TO_READ" || true)
    fi

    # Run the challenge
    CHALLENGE_RESULT=$(run_challenge "$CHALLENGER" "$FINDING" "$CODE_SNIPPET")

    # Batch-extract challenge result fields in single jq call
    _CHAL_FIELDS=$(echo "$CHALLENGE_RESULT" | jq -r '[
      (if .agree then "true" else "false" end),
      (.confidence_adjustment // 0 | floor),
      (.evidence // "")
    ] | @tsv') || _CHAL_FIELDS=""
    IFS=$'\t' read -r AGREE CONF_ADJ EVIDENCE <<< "$_CHAL_FIELDS"
    AGREE="${AGREE:-true}"
    CONF_ADJ="${CONF_ADJ:-0}"
    CONF_ADJ=${CONF_ADJ%%.*}  # Ensure integer

    # Apply confidence adjustment (integer arithmetic safe)
    NEW_CONFIDENCE=$((CONFIDENCE + CONF_ADJ))
    [ "$NEW_CONFIDENCE" -gt 100 ] && NEW_CONFIDENCE=100
    [ "$NEW_CONFIDENCE" -lt 0 ] && NEW_CONFIDENCE=0

    # Normalize AGREE to valid JSON boolean for --argjson
    _agree_bool="true"
    [ "$AGREE" = "false" ] && _agree_bool="false"

    # Update finding
    UPDATED_FINDINGS=$(echo "$UPDATED_FINDINGS" | jq --argjson idx "$idx" --argjson conf "$NEW_CONFIDENCE" --arg challenger "$CHALLENGER" --argjson agree "$_agree_bool" '
      .[$idx].confidence = $conf |
      .[$idx].debate_status = (if $agree then "confirmed" else "challenged") |
      .[$idx].challenger = $challenger |
      .[$idx].models = (.[$idx].models + [$challenger] | unique)
    ' || echo "$UPDATED_FINDINGS")

    # Log debate entry
    DEBATE_ENTRY=$(jq -n \
      --argjson round "$round" \
      --argjson idx "$idx" \
      --arg finding_title "$(echo "$FINDING" | jq -r '.title // ""')" \
      --arg challenger "$CHALLENGER" \
      --argjson agree "$AGREE" \
      --argjson adj "$CONF_ADJ" \
      --arg evidence "$EVIDENCE" \
      --argjson old_conf "$CONFIDENCE" \
      --argjson new_conf "$NEW_CONFIDENCE" \
      '{
        round: $round,
        finding_index: $idx,
        finding_title: $finding_title,
        challenger: $challenger,
        agree: $agree,
        confidence_adjustment: $adj,
        evidence: $evidence,
        old_confidence: $old_conf,
        new_confidence: $new_conf
      }')

    ROUND_LOG=$(echo "$ROUND_LOG" | jq ". += [$DEBATE_ENTRY]" || echo "$ROUND_LOG")

    idx=$((idx + 1))
  done

  CURRENT_FINDINGS="$UPDATED_FINDINGS"

  # Append round log to debate log
  if [ -f "$DEBATE_LOG" ]; then
    EXISTING_LOG=$(cat "$DEBATE_LOG")
    echo "$EXISTING_LOG" | jq ". += $ROUND_LOG" > "$DEBATE_LOG" || true
  fi
done

# =============================================================================
# Consensus Algorithm
# =============================================================================

CONSENSUS_RESULT=$(echo "$CURRENT_FINDINGS" | jq --argjson threshold "$CONSENSUS_THRESHOLD" '
  def categorize:
    # 2+ models agree -> accepted (with confidence boost)
    if (.models | unique | length) >= 2 and (.debate_status // "none") != "challenged" then
      "accepted"
    # Single model with high confidence -> accepted
    elif (.confidence // 0) >= $threshold then
      "accepted"
    # Challenged and confidence dropped significantly -> rejected
    elif (.debate_status // "none") == "challenged" and (.confidence // 0) < ($threshold * 0.5) then
      "rejected"
    # Challenged but still has some confidence -> disputed
    elif (.debate_status // "none") == "challenged" then
      "disputed"
    # Low confidence, no cross-model support -> disputed
    elif (.confidence // 0) < ($threshold * 0.6) then
      "disputed"
    # Default: accepted if decent confidence
    elif (.confidence // 0) >= ($threshold * 0.7) then
      "accepted"
    else
      "disputed"
    end;

  {
    accepted: [.[] | select(categorize == "accepted")],
    rejected: [.[] | select(categorize == "rejected")],
    disputed: [.[] | select(categorize == "disputed")]
  }
')

# Include fallback_level if any degradation occurred
if [ "$DEBATE_FALLBACK_LEVEL" -gt 0 ]; then
  CONSENSUS_RESULT=$(echo "$CONSENSUS_RESULT" | jq --argjson fl "$DEBATE_FALLBACK_LEVEL" '. + {fallback_level: $fl}')
fi

echo "$CONSENSUS_RESULT"
