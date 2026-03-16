<p align="center">
  <h1 align="center">AI Review Arena</h1>
  <p align="center">
    <strong>Make AI models argue with each other before your code ships.</strong>
  </p>
  <p align="center">
    <a href="README.md">English</a> | <a href="README.ko.md">한국어</a>
  </p>
</p>

---

## The Idea

You ask one AI to review your code. It finds 12 issues. But which ones are real?

**Arena's answer: make three AIs fight about it.**

```
┌──────────────────────────────────────────────────────────┐
│                    SINGLE AI REVIEW                       │
│                                                           │
│   You  ───►  One AI  ───►  "12 issues found"             │
│                                                           │
│   But... which are real? You have to check all 12.        │
└──────────────────────────────────────────────────────────┘

                        vs.

┌──────────────────────────────────────────────────────────┐
│                    ARENA REVIEW                           │
│                                                           │
│   You  ───►  Claude  ───┐                                │
│              Codex   ───┼──►  They argue  ───►  5 real   │
│              Gemini  ───┘    with each other    issues    │
│                                                           │
│   3 AIs independently review, then cross-examine          │
│   each other's findings. Fake issues get eliminated.      │
│   Real issues get confirmed with higher confidence.       │
└──────────────────────────────────────────────────────────┘
```

---

## How The Fight Works

Three AI families review your code separately, then challenge each other in 3 rounds:

```
 ROUND 1                    ROUND 2                    ROUND 3
 Independent Review         Cross-Examination           Defense
 ──────────────────         ─────────────────           ───────

 Claude: "I found           Codex: "Claude's            Claude: "No, look
  a SQL injection            finding #3 is a             at line 42 — user
  at line 42"                false positive,             input goes directly
                             this input is               into the query
 Codex: "I found             already sanitized"          without escaping.
  a race condition                                       Here's proof..."
  at line 89"               Gemini: "Actually,
                             I agree with                   ───►  CONFIRMED
 Gemini: "I found            Claude — the                        confidence: 92%
  unused imports             sanitization
  at line 7"                 misses Unicode"                ───►  DISMISSED
                                                                 (false positive)
```

**What survives this fight = what you should actually fix.**

---

## But Wait — It Does Way More Than Code Review

Arena isn't just a reviewer. It's a **full lifecycle system** that handles everything from "I have an idea" to "ship it."

```
    "Build an OAuth login"
              │
              ▼
    ┌─────────────────────────────────┐
    │       ARENA PIPELINE            │
    │                                 │
    │  1. Analyze your codebase       │  ← learns your coding style
    │  2. Research best practices     │  ← searches the web
    │  3. Check compliance rules      │  ← platform guidelines
    │  4. Debate implementation       │  ← AIs argue about HOW to build it
    │  5. Build it                    │
    │  6. Review with 3 AI teams      │  ← the fight described above
    │  7. Auto-fix safe issues        │  ← fixes trivial things automatically
    │  8. Generate tests              │  ← writes regression tests
    │  9. Final report                │  ← pass/fail verification
    │                                 │
    └─────────────────────────────────┘
```

And it works for **three domains**, not just code:

| | Code | Business | Documentation |
|---|---|---|---|
| **Routes** | A-F | G-I | J-K |
| **Example** | "Build OAuth" | "Write pitch deck" | "Review API docs" |
| **Reviewers** | 12 specialized agents | 10 specialized agents | 6 specialized agents |
| **Special** | Threat modeling, static analysis | Red team, quant validation | Code-doc drift detection |

---

## It Turns On Automatically

You don't call Arena. **Arena calls itself.**

Every request you make to Claude Code gets routed through Arena automatically:

```
You say:                          Arena does:
─────────────────────────────     ─────────────────────────────
"Build a login page"          →   Route A: Full lifecycle
"Fix this typo"               →   Route F: Quick fix (instant)
"Review this PR"              →   Route D: Multi-AI review
"Write a pitch deck"          →   Route G: Business pipeline
"Are the docs accurate?"      →   Route J: Doc review pipeline
"Refactor this module"        →   Route E: Refactoring pipeline
"Research auth best practices"→   Route B: Deep research
```

Simple stuff gets done in seconds. Complex stuff activates the full pipeline with debates.

---

## How Intensity Works

Arena decides how hard to think using a **4-agent debate**:

```
                    "Implement payment processing"
                               │
                 ┌─────────────┼─────────────┐
                 │             │             │
                 ▼             ▼             ▼
          ┌───────────┐ ┌───────────┐ ┌───────────┐
          │ "This is  │ │ "Standard │ │ "Payment = │
          │  complex, │ │  is fine, │ │  HIGH risk, │
          │  needs    │ │  it's a   │ │  data loss  │
          │  deep     │ │  known    │ │  possible"  │
          │  review"  │ │  pattern" │ │             │
          └─────┬─────┘ └─────┬─────┘ └─────┬─────┘
          Intensity     Efficiency     Risk
          Advocate      Advocate       Assessor
                 │             │             │
                 └─────────────┼─────────────┘
                               ▼
                    ┌─────────────────┐
                    │   Arbitrator:   │
                    │  "DEEP — this   │
                    │   touches money"│
                    └─────────────────┘
```

| Level | When | What Happens |
|-------|------|-------------|
| **Quick** | Typos, renames, explanations | Claude fixes it solo, no debate |
| **Standard** | Normal features, single-file | Full review + debate + auto-fix |
| **Deep** | Multi-file, auth, APIs | + Research + compliance + threat modeling |
| **Comprehensive** | Architecture, payment, security | + Benchmarking + full agent roster |

---

## The Phase Map

Here's every phase in the code pipeline, and when it runs:

```
                    quick    standard    deep    comprehensive
                    ─────    ────────    ────    ─────────────
Phase 0   Config     ●          ●        ●           ●
Phase 0.1 Intensity  ●          ●        ●           ●
Phase 0.2 Cost Est            ●        ●           ●
Phase 0.5 Codebase   ●          ●        ●           ●
Phase 1   Stack               ●        ●           ●
Phase 2   Research                      ●           ●
Phase 3   Compliance                    ●           ●
Phase 4   Benchmark                                 ●
Phase 5   Figma               ●        ●           ●
Phase 5.5  Strategy            ●        ●           ●
Phase 5.5.5 Spec Gate          ●        ●           ●
Phase 5.8 Static Analysis      ●        ●           ●
Phase 5.9 Threat Model                  ●           ●
Phase 6   Team Review          ●        ●           ●
Phase 6.5 Auto-Fix            ●        ●           ●
Phase 6.6 Test Gen            ●        ●           ●
Phase 6.7 Visual Verify        ●        ●           ●
Phase 7   Report     ●          ●        ●           ●

"Quick" = Claude solo. No team, no debate. Instant.
"Standard+" = Full Agent Team with 3-round cross-examination.
```

---

## The Review Team (Phase 6 Detail)

This is where the magic happens. Here's exactly how the multi-AI review works:

```
┌──────────────────────────────────────────────────────────────────────┐
│                                                                      │
│  STEP 1: Spawn debate-arbitrator first (Early Join)                  │
│  ═══════════════════════════════════════════════════                  │
│  It monitors everything from the start.                              │
│                                                                      │
│  STEP 2: Spawn 6-12 Claude reviewers simultaneously                  │
│  ══════════════════════════════════════════════════                   │
│                                                                      │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐               │
│  │ Security │ │   Bug    │ │  Perf    │ │  Arch    │  ... more      │
│  │ Reviewer │ │ Detector │ │ Reviewer │ │ Reviewer │  reviewers     │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘               │
│       │             │             │             │                     │
│       │    ┌────────┼─────────────┼─────────────┘                    │
│       │    │  They share SIGNALS in real-time:                       │
│       │    │                                                         │
│       │    │  Security→Bug: "Auth bypass at line 45,                │
│       │    │                 check for race conditions"              │
│       │    │  Perf→Security: "Unbounded query at line 89,           │
│       │    │                  possible DoS vector"                   │
│       │    └─────────────────────────────────────────                │
│       │                                                              │
│       └──────────► debate-arbitrator tracks all signals              │
│                    de-duplicates, finds cross-domain patterns        │
│                                                                      │
│  STEP 3: Run Codex & Gemini CLI in parallel                          │
│  ══════════════════════════════════════════                           │
│  External models review independently via shell scripts              │
│                                                                      │
│  STEP 4: Aggregate → 3-Round Cross-Examination → Consensus          │
│  ════════════════════════════════════════════════════════             │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

### Agent Roster

**Code Review (12 agents)**

| Agent | What It Looks For |
|-------|-------------------|
| security-reviewer | SQL injection, XSS, auth flaws, OWASP Top 10 |
| bug-detector | Logic errors, null pointers, race conditions |
| architecture-reviewer | SOLID violations, bad coupling, design smells |
| performance-reviewer | O(n^2) loops, memory leaks, N+1 queries |
| test-coverage-reviewer | Missing tests, untested edge cases |
| scope-reviewer | Drive-by refactors, unrelated changes |
| dependency-reviewer | Risky/outdated dependencies |
| api-contract-reviewer | Breaking API changes |
| observability-reviewer | Missing logs, metrics, traces |
| data-integrity-reviewer | Data validation gaps |
| accessibility-reviewer | A11y compliance |
| configuration-reviewer | Hardcoded configs, env issues |

**Business Review (10 agents)** — for pitch decks, proposals, marketing

| Agent | What It Looks For |
|-------|-------------------|
| accuracy-evidence-reviewer | Wrong numbers, unsupported claims |
| audience-fit-reviewer | Wrong tone for target audience |
| competitive-positioning-reviewer | Weak market positioning |
| financial-credibility-reviewer | Unrealistic projections |
| legal-compliance-reviewer | Regulatory issues |
| + 5 more | market-fit, conversion, localization, narrative, investor-readiness |

**Documentation Review (6 agents)** — for README, API docs, tutorials

| Agent | What It Looks For |
|-------|-------------------|
| doc-accuracy-reviewer | Code says X, docs say Y |
| doc-completeness-reviewer | Missing sections |
| doc-freshness-reviewer | Outdated content |
| doc-readability-reviewer | Confusing writing |
| doc-example-reviewer | Broken code examples |
| doc-consistency-reviewer | Contradictions across docs |

---

## Safety Systems

### High-Risk Pattern Detection

Arena automatically detects dangerous file patterns and escalates:

```
You edit auth/login.ts
         │
         ▼
  ┌──────────────────┐
  │ Escalation Scan   │   Matches: auth_security pattern
  │ (0 LLM cost,     │
  │  pure grep)       │
  └────────┬─────────┘
           │
  ┌────────▼─────────┐
  │ ● Intensity → deep (minimum)
  │ ● Auto-fix BLOCKED for this file
  │ ● Human approval may be required
  └──────────────────┘

Patterns: auth, payment, crypto, DB schema, dependencies, infrastructure
```

### Write Scope

Auto-fix can only touch files within the task scope:

```
Task: "Fix bug in utils/dates.ts"

  ✅ Can auto-fix: utils/dates.ts, tests/dates.test.ts
  ❌ Cannot auto-fix: src/auth/login.ts (out of scope → asks you first)
```

### Verification Contract

The final report isn't just "here are issues." It's a **pass/fail verification**:

```
┌─────────────────────────────────────────┐
│         VERIFICATION CONTRACT            │
├───────────────────────┬────────┬────────┤
│ Layer                 │ Status │ Issues │
├───────────────────────┼────────┼────────┤
│ Coding Guidelines     │  PASS  │ 0      │
│ Organization Rules    │  PASS  │ 0      │
│ Domain Contracts      │  WARN  │ 2      │
│ Acceptance Criteria   │  PASS  │ 0      │
│ Static Analysis       │  PASS  │ 0      │
│ Debate Consensus      │  FAIL  │ 1      │
├───────────────────────┼────────┼────────┤
│ Overall               │  FAIL  │        │
└───────────────────────┴────────┴────────┘
```

---

## Design Philosophy

### Why AI vs AI?

Single-model reviews have blind spots. Every AI has different training data, different biases, different strengths. By making them **argue**, you get:

1. **False positives eliminated** — if only one AI sees it and can't defend it, it's probably wrong
2. **Real issues confirmed** — if multiple AIs independently find it, it's probably real
3. **Confidence you can trust** — post-debate confidence reflects actual cross-validation

### Why Agents That Talk To Each Other?

Traditional approach: each reviewer works alone, results get merged.

Arena approach: reviewers **share signals in real-time**:

```
Traditional:                    Arena:
─────────────                   ──────

Security: finds auth issue      Security: finds auth issue
Bug: misses it                     │
Perf: misses it                    ├──SIGNAL──► Bug: "check race
                                   │            conditions here too"
                                   │
                                   └──SIGNAL──► Perf: "unbounded
                                                query, DoS risk?"

Result: 1 finding               Result: 3 findings from one signal
```

### Why Debates, Not Just Voting?

Voting: "2 out of 3 AIs say yes" → but what if 2 are wrong the same way?

Debate: "AI #2, you said this is safe. AI #1 says it's not. Defend your position." → forces reasoning, not just pattern matching.

---

## Quick Start

### Install

```bash
# Option 1: Claude Code plugin
claude plugin add HajinJ/ai-review-arena

# Option 2: From source
git clone https://github.com/HajinJ/ai-review-arena.git
cd ai-review-arena
bash scripts/setup-arena.sh
```

### Prerequisites

| Tool | Required? | What For |
|------|-----------|----------|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | Yes | Runs everything |
| [jq](https://jqlang.github.io/jq/) | Yes | JSON processing |
| [Codex CLI](https://github.com/openai/codex) | Optional | Second AI perspective |
| [Gemini CLI](https://github.com/google-gemini/gemini-cli) | Optional | Third AI perspective |

Without Codex/Gemini, Arena still works — it runs Claude-only multi-agent review with the same debate protocol.

### Configure

```bash
# Project-specific config (optional)
cat > .ai-review-arena.json << 'EOF'
{
  "review": {
    "intensity": "standard",
    "focus_areas": ["security", "performance"]
  },
  "output": {
    "language": "en"
  }
}
EOF
```

### Use It

Just use Claude Code normally. Arena activates automatically.

```
You: "Add rate limiting to the API"
     → Arena routes to: Feature Implementation (Route A)
     → Intensity debate: "standard" (API change, moderate risk)
     → Full pipeline executes
     → 3-round review with cross-examination
     → Report with pass/fail verification
```

To skip Arena: add `--no-arena` to your request.

---

## Fallback Framework

Arena degrades gracefully when tools are missing:

```
Level 0: Claude + Codex + Gemini (full power)
  │ Codex unavailable
Level 1: Claude + Gemini
  │ Gemini also unavailable
Level 2: Claude-only Agent Team (all roles)
  │ Agent Teams unavailable
Level 3: Claude solo with structured template
  │ jq unavailable
Level 4: Claude solo with manual JSON
  │ Critical failure
Level 5: Error report with partial findings
```

---

## Project Structure

```
ai-review-arena/
├── agents/           40 agent definitions (12 code + 10 biz + 6 doc + 12 utility)
├── commands/         8 slash commands (arena, multi-review, research, stack, ...)
├── config/           Config files, prompts, schemas, benchmarks
├── scripts/          36 shell scripts (orchestration, CLI adapters, utilities)
├── shared-phases/    10 reusable phase definitions
├── hooks/            Auto-review triggers
├── tests/            18 tests (unit + integration + e2e)
└── docs/             ADRs and reference docs
```

---

## License

MIT
