#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: API-based Model Version Detection
#
# Usage:
#   check-model-updates.sh <config_file> [--force] [--json]
#
# Checks provider APIs for newer model versions and notifies via stderr.
# Never exits non-zero (pipeline non-blocking).
#
# Exit: always 0
# Output: stderr → user notifications, stdout → JSON (--json flag)
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# --- Defaults ---
DEFAULT_TTL_DAYS=7
DEFAULT_API_TIMEOUT=10
CACHE_CATEGORY="model-updates"
CACHE_KEY="latest-models"

# =============================================================================
# Argument Parsing
# =============================================================================

CONFIG_FILE=""
FORCE=false
JSON_OUTPUT=false

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --force) FORCE=true ;;
      --json) JSON_OUTPUT=true ;;
      -*) log_warn "Unknown flag: $1" ;;
      *) CONFIG_FILE="$1" ;;
    esac
    shift
  done

  if [ -z "$CONFIG_FILE" ]; then
    log_warn "Usage: check-model-updates.sh <config_file> [--force] [--json]"
    exit 0
  fi

  if [ ! -f "$CONFIG_FILE" ]; then
    log_warn "Config file not found: $CONFIG_FILE"
    exit 0
  fi
}

# =============================================================================
# Config Reading
# =============================================================================

read_config() {
  if ! command -v jq &>/dev/null; then
    log_warn "jq not found, skipping model update check"
    exit 0
  fi

  ENABLED=$(jq -r 'if .model_updates.enabled == false then "false" else "true" end' "$CONFIG_FILE" 2>/dev/null || echo "true")
  if [ "$ENABLED" != "true" ]; then
    exit 0
  fi

  TTL_DAYS=$(jq -r '.model_updates.ttl_days // 7' "$CONFIG_FILE" 2>/dev/null || echo "$DEFAULT_TTL_DAYS")
  API_TIMEOUT=$(jq -r '.model_updates.api_timeout_seconds // 10' "$CONFIG_FILE" 2>/dev/null || echo "$DEFAULT_API_TIMEOUT")
  OUTPUT_LANG=$(jq -r '.output.language // "ko"' "$CONFIG_FILE" 2>/dev/null || echo "ko")

  OPENAI_ENABLED=$(jq -r '.model_updates.providers.openai.enabled // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
  OPENAI_PATTERN=$(jq -r '.model_updates.providers.openai.family_pattern // "^gpt-5"' "$CONFIG_FILE" 2>/dev/null || echo "^gpt-5")
  OPENAI_ENDPOINT=$(jq -r '.model_updates.providers.openai.api_endpoint // "https://api.openai.com/v1/models"' "$CONFIG_FILE" 2>/dev/null || echo "https://api.openai.com/v1/models")

  GEMINI_ENABLED=$(jq -r '.model_updates.providers.gemini.enabled // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
  GEMINI_PATTERN=$(jq -r '.model_updates.providers.gemini.family_pattern // "gemini-3"' "$CONFIG_FILE" 2>/dev/null || echo "gemini-3")
  GEMINI_ENDPOINT=$(jq -r '.model_updates.providers.gemini.api_endpoint // "https://generativelanguage.googleapis.com/v1beta/models"' "$CONFIG_FILE" 2>/dev/null || echo "https://generativelanguage.googleapis.com/v1beta/models")

  ANTHROPIC_ENABLED=$(jq -r '.model_updates.providers.anthropic.enabled // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
  ANTHROPIC_PATTERN=$(jq -r '.model_updates.providers.anthropic.family_pattern // "^claude-"' "$CONFIG_FILE" 2>/dev/null || echo "^claude-")
  ANTHROPIC_ENDPOINT=$(jq -r '.model_updates.providers.anthropic.api_endpoint // "https://api.anthropic.com/v1/models"' "$CONFIG_FILE" 2>/dev/null || echo "https://api.anthropic.com/v1/models")

  # Current model variants from config
  CURRENT_OPENAI=$(jq -r '.models.codex.model_variant // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
  CURRENT_GEMINI=$(jq -r '.models.gemini.model_variant // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
}

# =============================================================================
# API Fetch Functions
# =============================================================================

fetch_openai_models() {
  if [ "$OPENAI_ENABLED" != "true" ]; then
    echo "[]"
    return
  fi

  if [ -z "${OPENAI_API_KEY:-}" ]; then
    echo "[]"
    return
  fi

  if ! command -v curl &>/dev/null; then
    log_warn "curl not found, skipping OpenAI model check"
    echo "[]"
    return
  fi

  local response
  response=$(arena_timeout "$API_TIMEOUT" curl -sS \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    "$OPENAI_ENDPOINT" 2>/dev/null) || {
    log_warn "OpenAI API request failed or timed out"
    echo "[]"
    return
  }

  if ! is_valid_json "$response"; then
    log_warn "OpenAI API returned invalid JSON"
    echo "[]"
    return
  fi

  local models
  models=$(echo "$response" | jq -r \
    --arg pattern "$OPENAI_PATTERN" \
    '[.data[] | select(.id | test($pattern)) | {id: .id, created: .created}] | sort_by(-.created)' \
    2>/dev/null) || {
    echo "[]"
    return
  }

  echo "$models"
}

fetch_gemini_models() {
  if [ "$GEMINI_ENABLED" != "true" ]; then
    echo "[]"
    return
  fi

  if [ -z "${GEMINI_API_KEY:-}" ]; then
    echo "[]"
    return
  fi

  if ! command -v curl &>/dev/null; then
    log_warn "curl not found, skipping Gemini model check"
    echo "[]"
    return
  fi

  local response
  response=$(arena_timeout "$API_TIMEOUT" curl -sS \
    "${GEMINI_ENDPOINT}?key=${GEMINI_API_KEY}" 2>/dev/null) || {
    log_warn "Gemini API request failed or timed out"
    echo "[]"
    return
  }

  if ! is_valid_json "$response"; then
    log_warn "Gemini API returned invalid JSON"
    echo "[]"
    return
  fi

  local models
  models=$(echo "$response" | jq -r \
    --arg pattern "$GEMINI_PATTERN" \
    '[.models[] | select(.name | test($pattern)) | {id: (.name | sub("^models/"; "")), name: .displayName}]' \
    2>/dev/null) || {
    echo "[]"
    return
  }

  echo "$models"
}

fetch_anthropic_models() {
  if [ "$ANTHROPIC_ENABLED" != "true" ]; then
    echo "[]"
    return
  fi

  if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    echo "[]"
    return
  fi

  if ! command -v curl &>/dev/null; then
    log_warn "curl not found, skipping Anthropic model check"
    echo "[]"
    return
  fi

  local response
  response=$(arena_timeout "$API_TIMEOUT" curl -sS \
    -H "X-Api-Key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    "$ANTHROPIC_ENDPOINT" 2>/dev/null) || {
    log_warn "Anthropic API request failed or timed out"
    echo "[]"
    return
  }

  if ! is_valid_json "$response"; then
    log_warn "Anthropic API returned invalid JSON"
    echo "[]"
    return
  fi

  local models
  models=$(echo "$response" | jq -r \
    --arg pattern "$ANTHROPIC_PATTERN" \
    '[.data[] | select(.id | test($pattern)) | {id: .id, created_at: .created_at}] | sort_by(-.created_at)' \
    2>/dev/null) || {
    echo "[]"
    return
  }

  echo "$models"
}

# =============================================================================
# Version Comparison
# =============================================================================

compare_versions() {
  local provider="$1"
  local current="$2"
  local api_models="$3"

  if [ -z "$current" ] || [ "$api_models" = "[]" ] || [ -z "$api_models" ]; then
    echo '{"provider":"'"$provider"'","update_available":false,"reason":"no_data"}'
    return
  fi

  local latest_id
  latest_id=$(echo "$api_models" | jq -r '.[0].id // ""' 2>/dev/null || echo "")

  if [ -z "$latest_id" ]; then
    echo '{"provider":"'"$provider"'","update_available":false,"reason":"parse_error"}'
    return
  fi

  if [ "$latest_id" = "$current" ]; then
    echo '{"provider":"'"$provider"'","update_available":false,"current":"'"$current"'","latest":"'"$latest_id"'"}'
  else
    local created=""
    created=$(echo "$api_models" | jq -r '.[0].created // .[0].created_at // ""' 2>/dev/null || echo "")
    local release_date=""
    if [ -n "$created" ] && [ "$created" != "null" ] && [ "$created" != "" ]; then
      # Handle both epoch (OpenAI) and ISO format (Anthropic)
      if echo "$created" | grep -qE '^[0-9]+$'; then
        release_date=$(format_timestamp "$created" 2>/dev/null || echo "")
      else
        release_date="$created"
      fi
    fi
    echo '{"provider":"'"$provider"'","update_available":true,"current":"'"$current"'","latest":"'"$latest_id"'","release_date":"'"$release_date"'"}'
  fi
}

# =============================================================================
# Notification
# =============================================================================

notify_updates() {
  local results="$1"

  local has_updates
  has_updates=$(echo "$results" | jq -r '[.results[] | select(.update_available == true)] | length' 2>/dev/null || echo "0")

  if [ "$has_updates" = "0" ] || [ "$has_updates" = "" ]; then
    return
  fi

  if [ "$OUTPUT_LANG" = "ko" ]; then
    log_warn "모델 업데이트 감지:"
    echo "$results" | jq -r '.results[] | select(.update_available == true) | "  \(.provider): \(.current) → \(.latest)" + (if .release_date != "" then " (\(.release_date) 릴리스)" else "" end)' 2>/dev/null | while IFS= read -r line; do
      log_warn "$line"
    done
    log_warn "설정 업데이트: models.codex.model_variant 또는 models.gemini.model_variant 값을 변경하세요"
    log_warn "비활성화: model_updates.enabled = false"
  else
    log_warn "Model updates detected:"
    echo "$results" | jq -r '.results[] | select(.update_available == true) | "  \(.provider): \(.current) → \(.latest)" + (if .release_date != "" then " (released \(.release_date))" else "" end)' 2>/dev/null | while IFS= read -r line; do
      log_warn "$line"
    done
    log_warn "Update config: change models.codex.model_variant or models.gemini.model_variant"
    log_warn "Disable: model_updates.enabled = false"
  fi
}

# =============================================================================
# Main
# =============================================================================

main() {
  parse_args "$@"
  read_config

  # Use plugin dir as project root for global cache
  local cache_project_root="$SCRIPT_DIR/.."

  # Check cache (unless --force)
  if [ "$FORCE" != "true" ]; then
    local cached
    cached=$(bash "$SCRIPT_DIR/cache-manager.sh" read "$cache_project_root" "$CACHE_CATEGORY" "$CACHE_KEY" --ttl "$TTL_DAYS" 2>/dev/null) && {
      # Cache hit — use cached results
      if is_valid_json "$cached"; then
        notify_updates "$cached"
        if [ "$JSON_OUTPUT" = "true" ]; then
          echo "$cached"
        fi
        exit 0
      fi
    }
  fi

  # Fetch from APIs
  local openai_models gemini_models anthropic_models
  openai_models=$(fetch_openai_models)
  gemini_models=$(fetch_gemini_models)
  anthropic_models=$(fetch_anthropic_models)

  # Compare versions
  local openai_result gemini_result anthropic_result
  openai_result=$(compare_versions "openai" "$CURRENT_OPENAI" "$openai_models")
  gemini_result=$(compare_versions "gemini" "$CURRENT_GEMINI" "$gemini_models")
  anthropic_result=$(compare_versions "anthropic" "" "$anthropic_models")

  # Assemble result JSON
  local results
  results=$(jq -n \
    --argjson openai "$openai_result" \
    --argjson gemini "$gemini_result" \
    --argjson anthropic "$anthropic_result" \
    --arg checked_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{checked_at: $checked_at, results: [$openai, $gemini, $anthropic]}' \
    2>/dev/null) || {
    results='{"checked_at":"","results":[],"error":"json_assembly_failed"}'
  }

  # Write cache
  echo "$results" | bash "$SCRIPT_DIR/cache-manager.sh" write "$cache_project_root" "$CACHE_CATEGORY" "$CACHE_KEY" --ttl "$TTL_DAYS" 2>/dev/null || true

  # Notify user
  notify_updates "$results"

  # JSON output if requested
  if [ "$JSON_OUTPUT" = "true" ]; then
    echo "$results"
  fi

  exit 0
}

main "$@"
