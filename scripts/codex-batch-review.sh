#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Codex CSV Batch Review
#
# Uses Codex spawn_agents_on_csv to review multiple files in parallel.
# Each file gets its own worker subagent with the specified review role.
#
# Usage:
#   ./codex-batch-review.sh <role> <config_file> [file1 file2 ...]
#   echo "file1\nfile2" | ./codex-batch-review.sh <role> <config_file> --stdin
#
# Arguments:
#   role        - Review role: security|bugs|performance|architecture|testing
#   config_file - Path to JSON config
#   files       - Files to review (positional args or --stdin for stdin)
#
# Outputs valid JSON array of review results to stdout.
# =============================================================================

set -euo pipefail

# --- Arguments ---
ROLE="${1:?Usage: codex-batch-review.sh <role> <config_file> [files... | --stdin]}"
CONFIG_FILE="${2:?Usage: codex-batch-review.sh <role> <config_file> [files... | --stdin]}"
shift 2

# --- Resolve paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/utils.sh"

# --- Validate role ---
case "$ROLE" in
  security|bugs|performance|architecture|testing) ;;
  *)
    echo "{\"error\":\"Invalid role: $ROLE. Must be one of: security, bugs, performance, architecture, testing\",\"results\":[]}"
    exit 1
    ;;
esac

# --- Map role to agent name ---
_role_to_agent_name() {
  case "$1" in
    security)      echo "security_reviewer" ;;
    bugs)          echo "bug_detector" ;;
    performance)   echo "performance_reviewer" ;;
    architecture)  echo "architecture_reviewer" ;;
    testing)       echo "test_coverage_reviewer" ;;
    *)             echo "" ;;
  esac
}

_role_to_agent_file() {
  case "$1" in
    security)      echo "security-reviewer" ;;
    bugs)          echo "bug-detector" ;;
    performance)   echo "performance-reviewer" ;;
    architecture)  echo "architecture-reviewer" ;;
    testing)       echo "test-coverage-reviewer" ;;
    *)             echo "" ;;
  esac
}
AGENT_NAME="$(_role_to_agent_name "$ROLE")"

# --- Check dependencies ---
if ! command -v codex &>/dev/null; then
  echo "{\"error\":\"codex CLI not found. Install: npm install -g @openai/codex\",\"results\":[]}"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "{\"error\":\"jq not found. Install: brew install jq\",\"results\":[]}"
  exit 1
fi

# --- Collect files ---
FILES=()
if [ "${1:-}" = "--stdin" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && FILES+=("$line")
  done
else
  FILES=("$@")
fi

if [ ${#FILES[@]} -eq 0 ]; then
  echo "{\"error\":\"No files provided for batch review\",\"results\":[]}"
  exit 1
fi

# --- Read config ---
TIMEOUT=300
MAX_CONCURRENCY=6
CODEX_MODEL=""
if [ -f "$CONFIG_FILE" ]; then
  cfg_timeout=$(jq -r '.models.codex.multi_agent.job_max_runtime_seconds // .fallback.external_cli_timeout_seconds // 300' "$CONFIG_FILE" || true)
  [ -n "$cfg_timeout" ] && TIMEOUT="$cfg_timeout"

  cfg_concurrency=$(jq -r '.models.codex.multi_agent.max_threads // 6' "$CONFIG_FILE" || true)
  [ -n "$cfg_concurrency" ] && MAX_CONCURRENCY="$cfg_concurrency"

  cfg_model=$(jq -r '.codex.model_variant // .models.codex.model_variant // empty' "$CONFIG_FILE" || true)
  [ -n "$cfg_model" ] && CODEX_MODEL="$cfg_model"
fi

# --- Check if native subagent CSV mode is available ---
NATIVE_CSV=false
if codex --help 2>&1 | grep -q "spawn_agents_on_csv" 2>/dev/null; then
  NATIVE_CSV=true
fi

# --- Check if .codex/agents/ exists with our agent ---
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PLUGIN_DIR")
CODEX_AGENT_FILE="${PROJECT_ROOT}/.codex/agents/$(_role_to_agent_file "$ROLE").toml"

# --- Generate CSV ---
CSV_FILE=$(mktemp "${TMPDIR:-/tmp}/arena-batch-XXXXXX") && mv "$CSV_FILE" "${CSV_FILE}.csv" && CSV_FILE="${CSV_FILE}.csv"
OUTPUT_CSV=$(mktemp "${TMPDIR:-/tmp}/arena-batch-out-XXXXXX") && mv "$OUTPUT_CSV" "${OUTPUT_CSV}.csv" && OUTPUT_CSV="${OUTPUT_CSV}.csv"
echo "path,role,agent" > "$CSV_FILE"
for file in "${FILES[@]}"; do
  echo "${file},${ROLE},${AGENT_NAME}" >> "$CSV_FILE"
done

# --- Execute batch review ---
if [ "$NATIVE_CSV" = "true" ]; then
  # Native Codex spawn_agents_on_csv path
  log_stderr "codex-batch" "Using native spawn_agents_on_csv with ${#FILES[@]} files"

  CODEX_MODEL_ARGS=""
  [ -n "$CODEX_MODEL" ] && CODEX_MODEL_ARGS="-m $CODEX_MODEL"

  INSTRUCTION="Review the file at {path} for {role} issues. Use the {agent} agent persona. Return JSON with fields: path, severity (critical|high|medium|low), confidence (0-100), findings array, and summary. Call report_agent_job_result with your findings JSON."

  codex exec --full-auto ${CODEX_MODEL_ARGS} \
    --tool spawn_agents_on_csv \
    --csv_path "$CSV_FILE" \
    --id_column "path" \
    --instruction "$INSTRUCTION" \
    --output_csv_path "$OUTPUT_CSV" \
    --max_concurrency "$MAX_CONCURRENCY" \
    --max_runtime_seconds "$TIMEOUT" 2>/dev/null || {
      log_stderr "codex-batch" "Native CSV mode failed, falling back to parallel single reviews"
      NATIVE_CSV=false
    }
fi

if [ "$NATIVE_CSV" = "false" ]; then
  # Fallback: parallel single-agent reviews
  log_stderr "codex-batch" "Using parallel single reviews for ${#FILES[@]} files (max $MAX_CONCURRENCY concurrent)"

  RESULTS_DIR=$(mktemp -d)
  PIDS=()
  ACTIVE=0

  for file in "${FILES[@]}"; do
    # Throttle concurrency
    while [ $ACTIVE -ge "$MAX_CONCURRENCY" ]; do
      for i in "${!PIDS[@]}"; do
        if ! kill -0 "${PIDS[$i]}" 2>/dev/null; then
          unset 'PIDS[$i]'
          ACTIVE=$((ACTIVE - 1))
        fi
      done
      PIDS=("${PIDS[@]}")
      [ $ACTIVE -ge "$MAX_CONCURRENCY" ] && sleep 0.5
    done

    # Spawn review subprocesses
    RESULT_FILE="${RESULTS_DIR}/$(echo "$file" | tr '/' '_').json"
    (
      if [ -f "$file" ]; then
        cat "$file" | "$SCRIPT_DIR/codex-review.sh" "$file" "$CONFIG_FILE" "$ROLE" > "$RESULT_FILE" 2>/dev/null
      else
        echo "{\"model\":\"codex\",\"role\":\"$ROLE\",\"file\":\"$file\",\"error\":\"File not found\",\"findings\":[]}" > "$RESULT_FILE"
      fi
    ) &
    PIDS+=($!)
    ACTIVE=$((ACTIVE + 1))
  done

  # Wait for all
  for pid in "${PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  # Aggregate results
  echo "["
  FIRST=true
  for file in "${FILES[@]}"; do
    RESULT_FILE="${RESULTS_DIR}/$(echo "$file" | tr '/' '_').json"
    if [ -f "$RESULT_FILE" ] && jq . "$RESULT_FILE" &>/dev/null; then
      [ "$FIRST" = "true" ] && FIRST=false || echo ","
      cat "$RESULT_FILE"
    else
      [ "$FIRST" = "true" ] && FIRST=false || echo ","
      echo "{\"model\":\"codex\",\"role\":\"$ROLE\",\"file\":\"$file\",\"error\":\"Review failed\",\"findings\":[]}"
    fi
  done
  echo "]"

  rm -rf "$RESULTS_DIR"
  rm -f "$CSV_FILE" "$OUTPUT_CSV"
  exit 0
fi

# --- Parse native CSV output ---
if [ -f "$OUTPUT_CSV" ] && [ -s "$OUTPUT_CSV" ]; then
  # Convert CSV results to JSON array
  # Output CSV has columns: path, role, agent, job_id, item_id, status, last_error, result_json
  echo "["
  FIRST=true
  while IFS=, read -r path role agent job_id item_id status last_error result_json; do
    [ "$path" = "path" ] && continue  # skip header
    [ "$FIRST" = "true" ] && FIRST=false || echo ","
    if [ "$status" = "completed" ] && [ -n "$result_json" ]; then
      echo "$result_json" | jq --arg file "$path" --arg role "$role" '. + {file: $file, role: $role}'
    else
      echo "{\"model\":\"codex\",\"role\":\"$role\",\"file\":\"$path\",\"error\":\"${last_error:-Worker failed}\",\"findings\":[]}"
    fi
  done < "$OUTPUT_CSV"
  echo "]"
fi

rm -f "$CSV_FILE" "$OUTPUT_CSV"
