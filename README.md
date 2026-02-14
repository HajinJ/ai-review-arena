# AI Review Arena

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugin that makes AI models argue with each other about your code before any of it ships.

## The Problem

You ask an AI to review your code. It finds 12 issues. But how many are real? Single-model reviews produce false positives that waste your time and real vulnerabilities that slip through because one model has blind spots. You have no way to know which findings to trust.

## What Arena Does

Arena makes Claude, OpenAI Codex, and Google Gemini **independently review your code, then cross-examine each other's findings in a 3-round adversarial debate**. Models challenge each other, defend their positions, or concede when they're wrong. What survives is a set of findings validated by multiple AI perspectives, each with a confidence score you can actually trust.

It also handles the full development lifecycle: analyzing your codebase conventions before writing code, researching best practices, checking compliance requirements, defining verifiable success criteria, and ensuring implementations stay precisely scoped.

Arena activates automatically. You don't invoke it. Just use Claude Code normally, and the pipeline runs behind the scenes.

## Quick Start

```bash
git clone https://github.com/HajinJ/ai-review-arena.git
cd ai-review-arena
./install.sh  # macOS/Linux
# .\install.ps1  # Windows
```

Enable Agent Teams (required for multi-agent debates):

```bash
echo 'export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=true' >> ~/.zshrc
source ~/.zshrc
```

That's it. Every Claude Code session now runs through Arena automatically.

### Prerequisites

| Tool | Required | Why |
|------|----------|-----|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | Yes | Base platform |
| [jq](https://jqlang.github.io/jq/) | Recommended | JSON processing in scripts |
| [OpenAI Codex CLI](https://github.com/openai/codex) | Optional | Second AI perspective |
| [Google Gemini CLI](https://github.com/google-gemini/gemini-cli) | Optional | Third AI perspective |

Without Codex or Gemini, Arena runs the full pipeline with Claude agents only.

### Uninstall

```bash
./uninstall.sh
```

---

## How It Works

### You just type normally

Arena intercepts every request and decides what to do with it. No slash commands, no special syntax, any language.

| What you type | What Arena does |
|---|---|
| "implement login API" | Full pipeline: research, compliance, implement, 3-round review |
| "fix the production deadlock" | Agents debate severity, run deep analysis with cross-examination |
| "rename this variable" | Quick codebase scan for conventions, makes the change |
| "review PR #42 for security" | Multi-AI adversarial review focused on security |
| "how should I implement caching?" | Pre-implementation research with best practices |

### The pipeline decides its own intensity

When you make a request, Arena doesn't use hardcoded rules to decide how thorough to be. Instead, it spawns a team of agents that **debate** the question:

```
You: "Fix the deadlock in production"

intensity-advocate:   "Deadlock is a concurrency bug. A wrong fix creates
                       new race conditions. This needs deep analysis."
efficiency-advocate:  "If it's a known pattern like lock ordering,
                       standard analysis is enough."
risk-assessor:        "This is a production outage. Service disruption.
                       Deep analysis minimum."
intensity-arbitrator: "Deep. Production risk outweighs speed."
```

The arbitrator picks one of four levels:

| Level | What runs | When |
|-------|-----------|------|
| **quick** | Codebase scan, Claude solo | Renames, typo fixes, trivial changes |
| **standard** | + stack detection, strategy debate, code review, 3-round cross-exam | Standard features, CRUD, typical bug fixes |
| **deep** | + pre-implementation research, compliance check | Production bugs, security-sensitive code, complex logic |
| **comprehensive** | + model benchmarking, Figma analysis, all 5 debates | Auth systems, payment flows, anything where failure is catastrophic |

---

## The 3-Round Cross-Examination

This is the core of Arena. Three AI model families don't just review your code independently. They **fight about it**.

### Round 1: Independent Review

All three review in parallel, unaware of each other:

```
Claude Agent Team          Codex CLI            Gemini CLI
  security-reviewer          (independent)        (independent)
  bug-detector
  architecture-reviewer
  performance-reviewer
  test-coverage-reviewer
  scale-advisor
  scope-reviewer
         |                       |                     |
         v                       v                     v
  findings-claude.json    findings-codex.json   findings-gemini.json
```

### Round 2: Cross-Examination

Each model reads the other two models' findings and attacks or supports them:

- **Codex** reads Claude + Gemini findings, judges each one: `AGREE`, `DISAGREE`, or `PARTIAL`
- **Gemini** reads Claude + Codex findings, same judgment
- **Claude reviewers** read Codex + Gemini findings, same judgment

Each judgment includes a `confidence_adjustment` (-30 to +30) and cited evidence from the code. Models can also flag **new observations** the others missed.

### Round 3: Defense

Challenges from Round 2 are routed back to the model that made the original finding. Each model must respond:

- **DEFEND** — "I stand by this. Here's additional evidence you missed."
- **CONCEDE** — "You're right, this was a false positive." (Finding withdrawn)
- **MODIFY** — "The issue is real but I had the severity wrong." (Adjusted)

### Consensus

The debate-arbitrator synthesizes all three rounds into a final confidence score:

```
final_confidence = original_score
  + round2_adjustments          # from cross-examination
  + cross_exam_boost            # 2+ agree: +15, 2+ disagree: -20
  + defense_boost               # defend: +10, concede: -25
  + consensus_bonus             # multi-model agreement bonus
```

Every finding in the final report includes a `cross_examination_trail` showing exactly what each model said across all three rounds.

### Why this design?

**Single-round review is fundamentally limited.** If Codex flags a "critical SQL injection" but Claude and Gemini both point to parameterized queries that prevent it, that's a false positive. Without cross-examination, you'd waste time investigating it. Conversely, if all three independently flag the same race condition, confidence goes up significantly.

**Concession is a strong signal.** When a model reviews evidence against its own finding and says "you're right, I was wrong," that's more reliable than any confidence score. It means the model genuinely processed the counter-evidence rather than stubbornly defending a position.

**Stateless CLIs can still debate.** Codex and Gemini are CLI tools, not conversational agents. Arena achieves multi-round debate by piping accumulated context through multiple CLI invocations. Round 2 input includes Round 1 findings from other models. Round 3 input includes Round 2 challenges. The Team Lead orchestrates the data flow.

---

## Design Philosophy

### Why agents debate instead of rules deciding

Early versions used keyword matching: if a request mentioned "auth" or "security," intensity went to `deep`. This broke constantly. A request like "fix the deadlock in production" has no security keywords, but it's a concurrency bug where a bad fix creates new race conditions. No keyword list handles that.

Agent debate solves this because agents can **reason about novel scenarios**. The risk-assessor understands that production outages are serious. The efficiency-advocate pushes back when thoroughness isn't justified. The arbitrator weighs both sides. This works for any request, in any domain, without maintaining a keyword dictionary.

### Why success criteria exist before code is written

Inspired by [Karpathy's Goal-Driven Execution principle](https://github.com/forrestchang/andrej-karpathy-skills). Before implementation starts, the strategy debate produces **concrete, testable success criteria**:

```
1. API returns 200 for valid input     → verify: curl with sample payload
2. Invalid tokens return 401           → verify: curl with expired token
3. Rate limiting at 100 req/min        → verify: load test with k6
```

After implementation, Phase 7 runs each verification and reports PASS/FAIL. No ambiguity about whether the task is done.

### Why a scope reviewer exists

Also from Karpathy (Surgical Changes). AI implementations tend to sprawl. You ask for a login endpoint and get reformatted imports, renamed variables, an abstraction layer nobody asked for, and a config option for a feature that doesn't exist yet. The scope-reviewer agent compares the actual diff against the strategy and flags:

- **SCOPE_VIOLATION** — files changed that weren't in the plan
- **DRIVE_BY_REFACTOR** — unrelated renames or reformatting
- **GOLD_PLATING** — features or abstractions nobody requested
- **UNNECESSARY_CHANGE** — cosmetic edits outside the task scope

If everything is in scope, the verdict is `CLEAN`.

### Why codebase analysis runs first

Before writing any code, Arena scans your project for naming conventions, directory patterns, import styles, error handling approaches, and existing utilities. Generated code matches what's already there. No `camelCase` in a `snake_case` project. No reinventing a utility that already exists in `src/utils/`.

---

## Pipeline Phases

```
Phase 0     Argument parsing + MCP dependency detection
Phase 0.1   Intensity Decision          ★ agents debate how thorough to be
Phase 0.5   Codebase Analysis             scan conventions, reusable code, structure
Phase 1     Stack Detection               framework, language, dependencies (cached 7 days)
Phase 2     Pre-Implementation Research  ★ agents debate what to investigate (deep+)
Phase 3     Compliance Check             ★ agents debate which rules apply (deep+)
Phase 4     Model Benchmarking            score each AI per category (comprehensive only, cached 14 days)
Phase 5     Figma Design Analysis         if Figma MCP is available
Phase 5.5   Implementation Strategy      ★ agents debate approach + define success criteria
Phase 6     Implementation + Code Review + Scope Review
Phase 6.10  3-Round Cross-Examination     Round 1 → Round 2 → Round 3 → Consensus
Phase 7     Final Report                  success criteria PASS/FAIL, scope verdict, cost breakdown
```

Five decision points (★) use adversarial debate instead of static rules.

---

## Configuration

### Project-level

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

### Global config

Place at `~/.claude/.ai-review-arena.json` for defaults across all projects.

### Environment variables

```bash
ARENA_INTENSITY=deep               # Force intensity (skips debate)
ARENA_SKIP_CACHE=true              # Bypass all caches
MULTI_REVIEW_INTENSITY=standard    # Default review intensity
MULTI_REVIEW_LANGUAGE=en           # Output language
```

### Bypassing Arena

```bash
# Skip Arena for one request
"fix this typo --no-arena"

# Force intensity (skips the debate)
"implement this --intensity deep"

# Direct slash command (bypasses auto-routing)
/multi-review --focus security
```

---

## Slash Commands

Typically unnecessary since the router handles everything, but available for direct use:

| Command | Description |
|---------|-------------|
| `/arena` | Full lifecycle pipeline |
| `/arena-research` | Pre-implementation research only |
| `/arena-stack` | Technology stack detection |
| `/multi-review` | Multi-AI code review only |
| `/multi-review-config` | Configure review settings |
| `/multi-review-status` | View review session status |

---

## Routes

Arena classifies your intent into one of six routes:

| Route | When | Pipeline |
|-------|------|----------|
| **Feature Build** | New functionality, complex tasks | Full pipeline with all applicable phases |
| **Research** | "How should I..." questions | Pre-implementation investigation |
| **Stack Analysis** | Understanding project tech | Framework/dependency detection |
| **Code Review** | Reviewing existing code or PRs | Multi-AI adversarial review |
| **Refactoring** | Improving existing code structure | Codebase analysis + code review |
| **Simple Change** | Small, obvious modifications | Quick intensity, Claude solo |

---

## How Arena Loads

The installer adds `@ARENA-ROUTER.md` to `~/.claude/CLAUDE.md`. Claude Code loads this file into every session's system prompt, making the router always active.

```
~/.claude/CLAUDE.md
  └── @ARENA-ROUTER.md       ← loaded into every session
        ├── Context Discovery   gather git, GitHub, Figma context
        ├── Route Selection     intent-based classification
        └── Pipeline Execution  load and execute command .md files
```

The router reads command files using the Read tool, not slash commands. This prevents infinite recursion.

When a request requires an MCP server (Figma, Playwright, Notion) that isn't installed, Arena detects it and offers to install it. If you decline, the pipeline continues without that capability.

---

## Project Structure

```
ai-review-arena/
├── ARENA-ROUTER.md             # Always-on routing logic
├── CLAUDE.md                   # Plugin development rules
├── install.sh / install.ps1    # Installers
├── uninstall.sh                # Uninstaller
│
├── commands/                   # Pipeline definitions (6 commands)
│   ├── arena.md                # Main pipeline (~2100 lines)
│   ├── arena-research.md       # Research pipeline
│   ├── arena-stack.md          # Stack detection
│   ├── multi-review.md         # Code review pipeline
│   ├── multi-review-config.md  # Config management
│   └── multi-review-status.md  # Status dashboard
│
├── agents/                     # Agent role definitions (10 agents)
│   ├── security-reviewer.md    # OWASP, auth, injection, data exposure
│   ├── bug-detector.md         # Logic errors, null handling, edge cases
│   ├── architecture-reviewer.md # SOLID, patterns, coupling
│   ├── performance-reviewer.md # Complexity, memory, I/O
│   ├── test-coverage-reviewer.md # Missing tests, test quality
│   ├── scale-advisor.md        # Concurrency, load, bottlenecks
│   ├── scope-reviewer.md       # Surgical change enforcement
│   ├── debate-arbitrator.md    # 3-round consensus synthesis
│   ├── research-coordinator.md # Pre-implementation research
│   ├── design-analyzer.md      # Figma design extraction
│   └── compliance-checker.md   # OWASP, WCAG, GDPR compliance
│
├── scripts/                    # Shell scripts (17 scripts)
│   ├── codex-review.sh         # Codex Round 1 review
│   ├── gemini-review.sh        # Gemini Round 1 review
│   ├── codex-cross-examine.sh  # Codex Round 2 & 3
│   ├── gemini-cross-examine.sh # Gemini Round 2 & 3
│   ├── orchestrate-review.sh   # Review orchestration
│   ├── aggregate-findings.sh   # Finding aggregation
│   ├── run-debate.sh           # Debate execution
│   ├── generate-report.sh      # Report generation
│   ├── detect-stack.sh         # Stack detection
│   ├── benchmark-models.sh     # Model benchmarking
│   ├── search-best-practices.sh # Best practice search
│   ├── search-guidelines.sh    # Compliance guideline search
│   ├── cache-manager.sh        # Cache management
│   ├── cost-estimator.sh       # Token cost estimation
│   └── utils.sh                # Shared utilities
│
├── config/
│   ├── default-config.json     # All default settings
│   ├── compliance-rules.json   # Feature-to-guideline mapping
│   ├── tech-queries.json       # Tech-to-search-query mapping (31 technologies)
│   ├── review-prompts/         # Structured prompts (9 templates)
│   └── benchmarks/             # Model benchmark test cases (4 categories)
│
└── cache/                      # Runtime cache (gitignored)
```

---

## Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | Full support | |
| Linux | Full support | |
| Windows (WSL) | Full support | |
| Windows (Git Bash) | Partial | Core features work, some scripts may need WSL |
| Windows (Native) | Commands only | Scripts require WSL (`wsl --install`) |

---

## Changelog

### v2.6.0

- **3-Round Cross-Examination** between Claude, Codex, and Gemini
  - Round 2: each model evaluates other models' findings (agree/disagree/partial)
  - Round 3: each model defends its findings against challenges (defend/concede/modify)
  - Consensus synthesis with `cross_examination_trail` per finding
- New: `codex-cross-examine.sh`, `gemini-cross-examine.sh`
- New prompt templates: `cross-examine.txt`, `defend.txt`

### v2.5.0

- **Success Criteria** defined before implementation, verified in final report (PASS/FAIL)
- **Scope Reviewer** agent enforces surgical changes
- Inspired by [Karpathy's coding principles](https://github.com/forrestchang/andrej-karpathy-skills)

### v2.4.0

- **Agent Teams adversarial debate** at 5 pipeline decision points
- Replaced static keyword rules with agent reasoning

### v2.3.0

- Pipeline loads command files via Read tool (fixes infinite recursion)

### v2.2.0

- Intent-based routing (replaces keyword matching)
- Language-agnostic (works in any language)
- Context Discovery phase

### v2.1.0

- Always-on routing
- Codebase Analysis (Phase 0.5)
- MCP Dependency Detection

### v2.0.0

- Full lifecycle orchestrator, research, stack detection, compliance, benchmarking

### v1.0.0

- Multi-AI adversarial code review with Claude + Codex + Gemini

## License

MIT
