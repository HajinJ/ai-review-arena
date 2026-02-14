# AI Review Arena v2.6

> Full AI development lifecycle orchestrator for [Claude Code](https://docs.anthropic.com/en/docs/claude-code)

AI Review Arena intercepts every request in Claude Code and routes it through an intelligent pipeline — from codebase analysis and pre-implementation research to multi-AI adversarial code review. Critical decisions (intensity level, research direction, compliance scope, implementation strategy) are made by **Agent Teams adversarial debate**, not static keyword matching. Every implementation is verified against **success criteria** defined before coding, and a dedicated **scope reviewer** ensures changes stay surgical.

```
Your Request
  │
  ├── Context Discovery ─── gather external context (issues, PRs, Figma, docs)
  ├── Route Selection ────── intent-based routing (language-agnostic)
  └── Pipeline Execution ─── Phase 0 → 0.1 → 0.5 → 1 → 2 → 3 → 4 → 5 → 5.5 → 6 → 7
                                   │
                              Agent Teams debate at every critical decision point
```

## Key Features

### Always-On Routing

Every request passes through Arena automatically. The routing system understands intent in any language — no keywords or slash commands needed. Just type what you want naturally.

| What you say | What happens |
|---|---|
| "implement login API" | Full lifecycle pipeline (research → compliance → review) |
| "fix the deadlock in production" | Agent debate determines intensity → deep pipeline |
| "rename this function" | Quick codebase analysis → convention-aware change |
| "review PR #42 for security" | Multi-AI adversarial code review |
| "how should I implement caching?" | Pre-implementation research |
| "refactor this service" | Codebase analysis → code review |

### Agent Teams Adversarial Debate

Critical pipeline decisions are made through structured debate between multiple Claude agents with opposing roles. This replaces brittle keyword matching — agents can reason about novel scenarios like deadlock bugs or complex concurrency issues that no keyword list would cover.

**5 debate points across the pipeline:**

| Debate | Purpose | When |
|--------|---------|------|
| Intensity Decision | How thorough should the pipeline be? | Every request (mandatory) |
| Research Direction | What should we investigate before building? | deep, comprehensive |
| Compliance Scope | Which compliance rules actually apply? | deep, comprehensive |
| Implementation Strategy | What's the best approach? + define success criteria | standard, deep, comprehensive |
| 3-Round Cross-Exam | All AIs cross-examine + defend findings | standard, deep, comprehensive |

**Example — Intensity Decision debate:**

```
Request: "Fix the deadlock in production"

intensity-advocate:  "Deadlock is a concurrency bug. A bad fix introduces
                      new race conditions. Needs deep analysis."
efficiency-advocate: "If it's a known pattern, standard is enough."
risk-assessor:       "Production outage. Service disruption risk. deep+."
intensity-arbitrator: "deep. Production risk + concurrency complexity."
```

### Multi-AI 3-Round Cross-Examination

Claude, OpenAI Codex, and Google Gemini don't just review independently — they **cross-examine each other** in a structured 3-round debate. Every AI sees every other AI's findings and can agree, disagree, or add new observations. Then each AI defends its own findings against challenges.

```
Round 1: Independent Review (parallel)
  Claude Agent Team (5-10 reviewers)     → findings JSON
    ├── security-reviewer
    ├── bug-detector
    ├── architecture-reviewer
    ├── performance-reviewer
    ├── test-coverage-reviewer
    ├── scale-advisor
    ├── scope-reviewer
    ├── compliance-checker (conditional)
    └── debate-arbitrator
  OpenAI Codex CLI                       → findings JSON
  Google Gemini CLI                      → findings JSON

Round 2: Cross-Examination (parallel)
  Codex reads Claude+Gemini findings     → agree/disagree/partial
  Gemini reads Claude+Codex findings     → agree/disagree/partial
  Claude reads Codex+Gemini findings     → agree/disagree/partial

Round 3: Defense (parallel)
  Each AI defends its own findings       → defend/concede/modify
  against the other two AIs' challenges

Final: debate-arbitrator synthesizes all 3 rounds → Consensus Report
```

**Why this matters**: A single-round review can't catch false positives. With cross-examination, if Codex flags a "security vulnerability" but Claude and Gemini both disagree with evidence, the finding gets downgraded or dismissed. If all three agree, confidence increases. If an AI concedes during defense, that's strong signal the finding was wrong.

### Success Criteria (Phase 5.5)

Before any code is written, the strategy debate defines **verifiable success criteria**. These are concrete, testable conditions — not vague quality goals.

```
Success Criteria (from strategy-arbitrator):
  1. API returns 200 for valid input      → verify: curl test with sample payload
  2. Invalid tokens return 401             → verify: curl with expired/bad token
  3. Rate limiting at 100 req/min          → verify: load test with k6
```

After implementation, Phase 7 verifies each criterion and reports PASS/FAIL in the final report. If criteria fail, the team knows exactly what needs fixing.

### Scope Reviewer (Phase 6)

A dedicated **scope-reviewer** agent verifies every implementation stays surgical. It compares the actual diff against the Phase 5.5 strategy and flags:

- **SCOPE_VIOLATION** — files changed that weren't in the strategy
- **DRIVE_BY_REFACTOR** — unrelated variable renames, reformatting, import reordering
- **GOLD_PLATING** — features, config options, or abstractions nobody asked for
- **UNNECESSARY_CHANGE** — cosmetic edits to code that wasn't part of the task

If all changes are in scope, the verdict is `CLEAN`. This prevents the common problem of implementations that quietly grow beyond the original request.

### Codebase Analysis (Phase 0.5)

Before any work begins, the pipeline analyzes the existing codebase:

- Naming conventions (camelCase, snake_case, PascalCase)
- Directory structure patterns
- Import styles and module organization
- Error handling patterns
- Reusable utilities, services, and type definitions

All generated code follows existing conventions. No reinventing what already exists.

### MCP Dependency Detection

When a request needs an MCP server (Figma, Playwright, Notion), Arena detects it automatically and offers installation if missing. If you decline, the pipeline continues without that capability.

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

### Agent Teams Setup

Agent Teams is required for the adversarial debate system. Enable it:

```bash
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=true
```

Add to your shell profile (`~/.zshrc` or `~/.bashrc`) to persist across sessions.

## Prerequisites

| Tool | Required | Purpose |
|------|----------|---------|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | Yes | Base platform |
| [jq](https://jqlang.github.io/jq/) | Recommended | JSON processing in shell scripts |
| [OpenAI Codex CLI](https://github.com/openai/codex) | Optional | Multi-AI review (second opinion) |
| [Google Gemini CLI](https://github.com/google-gemini/gemini-cli) | Optional | Multi-AI review (third opinion) |

Without Codex/Gemini, Arena runs in Claude-only mode with the full Agent Teams pipeline.

## Pipeline Phases

```
Phase 0     Argument Parsing + MCP Detection
Phase 0.1   Intensity Decision ★ Agent Teams debate (mandatory)
Phase 0.5   Codebase Analysis (conventions, reusable code, structure)
Phase 1     Stack Detection (framework, language, dependencies)
Phase 2     Pre-Implementation Research ★ Research Direction debate
Phase 3     Compliance Check ★ Compliance Scope debate
Phase 4     Model Benchmarking (score Claude/Codex/Gemini per category)
Phase 5     Figma Design Analysis (if Figma MCP available)
Phase 5.5   Implementation Strategy ★ Agent Teams debate + Success Criteria
Phase 6     Implementation + Agent Team Code Review + Scope Review
Phase 6.10  3-Round Cross-Examination (Round 1 → Round 2 → Round 3 → Consensus)
Phase 7     Final Report + Cleanup
```

### Intensity Levels

Intensity determines which phases run. It's decided by adversarial debate (Phase 0.1), not hardcoded rules.

| Intensity | Phases | Debates | Review Agents |
|-----------|--------|---------|---------------|
| `quick` | 0 → 0.1 → 0.5 | Intensity only | None (Claude solo) |
| `standard` | 0 → 0.1 → 0.5 → 1(cached) → 5.5 → 6 → 7 | Intensity + Strategy | 3-5 |
| `deep` | 0 → 0.1 → 0.5 → 1 → 2 → 3 → 5.5 → 6 → 7 | Intensity + Research + Compliance + Strategy | 5-7 |
| `comprehensive` | 0 → 0.1 → 0.5 → 1 → 2 → 3 → 4 → 5 → 5.5 → 6 → 7 | All 5 debates | 7-10 |

**How the debate decides:**

- A simple rename → agents quickly agree on `quick`
- A standard CRUD feature → agents settle on `standard`
- A deadlock bug in production → risk-assessor flags production impact → `deep`
- OAuth authentication system → security risk is catastrophic → `comprehensive`

## Slash Commands

These are available but typically unnecessary — the always-on router handles everything automatically.

| Command | Description |
|---------|-------------|
| `/arena` | Full lifecycle orchestrator |
| `/arena-research` | Pre-implementation research |
| `/arena-stack` | Project tech stack detection |
| `/multi-review` | Multi-AI adversarial code review |
| `/multi-review-config` | Review configuration |
| `/multi-review-status` | Review status dashboard |

## Routes

The router selects a route based on the intent of your request:

| Route | Intent | Pipeline |
|-------|--------|----------|
| A: Feature Build | New functionality, complex implementation | `arena.md` — full pipeline |
| B: Research | Investigation before building | `arena-research.md` |
| C: Stack Analysis | Understand project technology | `arena-stack.md` |
| D: Code Review | Review existing code, PRs | `multi-review.md` |
| E: Refactoring | Improve existing code structure | `arena.md` — codebase + review phases |
| F: Simple Change | Small, scoped modifications | `arena.md` — quick intensity |

## Configuration

### Project-Level

Create `.ai-review-arena.json` in your project root:

```json
{
  "models": {
    "claude": { "enabled": true, "roles": ["security", "bugs"] },
    "codex": { "enabled": true },
    "gemini": { "enabled": true, "roles": ["architecture"] }
  },
  "review": {
    "intensity": "standard",
    "focus_areas": ["security", "bugs"]
  },
  "output": {
    "language": "en"
  }
}
```

### Global Config

Place at `~/.claude/.ai-review-arena.json` for defaults across all projects.

### Environment Variables

```bash
MULTI_REVIEW_INTENSITY=standard    # Default intensity
MULTI_REVIEW_LANGUAGE=en           # Output language
ARENA_SKIP_CACHE=true              # Bypass cache
ARENA_INTENSITY=deep               # Force intensity level
```

## Routing Bypass

```bash
# Disable Arena routing for one request
"fix this --no-arena"

# Force a specific intensity (skips Phase 0.1 debate)
"implement this --intensity deep"

# Direct slash command (bypasses auto-routing)
/multi-review --focus security
```

## Project Structure

```
ai-review-arena/
├── ARENA-ROUTER.md              # Routing intelligence (loaded into system prompt)
├── install.sh                   # macOS/Linux installer
├── install.ps1                  # Windows installer
├── uninstall.sh                 # Uninstaller
├── CLAUDE.md                    # Plugin development rules
│
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest
│
├── commands/                    # Slash commands (6)
│   ├── arena.md                 # Full lifecycle orchestrator (~2100 lines)
│   ├── arena-research.md        # Pre-implementation research
│   ├── arena-stack.md           # Stack detection
│   ├── multi-review.md          # Multi-AI code review
│   ├── multi-review-config.md   # Review config management
│   └── multi-review-status.md   # Review status dashboard
│
├── agents/                      # Claude agent definitions (10)
│   ├── security-reviewer.md
│   ├── bug-detector.md
│   ├── architecture-reviewer.md
│   ├── performance-reviewer.md
│   ├── test-coverage-reviewer.md
│   ├── scale-advisor.md
│   ├── scope-reviewer.md        # Surgical changes checker (v2.5)
│   ├── debate-arbitrator.md
│   ├── research-coordinator.md
│   ├── design-analyzer.md
│   └── compliance-checker.md
│
├── scripts/                     # Shell scripts (17)
│   ├── orchestrate-review.sh    # Core review orchestration
│   ├── codex-review.sh          # Codex CLI integration
│   ├── gemini-review.sh         # Gemini CLI integration
│   ├── aggregate-findings.sh    # Finding aggregation
│   ├── run-debate.sh            # Debate execution
│   ├── generate-report.sh       # Report generation
│   ├── cost-estimator.sh        # Token cost estimation
│   ├── detect-stack.sh          # Technology stack detection
│   ├── cache-manager.sh         # Knowledge cache management
│   ├── benchmark-models.sh      # Model benchmarking
│   ├── search-best-practices.sh # Best practices search
│   ├── search-guidelines.sh     # Compliance guideline search
│   ├── setup.sh                 # Review setup
│   ├── setup-arena.sh           # Arena setup
│   ├── codex-cross-examine.sh   # Codex cross-examination wrapper (v2.6)
│   ├── gemini-cross-examine.sh  # Gemini cross-examination wrapper (v2.6)
│   └── utils.sh                 # Shared utilities
│
├── config/
│   ├── default-config.json      # All settings
│   ├── compliance-rules.json    # Feature → guideline mapping
│   ├── tech-queries.json        # Technology → search queries (31 techs)
│   ├── review-prompts/          # Role-specific review prompts (9)
│   │   ├── security.txt
│   │   ├── bugs.txt
│   │   ├── architecture.txt
│   │   ├── performance.txt
│   │   ├── testing.txt
│   │   ├── debate-challenge.txt
│   │   ├── debate-synthesis.txt
│   │   ├── cross-examine.txt      # Round 2 cross-examination prompt (v2.6)
│   │   └── defend.txt             # Round 3 defense prompt (v2.6)
│   └── benchmarks/              # Model benchmark test cases (4)
│       ├── security-test-01.json
│       ├── bugs-test-01.json
│       ├── architecture-test-01.json
│       └── performance-test-01.json
│
├── hooks/
│   └── hooks.json               # PostToolUse auto-review hook
│
└── cache/                       # Runtime knowledge cache (gitignored)
```

## How It Works

### The Routing Layer

`ARENA-ROUTER.md` is installed into `~/.claude/` and referenced from `~/.claude/CLAUDE.md`. This means Claude Code loads it into every session's system prompt. It contains:

1. **Context Discovery** — rules for gathering external information (issues, PRs, Figma designs, docs)
2. **Route Selection** — intent-based routing using Claude's natural language understanding
3. **Pipeline Execution** — instructions to load and execute the appropriate command file via the Read tool

The router never calls slash commands internally. It reads command files directly with the Read tool, ensuring the full pipeline definition is loaded into context.

### The Pipeline

When `arena.md` is loaded, it provides ~1910 lines of detailed instructions for the team lead (Claude) to orchestrate the entire lifecycle. Each phase has:

- Entry conditions (which intensity levels include this phase)
- Tool calls to make (Bash for scripts, Glob/Grep/Read for codebase analysis)
- Agent Teams setup (Teammate tool for team creation, Task tool for spawning agents)
- Inter-agent communication (SendMessage for debate coordination)
- Output format and handoff to the next phase

### The Agent Teams

Arena uses Claude Code's [Agent Teams](https://docs.anthropic.com/en/docs/claude-code) for two distinct purposes:

1. **Decision Debates** (Phases 0.1, 2, 3, 5.5) — small teams of 3-4 agents with opposing roles debate critical decisions
2. **Code Review** (Phase 6) — large teams of 5-10 reviewer agents analyze code from different perspectives, then debate findings

Each agent is a separate Claude Code instance with its own context, communicating through shared task lists and direct messages.

## Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | Full | Native bash support |
| Linux | Full | Native bash support |
| Windows (WSL) | Full | All features via WSL |
| Windows (Git Bash) | Partial | Core features work |
| Windows (Native) | Commands only | Slash commands and agents work; scripts need WSL |

## Changelog

### v2.6.0

- **3-Round Cross-Examination** — all AI models (Claude, Codex, Gemini) now cross-examine each other's findings in a structured 3-round debate:
  - Round 1: Independent review (existing)
  - Round 2: Each AI evaluates other AIs' findings (agree/disagree/partial + new observations)
  - Round 3: Each AI defends its own findings against challenges (defend/concede/modify)
- New scripts: `codex-cross-examine.sh`, `gemini-cross-examine.sh`
- New prompt templates: `cross-examine.txt`, `defend.txt`
- Updated `debate-arbitrator.md` with 3-round consensus algorithm and `cross_examination_trail` output
- All intensity levels now use 3-round cross-examination (standard/deep/comprehensive)
- Phase 7 report includes Cross-Examination Summary with per-round breakdown

### v2.5.0

- **Success Criteria** — strategy arbitrator defines verifiable goals before implementation; Phase 7 reports PASS/FAIL for each
- **Scope Reviewer** — new reviewer agent that checks changes are surgical (no drive-by refactors, gold-plating, or scope violations)
- Inspired by [Karpathy's coding principles](https://github.com/forrestchang/andrej-karpathy-skills) (Goal-Driven Execution, Surgical Changes)

### v2.4.0

- **Agent Teams adversarial debate** for intensity determination (Phase 0.1, mandatory)
- **Research Direction debate** before investigation (Phase 2, deep+)
- **Compliance Scope debate** before compliance check (Phase 3, deep+)
- **Implementation Strategy debate** before coding (Phase 5.5, standard+)
- Removed static keyword-based intensity rules

### v2.3.0

- Fixed slash command routing — pipeline now uses Read tool to load command files directly
- Prevents infinite recursion from slash command self-invocation

### v2.2.0

- Rewrote routing system from keyword matching to intent-based NLU
- Language-agnostic routing (works in any language)
- Context Discovery phase for external information gathering

### v2.1.0

- Always-on routing: all code requests go through Arena
- Codebase Analysis (Phase 0.5): convention extraction, reusable code detection
- MCP Dependency Detection: auto-detect and offer installation
- Quick intensity mode: Claude-solo with codebase analysis

### v2.0.0

- Full lifecycle orchestrator (`/arena`)
- Pre-implementation research (`/arena-research`)
- Stack detection (`/arena-stack`)
- Compliance checking, model benchmarking, knowledge caching

### v1.0.0

- Multi-AI adversarial code review (`/multi-review`)
- Claude + Codex + Gemini support
- Adversarial debate system

## License

MIT
