# AI Review Arena

[English](README.md) | [한국어](README.ko.md)

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugin that makes AI models argue with each other about your code **and business content** before any of it ships.

## The Problem

You ask an AI to review your code. It finds 12 issues. But how many are real? Single-model reviews produce false positives that waste your time and real vulnerabilities that slip through because one model has blind spots. You have no way to know which findings to trust.

The same problem applies to business content. A pitch deck with wrong market numbers or overclaimed product capabilities can kill a fundraising round. A single reviewer won't catch everything.

## What Arena Does

Arena makes Claude, OpenAI Codex, and Google Gemini **independently review your code or business content, then cross-examine each other's findings in a 3-round adversarial debate**. Models challenge each other, defend their positions, or concede when they're wrong. What survives is a set of findings validated by multiple AI perspectives, each with a confidence score you can actually trust.

**Two pipelines, one system:**

- **Code Pipeline** (Routes A-F): Analyzes your codebase conventions, researches best practices, checks compliance, benchmarks models, debates implementation strategy, reviews code with 7-10 specialized agents, auto-fixes safe findings, and verifies with your test suite.
- **Business Pipeline** (Routes G-I): Extracts business context from your docs, researches market data, audits accuracy of claims, benchmarks models on business content, debates content strategy, reviews with 5 specialized agents + external CLIs, and auto-revises content.

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
| [Python 3](https://www.python.org/) + `openai>=2.22.0` | Optional | WebSocket debate acceleration (~40% faster) |

Without Codex or Gemini, Arena runs the full pipeline with Claude agents only. The fallback framework ensures graceful degradation at every level.

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
| "implement login API" | Full code pipeline: research, compliance, implement, 3-round review, auto-fix |
| "fix the production deadlock" | Agents debate severity, run deep analysis with cross-examination |
| "rename this variable" | Quick codebase scan for conventions, makes the change |
| "review PR #42 for security" | Multi-AI adversarial review focused on security |
| "how should I implement caching?" | Pre-implementation research with best practices |
| "write a business plan" | Full business pipeline: market research, accuracy audit, 5-agent review |
| "draft an investor pitch deck" | Business pipeline with deep accuracy + audience fit review |
| "respond to this investor question" | Communication pipeline, quick or standard intensity |

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

| Level | Code Pipeline | Business Pipeline |
|-------|-----------|------|
| **quick** | Codebase scan, Claude solo | Business context scan, Claude solo |
| **standard** | + stack detection, strategy debate, review, 3-round cross-exam, auto-fix | + market research, strategy debate, 5-agent review + external CLIs (cross-review), auto-revise |
| **deep** | + research, compliance, intensity checkpoint | + best practices research, accuracy audit, intensity checkpoint |
| **comprehensive** | + model benchmarking, Figma analysis, all debates | + business model benchmarking, benchmark-driven external CLI roles |

**Intensity can change mid-pipeline.** After research completes (Phase 2.9 / B2.9), Arena re-evaluates whether the decided intensity is still appropriate. If research reveals hidden complexity, it recommends upgrading. If the task turns out simpler, it recommends downgrading. Both directions are supported.

### Cost estimation before execution

After intensity is decided, Arena estimates cost and time before proceeding (Phase 0.2 / B0.2). You see the breakdown and can proceed, adjust intensity, or cancel. Below `$5.00` (configurable), it auto-proceeds. The estimator supports prompt cache discount configuration for accurate cost projections when using Claude's prefix caching.

---

## The 3-Round Cross-Examination

This is the core of Arena. Three AI model families don't just review independently. They **fight about it**.

### Round 1: Independent Review

All three review in parallel, unaware of each other:

```
Claude Agent Team          Codex CLI            Gemini CLI
  security-reviewer          (independent)        (independent)
  bug-detector
  architecture-reviewer
  performance-reviewer
  test-coverage-reviewer
  scope-reviewer
  + observability, dependency, api-contract, data-integrity,
    accessibility, configuration (at higher intensities)
         |                       |                     |
         v                       v                     v
  findings-claude.json    findings-codex.json   findings-gemini.json
```

For business reviews, the same structure applies with domain-specific reviewers (accuracy-evidence, audience-fit, communication-narrative, competitive-positioning, market-fit, and more at higher intensities) plus external CLIs. At `comprehensive` intensity, benchmark scores determine whether external models serve as Round 1 primary reviewers or Round 2 cross-reviewers.

### Round 2: Cross-Examination

Each model reads the other two models' findings and attacks or supports them:

- **Codex** reads Claude + Gemini findings, judges each one: `AGREE`, `DISAGREE`, or `PARTIAL`
- **Gemini** reads Claude + Codex findings, same judgment
- **Claude reviewers** read Codex + Gemini findings, same judgment

Each judgment includes a `confidence_adjustment` (-30 to +30) and cited evidence. Models can also flag **new observations** the others missed.

### Round 3: Defense

Challenges from Round 2 are routed back to the model that made the original finding. Each model must respond:

- **DEFEND** — "I stand by this. Here's additional evidence you missed."
- **CONCEDE** — "You're right, this was a false positive." (Finding withdrawn)
- **MODIFY** — "The issue is real but I had the severity wrong." (Adjusted)

External models that participated only as Round 2 cross-reviewers receive `implicit_defend` — their findings are maintained at current confidence since they can't be called again for defense.

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

**Stateless CLIs can still debate.** Codex and Gemini are CLI tools, not conversational agents. Arena achieves multi-round debate by piping accumulated context through multiple CLI invocations. Round 2 input includes Round 1 findings from other models. Round 3 input includes Round 2 challenges. The Team Lead orchestrates the data flow. Business review scripts support dual-mode (`--mode round1` for independent review, `--mode round2` for cross-review) with category-specific prompts.

---

## Auto-Fix Loop (Phase 6.5)

After the 3-round debate reaches consensus, Arena can automatically fix safe, high-confidence findings.

### Code Pipeline

Strict criteria — only fixes that meet ALL of:

| Criterion | Requirement |
|-----------|------------|
| Severity | `medium` or `low` only (never critical/high) |
| Confidence | >= 90% post-debate |
| Agreement | Unanimous or majority |
| Scope | <= 10 lines of code |
| Category | Only: naming, imports, unused code, types, null checks, docs |

Security vulnerabilities, logic errors, race conditions, architecture, and performance issues are **never** auto-fixed.

After applying fixes, Arena runs your test suite (auto-detected: `npm test`, `pytest`, `go test`, `cargo test`). If tests fail, **all fixes are reverted** via `git checkout -- .` and marked as "auto-fix-failed, manual review required."

### Business Pipeline

Business auto-fix is more aggressive: it revises content based on consensus findings (including critical/high severity), updates overclaimed capabilities, and fixes tone/audience mismatches.

---

## Stale Review Detection

Arena tracks code freshness using a git-hash-based invalidation system. When a review starts, the current `HEAD` commit hash is stored. Before findings are aggregated, the current `HEAD` is compared against the stored hash. If code changed during the review:

- All findings are marked with `stale: true`
- A warning banner appears in the report: **"Code changed after review — re-verify findings"**
- Findings are preserved (not discarded) for reference, but flagged for re-verification

This prevents acting on outdated findings when code changes land mid-review.

---

## Business Model Benchmarking

At `comprehensive` intensity, Arena benchmarks Claude, Codex, and Gemini on **12 planted-error business documents** (3 per category) to determine which model is best at catching each type of issue:

| Category | Test Cases | Planted Errors |
|----------|-----------|----------------|
| **accuracy** | pitch deck, business plan, investor update | Wrong market size, inflated growth, misquoted data |
| **audience** | pitch deck, blog post, internal memo | Wrong tone, missing metrics, leaked terms |
| **positioning** | competitor analysis, landing page, sales deck | False competitor claims, unsubstantiated "best in class" |
| **evidence** | business plan, market report, case study | Uncited stats, methodology flaws, survivorship bias |

Each model's findings are scored using **F1** (precision x recall), averaged across 3 tests per category. The highest-scoring model for each category becomes the **Round 1 primary reviewer** for that category. Lower-scoring models participate as Round 2 cross-reviewers.

At `standard` and `deep` intensity (no benchmarking data), external models always participate as Round 2 cross-reviewers.

---

## Design Philosophy

### Why agents debate instead of rules deciding

Early versions used keyword matching: if a request mentioned "auth" or "security," intensity went to `deep`. This broke constantly. A request like "fix the deadlock in production" has no security keywords, but it's a concurrency bug where a bad fix creates new race conditions. No keyword list handles that.

Agent debate solves this because agents can **reason about novel scenarios**. The risk-assessor understands that production outages are serious. The efficiency-advocate pushes back when thoroughness isn't justified. The arbitrator weighs both sides. This works for any request, in any domain, without maintaining a keyword dictionary.

### Why agents use positive framing

Agent specifications use positive criteria ("report ONLY when criteria met") instead of negative instructions ("don't report X"). This is based on the [AGENTS.md benchmark paper](https://arxiv.org/abs/2602.11988) which found that context files with negative instructions trigger a "pink elephant effect" — telling an agent NOT to do something paradoxically increases its attention on excluded patterns, reducing SWE-bench success by 0.5%, AgentBench by 2%, and increasing inference cost by 20-23%.

All 16 agents define a **Reporting Threshold** with 3 AND-criteria that must all be true for a finding to be reportable, plus a list of **Recognized Patterns** that confirm mitigation. For example, the security-reviewer reports only when a finding is Exploitable AND Unmitigated AND Production-reachable — and lists patterns like "parameterized queries" as confirmation that SQL injection is mitigated.

### Why external CLI prompts repeat core instructions

External CLI scripts (Codex, Gemini) use the [Duplicate Prompt Technique](https://arxiv.org/abs/2512.14982) — repeating the core review instruction at the end of the prompt. This improved non-reasoning LLM accuracy across 47/70 benchmarks with 0 losses. Gemini Flash-Lite accuracy improved from 21.33% to 97.33% on one benchmark. The technique has no effect (positive or negative) on reasoning-mode models, so it's applied only to external CLIs.

### Why success criteria exist before code is written

Inspired by [Karpathy's Goal-Driven Execution principle](https://github.com/forrestchang/andrej-karpathy-skills). Before implementation starts, the strategy debate produces **concrete, testable success criteria**:

```
1. API returns 200 for valid input     -> verify: curl with sample payload
2. Invalid tokens return 401           -> verify: curl with expired token
3. Rate limiting at 100 req/min        -> verify: load test with k6
```

After implementation, Phase 7 runs each verification and reports PASS/FAIL. No ambiguity about whether the task is done.

### Why a scope reviewer exists

Also from Karpathy (Surgical Changes). AI implementations tend to sprawl. You ask for a login endpoint and get reformatted imports, renamed variables, an abstraction layer nobody asked for, and a config option for a feature that doesn't exist yet. The scope-reviewer agent compares the actual diff against the strategy and flags:

- **SCOPE_VIOLATION** -- files changed that weren't in the plan
- **DRIVE_BY_REFACTOR** -- unrelated renames or reformatting
- **GOLD_PLATING** -- features or abstractions nobody requested
- **UNNECESSARY_CHANGE** -- cosmetic edits outside the task scope

If everything is in scope, the verdict is `CLEAN`.

### Why codebase analysis runs first

Before writing any code, Arena scans your project for naming conventions, directory patterns, import styles, error handling approaches, and existing utilities. Generated code matches what's already there. No `camelCase` in a `snake_case` project. No reinventing a utility that already exists in `src/utils/`.

### Why fallback exists at every level

External CLIs can timeout. Agent Teams can fail to spawn. Research queries can return nothing. Arena handles all of this with a structured fallback framework (6 levels for code, 5 for business) that degrades gracefully. If Codex times out, Claude handles it alone. If Agent Teams fail, Task subagents run without debate. If everything fails, Claude does an inline analysis. The final report always shows which fallback level was active and what was skipped.

---

## Pipeline Phases

### Code Pipeline

```
Phase 0     Argument parsing + MCP dependency detection
Phase 0.1   Intensity Decision          * agents debate how thorough to be
Phase 0.2   Cost & Time Estimation        user can cancel or adjust before execution
Phase 0.5   Codebase Analysis             scan conventions, reusable code, structure
Phase 1     Stack Detection               framework, language, dependencies (cached 7 days)
Phase 2     Pre-Implementation Research  * agents debate what to investigate (deep+)
Phase 2.9   Intensity Checkpoint          bidirectional: upgrade or downgrade based on findings
Phase 3     Compliance Check             * agents debate which rules apply (deep+)
Phase 4     Model Benchmarking            score each AI per category (comprehensive, cached 14 days)
Phase 5     Figma Design Analysis         if Figma MCP is available
Phase 5.5   Implementation Strategy      * agents debate approach + define success criteria
Phase 6     Implementation + Code Review + 3-Round Cross-Examination
Phase 6.5   Auto-Fix Loop                 fix safe findings, verify with tests, revert on failure
Phase 7     Final Report + Feedback        success criteria PASS/FAIL, scope verdict, cost breakdown
```

Seven decision points (*) use adversarial debate instead of static rules.

### Business Pipeline

```
Phase B0     Argument parsing + MCP dependency detection
Phase B0.1   Intensity Decision           * agents debate (audience exposure, brand risk, accuracy)
Phase B0.2   Cost & Time Estimation         user can cancel or adjust before execution
Phase B0.5   Business Context Analysis      extract from docs: product, value props, brand voice
Phase B1     Market/Industry Context        WebSearch for market data, competitors, trends
Phase B2     Best Practices Research       * agents debate research direction (deep+)
Phase B2.9   Intensity Checkpoint           bidirectional based on market/research findings
Phase B3     Accuracy & Consistency Audit  * agents debate verification scope (deep+)
Phase B4     Business Model Benchmarking    12 planted-error test cases, F1 scoring (comprehensive)
Phase B5.5   Content Strategy Debate       * agents debate messaging, audience fit, factual accuracy
Phase B6     5-Agent Review + External CLIs + 3-Round Cross-Examination
Phase B6.5   Apply Findings                 auto-revise content based on consensus
Phase B7     Final Report + Feedback        quality scorecard, model attribution, cost breakdown
```

---

## Routes

Arena classifies your intent into one of nine routes:

### Code Routes (A-F)

| Route | When | Pipeline |
|-------|------|----------|
| **A: Feature Build** | New functionality, complex tasks | Full code pipeline with all applicable phases |
| **B: Research** | "How should I..." questions | Pre-implementation investigation |
| **C: Stack Analysis** | Understanding project tech | Framework/dependency detection |
| **D: Code Review** | Reviewing existing code or PRs | Multi-AI adversarial review |
| **E: Refactoring** | Improving existing code structure | Codebase analysis + code review |
| **F: Simple Change** | Small, obvious modifications | Quick intensity, Claude solo |

### Business Routes (G-I)

| Route | When | Pipeline |
|-------|------|----------|
| **G: Business Content** | Business plans, pitch decks, proposals, marketing copy | Full business pipeline |
| **H: Business Analysis** | Market research, competitive analysis, SWOT, strategy | Business pipeline with strategy emphasis |
| **I: Communication** | Investor Q&A, customer emails, presentation scripts | Business pipeline with audience/tone emphasis |

### Multi-Route Requests

Requests that span both pipelines are decomposed and run sequentially with **context forwarding**:

```
"Write a pitch deck and build a landing page based on it"

  Route G (business plan) -> Route A (landing page)
                          ^
                          |
              context forwarding: key_themes, tone, audience
              (tiered limits: 2K summary, 15K content, 1K metadata, 20K total)
```

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

### Config merge order

Settings are deep-merged in priority order: **default** (built-in) → **global** (`~/.claude/.ai-review-arena.json`) → **project** (`.ai-review-arena.json`). Project-level values override global, which overrides defaults.

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
| `/arena` | Full code lifecycle pipeline |
| `/arena-business` | Full business lifecycle pipeline |
| `/arena-research` | Pre-implementation research only |
| `/arena-stack` | Technology stack detection |
| `/multi-review` | Multi-AI code review only |
| `/multi-review-config` | Configure review settings |
| `/multi-review-status` | View review session status |

---

## Fallback Framework

Arena never crashes the pipeline. If something fails, it degrades gracefully:

### Code Pipeline (6 levels)

| Level | Trigger | Action |
|-------|---------|--------|
| 0 | None | Full operation |
| 1 | Benchmark failure | Use default role assignments |
| 2 | Research failure | Skip context enrichment |
| 3 | Agent Teams failure | Use Task subagents (no debate) |
| 4 | External CLI failure | Claude-only review |
| 5 | All failure | Inline Claude solo analysis |

### Business Pipeline (5 levels)

| Level | Trigger | Action |
|-------|---------|--------|
| 0 | None | Full operation |
| 1 | Research failure | Skip market context |
| 1.5 | Benchmark failure | Use default role assignments |
| 2 | Agent Teams failure | Use Task subagents (no debate) |
| 2.5 | External CLI failure | Claude-only review |
| 3 | All failure | Claude solo inline analysis |

The final report always shows which fallback level was active and what was skipped.

---

## Feedback Loop

After each review session, Arena optionally collects feedback on findings (useful / not useful / false positive). Feedback is stored in JSONL format and used for two purposes:

1. **Accuracy reports** — per-model, per-category quality tracking:

```
Model Quality Report (last 30 days):
| Model  | Useful | Not Useful | False Positive | Accuracy |
|--------|--------|------------|----------------|----------|
| Claude | 45     | 8          | 3              | 80.4%    |
| Codex  | 38     | 12         | 5              | 69.1%    |
| Gemini | 41     | 10         | 4              | 74.5%    |
```

2. **Routing optimization** — combined score (60% feedback accuracy + 40% benchmark F1) determines which model reviews which category in future sessions.

---

## Context Density

Arena provides each review agent with context tailored to its role. Instead of sending the full codebase to every agent, it filters by role-specific patterns:

| Role | Prioritized Patterns |
|------|---------------------|
| security | `auth`, `login`, `password`, `token`, `session`, `csrf`, `inject`, `eval` |
| bugs | `catch`, `throw`, `error`, `null`, `undefined`, `async`, `await`, `race` |
| performance | `for`, `while`, `map`, `query`, `select`, `cache`, `Promise.all`, `stream` |
| architecture | `import`, `export`, `class`, `interface`, `extends`, `module`, `provider` |
| testing | `describe`, `it`, `test`, `expect`, `mock`, `jest`, `vitest`, `pytest` |

Each agent receives up to 8,000 tokens of role-relevant context (configurable). Files under 200 lines bypass filtering and are sent in full.

---

## Memory Tiers

Arena maintains a 4-tier memory architecture for learning across review sessions:

| Tier | Scope | TTL | Tracks |
|------|-------|-----|--------|
| **Working** | Current session | Session | Pipeline variables, current context |
| **Short-term** | Per project | 7 days | Recurring findings, recent review patterns |
| **Long-term** | Cross-session | 90 days | Model accuracy by category, feedback trends |
| **Permanent** | Per project | Never | Team coding standards, architecture decisions |

Short-term and long-term tiers inform routing decisions and agent context. Permanent tier is manually curated.

---

## How Arena Loads

The installer adds `@ARENA-ROUTER.md` to `~/.claude/CLAUDE.md`. Claude Code loads this file into every session's system prompt, making the router always active.

```
~/.claude/CLAUDE.md
  +-- @ARENA-ROUTER.md       <- loaded into every session
        +-- Context Discovery   gather git, GitHub, Figma context
        +-- Route Selection     intent-based classification (9 routes)
        +-- Pipeline Execution  load and execute command .md files
```

The router reads command files using the Read tool, not slash commands. This prevents infinite recursion.

When a request requires an MCP server (Figma, Playwright, Notion) that isn't installed, Arena detects it and offers to install it. If you decline, the pipeline continues without that capability.

---

## Project Structure

```
ai-review-arena/
+-- ARENA-ROUTER.md              # Always-on routing logic (9 routes, context forwarding)
+-- CLAUDE.md                    # Plugin development rules
+-- install.sh / install.ps1     # Installers
+-- uninstall.sh                 # Uninstaller
+-- requirements.txt             # Python dependencies (openai>=2.22.0)
|
+-- hooks/                       # Auto-review hooks
|   +-- hooks.json               # Claude Code PostToolUse hook
|   +-- gemini-hooks.json        # Gemini CLI AfterTool hook adapter config
|
+-- commands/                    # Pipeline definitions (7 commands)
|   +-- arena.md                 # Code pipeline (~2500 lines)
|   +-- arena-business.md        # Business pipeline (~2900 lines)
|   +-- arena-research.md        # Research pipeline
|   +-- arena-stack.md           # Stack detection
|   +-- multi-review.md          # Code review pipeline
|   +-- multi-review-config.md   # Config management
|   +-- multi-review-status.md   # Status dashboard
|
+-- agents/                      # Agent role definitions (27 agents)
|   +-- security-reviewer.md     # OWASP, auth, injection, data exposure
|   +-- bug-detector.md          # Logic errors, null handling, error handling, concurrency
|   +-- architecture-reviewer.md # SOLID, patterns, coupling
|   +-- performance-reviewer.md  # Complexity, memory, I/O, failover, scale
|   +-- test-coverage-reviewer.md # Missing tests, test quality
|   +-- scope-reviewer.md        # Change scope validation
|   +-- dependency-reviewer.md   # Dependency health, versioning
|   +-- api-contract-reviewer.md # API schema, versioning, breaking changes
|   +-- observability-reviewer.md # Logging, tracing, monitoring
|   +-- data-integrity-reviewer.md # Data validation, migration safety
|   +-- accessibility-reviewer.md # WCAG, ARIA, keyboard navigation
|   +-- configuration-reviewer.md # Environment, secrets, IaC
|   +-- debate-arbitrator.md     # Code review 3-round consensus
|   +-- research-coordinator.md  # Pre-implementation research
|   +-- design-analyzer.md       # Figma design extraction
|   +-- compliance-checker.md    # OWASP, WCAG, GDPR compliance
|   +-- accuracy-evidence-reviewer.md      # Business: factual accuracy + data evidence
|   +-- audience-fit-reviewer.md           # Business: audience match
|   +-- competitive-positioning-reviewer.md # Business: market positioning
|   +-- communication-narrative-reviewer.md # Business: writing quality + narrative
|   +-- market-fit-reviewer.md             # Business: product-market fit, TAM/SAM/SOM
|   +-- financial-credibility-reviewer.md  # Business: financial model credibility
|   +-- legal-compliance-reviewer.md       # Business: legal/regulatory compliance
|   +-- localization-reviewer.md           # Business: multilingual/cultural adaptation
|   +-- investor-readiness-reviewer.md     # Business: investor readiness
|   +-- conversion-impact-reviewer.md      # Business: conversion optimization
|   +-- business-debate-arbitrator.md      # Business: 3-round consensus + external model handling
|
+-- scripts/                     # Shell/Python scripts (24 scripts)
|   +-- codex-review.sh          # Codex Round 1 code review
|   +-- gemini-review.sh         # Gemini Round 1 code review
|   +-- codex-cross-examine.sh   # Codex Round 2 & 3 (code)
|   +-- gemini-cross-examine.sh  # Gemini Round 2 & 3 (code)
|   +-- codex-business-review.sh # Codex business review (dual-mode: round1/round2)
|   +-- gemini-business-review.sh # Gemini business review (dual-mode: round1/round2)
|   +-- benchmark-models.sh      # Code model benchmarking
|   +-- benchmark-business-models.sh # Business model benchmarking (12 test cases, F1)
|   +-- evaluate-pipeline.sh     # Pipeline evaluation (precision/recall/F1)
|   +-- feedback-tracker.sh      # Review quality feedback recording + reporting
|   +-- orchestrate-review.sh    # Review orchestration + stale review detection
|   +-- aggregate-findings.sh    # Finding aggregation + stale marking
|   +-- run-debate.sh            # Debate execution
|   +-- generate-report.sh       # Report generation + stale warning banner
|   +-- detect-stack.sh          # Stack detection
|   +-- search-best-practices.sh # Best practice search
|   +-- search-guidelines.sh     # Compliance guideline search
|   +-- cache-manager.sh         # Cache management
|   +-- cost-estimator.sh        # Token cost estimation + cache discount
|   +-- utils.sh                 # Shared utilities
|   +-- openai-ws-debate.py       # WebSocket debate client (Responses API)
|   +-- gemini-hook-adapter.sh   # Gemini hook → Arena review adapter
|   +-- setup-arena.sh           # Arena setup
|   +-- setup.sh                 # General setup
|
+-- shared-phases/               # Common phase definitions (shared by code + business)
|   +-- intensity-decision.md    # Phase 0.1/B0.1: Agent Teams intensity debate
|   +-- cost-estimation.md       # Phase 0.2/B0.2: Cost & time estimation
|   +-- feedback-routing.md      # Feedback-based model-category role assignment
|
+-- config/
|   +-- default-config.json      # All settings (models, review, debate, arena, cache,
|   |                            #   benchmarks, compliance, routing, fallback, cost,
|   |                            #   feedback, context forwarding, context density,
|   |                            #   memory tiers, pipeline evaluation)
|   +-- compliance-rules.json    # Feature-to-guideline mapping
|   +-- tech-queries.json        # Tech-to-search-query mapping (31 technologies)
|   +-- review-prompts/          # Structured prompts (9 templates)
|   +-- schemas/                 # Codex structured output JSON schemas (5 schemas)
|   |   +-- codex-review.json, codex-cross-examine.json, codex-defend.json
|   |   +-- codex-business-review.json, codex-business-cross-review.json
|   +-- codex-agents/            # Codex multi-agent TOML configs (5 agents)
|   |   +-- security.toml, bugs.toml, performance.toml
|   |   +-- architecture.toml, testing.toml
|   +-- benchmarks/              # Model benchmark test cases
|       +-- security-test-01.json          # Code: security
|       +-- bugs-test-01.json              # Code: bugs
|       +-- architecture-test-01.json      # Code: architecture
|       +-- performance-test-01.json       # Code: performance
|       +-- business-accuracy-test-{01,02,03}.json    # Business: accuracy (3 tests)
|       +-- business-audience-test-{01,02,03}.json    # Business: audience (3 tests)
|       +-- business-positioning-test-{01,02,03}.json # Business: positioning (3 tests)
|       +-- business-evidence-test-{01,02,03}.json    # Business: evidence (3 tests)
|
+-- docs/                        # Documentation
|   +-- TODO-external-integrations.md  # Research-backed TODO items
|
+-- cache/                       # Runtime cache (gitignored)
    +-- feedback/                # Feedback JSONL storage
    +-- short-term/              # Short-term memory (7-day TTL)
    +-- long-term/               # Long-term memory (90-day TTL)
    +-- permanent/               # Permanent memory (manually curated)
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

### v3.2.0

- **Commit/PR Safety Protocol**: Mandatory review gate + user confirmation before `git commit` or `gh pr create`
  - Commits: diff review for secrets, debug code, unintended files → AskUserQuestion confirmation
  - PRs: full Route D code review at standard+ intensity → review findings summary → AskUserQuestion confirmation
- **Phase 0.1-Pre: Quick Intensity Pre-Filter**: Rule-based pre-filter skips 4-agent intensity debate for obvious quick cases (rename, explanation, test execution), saving ~$0.50+ and ~30s per trivial request
- **Core Rule Enforcement**: Explicit exempt/non-exempt lists replace vague "every request" rule — code explanations, commits, debugging all MUST route through pipeline
- **Config 3-Level Deep Merge**: `load_config()` now properly merges default → global → project configs via `jq -s` deep merge (previously only returned first found file)
- **Phase-Based Cost Estimation**: Rewrote `cost-estimator.sh` with per-phase token/cost tables, `--intensity`/`--pipeline`/`--lines`/`--json` params, scales by agent count and input size
- **Shared Phases**: Extracted common phase definitions (`shared-phases/`) for intensity debate, cost estimation, and feedback routing — shared by code and business pipelines
- **Feedback-Based Routing**: `feedback-tracker.sh recommend` computes combined score (60% feedback accuracy + 40% benchmark F1) for model-category role assignment in Phase 6/B6
- **Benchmark Negation Detection**: `keyword_match_positive()` prevents false positives from negated mentions ("no evidence of SQL injection" no longer counts as finding SQL injection)
- **Benchmark Multi-Format Support**: `check_ground_truth()` handles array-of-objects, single-object, and flat-array ground truth formats
- **Cache Session Cleanup**: `cache-manager.sh cleanup-sessions` removes stale `/tmp/ai-review-arena*` directories and merged config temp files
- **Hash Collision Resistance**: `project_hash()` extended from 48-bit (12 chars) to 80-bit (20 chars)
- **i18n Cleanup**: All prompts, examples, and metadata in routing/command files converted to English; Korean retained only in intentional i18n output templates
- **Context Density Filtering**: Role-based context filtering provides each agent with relevant code patterns only, reducing noise and token cost (8,000 token budget per agent)
- **Memory Tiers**: 4-tier memory architecture (working/short-term/long-term/permanent) for cross-session learning
- **Pipeline Evaluation**: Precision/recall/F1 metrics with LLM-as-Judge scoring and position bias mitigation
- **Agent Hardening**: Error Recovery Protocol added to all 16 agents (retry → partial submit → team lead notification)
- **Positive Framing** ([arxiv 2602.11988](https://arxiv.org/abs/2602.11988)): All 16 agent specs reframed from negative ("When NOT to Report") to positive ("Reporting Threshold") to avoid the pink elephant effect
- **Duplicate Prompt Technique** ([arxiv 2512.14982](https://arxiv.org/abs/2512.14982)): Core review instructions repeated in external CLI scripts for improved non-reasoning LLM accuracy
- **Stale Review Detection**: Git-hash-based review freshness check prevents acting on outdated findings when code changes mid-review
- **Prompt Cache-Aware Cost Estimation**: `prompt_cache_discount` config for accurate cost projections with Claude's prefix caching
- **Codex Structured Output**: `--output-schema` + `-o` flags for guaranteed-valid JSON output, eliminating 4-layer JSON extraction fallback. 5 JSON schemas for code review, cross-examine, defend, business review, and business cross-review. Controlled by `models.codex.structured_output` (default: `true`)
- **Codex Multi-Agent Sub-Agents**: 5 TOML agent configs (security, bugs, performance, architecture, testing) for Codex's experimental multi-agent feature. Dual-gated: config flag AND runtime feature check. Controlled by `models.codex.multi_agent.enabled` (default: `true`). Automatic fallback to single-agent path if feature unavailable
- **OpenAI WebSocket Debate Acceleration**: Persistent WebSocket connection (`wss://api.openai.com/v1/responses`) for ~40% faster debate rounds via `previous_response_id` chaining. Python client (`scripts/openai-ws-debate.py`) with automatic HTTP fallback. Requires `pip install openai>=2.22.0`. Controlled by `websocket.enabled` (default: `true`)
- **Gemini CLI Hooks Cross-Compatibility**: Native Gemini CLI AfterTool hook adapter (`scripts/gemini-hook-adapter.sh`) translates Gemini hook events to Arena's review pipeline. Installer/uninstaller updated for Gemini settings. Controlled by `gemini_hooks.enabled` (default: `true`)

### v3.1.0

- **Business Pipeline** with Codex/Gemini external CLI integration
  - Dual-mode scripts: `codex-business-review.sh` and `gemini-business-review.sh` (`--mode round1` for primary review, `--mode round2` for cross-review)
  - Intensity-dependent roles: cross-reviewer at standard/deep, benchmark-driven primary at comprehensive
- **Business Model Benchmarking** (Phase B4): 12 planted-error test cases (3 per category), F1 scoring, benchmark-driven role assignment
- **Fallback Framework**: Structured 6-level (code) / 5-level (business) graceful degradation with state tracking and report integration
- **Cost & Time Estimation** (Phase 0.2 / B0.2): Pre-execution cost breakdown with proceed/adjust/cancel
- **Code Auto-Fix Loop** (Phase 6.5): Auto-fixes safe, high-confidence findings with test verification and full revert on failure
- **Intensity Checkpoints** (Phase 2.9 / B2.9): Bidirectional mid-pipeline adjustment (upgrade or downgrade) based on research findings
- **Feedback Loop**: JSONL-based feedback tracking with per-model/per-category accuracy reports (`feedback-tracker.sh`)
- **Context Forwarding**: Multi-route requests pass context between pipelines with tiered token limits (20K total hard limit)
- Updated `business-debate-arbitrator.md` with external model handling (equal weight, implicit_defend, confidence normalization)

### v2.7.0

- **Business Content Lifecycle Orchestrator** (`arena-business.md`)
  - Routes G (content), H (strategy), I (communication)
  - 5 business reviewer agents + business-debate-arbitrator
  - Phases B0-B7: context extraction, market research, best practices, accuracy audit, strategy debate, review, report
- Updated ARENA-ROUTER.md with 9 routes (A-F code, G-I business)

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
