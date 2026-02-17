#!/usr/bin/env bash
# AI Review Arena v3.1.0 - Installer (macOS / Linux / WSL)
set -e

CLAUDE_DIR="$HOME/.claude"
PLUGIN_DIR="$CLAUDE_DIR/plugins/ai-review-arena"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  AI Review Arena v3.1.0 - Installer${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}[1/5] Checking prerequisites...${NC}"

if ! command -v claude &>/dev/null; then
  echo -e "${RED}ERROR: Claude Code CLI not found.${NC}"
  echo "  Install: https://docs.anthropic.com/en/docs/claude-code"
  exit 1
fi
echo -e "  ${GREEN}✓${NC} Claude Code CLI"

if command -v jq &>/dev/null; then
  echo -e "  ${GREEN}✓${NC} jq"
else
  echo -e "  ${YELLOW}!${NC} jq not found (optional, some features limited)"
fi

for tool in codex gemini; do
  if command -v "$tool" &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} $tool"
  else
    echo -e "  ${YELLOW}!${NC} $tool not found (optional, Claude-only mode available)"
  fi
done

# Create directories
echo ""
echo -e "${YELLOW}[2/5] Creating directories...${NC}"
mkdir -p "$CLAUDE_DIR"
mkdir -p "$PLUGIN_DIR"
echo -e "  ${GREEN}✓${NC} $PLUGIN_DIR"

# Copy plugin files
echo ""
echo -e "${YELLOW}[3/5] Installing plugin files...${NC}"

# Remove old installation if exists
if [ -d "$PLUGIN_DIR" ] && [ "$(ls -A "$PLUGIN_DIR" 2>/dev/null)" ]; then
  echo -e "  ${YELLOW}!${NC} Existing installation found, updating..."
  rm -rf "$PLUGIN_DIR"
  mkdir -p "$PLUGIN_DIR"
fi

# Copy all plugin files
for item in .claude-plugin agents commands config hooks scripts CLAUDE.md; do
  if [ -e "$SCRIPT_DIR/$item" ]; then
    cp -r "$SCRIPT_DIR/$item" "$PLUGIN_DIR/"
    echo -e "  ${GREEN}✓${NC} $item"
  fi
done

# Make scripts executable
chmod +x "$PLUGIN_DIR/scripts/"*.sh 2>/dev/null || true
echo -e "  ${GREEN}✓${NC} Scripts made executable"

# Install ARENA-ROUTER.md
echo ""
echo -e "${YELLOW}[4/5] Installing ARENA-ROUTER.md...${NC}"

if [ -f "$CLAUDE_DIR/ARENA-ROUTER.md" ]; then
  echo -e "  ${YELLOW}!${NC} ARENA-ROUTER.md already exists, backing up..."
  cp "$CLAUDE_DIR/ARENA-ROUTER.md" "$CLAUDE_DIR/ARENA-ROUTER.md.bak"
fi
cp "$SCRIPT_DIR/ARENA-ROUTER.md" "$CLAUDE_DIR/ARENA-ROUTER.md"
echo -e "  ${GREEN}✓${NC} $CLAUDE_DIR/ARENA-ROUTER.md"

# Update CLAUDE.md
echo ""
echo -e "${YELLOW}[5/5] Updating CLAUDE.md...${NC}"

if [ ! -f "$CLAUDE_DIR/CLAUDE.md" ]; then
  echo -e "# Claude Code Configuration" > "$CLAUDE_DIR/CLAUDE.md"
  echo "" >> "$CLAUDE_DIR/CLAUDE.md"
  echo -e "  ${GREEN}✓${NC} Created new CLAUDE.md"
fi

if grep -q "@ARENA-ROUTER.md" "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null; then
  echo -e "  ${GREEN}✓${NC} @ARENA-ROUTER.md already referenced in CLAUDE.md"
else
  echo "" >> "$CLAUDE_DIR/CLAUDE.md"
  echo "@ARENA-ROUTER.md" >> "$CLAUDE_DIR/CLAUDE.md"
  echo -e "  ${GREEN}✓${NC} Added @ARENA-ROUTER.md to CLAUDE.md"
fi

# Create cache directory
mkdir -p "$PLUGIN_DIR/cache"

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Installation complete!${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Usage:"
echo "    Open any project with Claude Code and type naturally:"
echo '    - "로그인 기능 구현해줘"     → Full lifecycle orchestration'
echo '    - "코드 리뷰해줘"            → Multi-AI code review'
echo '    - "리팩토링해줘"             → Codebase analysis + review'
echo '    - "파라미터 빼줘"            → Quick codebase-aware change'
echo ""
echo "  Commands:"
echo "    /arena              Full lifecycle orchestrator (code)"
echo "    /arena-business     Business content lifecycle orchestrator"
echo "    /arena-research     Pre-implementation research"
echo "    /arena-stack        Project stack detection"
echo "    /multi-review       Multi-AI code review"
echo ""
