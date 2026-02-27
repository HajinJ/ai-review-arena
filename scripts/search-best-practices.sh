#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Best Practices Search Query Generator
#
# Usage: search-best-practices.sh <technology> [--version <ver>] [--config <config-file>]
#
# Reads tech-queries.json from $PLUGIN_DIR/config/tech-queries.json.
# Substitutes {version} and {year} placeholders in query templates.
# Checks cache via cache-manager.sh for previously fetched results.
#
# Output: JSON with technology, cached status, search queries, and TTL.
#
# Exit codes:
#   0 - Always (informational tool)
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

ensure_jq

# --- Arguments ---
TECHNOLOGY="${1:-}"
VERSION=""
CONFIG_FILE=""

if [ -z "$TECHNOLOGY" ]; then
  log_error "Usage: search-best-practices.sh <technology> [--version <ver>] [--config <config-file>]"
  exit 0
fi

shift 1
# shellcheck disable=SC2034
while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2 ;;
    --config) CONFIG_FILE="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

# --- Resolve config ---
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
QUERIES_FILE="${PLUGIN_DIR}/config/tech-queries.json"

if [ ! -f "$QUERIES_FILE" ]; then
  log_warn "tech-queries.json not found at $QUERIES_FILE"
  # Output empty result
  jq -n \
    --arg tech "$TECHNOLOGY" \
    '{technology: $tech, cached: false, cache_path: null, search_queries: [], ttl_days: 3}'
  exit 0
fi

# --- Determine project root for cache ---
PROJECT_ROOT=$(find_project_root)
CURRENT_YEAR=$(get_current_year)

# --- Read queries for this technology ---
TECH_ENTRY=$(jq --arg tech "$TECHNOLOGY" '.[$tech] // null' "$QUERIES_FILE" 2>/dev/null)

if [ -z "$TECH_ENTRY" ] || [ "$TECH_ENTRY" = "null" ]; then
  log_warn "No query templates found for technology: $TECHNOLOGY"
  jq -n \
    --arg tech "$TECHNOLOGY" \
    '{technology: $tech, cached: false, cache_path: null, search_queries: [], ttl_days: 3}'
  exit 0
fi

# --- Extract TTL ---
TTL_DAYS=$(echo "$TECH_ENTRY" | jq -r '.ttl_days // 3')

# --- Check cache ---
CACHE_KEY="${TECHNOLOGY}"
if [ -n "$VERSION" ]; then
  CACHE_KEY="${TECHNOLOGY}-${VERSION}"
fi

CACHE_PATH=""
CACHE_PATH=$("$SCRIPT_DIR/cache-manager.sh" hash "$PROJECT_ROOT" || true)
if [ -n "$CACHE_PATH" ]; then
  CACHE_PATH="${PLUGIN_DIR}/cache/${CACHE_PATH}/best-practices/${CACHE_KEY}"
fi

# Check if cached and fresh
if "$SCRIPT_DIR/cache-manager.sh" check "$PROJECT_ROOT" "best-practices" "$CACHE_KEY" --ttl "$TTL_DAYS" 2>/dev/null; then
  # Cache hit - return cached content
  CACHED_CONTENT=$("$SCRIPT_DIR/cache-manager.sh" read "$PROJECT_ROOT" "best-practices" "$CACHE_KEY" --ttl "$TTL_DAYS" || true)
  if [ -n "$CACHED_CONTENT" ]; then
    jq -n \
      --arg tech "$TECHNOLOGY" \
      --arg content "$CACHED_CONTENT" \
      --arg cache_path "$CACHE_PATH" \
      '{technology: $tech, cached: true, content: $content, cache_path: $cache_path}'
    exit 0
  fi
fi

# --- Build search queries with substitutions ---
VERSION_SUB="${VERSION:-latest}"
SEARCH_QUERIES=$(echo "$TECH_ENTRY" | jq --arg version "$VERSION_SUB" --arg year "$CURRENT_YEAR" '
  .queries // [] |
  map(
    gsub("\\{version\\}"; $version) |
    gsub("\\{year\\}"; $year)
  )
' 2>/dev/null)

if [ -z "$SEARCH_QUERIES" ] || [ "$SEARCH_QUERIES" = "null" ]; then
  SEARCH_QUERIES="[]"
fi

# --- Output ---
jq -n \
  --arg tech "$TECHNOLOGY" \
  --argjson queries "$SEARCH_QUERIES" \
  --argjson ttl "$TTL_DAYS" \
  --arg cache_path "$CACHE_PATH" \
  '{
    technology: $tech,
    cached: false,
    cache_path: $cache_path,
    search_queries: $queries,
    ttl_days: $ttl
  }'

exit 0
