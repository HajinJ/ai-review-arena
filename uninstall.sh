#!/usr/bin/env bash
# AI Review Arena v3.1.0 - Uninstaller
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

# Remove plugin directory
if [ -d "$PLUGIN_DIR" ]; then
  rm -rf "$PLUGIN_DIR"
  echo -e "${GREEN}✓${NC} Removed $PLUGIN_DIR"
else
  echo -e "${YELLOW}!${NC} Plugin directory not found"
fi

# Remove ARENA-ROUTER.md
if [ -f "$CLAUDE_DIR/ARENA-ROUTER.md" ]; then
  rm "$CLAUDE_DIR/ARENA-ROUTER.md"
  echo -e "${GREEN}✓${NC} Removed ARENA-ROUTER.md"
fi

# Remove backup if exists
rm -f "$CLAUDE_DIR/ARENA-ROUTER.md.bak"

# Remove reference from CLAUDE.md
if [ -f "$CLAUDE_DIR/CLAUDE.md" ] && grep -q "@ARENA-ROUTER.md" "$CLAUDE_DIR/CLAUDE.md"; then
  sed -i.tmp '/@ARENA-ROUTER.md/d' "$CLAUDE_DIR/CLAUDE.md"
  rm -f "$CLAUDE_DIR/CLAUDE.md.tmp"
  echo -e "${GREEN}✓${NC} Removed @ARENA-ROUTER.md from CLAUDE.md"
fi

echo ""
echo -e "${GREEN}Uninstallation complete.${NC}"
