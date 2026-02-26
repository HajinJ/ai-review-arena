#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Compliance Guideline Search
#
# Usage: search-guidelines.sh <feature-keywords> <platform> [--config <config-file>]
#
# Reads compliance-rules.json from $PLUGIN_DIR/config/compliance-rules.json.
# Splits feature-keywords by comma. For each keyword, finds matching
# feature_patterns. Filters guidelines by platform.
# Checks cache for each guideline.
#
# Output: JSON with matched features and guidelines.
#
# Exit codes:
#   0 - Always (informational tool)
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

ensure_jq

# --- Arguments ---
FEATURE_KEYWORDS="${1:-}"
PLATFORM="${2:-all}"
CONFIG_FILE=""

if [ -z "$FEATURE_KEYWORDS" ]; then
  log_error "Usage: search-guidelines.sh <feature-keywords> <platform> [--config <config-file>]"
  exit 0
fi

shift 2 2>/dev/null || true
while [ $# -gt 0 ]; do
  case "$1" in
    --config) CONFIG_FILE="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

# --- Resolve paths ---
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
RULES_FILE="${PLUGIN_DIR}/config/compliance-rules.json"

if [ ! -f "$RULES_FILE" ]; then
  log_warn "compliance-rules.json not found at $RULES_FILE"
  jq -n '{"matched_features": [], "guidelines": []}'
  exit 0
fi

# --- Determine project root for cache ---
PROJECT_ROOT=$(find_project_root)

# --- Split keywords ---
IFS=',' read -ra KEYWORDS <<< "$FEATURE_KEYWORDS"

# --- Find matching features ---
MATCHED_FEATURES="[]"

for keyword in "${KEYWORDS[@]}"; do
  # Trim whitespace
  keyword=$(echo "$keyword" | xargs)
  [ -z "$keyword" ] && continue

  # Search feature_patterns for this keyword
  MATCHES=$(jq --arg kw "$keyword" --arg platform "$PLATFORM" '
    .feature_patterns // {} |
    to_entries |
    map(select(
      .value.keywords // [] | any(. | ascii_downcase | contains($kw | ascii_downcase))
    )) |
    map(.value.guidelines // []) | flatten |
    map(select(
      $platform == "all" or
      (.platform // "all") == "all" or
      (.platform // "all") == $platform
    )) |
    map(.name // "unknown") |
    unique
  ' "$RULES_FILE" 2>/dev/null || echo "[]")

  if [ "$MATCHES" != "[]" ] && [ "$MATCHES" != "null" ]; then
    MATCHED_FEATURES=$(echo "$MATCHED_FEATURES" | jq --arg kw "$keyword" --argjson matches "$MATCHES" \
      '. + [{"keyword": $kw, "matched_rules": $matches}]')
  fi
done

# --- Collect all matching guidelines ---
ALL_MATCHED_RULE_NAMES=$(echo "$MATCHED_FEATURES" | jq -r '.[].matched_rules[]' 2>/dev/null | sort -u)

GUIDELINES="[]"

if [ -n "$ALL_MATCHED_RULE_NAMES" ]; then
  while IFS= read -r rule_name; do
    [ -z "$rule_name" ] && continue

    # Get rule details from feature_patterns guidelines
    RULE_DETAIL=$(jq --arg name "$rule_name" '
      [.feature_patterns // {} | .[] | .guidelines // [] | .[] | select(.name == $name)] |
      first // null
    ' "$RULES_FILE" 2>/dev/null)

    if [ -z "$RULE_DETAIL" ] || [ "$RULE_DETAIL" = "null" ]; then
      continue
    fi

    RULE_PLATFORM=$(echo "$RULE_DETAIL" | jq -r '.platform // "all"' 2>/dev/null)
    SEARCH_QUERY=$(echo "$RULE_DETAIL" | jq -r '.search_query // ""' 2>/dev/null)
    CACHE_KEY=$(echo "$rule_name" | tr ' ' '_' | tr '[:upper:]' '[:lower:]')

    # Check cache
    IS_CACHED=false
    CACHED_CONTENT=""
    CACHE_PATH=""

    HASH=$("$SCRIPT_DIR/cache-manager.sh" hash "$PROJECT_ROOT" 2>/dev/null || true)
    if [ -n "$HASH" ]; then
      CACHE_PATH="${PLUGIN_DIR}/cache/${HASH}/guidelines/${CACHE_KEY}"
    fi

    if "$SCRIPT_DIR/cache-manager.sh" check "$PROJECT_ROOT" "guidelines" "$CACHE_KEY" 2>/dev/null; then
      IS_CACHED=true
      CACHED_CONTENT=$("$SCRIPT_DIR/cache-manager.sh" read "$PROJECT_ROOT" "guidelines" "$CACHE_KEY" 2>/dev/null || true)
    fi

    # Build guideline entry
    if [ "$IS_CACHED" = true ] && [ -n "$CACHED_CONTENT" ]; then
      ENTRY=$(jq -n \
        --arg name "$rule_name" \
        --arg platform "$RULE_PLATFORM" \
        --argjson cached true \
        --arg search_query "$SEARCH_QUERY" \
        --arg cache_path "$CACHE_PATH" \
        --arg content "$CACHED_CONTENT" \
        '{
          name: $name,
          platform: $platform,
          cached: $cached,
          search_query: $search_query,
          cache_path: $cache_path,
          content: $content
        }')
    else
      ENTRY=$(jq -n \
        --arg name "$rule_name" \
        --arg platform "$RULE_PLATFORM" \
        --argjson cached false \
        --arg search_query "$SEARCH_QUERY" \
        --arg cache_path "$CACHE_PATH" \
        '{
          name: $name,
          platform: $platform,
          cached: $cached,
          search_query: $search_query,
          cache_path: $cache_path
        }')
    fi

    GUIDELINES=$(echo "$GUIDELINES" | jq --argjson entry "$ENTRY" '. + [$entry]')

  done <<< "$ALL_MATCHED_RULE_NAMES"
fi

# --- Output ---
jq -n \
  --argjson matched_features "$MATCHED_FEATURES" \
  --argjson guidelines "$GUIDELINES" \
  '{
    matched_features: $matched_features,
    guidelines: $guidelines
  }'

exit 0
