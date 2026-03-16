# AI Review Arena

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugin that orchestrates **Claude, OpenAI Codex, and Google Gemini** into adversarial multi-agent review pipelines for code, business content, and documentation.

[English](README.md) | [한국어](README.ko.md)

---

## How It Works

Every request routes through the Arena pipeline automatically. The router classifies intent, selects a pipeline, and determines intensity through agent debate.

```
                          ┌──────────────────────┐
                          │     User Request      │
                          └──────────┬───────────┘
                                     │
                          ┌──────────▼───────────┐
                          │    Always-On Router   │
                          │    (ARENA-ROUTER)     │
                          └──────────┬───────────┘
                                     │
              ┌──────────────────────┼──────────────────────┐
              │                      │                      │
    ┌─────────▼─────────┐ ┌─────────▼─────────┐ ┌─────────▼─────────┐
    │   Code Pipeline   │ │ Business Pipeline │ │   Docs Pipeline   │
    │   Routes A-F      │ │   Routes G-I      │ │   Routes J-K      │
    │                   │ │                   │ │                   │
    │ A: Feature Impl   │ │ G: Biz Content    │ │ J: Doc Review     │
    │ B: Research        │ │ H: Biz Analysis   │ │ K: Doc Generation │
    │ C: Stack Analysis  │ │ I: Communication  │ │                   │
    │ D: Code Review     │ │                   │ │                   │
    │ E: Refactoring     │ │                   │ │                   │
    │ F: Simple Change   │ │                   │ │                   │
    └───────────────────┘ └───────────────────┘ └───────────────────┘
```

Multi-route requests are decomposed and executed sequentially: **Code → Docs → Business**.

---

## Pipeline Architecture

All three pipelines share a common architecture of progressive phases, where each phase enriches context for the next. Intensity determines how many phases execute.

### Code Pipeline (Routes A-F) — Full Phase Map

```
Phase 0 ─────── Context & Configuration
                 ├── Load config (default → global → project merge)
                 ├── Parse arguments (scope, intensity, models, focus)
                 ├── Validate CLI tools (codex, gemini, jq, gh)
                 └── MCP dependency detection (Figma, Playwright, Notion, Agentation)

Phase 0.1 ────── Intensity Decision (Agent Teams Debate)
                 ├── intensity-advocate    → argues for higher intensity
                 ├── efficiency-advocate   → argues for lower intensity
                 ├── risk-assessor         → evaluates production/security risk
                 ├── intensity-arbitrator  → synthesizes → decides intensity
                 └── Escalation floor enforcement (from Phase 0.5 Step 7)

Phase 0.2 ────── Cost & Time Estimation
                 ├── Sum applicable phase costs by intensity
                 ├── Display estimate → AskUserQuestion [Proceed / Adjust / Cancel]
                 └── Auto-proceed if under cost threshold

Phase 0.5 ────── Codebase Analysis
                 ├── Step 1: Project structure scan (Glob)
                 ├── Step 2: Related code search (Grep)
                 ├── Step 3: Convention extraction (naming, imports, errors, tests)
                 ├── Step 4: Reusable code inventory
                 ├── Step 5: Save analysis to session context
                 ├── Step 6: Mandatory instructions for all subsequent phases
                 ├── Step 7: Escalation trigger scan (auth/payment/DB/crypto/deps/infra)
                 ├── Step 8: Write scope resolution
                 └── Step 9: Quick mode execution (if intensity = quick → exit)

Phase 1 ──────── Stack Detection
                 ├── Cache check (7-day TTL)
                 ├── detect-stack.sh → platform, languages, frameworks, DBs, infra
                 └── Save stack profile to session

Phase 2 ──────── Pre-Implementation Research (deep+)
                 ├── Research Direction Debate (Agent Teams):
                 │   ├── researcher-tech      → technology best practices
                 │   ├── researcher-domain    → domain patterns
                 │   ├── researcher-risk      → failure modes, CVEs
                 │   └── research-arbitrator  → prioritizes agenda
                 └── Collaborative Search Execution:
                     └── Researchers share findings in real-time via SendMessage

Phase 3 ──────── Compliance Detection (deep+)
                 ├── search-guidelines.sh + WebSearch
                 └── Compliance Scope Debate:
                     ├── compliance-advocate   → more rules
                     ├── scope-challenger      → against over-application
                     └── compliance-arbitrator → decides actual scope

Phase 4 ──────── Model Benchmarking (comprehensive only)
                 ├── benchmark-models.sh against planted-error test cases
                 ├── Score each model per category (avg F1)
                 └── Determine model-role assignments for Phase 6

Phase 5 ──────── Figma Design Analysis (optional, if URL provided)
                 └── Figma MCP → components, tokens, layout, interactions

Phase 5.5 ────── Implementation Strategy (Agent Teams Debate, standard+)
                 ├── architecture-advocate   → proposes design approach
                 ├── security-challenger     → challenges security implications
                 ├── pragmatic-challenger    → challenges complexity/feasibility
                 ├── strategy-arbitrator     → synthesizes best approach
                 │   └── Output: approach, architecture, security, files, success criteria
                 └── Update write scope with strategy files

Phase 5.5.5 ──── Spec Approval Gate (standard+)
                 ├── Parse Success Criteria → structured JSON
                 ├── Auto-classify: automated_test / static_assertion / manual_check
                 ├── AskUserQuestion: approve/edit/add criteria
                 └── Store APPROVED_SPEC_CRITERIA for Phase 6.6 and Phase 7

Phase 5.8 ────── Static Analysis Integration (standard+)
                 ├── Stack-based scanner selection (semgrep/eslint/bandit/gosec)
                 ├── Parallel scanner execution
                 └── Output normalization → STATIC_ANALYSIS_FINDINGS

Phase 5.9 ────── STRIDE Threat Modeling (deep+)
                 ├── threat-modeler     → STRIDE threat identification
                 ├── threat-defender    → challenge threats as mitigated/unlikely
                 └── threat-arbitrator  → prioritized attack surface consensus

Phase 6 ──────── Agent Team Collaborative Review
                 (see detailed diagram below)

Phase 6.5 ────── Apply Findings (Auto-Fix Loop, standard+)
                 ├── Filter: medium/low severity, >=90% confidence, <=10 lines
                 ├── Enforce write scope + escalation block constraints
                 ├── Apply fixes via Edit tool
                 ├── Run test suite verification
                 └── Revert on test failure

Phase 6.6 ────── Test Generation (standard+)
                 ├── Filter critical/high findings with confidence >= 70
                 ├── Detect test framework and directory
                 ├── Generate regression test stubs
                 └── Generate spec acceptance tests (from APPROVED_SPEC_CRITERIA)

Phase 6.7 ────── Visual Verification (standard+, frontend only)
                 ├── Detect frontend files and visual feedback tools
                 ├── Extract CSS selectors from affected components
                 ├── Generate visual regression checklist
                 └── Playwright MCP / Agentation MCP integration

Phase 7 ──────── Final Report & Cleanup
                 ├── Verification Contract table (6-layer PASS/WARN/FAIL)
                 ├── Escalation triggers section
                 ├── Spec acceptance test results (deterministic PASS/FAIL)
                 ├── Round 1 collaboration summary
                 ├── Findings by severity (critical → low)
                 ├── Disputed findings (manual review needed)
                 ├── Cost estimate
                 ├── Shutdown all teammates
                 └── Cleanup team
```

### Intensity Controls Which Phases Run

```
QUICK           STANDARD              DEEP                    COMPREHENSIVE
─────           ────────              ────                    ─────────────
Phase 0         Phase 0               Phase 0                 Phase 0
Phase 0.1       Phase 0.1             Phase 0.1               Phase 0.1
                Phase 0.2             Phase 0.2               Phase 0.2
Phase 0.5       Phase 0.5             Phase 0.5               Phase 0.5
                  +escalation           +escalation              +escalation
                  +write scope          +write scope             +write scope
                Phase 1 (cached)      Phase 1                 Phase 1
                                      Phase 2 (+debate)       Phase 2 (+debate)
                                      Phase 3 (+debate)       Phase 3 (+debate)
                                                              Phase 4 (benchmark)
                                                              Phase 5 (Figma)
                Phase 5.5             Phase 5.5               Phase 5.5
                Phase 5.5.5           Phase 5.5.5             Phase 5.5.5
                Phase 5.8             Phase 5.8               Phase 5.8
                                      Phase 5.9 (STRIDE)     Phase 5.9 (STRIDE)
                Phase 6               Phase 6 (+Round 4)      Phase 6 (+Round 4)
                Phase 6.5             Phase 6.5               Phase 6.5
                Phase 6.6             Phase 6.6               Phase 6.6
                Phase 6.7             Phase 6.7               Phase 6.7
                Phase 7               Phase 7                 Phase 7
                  +contract             +contract               +contract
[Claude solo]   [Agent Team]          [Agent Team]            [Agent Team]
```

---

## Phase 6: Agent Team Collaborative Review (Detail)

Phase 6 is where the multi-AI adversarial review happens. It uses Agent Teams for real-time inter-reviewer collaboration and a 3-round cross-examination protocol.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    PHASE 6: AGENT TEAM REVIEW                          │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │ Step 6.3: Create Agent Team                                      │  │
│  └──────────────────────────┬───────────────────────────────────────┘  │
│                             │                                          │
│  ┌──────────────────────────▼───────────────────────────────────────┐  │
│  │ Step 6.5.0: Spawn debate-arbitrator (EARLY JOIN)                 │  │
│  │   Monitors all inter-reviewer signals from Round 1               │  │
│  │   Tracks convergence, de-duplicates, identifies cross-domain     │  │
│  └──────────────────────────┬───────────────────────────────────────┘  │
│                             │                                          │
│  ┌──────────────────────────▼───────────────────────────────────────┐  │
│  │ Step 6.5.1: Spawn Reviewers with Collaboration Protocol          │  │
│  │                                                                   │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │  │
│  │  │  security    │  │    bug      │  │architecture │  ...6-12     │  │
│  │  │  reviewer    │  │  detector   │  │  reviewer   │  reviewers   │  │
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘              │  │
│  │         │    SIGNAL       │    SIGNAL       │                     │  │
│  │         │◄───────────────►│◄───────────────►│   Real-time        │  │
│  │         │  SendMessage    │  SendMessage     │   cross-domain     │  │
│  │         │                 │                  │   discovery        │  │
│  │         ▼                 ▼                  ▼                     │  │
│  │  ┌───────────────────────────────────────────────┐               │  │
│  │  │          debate-arbitrator (Early Join)        │               │  │
│  │  │  Receives all signals, tracks convergence     │               │  │
│  │  └───────────────────────────────────────────────┘               │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │ Step 6.7: External CLI Reviews (Parallel with Claude)            │  │
│  │                                                                   │  │
│  │  ┌──────────────┐         ┌──────────────┐                       │  │
│  │  │  Codex CLI   │         │  Gemini CLI  │                       │  │
│  │  │ (Bash shell) │         │ (Bash shell) │                       │  │
│  │  └──────┬───────┘         └──────┬───────┘                       │  │
│  │         └─────────┬──────────────┘                                │  │
│  │                   ▼                                               │  │
│  │            JSON findings files                                    │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │ Step 6.8-6.9: Collect & Aggregate                                │  │
│  │                                                                   │  │
│  │  Claude findings ─┐                                              │  │
│  │  Codex findings  ─┼──► Merge + Dedup + Collaboration bonuses     │  │
│  │  Gemini findings ─┘    (+20% for cross-domain confirmations)     │  │
│  └──────────────────────────┬───────────────────────────────────────┘  │
│                             │                                          │
│  ┌──────────────────────────▼───────────────────────────────────────┐  │
│  │ Step 6.10: 3-Round Cross-Examination                             │  │
│  │                                                                   │  │
│  │  (see cross-examination detail below)                             │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3-Round Cross-Examination + Round 4 Escalation

```
ROUND 1: Independent Review (already completed)
─────────────────────────────────────────────────
  Claude (6-12 reviewers)  ←→  Real-time signals between reviewers
  Codex CLI                    (Collaboration Protocol)
  Gemini CLI
           │
           ▼
  Aggregated findings (per-model partitions)


ROUND 2: Cross-Examination (all models challenge each other)
─────────────────────────────────────────────────
  ┌───────────┐    examines    ┌───────────┐
  │   Claude   │──────────────►│   Codex   │ findings
  │ reviewers  │──────────────►│   Gemini  │ findings
  └───────────┘                └───────────┘
  ┌───────────┐    examines    ┌───────────┐
  │   Codex   │──────────────►│   Claude  │ findings
  │   CLI     │──────────────►│   Gemini  │ findings
  └───────────┘                └───────────┘
  ┌───────────┐    examines    ┌───────────┐
  │   Gemini  │──────────────►│   Claude  │ findings
  │   CLI     │──────────────►│   Codex   │ findings
  └───────────┘                └───────────┘

  For each finding: AGREE (+confidence) / DISAGREE (-confidence) / PARTIAL
           │
           ▼

ROUND 3: Defense (each model defends challenged findings)
─────────────────────────────────────────────────
  Claude reviewers: defend against Codex + Gemini challenges
  Codex CLI:        defend against Claude + Gemini challenges
  Gemini CLI:       defend against Claude + Codex challenges

  For each challenge: DEFEND / CONCEDE / MODIFY
           │
           ▼

ROUND 4: Escalation (deep+ only, if disputed high-severity remain)
─────────────────────────────────────────────────
  debate-arbitrator re-evaluates with:
    - Fresh evidence review
    - WebSearch for CVEs/standards
    - No "disputed" status allowed — must resolve to CONFIRMED or DISMISSED
           │
           ▼

CONSENSUS: debate-arbitrator synthesizes all rounds
─────────────────────────────────────────────────
  Output: { accepted: [...], rejected: [...], disputed: [...] }
  Each finding includes cross_examination_trail with all 3-4 rounds
```

---

## Verification Contract (Swiss Cheese Model)

Findings are classified into 6 verification layers. The report shows PASS/WARN/FAIL per layer.

```
┌─────────────────────────────────────────────────────────┐
│                  VERIFICATION CONTRACT                   │
├─────────────────────┬────────┬──────────────────────────┤
│ Layer               │ Status │ Sources                  │
├─────────────────────┼────────┼──────────────────────────┤
│ Coding Guidelines   │ PASS   │ security, bug, perf,     │
│                     │        │ architecture reviewers    │
├─────────────────────┼────────┼──────────────────────────┤
│ Organization        │ PASS   │ compliance-checker        │
│ Invariants          │        │                          │
├─────────────────────┼────────┼──────────────────────────┤
│ Domain Contracts    │ WARN   │ data-integrity,          │
│                     │        │ api-contract reviewers    │
├─────────────────────┼────────┼──────────────────────────┤
│ Acceptance Criteria │ PASS   │ scope-reviewer +          │
│                     │        │ spec tests (Phase 5.5.5) │
├─────────────────────┼────────┼──────────────────────────┤
│ Static Analysis     │ PASS   │ semgrep/eslint/bandit    │
├─────────────────────┼────────┼──────────────────────────┤
│ Debate Consensus    │ FAIL   │ cross-model agreement    │
│                     │        │ from 3-round debate       │
├─────────────────────┼────────┼──────────────────────────┤
│ Overall             │ FAIL   │ All layers must pass     │
└─────────────────────┴────────┴──────────────────────────┘
```

---

## Safety Systems

### Escalation Triggers

High-risk file patterns automatically escalate intensity and block auto-fix:

```
File matches auth/payment/crypto/DB schema/deps/infra patterns
                    │
                    ▼
         ┌─────────────────┐
         │ escalation-scan  │ (shell script, 0 LLM cost)
         │   .sh            │
         └────────┬────────┘
                  │
     ┌────────────┼────────────┐
     │            │            │
     ▼            ▼            ▼
 Intensity    Require       Block
 floor ↑     human         auto-fix
 (e.g.       approval      on matched
  deep)      gate          files
```

### Write Scope Constraint

Auto-fix is restricted to files within the resolved scope:

```
Scope Resolution Priority:
  1. User's explicit file paths        (highest)
  2. git diff file list
  3. Phase 5.5 strategy files
  4. PROJECT_ROOT (no restriction)      (lowest, with warning)

Phase 6.5 applies:
  IF file NOT IN WRITE_SCOPE → skip (or prompt user)
  IF file IN ESCALATION_BLOCKED_FILES → skip always
```

### Commit/PR Safety Gate

```
Commit request:
  Route F (quick) → Phase 0.5 → Commit Safety Gate → AskUserQuestion

PR request:
  Route D → full review pipeline → PR Safety Gate → AskUserQuestion
```

---

## Business Pipeline (Routes G-I)

```
Phase B0 ────── Context & Configuration
Phase B0.1 ──── Intensity Decision (Agent Teams Debate)
Phase B0.2 ──── Cost & Time Estimation
Phase B0.5 ──── Business Context Analysis
Phase B1 ────── Market/Industry Context (WebSearch)
Phase B1.5 ──── Framework Selection Debate (standard+)
                ├── framework-advocate    → comprehensive framework set
                ├── framework-minimalist  → focused framework set
                └── framework-arbitrator  → selects up to 3 frameworks
Phase B2 ────── Content Best Practices Research (deep+, with debate)
Phase B3 ────── Accuracy & Consistency Audit (deep+, with debate)
Phase B4 ────── Business Model Benchmarking (comprehensive only)
Phase B5.5 ──── Content Strategy Debate (standard+, 3-scenario mandate)
                ├── messaging-advocate    → proposes messaging strategy
                ├── audience-challenger   → challenges audience fit
                ├── accuracy-challenger   → challenges factual claims
                └── strategy-arbitrator   → synthesizes + 3 scenarios
Phase B5.6 ──── Quantitative Validation (deep+)
                ├── data-verifier         → cross-reference numbers
                └── methodology-auditor   → validate projections
Phase B5.7 ──── Adversarial Red Team (deep+)
                ├── skeptical-investor    → "Why should I NOT invest?"
                ├── competitor-response   → "How would competitors counter?"
                └── regulatory-risk       → "Hidden regulatory/legal risks?"
Phase B6 ────── Multi-Agent Business Review (5+ reviewers, 3-round debate)
Phase B6.5 ──── Apply Findings (auto-revise content)
Phase B7 ────── Final Report (+ consistency validation)
```

### Business Reviewer Agents (10)

| Agent | Focus |
|-------|-------|
| accuracy-evidence-reviewer | Factual claims, data accuracy |
| audience-fit-reviewer | Target audience alignment |
| competitive-positioning-reviewer | Market positioning |
| communication-narrative-reviewer | Story flow, persuasion |
| financial-credibility-reviewer | Financial projections |
| legal-compliance-reviewer | Regulatory compliance |
| market-fit-reviewer | Product-market fit |
| conversion-impact-reviewer | CTA effectiveness |
| localization-reviewer | Cultural adaptation |
| investor-readiness-reviewer | Investment readiness |

---

## Documentation Pipeline (Routes J-K)

```
Phase D0 ────── Context & Configuration
Phase D0.1 ──── Intensity Decision (Agent Teams Debate)
Phase D0.2 ──── Cost & Time Estimation
Phase D0.5 ──── Documentation Inventory (doc-inventory.sh)
                ├── Scan project for all doc files
                ├── Classify by type (readme, api, tutorial, changelog, adr, runbook)
                └── Generate inventory with metadata
Phase D1 ────── Code-Doc Diff Analysis
                ├── git diff → recent code changes
                ├── Cross-reference with doc modification dates
                └── Generate CODE_DOC_DRIFT map
Phase D2 ────── Documentation Standards Research (deep+, with debate)
Phase D3 ────── Cross-Reference Validation (deep+, with debate)
Phase D4 ────── Documentation Benchmarking (comprehensive only)
Phase D5.5 ──── Documentation Strategy Debate (standard+)
Phase D6 ────── Multi-Agent Doc Review (6 reviewers, 3-round debate)
Phase D6.5 ──── Apply Findings (auto-fix critical/high doc issues)
Phase D6.6 ──── Example Code Validation (standard+)
                ├── Extract code blocks from docs
                ├── Syntax check each block
                ├── Verify imports exist
                └── Flag deprecated API usage
Phase D7 ────── Final Report (+ cross-doc consistency validation)
```

### Documentation Reviewer Agents (6)

| Agent | Focus |
|-------|-------|
| doc-accuracy-reviewer | Technical accuracy vs codebase |
| doc-completeness-reviewer | Missing sections, gaps |
| doc-freshness-reviewer | Outdated content, stale references |
| doc-readability-reviewer | Clarity, structure, formatting |
| doc-example-reviewer | Code examples correctness |
| doc-consistency-reviewer | Cross-document consistency |

---

## Agent Inventory

### Code Review Agents (12)

| Agent | Domain |
|-------|--------|
| security-reviewer | OWASP Top 10, injection, auth flaws |
| bug-detector | Logic errors, null handling, race conditions |
| architecture-reviewer | SOLID, design patterns, coupling |
| performance-reviewer | Complexity, memory, N+1, blocking ops |
| test-coverage-reviewer | Test completeness, edge cases |
| scope-reviewer | Change scope verification |
| dependency-reviewer | Dependency risks |
| api-contract-reviewer | API consistency |
| observability-reviewer | Logging, metrics, tracing |
| data-integrity-reviewer | Data validation, consistency |
| accessibility-reviewer | A11y compliance |
| configuration-reviewer | Config management |

### Debate & Utility Agents (8)

| Agent | Role |
|-------|------|
| debate-arbitrator | Cross-examination consensus (code) |
| business-debate-arbitrator | Cross-examination consensus (business) |
| doc-debate-arbitrator | Cross-examination consensus (docs) |
| research-coordinator | Cross-reference research findings |
| design-analyzer | Figma design extraction |
| compliance-checker | Platform/regulatory compliance |
| threat-modeler / threat-defender / threat-arbitrator | STRIDE threat modeling |

---

## External CLI Integration

```
┌─────────────────┐     JSON stdin     ┌──────────────────────┐
│                  │──────────────────►│  codex-review.sh      │
│   Team Lead      │                   │  codex-cross-examine  │
│   (Claude Code)  │     JSON stdin    │  codex-business-rev   │
│                  │──────────────────►│  codex-doc-review.sh  │
│                  │                   └──────────────────────┘
│                  │
│                  │     JSON stdin     ┌──────────────────────┐
│                  │──────────────────►│  gemini-review.sh     │
│                  │                   │  gemini-cross-examine  │
│                  │     JSON stdin    │  gemini-business-rev   │
│                  │──────────────────►│  gemini-doc-review.sh │
└─────────────────┘                   └──────────────────────┘

External CLIs run via Bash (not Agent Teams).
Findings flow as JSON files in the session directory.
```

---

## Feedback-Driven Model Routing

```
                   ┌───────────────┐
                   │ User Feedback  │
                   │ (accept/reject │
                   │  findings)     │
                   └───────┬───────┘
                           │
                           ▼
                 ┌─────────────────┐
                 │ feedback-tracker │
                 │  .sh             │  BM25 scoring
                 └────────┬────────┘
                          │
              ┌───────────┼───────────┐
              │           │           │
              ▼           ▼           ▼
         Category    Category    Category
         Security    Bugs        Perf
              │           │           │
              ▼           ▼           ▼
     Best model   Best model   Best model
     for this     for this     for this
     category     category     category

Routing strategy: 60% feedback score + 40% benchmark score (configurable)
```

---

## Fallback Framework

6-level graceful degradation when external tools are unavailable:

```
Level 0: Full pipeline (Claude + Codex + Gemini + all phases)
  │
  ▼ Codex unavailable
Level 1: Claude + Gemini (Codex roles reassigned)
  │
  ▼ Gemini also unavailable
Level 2: Claude-only Agent Team (all roles assigned to Claude reviewers)
  │
  ▼ Agent Teams unavailable
Level 3: Claude solo with structured review template
  │
  ▼ jq unavailable
Level 4: Claude solo with manual JSON handling
  │
  ▼ critical failure
Level 5: Error report with partial findings
```

---

## Configuration

Three-level config merge (later overrides earlier):

```
config/default-config.json    →    ~/.claude/.ai-review-arena.json    →    .ai-review-arena.json
      (plugin default)                  (global user)                       (project-specific)
```

Key configuration sections:

| Section | Controls |
|---------|----------|
| `models` | Claude/Codex/Gemini model variants, enable/disable |
| `review` | Intensity, focus areas, confidence threshold |
| `debate` | Enable/disable, rounds, escalation |
| `arena` | Default phases, caching, interactive mode |
| `intensity_presets` | Reviewer roles per intensity level |
| `static_analysis` | Scanner selection, confidence floor |
| `escalation_triggers` | High-risk file/content patterns |
| `write_scope` | Auto-fix file boundary enforcement |
| `contract_verification` | 6-layer verification report |
| `spec_verification` | BDD test generation from specs |
| `agent_teams` | Collaboration protocol settings |
| `cost_estimation` | Token costs, auto-proceed threshold |
| `feedback` | Model routing strategy weights |
| `context_density` | Per-agent token budgets, chunking |

Environment variable overrides: `MULTI_REVIEW_*` (review), `ARENA_*` (lifecycle).

---

## Installation

```bash
# Clone or install
git clone https://github.com/HajinJ/ai-review-arena.git
cd ai-review-arena
bash scripts/setup-arena.sh

# Or add as Claude Code plugin
claude plugin add HajinJ/ai-review-arena
```

### Prerequisites

| Tool | Required | Purpose |
|------|----------|---------|
| Claude Code | Yes | Host environment |
| jq | Yes | JSON processing |
| Codex CLI | Optional | External model review |
| Gemini CLI | Optional | External model review |
| gh (GitHub CLI) | Optional | PR review support |

### Optional MCP Servers

| MCP | Purpose | Auto-detected |
|-----|---------|---------------|
| Figma MCP | Design analysis (Phase 5) | Figma URL in request |
| Playwright MCP | Visual verification (Phase 6.7) | Frontend file changes |
| Notion MCP | Notion integration | "Notion" in request |
| Agentation MCP | Visual feedback | Frontend file changes |

---

## Commands

| Command | Description |
|---------|-------------|
| `/arena` | Full lifecycle orchestrator |
| `/multi-review` | Multi-AI adversarial code review |
| `/arena-research` | Pre-implementation research |
| `/arena-stack` | Project stack detection |
| `/multi-review-config` | Review config management |
| `/multi-review-status` | Review status dashboard |

The Always-On Router automatically invokes the appropriate pipeline for every request, so you rarely need to use commands directly.

---

## Project Structure

```
ai-review-arena/
├── .claude-plugin/        Plugin manifest (v3.3.0)
├── agents/                40 agent definitions
│   ├── (12 code review)   security, bug, arch, perf, test, scope, dep, api, obs, data, a11y, config
│   ├── (10 business)      accuracy, audience, competitive, narrative, financial, legal, market, conversion, localization, investor
│   ├── (6 documentation)  accuracy, completeness, freshness, readability, example, consistency
│   ├── (3 threat model)   threat-modeler, threat-defender, threat-arbitrator
│   ├── (3 red team)       skeptical-investor, competitor-response, regulatory-risk
│   ├── (3 debate)         debate-arbitrator, business-debate-arbitrator, doc-debate-arbitrator
│   ├── (2 research)       research-coordinator, design-analyzer
│   └── (1 compliance)     compliance-checker
├── commands/              8 slash command files
├── config/
│   ├── default-config.json
│   ├── review-prompts/    15 role-specific prompts (9 code + 6 doc)
│   ├── schemas/           7 Codex structured output schemas
│   ├── codex-agents/      5 Codex multi-agent TOML configs
│   ├── compliance-rules.json
│   ├── tech-queries.json  31 technology → search query mappings
│   └── benchmarks/        28 model benchmark test cases (8 code + 12 biz + 8 doc)
├── scripts/               36 shell/Python scripts
├── shared-phases/         10 shared phase definitions
├── docs/                  ADRs, router reference, safety protocol
├── tests/                 18 test files (8 unit + 8 integration + 2 e2e)
├── hooks/                 PostToolUse hook + Gemini CLI adapter
└── cache/                 Runtime knowledge cache (gitignored)
```

---

## License

MIT
