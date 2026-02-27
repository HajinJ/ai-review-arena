#!/usr/bin/env bash
# AI Review Arena v3.2.0 - Uninstaller
set -e

CLAUDE_DIR="$HOME/.claude"
PLUGIN_DIR="$CLAUDE_DIR/plugins/ai-review-arena"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}AI Review Arena - Uninstaller${NC}"
echo ""

# Offer cache cleanup before removing plugin directory
CACHE_DIR="$PLUGIN_DIR/cache"
if [ -d "$CACHE_DIR" ]; then
  echo ""
  read -r -p "Remove cached data (reviews, benchmarks, feedback)? [y/N]: " CLEAN_CACHE
  CLEAN_CACHE="${CLEAN_CACHE:-n}"
  if [[ "$CLEAN_CACHE" =~ ^[Yy]$ ]]; then
    rm -rf "$CACHE_DIR"
    echo -e "${GREEN}✓${NC} Cache data removed"
  else
    # Move cache out before plugin removal, then restore
    _CACHE_BACKUP=$(mktemp -d)
    cp -a "$CACHE_DIR" "$_CACHE_BACKUP/" 2>/dev/null || true
    echo -e "${YELLOW}!${NC} Cache data will be preserved"
  fi
fi

# Remove plugin directory
if [ -d "$PLUGIN_DIR" ]; then
  rm -rf "$PLUGIN_DIR"
  echo -e "${GREEN}✓${NC} Removed $PLUGIN_DIR"
else
  echo -e "${YELLOW}!${NC} Plugin directory not found"
fi

# Restore cache if user chose to preserve it
if [ -n "${_CACHE_BACKUP:-}" ] && [ -d "${_CACHE_BACKUP}/cache" ]; then
  mkdir -p "$PLUGIN_DIR"
  mv "$_CACHE_BACKUP/cache" "$PLUGIN_DIR/cache" 2>/dev/null || true
  rm -rf "$_CACHE_BACKUP"
  echo -e "${GREEN}✓${NC} Cache data preserved at $CACHE_DIR"
fi

# Remove ARENA-ROUTER.md
if [ -f "$CLAUDE_DIR/ARENA-ROUTER.md" ]; then
  rm "$CLAUDE_DIR/ARENA-ROUTER.md"
  echo -e "${GREEN}✓${NC} Removed ARENA-ROUTER.md"
fi

# Remove backup if exists
rm -f "$CLAUDE_DIR/ARENA-ROUTER.md.bak"

# Remove reference from CLAUDE.md
if [ -f "$CLAUDE_DIR/CLAUDE.md" ] && grep -q "ARENA-ROUTER.md" "$CLAUDE_DIR/CLAUDE.md"; then
  # Remove any line referencing ARENA-ROUTER.md (both old @ARENA-ROUTER.md and new @plugins/... paths)
  sed -i.tmp '/ARENA-ROUTER\.md/d' "$CLAUDE_DIR/CLAUDE.md"
  rm -f "$CLAUDE_DIR/CLAUDE.md.tmp"
  echo -e "${GREEN}✓${NC} Removed ARENA-ROUTER.md reference from CLAUDE.md"
fi

# Remove Gemini hooks
GEMINI_SETTINGS="$HOME/.gemini/settings.json"
if [ -f "$GEMINI_SETTINGS" ] && command -v jq &>/dev/null; then
  if jq -e '.hooks.AfterTool[]? | select(.hooks[]?.command | contains("gemini-hook-adapter"))' "$GEMINI_SETTINGS" &>/dev/null; then
    # Remove our hook entries from AfterTool
    CLEANED=$(jq '
      if .hooks.AfterTool then
        .hooks.AfterTool = [.hooks.AfterTool[] | select(.hooks[]?.command | contains("gemini-hook-adapter") | not)]
      else . end |
      if .hooks.AfterTool == [] then del(.hooks.AfterTool) else . end |
      if .hooks == {} then del(.hooks) else . end
    ' "$GEMINI_SETTINGS" 2>/dev/null)

    if [ -n "$CLEANED" ] && echo "$CLEANED" | jq . &>/dev/null; then
      echo "$CLEANED" > "$GEMINI_SETTINGS"
      echo -e "${GREEN}✓${NC} Removed Gemini hooks"
    fi
  fi
fi
rm -f "${GEMINI_SETTINGS}.bak"

echo ""
echo -e "${GREEN}Uninstallation complete.${NC}"
