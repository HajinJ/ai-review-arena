#!/usr/bin/env bash
# Validates AI Review Arena configuration file
# Usage: validate-config.sh <config_file>
# Exit 0 = valid, Exit 1 = invalid

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"
ensure_jq

CONFIG_FILE="${1:?Usage: validate-config.sh <config_file>}"
ERRORS=0

# Check file exists and is valid JSON
if [ ! -f "$CONFIG_FILE" ]; then
  log_error "Config file not found: $CONFIG_FILE"
  exit 1
fi
if ! jq . "$CONFIG_FILE" >/dev/null 2>&1; then
  log_error "Invalid JSON: $CONFIG_FILE"
  exit 1
fi

# Required top-level keys
for key in models review debate output; do
  if ! jq -e ".$key" "$CONFIG_FILE" >/dev/null 2>&1; then
    log_error "Missing required key: $key"
    ERRORS=$((ERRORS + 1))
  fi
done

# Validate cost caps (if present)
max_review=$(jq -r '.cost_estimation.max_per_review_dollars // empty' "$CONFIG_FILE" 2>/dev/null)
if [ -n "$max_review" ]; then
  if ! echo "$max_review" | awk '{exit ($1 > 0 && $1 <= 1000) ? 0 : 1}'; then
    log_error "max_per_review_dollars out of range (0-1000): $max_review"
    ERRORS=$((ERRORS + 1))
  fi
fi

# Validate confidence threshold
threshold=$(jq -r '.review.confidence_threshold // empty' "$CONFIG_FILE" 2>/dev/null)
if [ -n "$threshold" ]; then
  if ! echo "$threshold" | awk '{exit ($1 >= 0 && $1 <= 100) ? 0 : 1}'; then
    log_error "confidence_threshold out of range (0-100): $threshold"
    ERRORS=$((ERRORS + 1))
  fi
fi

# Summary
if [ "$ERRORS" -eq 0 ]; then
  log_info "Config validation passed: $CONFIG_FILE"
  exit 0
else
  log_error "Config validation failed with $ERRORS error(s)"
  exit 1
fi
