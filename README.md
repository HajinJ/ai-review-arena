# AI Review Arena v2.1

> Full AI development lifecycle orchestrator for [Claude Code](https://docs.anthropic.com/en/docs/claude-code)

Multi-AI adversarial code review + codebase-aware development with always-on intelligent routing.

```
User Input → ARENA-ROUTER → Auto Routing
  │
  ├── "로그인 API 구현해줘"        → /arena (Full Lifecycle)
  ├── "어떻게 구현하면 좋을까?"     → /arena-research (Research)
  ├── "기술 스택 뭐야?"            → /arena-stack (Stack Detection)
  ├── "코드 리뷰해줘"              → /multi-review (Code Review)
  ├── "리팩토링해줘"               → /arena --phase codebase,review
  └── "파라미터 빼줘"              → /arena --intensity quick
```

## Features

### Always-On Routing
All code-related requests automatically go through Arena. Even simple changes go through codebase analysis to match existing conventions.

### Codebase Analysis (Phase 0.5)
Analyzes existing code before any work:
- Extracts naming conventions, import styles, error handling patterns
- Identifies reusable utils/helpers/services
- Generates code that matches existing patterns

### Multi-AI Adversarial Review
Claude + OpenAI Codex + Google Gemini validate each other's reviews through adversarial debate:
- Each model reviews code independently
- Models debate each other's findings
- Only consensus findings make the final report

### MCP Dependency Detection
Detects when requests need MCP servers (Figma, Playwright, Notion) and offers installation if missing.

## Installation

### macOS / Linux
```bash
git clone https://github.com/HajinJ/ai-review-arena.git
cd ai-review-arena
./install.sh
```

### Windows (PowerShell)
```powershell
git clone https://github.com/HajinJ/ai-review-arena.git
cd ai-review-arena
.\install.ps1
```

> **Windows Note**: Shell scripts require WSL or Git Bash. Core features (commands, agents, routing) work natively. Install WSL: `wsl --install`

### Uninstall
```bash
./uninstall.sh
```

## Prerequisites

| Tool | Required | Purpose |
|------|----------|---------|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | Yes | Base platform |
| [jq](https://jqlang.github.io/jq/) | Recommended | JSON processing in scripts |
| [OpenAI Codex CLI](https://github.com/openai/codex) | Optional | Multi-AI review (Codex) |
| [Google Gemini CLI](https://github.com/google-gemini/gemini-cli) | Optional | Multi-AI review (Gemini) |

## Usage

After installation, open any project with Claude Code and type naturally.

### Slash Commands

| Command | Description |
|---------|-------------|
| `/arena` | Full lifecycle orchestrator (research → compliance → benchmark → review) |
| `/arena-research` | Pre-implementation research (best practices, guidelines) |
| `/arena-stack` | Project tech stack detection |
| `/multi-review` | Multi-AI adversarial code review |
| `/multi-review-config` | Review configuration management |
| `/multi-review-status` | Review status dashboard |

### Intensity Levels

| Level | Phases | Agent Team | Use Case |
|-------|--------|------------|----------|
| `quick` | Codebase Analysis only | No | Simple changes (rename, add param) |
| `standard` | Codebase + Stack(cached) + Review | 3-5 agents | Medium changes (refactoring) |
| `deep` | Codebase + Stack + Research + Compliance + Review | 5-7 agents | Complex features |
| `comprehensive` | All phases including Benchmark + Figma | 7-10 agents | Full lifecycle |

### Examples

```
# Full lifecycle
"로그인 API 구현해줘"
"implement chat feature"

# Research
"Redis 캐싱 어떻게 구현하면 좋을까?"
"best practices for OAuth implementation"

# Code Review
"코드 리뷰해줘"
"review PR #42 --focus security"

# Refactoring
"리팩토링해줘"
"optimize src/services/"

# Quick Change
"파라미터 빼줘"
"rename this function"
```

## Architecture

### Pipeline Phases

```
Phase 0   → Argument Parsing + MCP Detection
Phase 0.5 → Codebase Analysis (conventions, reusable code)
Phase 1   → Stack Detection
Phase 2   → Pre-Implementation Research
Phase 3   → Compliance Check
Phase 4   → Model Benchmarking
Phase 5   → Figma Design Analysis (if MCP available)
Phase 6   → Implementation (Agent Team)
Phase 7   → Multi-AI Code Review + Debate
```

### Project Structure

```
ai-review-arena/
├── .claude-plugin/          # Plugin manifest
│   └── plugin.json
├── agents/                  # Claude agent definitions (10 agents)
│   ├── security-reviewer.md
│   ├── bug-detector.md
│   ├── architecture-reviewer.md
│   ├── performance-reviewer.md
│   ├── test-coverage-reviewer.md
│   ├── debate-arbitrator.md
│   ├── research-coordinator.md
│   ├── design-analyzer.md
│   ├── compliance-checker.md
│   └── scale-advisor.md
├── commands/                # Slash commands (6 commands)
│   ├── arena.md
│   ├── arena-research.md
│   ├── arena-stack.md
│   ├── multi-review.md
│   ├── multi-review-config.md
│   └── multi-review-status.md
├── config/                  # Configuration
│   ├── default-config.json
│   ├── compliance-rules.json
│   ├── tech-queries.json
│   ├── review-prompts/
│   └── benchmarks/
├── hooks/                   # PostToolUse auto-review hook
├── scripts/                 # Shell scripts (15 scripts)
├── ARENA-ROUTER.md          # Always-on routing intelligence
├── install.sh               # macOS/Linux installer
├── install.ps1              # Windows installer
└── uninstall.sh             # Uninstaller
```

## Configuration

### Project-Level
Create `.ai-review-arena.json` in your project root:

```json
{
  "models": {
    "claude": { "enabled": true, "roles": ["security", "bugs"] },
    "codex": { "enabled": false },
    "gemini": { "enabled": true, "roles": ["architecture"] }
  },
  "review": {
    "intensity": "standard",
    "focus_areas": ["security", "bugs"]
  },
  "output": {
    "language": "ko"
  }
}
```

### Global Config
Place at `~/.claude/.ai-review-arena.json` for defaults across all projects.

### Environment Variables
```bash
MULTI_REVIEW_INTENSITY=standard
MULTI_REVIEW_LANGUAGE=ko
ARENA_SKIP_CACHE=true
ARENA_INTENSITY=deep
```

## Routing Bypass

```bash
# Disable Arena routing
"fix this --no-arena"

# Force specific route
"analyze this --arena-route=review"

# Direct slash command (bypasses auto-routing)
/multi-review --focus security
```

## Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | Full | Native bash |
| Linux | Full | Native bash |
| Windows (WSL) | Full | All features via WSL |
| Windows (Git Bash) | Partial | Core features work |
| Windows (Native) | Commands only | Slash commands and agents work, scripts need WSL |

## License

MIT

## Changelog

### v2.1.0
- Always-On Routing: all code requests go through Arena
- Codebase Analysis (Phase 0.5): convention extraction, reusable code detection
- MCP Dependency Detection: auto-detect and offer installation
- Quick intensity mode: Claude-solo with codebase analysis
- Route 5 (Refactoring) and Route 6 (Simple Changes)

### v2.0.0
- Full lifecycle orchestrator (`/arena`)
- Pre-implementation research (`/arena-research`)
- Stack detection (`/arena-stack`)
- Compliance checking, model benchmarking, knowledge caching

### v1.0.0
- Multi-AI adversarial code review (`/multi-review`)
- Claude + Codex + Gemini support
- Adversarial debate system
