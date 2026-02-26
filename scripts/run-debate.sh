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
FINDINGS_FILE="${1:?Usage: run-debate.sh <findings_json> <config_file> <session_dir>}"
CONFIG_FILE="${2:?Usage: run-debate.sh <findings_json> <config_file> <session_dir>}"
SESSION_DIR="${3:?Usage: run-debate.sh <findings_json> <config_file> <session_dir>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# --- Dependencies ---
if ! command -v jq &>/dev/null; then
  echo '{"accepted":[],"rejected":[],"disputed":[],"error":"jq not found"}'
  exit 0
fi

# --- Read config ---
DEBATE_ENABLED=$(jq -r '.debate.enabled // false' "$CONFIG_FILE" 2>/dev/null)
MAX_ROUNDS=$(jq -r '.debate.max_rounds // 2' "$CONFIG_FILE" 2>/dev/null)
CONSENSUS_THRESHOLD=$(jq -r '.debate.consensus_threshold // 80' "$CONFIG_FILE" 2>/dev/null)
CHALLENGE_THRESHOLD=$(jq -r '.debate.challenge_threshold // 60' "$CONFIG_FILE" 2>/dev/null)
TIMEOUT=$(jq -r '.timeout // 120' "$CONFIG_FILE" 2>/dev/null)

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
WS_ENABLED=$(jq -r '.websocket.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")

if [ "$WS_ENABLED" = "true" ] && command -v python3 &>/dev/null; then
  # Check if openai package is available
  if python3 -c "import openai" &>/dev/null 2>&1; then
    WS_SCRIPT="${PLUGIN_DIR}/scripts/openai-ws-debate.py"
    if [ -f "$WS_SCRIPT" ]; then
      # Build input JSON for WebSocket client
      WS_INPUT=$(jq -n \
        --argjson findings "$FINDINGS" \
        --slurpfile config "$CONFIG_FILE" \
        '{ findings: $findings, config: $config[0] }')

      WS_RESULT=$(echo "$WS_INPUT" | timeout 300s python3 "$WS_SCRIPT" 2>/dev/null) || true

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

  local file_path
  file_path=$(echo "$finding_json" | jq -r '.file // "unknown"')
  local line
  line=$(echo "$finding_json" | jq -r '.line // 0')
  local title
  title=$(echo "$finding_json" | jq -r '.title // "unknown"')
  local description
  description=$(echo "$finding_json" | jq -r '.description // ""')
  local severity
  severity=$(echo "$finding_json" | jq -r '.severity // "medium"')
  local original_model
  original_model=$(echo "$finding_json" | jq -r '.models[0] // "unknown"')

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
    codex_model=$(jq -r '.models.codex.model_variant // "gpt-5.3-codex-spark"' "$CONFIG_FILE" 2>/dev/null)
    result=$(echo "$challenge_prompt" | timeout "${TIMEOUT}s" codex exec --full-auto -m "$codex_model" 2>/dev/null) || true
  elif [ "$challenger" = "gemini" ]; then
    local model_variant
    model_variant=$(jq -r '.models.gemini.model_variant // "gemini-3-pro-preview"' "$CONFIG_FILE" 2>/dev/null)
    result=$(timeout "${TIMEOUT}s" gemini --model "$model_variant" "$challenge_prompt" 2>/dev/null) || true
  fi

  if [ -z "$result" ]; then
    echo '{"agree":true,"confidence_adjustment":0,"evidence":"Challenger did not respond"}'
    return
  fi

  # Try to extract JSON from result
  local parsed=""

  # Try direct parse
  if echo "$result" | jq . &>/dev/null 2>&1; then
    parsed="$result"
  else
    # Try extracting from code blocks
    parsed=$(echo "$result" | sed -n '/^```json/,/^```$/p' | sed '1d;$d' 2>/dev/null)
    if [ -z "$parsed" ] || ! echo "$parsed" | jq . &>/dev/null 2>&1; then
      parsed=$(echo "$result" | sed -n '/^```/,/^```$/p' | sed '1d;$d' 2>/dev/null)
    fi
    if [ -z "$parsed" ] || ! echo "$parsed" | jq . &>/dev/null 2>&1; then
      parsed=$(echo "$result" | sed -n '/^[[:space:]]*{/,/}[[:space:]]*$/p' 2>/dev/null)
    fi
  fi

  if [ -n "$parsed" ] && echo "$parsed" | jq . &>/dev/null 2>&1; then
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
  FINDINGS_COUNT=$(echo "$CURRENT_FINDINGS" | jq 'length' 2>/dev/null || echo "0")

  if [ "$FINDINGS_COUNT" -eq 0 ]; then
    break
  fi

  # Identify challengeable findings
  CHALLENGEABLE_INDICES=$(echo "$CURRENT_FINDINGS" | jq --argjson threshold "$CHALLENGE_THRESHOLD" '
    [range(length)] | map(select(
      . as $i |
      ($CURRENT_FINDINGS[$i] |
        ((.models | length) <= 1) or
        ((.confidence // 50) < $threshold)
      )
    ))
  ' --jsonargs 2>/dev/null || echo "[]")

  # Substitute $CURRENT_FINDINGS properly
  CHALLENGEABLE_INDICES=$(echo "$CURRENT_FINDINGS" | jq --argjson threshold "$CHALLENGE_THRESHOLD" '
    [range(length)] | [.[] | select(
      . as $i |
      (input[$i] |
        ((.models | length) <= 1) or
        ((.confidence // 50) < $threshold)
      )
    )]
  ' 2>/dev/null || echo "[]")

  # Simpler approach: iterate through findings
  UPDATED_FINDINGS="$CURRENT_FINDINGS"
  idx=0

  while [ "$idx" -lt "$FINDINGS_COUNT" ]; do
    FINDING=$(echo "$CURRENT_FINDINGS" | jq ".[$idx]" 2>/dev/null)
    if [ -z "$FINDING" ] || [ "$FINDING" = "null" ]; then
      idx=$((idx + 1))
      continue
    fi

    # Check if challengeable
    MODEL_COUNT=$(echo "$FINDING" | jq '(.models // []) | length' 2>/dev/null || echo "1")
    CONFIDENCE=$(echo "$FINDING" | jq '.confidence // 50' 2>/dev/null || echo "50")

    is_challengeable=false
    if [ "$MODEL_COUNT" -le 1 ] || [ "$CONFIDENCE" -lt "$CHALLENGE_THRESHOLD" ]; then
      is_challengeable=true
    fi

    if [ "$is_challengeable" != "true" ]; then
      idx=$((idx + 1))
      continue
    fi

    # Get the finding's model
    FINDING_MODEL=$(echo "$FINDING" | jq -r '.models[0] // "unknown"' 2>/dev/null)
    CHALLENGER=$(pick_challenger "$FINDING_MODEL")

    if [ -z "$CHALLENGER" ]; then
      idx=$((idx + 1))
      continue
    fi

    # Read code snippet from the actual file
    FILE_TO_READ=$(echo "$FINDING" | jq -r '.file // ""' 2>/dev/null)
    LINE_NUM=$(echo "$FINDING" | jq -r '.line // 0' 2>/dev/null)
    CODE_SNIPPET=""

    if [ -n "$FILE_TO_READ" ] && [ -f "$FILE_TO_READ" ] && [ "$LINE_NUM" -gt 0 ]; then
      START_LINE=$((LINE_NUM - 5))
      [ "$START_LINE" -lt 1 ] && START_LINE=1
      END_LINE=$((LINE_NUM + 15))
      CODE_SNIPPET=$(sed -n "${START_LINE},${END_LINE}p" "$FILE_TO_READ" 2>/dev/null || true)
    fi

    if [ -z "$CODE_SNIPPET" ] && [ -n "$FILE_TO_READ" ] && [ -f "$FILE_TO_READ" ]; then
      CODE_SNIPPET=$(head -n 50 "$FILE_TO_READ" 2>/dev/null || true)
    fi

    # Run the challenge
    CHALLENGE_RESULT=$(run_challenge "$CHALLENGER" "$FINDING" "$CODE_SNIPPET")

    AGREE=$(echo "$CHALLENGE_RESULT" | jq -r '.agree // true' 2>/dev/null)
    CONF_ADJ=$(echo "$CHALLENGE_RESULT" | jq -r '.confidence_adjustment // 0' 2>/dev/null)
    EVIDENCE=$(echo "$CHALLENGE_RESULT" | jq -r '.evidence // ""' 2>/dev/null)

    # Apply confidence adjustment
    NEW_CONFIDENCE=$((CONFIDENCE + CONF_ADJ))
    [ "$NEW_CONFIDENCE" -gt 100 ] && NEW_CONFIDENCE=100
    [ "$NEW_CONFIDENCE" -lt 0 ] && NEW_CONFIDENCE=0

    # Update finding
    UPDATED_FINDINGS=$(echo "$UPDATED_FINDINGS" | jq --argjson idx "$idx" --argjson conf "$NEW_CONFIDENCE" --arg challenger "$CHALLENGER" --argjson agree "$AGREE" '
      .[$idx].confidence = $conf |
      .[$idx].debate_status = (if $agree then "confirmed" else "challenged") |
      .[$idx].challenger = $challenger |
      .[$idx].models = (.[$idx].models + [$challenger] | unique)
    ' 2>/dev/null || echo "$UPDATED_FINDINGS")

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

    ROUND_LOG=$(echo "$ROUND_LOG" | jq ". += [$DEBATE_ENTRY]" 2>/dev/null || echo "$ROUND_LOG")

    idx=$((idx + 1))
  done

  CURRENT_FINDINGS="$UPDATED_FINDINGS"

  # Append round log to debate log
  if [ -f "$DEBATE_LOG" ]; then
    EXISTING_LOG=$(cat "$DEBATE_LOG")
    echo "$EXISTING_LOG" | jq ". += $ROUND_LOG" > "$DEBATE_LOG" 2>/dev/null || true
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

echo "$CONSENSUS_RESULT"
