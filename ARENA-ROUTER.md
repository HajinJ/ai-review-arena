# ARENA-ROUTER.md - AI Review Arena Routing System v3.2

## Core Rule

**Every request goes through the Arena pipeline by default.** The pipeline runs unless the request matches one of the explicit exemptions below.

Code explanations, questions about code behavior, commit messages, simple renames — ALL of these go through the pipeline. Route F handles simple tasks with `quick` intensity (no Agent Team overhead).

### Exempt Requests (NO pipeline — respond directly)

The following are the ONLY cases where you skip the pipeline entirely:

1. `--no-arena` flag is explicitly provided
2. User directly invokes a slash command (`/arena`, `/multi-review`, etc.)
3. **Meta questions about the Arena plugin itself** (e.g., "How does Arena work?", "Change Review Arena settings")
4. **Pure conversational exchanges** with no task intent (e.g., greetings like "Hello", "Thanks", acknowledgments like "Got it")
5. **Claude Code CLI usage questions** (e.g., "/help", "How do I configure MCP?")

### NOT Exempt (MUST go through pipeline)

These might seem like simple questions, but they MUST be routed:

| Request | Why it MUST route | Route |
|---------|-------------------|-------|
| "What does this code do?" | Code explanation requires codebase analysis | F (quick) |
| "Explain this function" | Same — needs context from Phase 0.5 | F (quick) |
| "Commit this" | Commit needs diff review + user confirmation | F → Commit Safety Gate |
| "Create a PR" | PR requires code review + user confirmation | D → PR Safety Gate |
| "Why is this erroring?" | Debugging requires code context | F or A |
| "Run the tests" | Test execution benefits from stack detection | F (quick) |
| "Update the README" | Documentation change | F (quick) |
| "Refactor this code" | Refactoring | E |
| "Analyze the market" | Business analysis | H |

**When in doubt: route it.** The intensity debate (Phase 0.1) will decide `quick` for simple tasks, keeping overhead minimal.

---

## Plugin Directory

```
PLUGIN_DIR = ~/.claude/plugins/ai-review-arena
```

All command files, agent definitions, and config files are located in this directory.

---

## Process: 3 Steps

```
Every Request
  │
  ├── Step 1: Context Discovery
  │     Gather external information needed to fully understand the request
  │
  ├── Step 2: Route Selection
  │     Determine the appropriate route(s) based on context + intent
  │
  └── Step 3: Pipeline Execution
        Read the command file for the selected route via Read tool
        and execute the pipeline defined in it
```

---

## Step 1: Context Discovery

Before processing a request, gather any external context needed to fully understand it.

### When Discovery Is Needed

| Request Pattern | Discovery Action |
|----------------|-----------------|
| Issue/ticket reference ("handle the issue", "next issue", "next task") | `gh issue list` → select issue → `gh issue view N` → understand content |
| PR reference ("review PR", "PR #42") | `gh pr view N` → understand PR diff and description |
| Figma URL included | Collect design info via Figma MCP (suggest install if missing) |
| File/directory reference ("this file", "src/services/") | Read/Glob to understand target code |
| Ambiguous request ("fix this", "something's wrong") | `git diff`, `git status` to understand recent changes |
| External library/framework mention | WebSearch or Context7 MCP for latest documentation |
| Business document reference ("business plan", "pitch deck", "proposal", "BMC") | Read docs/ directory, understand existing business documents |
| Competitor/market analysis request | WebSearch for market data, competitor landscape |
| Investor/customer communication | Read docs/ for existing IR/marketing materials |
| Comment/review response request | Understand target comments + existing product description |

### When Discovery Is Not Needed

If the request already contains sufficient context, proceed directly to Step 2:
- "Add a getById method to UserService" → target and action are clear
- "Implement login API" → feature to implement is clear
- "Write a response to this comment: ..." → content is provided inline

### How Discovery Results Are Used

Collected context is passed to both Step 2 (route selection) and Step 3 (pipeline execution).
Example: If an issue says "Add multiplayer lobby system" → complex feature → Route A, intensity deep

---

## Step 2: Route Selection

Use natural language understanding to determine the request's intent and select the appropriate route(s).
Works regardless of language (Korean, English, Japanese, French, etc.).

### Available Routes

#### Code Routes (A-F)

##### Route A: Feature Implementation

**Intent**: Build new features or add functionality to existing systems.

- New feature development, feature implementation
- Complex tasks requiring design through implementation
- Issue/ticket-based implementation work (after Context Discovery)
- Figma design-based implementation

##### Route B: Pre-Implementation Research

**Intent**: Investigate methodologies, best practices, or technology comparisons before coding.

- Implementation method research, technology comparison
- Best practices/guideline verification
- Preliminary research for architectural decisions
- Exploratory questions ("what's the best way to...")

##### Route C: Stack Analysis

**Intent**: Understand the project's technology stack, frameworks, and dependencies.

- Project technology composition analysis
- Framework/library identification
- Stack-based recommendations

##### Route D: Code Review

**Intent**: Review existing code and find problems.

- Code quality/security/performance review
- PR review
- Vulnerability scanning, bug detection
- Change review

##### Route E: Refactoring/Improvement

**Intent**: Improve existing code structure, quality, or performance.

- Refactoring, code cleanup
- Performance optimization
- Structural improvement, deduplication
- Technical debt resolution

##### Route F: Simple Change

**Intent**: Small, well-defined code modifications.

- Parameter addition/removal, renaming
- Type changes, import fixes
- Single method addition
- Simple bug fixes
- Commits, code explanations, and other trivial tasks

#### Business Routes (G-I)

##### Route G: Business Content Creation

**Intent**: Write or revise business documents, content, and proposals.

- Business plans, BMC (Business Model Canvas)
- Proposals, pitch decks, IR materials
- Product descriptions, service brochures
- Marketing copy, press releases
- Case studies, whitepapers

##### Route H: Business Analysis/Strategy

**Intent**: Market analysis, competitive analysis, strategy formulation, and analytical business tasks.

- Market research, competitor analysis
- SWOT analysis, Porter's Five Forces
- Financial analysis, KPI design
- Growth strategy, market entry strategy
- Business feasibility review

##### Route I: Communication

**Intent**: External communication and stakeholder correspondence.

- Investor Q&A, IR responses
- Customer support messages, comment/review responses
- Partnership proposals
- Emails, presentation scripts
- Hackathon/demo day presentation materials

### Multi-Route Requests

Some requests span both code and business domains, or require sequential execution of multiple routes.

#### Detection

A request is multi-route when it contains **two or more distinct intents** that map to different pipelines:
- "Write a business plan and build a landing page based on it" → Route G then Route A
- "Analyze the market and implement a pricing strategy in code" → Route H then Route A
- "Review this PR and also draft a release announcement" → Route D then Route G

#### Context Forwarding Interface

Each pipeline produces a **context output** that can be forwarded to the next pipeline:

| Source Route | Context Output | Available Fields |
|-------------|---------------|-----------------|
| G (Business Content) | `business_content_output` | content_text, quality_scorecard, key_themes, audience, tone |
| H (Business Strategy) | `strategy_output` | analysis_summary, recommendations, market_data, competitive_landscape |
| I (Communication) | `communication_output` | draft_text, tone_analysis, audience_fit_score |
| A (Feature Impl) | `implementation_output` | files_changed, test_results, architecture_decisions |
| D (Code Review) | `review_output` | findings_summary, severity_counts, quality_score |

#### Forwarding Rules

1. Context is passed as an additional `PRIOR_ROUTE_CONTEXT` variable
2. The receiving pipeline reads it in Phase 0/B0 alongside other context
3. Context is INFORMATIONAL — the receiving pipeline decides how to use it
4. Tiered token limits by field type:

| Field Type | Limit | Examples |
|-----------|-------|---------|
| summary_fields | 2,000 tokens | quality_scorecard, key_themes, severity_counts |
| content_text | 15,000 tokens | Full document if needed by next route |
| metadata | 1,000 tokens | audience, tone, audience_fit_score |
| **Total hard limit** | **20,000 tokens** | |

Overflow behavior:
- IF any field exceeds its limit: auto-summarize before forwarding
- IF total exceeds hard limit: drop content_text, keep summaries only

#### Execution Order

1. Parse all intents from user request
2. Order by dependency: business routes before code routes
3. Execute sequentially
4. After each route completes, extract context output
5. Pass to next route as `PRIOR_ROUTE_CONTEXT`

#### Example

```
Request: "Write a pitch deck and build a landing page based on it"

Sub-task 1: Route G (Business Content)
  Input: "Write a pitch deck"
  Output: business_content_output = {
    content_text: "<full pitch deck>",
    quality_scorecard: {accuracy: 88, audience_fit: 92, ...},
    key_themes: ["AI-powered trade compliance", "reduce costs by 60%"],
    audience: "investor",
    tone: "persuasive"
  }

Sub-task 2: Route A (Feature Implementation)
  Input: "Build a landing page"
  PRIOR_ROUTE_CONTEXT: business_content_output from Sub-task 1
  → Codebase analysis uses key_themes for content
  → Implementation uses tone and audience for design decisions
```

#### Ambiguous Cases

| Request | Resolution |
|---------|-----------|
| "Update the README" | Route F (code-adjacent, simple change) |
| "Write API documentation" | Route F (code-adjacent, documentation) |
| "Write a product description for the website" | Route G (business content) |
| "Explain this code" | Route F (simple task) |
| "Analyze our codebase architecture" | Route C or Route E (code analysis) |

### Route Selection Principles

1. **Clear intent** → go directly to that route
2. **Complex intent** → choose the more comprehensive route (A over F, G over I)
3. **Code tasks** → Route A-F; **Business tasks** → Route G-I
4. **Unknown code intent** → default to Route A; **Unknown business intent** → default to Route G
5. **Context Discovery revealed issue/PR** → route based on the issue content's intent
6. **Multi-route detected** → decompose and execute sequentially with context forwarding

---

## Step 3: Pipeline Execution

### Execution Method (Mandatory — follow this order exactly)

1. **Load command file**: Check the mapping table below for the selected route's command file path, and **read it using the Read tool.**
2. **Execute pipeline**: Follow the Phase sequence, Agent Team composition, and execution procedures defined in the command file **exactly**.
3. **Pass arguments**: Forward the context collected in Step 1 and arguments extracted in Step 2 (intensity, focus, figma URL, etc.) as pipeline context.

**Never invoke via slash commands (`/arena`, `/multi-review`, etc.). Always read the command file directly with the Read tool and follow the pipeline defined in the file.**

### Command File Mapping

| Route | Command File | Arguments |
|-------|-------------|-----------|
| A: Feature Implementation | `${PLUGIN_DIR}/commands/arena.md` | `--intensity` (auto-decided) |
| B: Pre-Implementation Research | `${PLUGIN_DIR}/commands/arena-research.md` | research topic |
| C: Stack Analysis | `${PLUGIN_DIR}/commands/arena-stack.md` | |
| D: Code Review | `${PLUGIN_DIR}/commands/multi-review.md` | `--focus`, `--pr` |
| E: Refactoring | `${PLUGIN_DIR}/commands/arena.md` | `--phase codebase,review` |
| F: Simple Change | `${PLUGIN_DIR}/commands/arena.md` | `--intensity quick` |
| G: Business Content | `${PLUGIN_DIR}/commands/arena-business.md` | `--type content` |
| H: Business Analysis | `${PLUGIN_DIR}/commands/arena-business.md` | `--type strategy` |
| I: Communication | `${PLUGIN_DIR}/commands/arena-business.md` | `--type communication` |

### Commit/PR Safety Protocol

Commits and PRs affect shared state (repository history, team visibility). They require a **mandatory review step** and **explicit user confirmation** before execution.

#### Commit Request

When the user requests a commit ("commit this", "commit changes", etc.):

1. **Route**: F (Simple Change) with `quick` intensity
2. **Pipeline**: Phase 0 → 0.1-Pre → 0.5 (codebase analysis)
3. **Commit Safety Gate** (mandatory, runs after Phase 0.5):
   a. Run `git diff --staged` (or `git diff` if nothing staged) to review all changes
   b. Analyze changes for:
      - Accidental inclusion of secrets/credentials (`.env`, API keys, tokens)
      - Unintended file additions (build artifacts, node_modules, large binaries)
      - Incomplete changes (debug code, TODO markers, commented-out blocks)
   c. Present change summary to user:
      ```
      ## Commit Review
      - Files: {count} files changed (+{additions}/-{deletions})
      - Summary: {brief description of changes}
      - Warnings: {any issues found, or "None"}
      ```
   d. **Require user confirmation** via AskUserQuestion:
      - [Commit] — proceed with commit
      - [Edit message] — let user modify the commit message
      - [Cancel] — abort commit

**The commit MUST NOT execute without explicit user approval.**

#### PR Request

When the user requests a PR ("create a PR", "open a pull request", etc.):

1. **Route**: D (Code Review) at `standard` intensity minimum
2. **Pipeline**: Full Route D pipeline (multi-AI code review)
3. **PR Safety Gate** (mandatory, runs after review pipeline completes):
   a. Present review findings summary:
      ```
      ## PR Review Summary
      - Critical issues: {count}
      - Warnings: {count}
      - Quality score: {score}/100
      - Changes: {commit count} commits, {file count} files
      ```
   b. If critical issues found (severity: critical/high):
      - Recommend fixing before creating PR
      - List specific issues to address
   c. **Require user confirmation** via AskUserQuestion:
      - [Create PR] — proceed with PR creation
      - [Fix issues first] — address review findings before creating PR
      - [Create PR anyway] — create despite warnings (user accepts risk)
      - [Cancel] — abort PR creation

**The PR MUST NOT be created without explicit user approval.**

---

### Intensity Decision

Intensity is determined in two stages: a **fast pre-filter** for obvious cases, then an **Agent Teams debate** for everything else.

#### Phase 0.1-Pre: Quick Intensity Pre-Filter (Rule-Based)

Before spawning any agents, apply these rules to skip the debate for obvious cases. This saves ~$0.50+ and ~30 seconds per trivial request.

**Auto-assign `quick` (skip debate) when ALL of these are true:**
- Route is F (Simple Change)
- AND the request matches one of these patterns:
  - Single file rename, typo fix, import fix
  - Code explanation ("what does this do", "explain this function")
  - README/docs minor edit
  - Single function/method addition with clear specification
  - Variable/type rename across files
  - Test execution ("run tests", "run the test suite")

**Note**: Commits and PRs are NOT eligible for auto-quick. They always go through the Commit/PR Safety Protocol regardless of apparent simplicity.

**Auto-assign `standard` (skip debate) when:**
- Route is D (Code Review) with `--pr` flag and diff < 500 lines
- Route is E (Refactoring) with single file target

**Always require debate for:**
- Route A (Feature Implementation) — complexity is hard to judge
- Route B (Pre-Implementation Research)
- Route C (Stack Analysis)
- Routes G, H, I (all Business routes)
- Any request touching authentication, payment, security, or user data
- Any request involving multiple modules/services
- Any request from an issue/ticket (issue content may reveal hidden complexity)

#### Phase 0.1: Intensity Decision (Agent Teams Debate)

Runs when the pre-filter does not resolve intensity. 3-4 Claude agents debate the appropriate intensity:

- **intensity-advocate**: Argues for higher intensity. Considers worst-case scenarios, security/accuracy risks, complexity.
- **efficiency-advocate**: Argues for lower intensity. Considers practicality, cost, scope constraints.
- **risk-assessor**: Evaluates production impact, security sensitivity, audience exposure, brand risk.
- **intensity-arbitrator**: Weighs both sides and makes the final intensity decision.

Debate continues until consensus is reached. Skipped if user explicitly specifies `--intensity` or if Phase 0.1-Pre already resolved it.

#### Code Pipeline: Intensity Phase Scope

| Intensity | Phases | Decision Debates | Review Agents |
|-----------|--------|------------------|---------------|
| `quick` | 0 → 0.1-Pre → 0.5 | pre-filter (no debate) | none (Claude solo) |
| `standard` | 0 → 0.1 → 0.2 → 0.5 → 1(cached) → 5.5 → 6 → 6.5 → 7 | intensity + implementation strategy | 3-5 agents |
| `deep` | 0 → 0.1 → 0.2 → 0.5 → 1 → 2 → **2.9** → 3 → 5.5 → 6 → 6.5 → 7 | intensity + research direction + compliance scope + strategy | 5-7 agents |
| `comprehensive` | 0 → 0.1 → 0.2 → 0.5 → 1 → 2 → **2.9** → 3 → 4 → 5 → 5.5 → 6 → 6.5 → 7 | all 4 debates | 7-10 agents |

Phase 0.2 = Cost & Time Estimation (user can cancel or adjust intensity before execution begins).
Phase 2.9 = Intensity Checkpoint — bidirectional adjustment (upgrade/downgrade) based on research findings.
Phase 6.5 = Auto-Fix Loop (applies safe, high-confidence findings with test verification).

#### Business Pipeline: Intensity Phase Scope

| Intensity | Phases | Decision Debates | Review Agents |
|-----------|--------|------------------|---------------|
| `quick` | B0 → B0.1-Pre → B0.5 | pre-filter (no debate) | none (Claude solo) |
| `standard` | B0 → B0.1 → B0.2 → B0.5 → B1 → B5.5 → B6 → B6.5 → B7 | intensity + content strategy | 5 agents + external CLIs (cross-review) |
| `deep` | B0 → B0.1 → B0.2 → B0.5 → B1 → B2(+debate) → **B2.9** → B3(+debate) → B5.5 → B6 → B6.5 → B7 | intensity + research + accuracy scope + strategy | 5 agents + external CLIs (cross-review) |
| `comprehensive` | B0 → B0.1 → B0.2 → B0.5 → B1 → B2 → **B2.9** → B3 → B4 → B5.5 → B6 → B6.5 → B7 | all debates | 5 agents + external CLIs (benchmark-driven role) |

Phase B0.2 = Cost & Time Estimation (user can cancel or adjust intensity before execution begins).
Phase B2.9 = Intensity Checkpoint — bidirectional adjustment based on market/research findings.
Phase B4 = Business Model Benchmarking (comprehensive only — determines external CLI role assignment).

#### Decision Debates Overview

| Decision Debate | Purpose | Applies To |
|----------------|---------|------------|
| Phase 0.1 / B0.1: Intensity Decision | Determine pipeline intensity | all (mandatory) |
| Phase 2 / B2: Research Direction Debate | Determine what to research | deep, comprehensive |
| Phase 3 / B3: Compliance/Accuracy Scope | Determine rule/verification scope | deep, comprehensive |
| Phase 5.5 / B5.5: Strategy Decision | Design/content approach debate | standard, deep, comprehensive |
| Phase 6.10 / B6.7: Review Debate | Code review / business review cross-examination | standard, deep, comprehensive |

---

## Argument Extraction

After route selection, extract the following from the request and pass as pipeline context:

| Target | Passed As |
|--------|-----------|
| Figma URL (`figma.com/...`) | `--figma <url>` |
| PR number | `--pr <number>` |
| Focus area (security, performance, architecture) | `--focus <area>` |
| Target file/directory paths | pipeline context |
| Interactive request | `--interactive` |
| Skip cache request | `--skip-cache` |
| Explicit intensity | `--intensity <level>` |
| Business type (content, strategy, communication) | `--type <type>` |
| Target audience (investor, customer, partner, internal) | `--audience <audience>` |
| Tone (formal, casual, persuasive, analytical) | `--tone <tone>` |

---

## MCP Dependency Detection

When an MCP server is needed to process the request:

1. **Check installation via ToolSearch**
2. **Installed** → use the MCP
3. **Not installed** → suggest installation to user (AskUserQuestion)
   - Install and continue
   - Continue without the feature
   - Cancel

Detection patterns:
- Figma URL → Figma MCP
- Test/E2E/browser tasks → Playwright MCP
- Notion references → Notion MCP

---

## Examples

### Issue-Based Work
```
Request: "Handle the next issue from my git issues"

Step 1: gh issue list → check issue list → select next → gh issue view N → understand content
Step 2: Issue content says "Add lobby system" → Route A (Feature Implementation)
Step 3: Read ${PLUGIN_DIR}/commands/arena.md
        → Phase 0 → Phase 0.1 Intensity Debate
          intensity-advocate: "Multiplayer involves networking + security + concurrency. comprehensive needed"
          efficiency-advocate: "Lobby alone is manageable. deep is sufficient"
          risk-assessor: "Game service requires security + compliance attention"
          intensity-arbitrator: "deep. Lobby itself doesn't warrant comprehensive"
        → Execute subsequent phases at deep intensity
```

### Production Deadlock Fix
```
Request: "Fix a deadlock happening in production"

Step 1: git diff, identify related code
Step 2: Bug fix → Route A (complex, cross-module work)
Step 3: Read ${PLUGIN_DIR}/commands/arena.md
        → Phase 0 → Phase 0.1 Intensity Debate
          intensity-advocate: "Deadlock is a concurrency bug. Wrong fix creates new race conditions. deep needed"
          efficiency-advocate: "Known patterns may apply. standard is sufficient"
          risk-assessor: "Production outage. Service disruption risk. deep or above recommended"
          intensity-arbitrator: "deep. Production risk + concurrency complexity"
        → Execute at deep intensity
```

### Simple Rename
```
Request: "Rename this function to calculateScore"

Step 1: Context sufficient → no discovery needed
Step 2: Simple change → Route F
Step 3: Read ${PLUGIN_DIR}/commands/arena.md
        → Phase 0 → Phase 0.1-Pre: Single file rename → auto-quick (skip debate)
        → Execute Phase 0.5 only (Claude solo)
```

### Code Explanation
```
Request: "What does this code do?"

Step 1: Context Discovery → Read/Glob target file
Step 2: Code explanation → Route F
Step 3: Read ${PLUGIN_DIR}/commands/arena.md
        → Phase 0 → Phase 0.1-Pre: Code explanation → auto-quick (skip debate)
        → Execute Phase 0.5 (codebase analysis for context) → Claude explains
```

### Commit
```
Request: "Commit these changes"

Step 1: Context Discovery → git diff, git status
Step 2: Commit request → Route F (quick) → triggers Commit Safety Protocol
Step 3: Read ${PLUGIN_DIR}/commands/arena.md
        → Phase 0 → 0.1-Pre → Phase 0.5 (analyze changes)
        → Commit Safety Gate:
          - Review staged diff
          - Check for secrets, debug code, unintended files
          - Present summary to user
          - AskUserQuestion: [Commit] [Edit message] [Cancel]
        → User approves → execute git commit
```

### Create PR
```
Request: "Create a PR for this feature"

Step 1: Context Discovery → git diff main...HEAD, git log
Step 2: PR request → Route D (Code Review) → triggers PR Safety Protocol
Step 3: Read ${PLUGIN_DIR}/commands/multi-review.md
        → Execute review pipeline at standard intensity
        → PR Safety Gate:
          - Present review findings (critical: 0, warnings: 2, score: 87/100)
          - AskUserQuestion: [Create PR] [Fix issues first] [Create anyway] [Cancel]
        → User approves → execute gh pr create
```

### OAuth Implementation
```
Request: "Implement OAuth login system"

Step 1: Context sufficient
Step 2: Feature implementation → Route A
Step 3: Read ${PLUGIN_DIR}/commands/arena.md
        → Phase 0 → Phase 0.1 Intensity Debate
          intensity-advocate: "Authentication breach compromises entire system. comprehensive needed"
          efficiency-advocate: "OAuth is a standard protocol. deep is sufficient"
          risk-assessor: "Auth is security-critical. Model benchmarking needed for best security reviewer"
          intensity-arbitrator: "comprehensive. Security-first + Phase 4 benchmarking required"
        → Execute all phases at comprehensive intensity
```

### Code Review
```
Request: "Review PR 42 with focus on security"

Step 1: gh pr view 42 → understand PR diff
Step 2: Code review → Route D
Step 3: Read ${PLUGIN_DIR}/commands/multi-review.md
        → Execute review pipeline with --pr 42 --focus security
```

### Refactoring
```
Request: "Clean up this service code"

Step 1: Identify target files/directory
Step 2: Code improvement → Route E
Step 3: Read ${PLUGIN_DIR}/commands/arena.md
        → Phase 0 → Phase 0.1 Intensity Debate → decide intensity
        → Execute with --phase codebase,review
```

### Business Plan Writing
```
Request: "Write a business plan for TradeFlow AI"

Step 1: Read docs/ directory for existing business docs (business plan, post-MVP direction, etc.)
Step 2: Business content creation → Route G
Step 3: Read ${PLUGIN_DIR}/commands/arena-business.md
        → Phase B0 → Phase B0.1 Intensity Debate
          intensity-advocate: "Business plan is core to fundraising. External exposure + accuracy critical. deep needed"
          efficiency-advocate: "Existing documents provide strong foundation. standard is sufficient"
          risk-assessor: "Investor-facing. High brand/trust risk. Accuracy matters"
          intensity-arbitrator: "deep. External exposure + strategic importance"
        → Execute at deep intensity
```

### Investor Q&A Response
```
Request: "An investor asked about our TAM. Draft a response"

Step 1: Gather context — existing business docs, market data
Step 2: Communication → Route I
Step 3: Read ${PLUGIN_DIR}/commands/arena-business.md
        → --type communication --audience investor
        → Phase B0.1 Intensity Debate → standard decided
        → Execute at standard intensity
```

### Hackathon Comment Replies
```
Request: "Write replies to these hackathon project comments"

Step 1: Understand comment content + product description
Step 2: Communication → Route I
Step 3: Read ${PLUGIN_DIR}/commands/arena-business.md
        → --type communication --audience general
        → Phase B0.1 Intensity Debate
          intensity-advocate: "External image impact. standard or above needed"
          efficiency-advocate: "Comment replies are short and low-stakes. quick is sufficient"
          intensity-arbitrator: "quick. Small scope, low risk"
        → Execute Phase B0.5 only (Claude solo)
```

### Market Analysis
```
Request: "Analyze the customs automation market"

Step 1: WebSearch for market data
Step 2: Business analysis → Route H
Step 3: Read ${PLUGIN_DIR}/commands/arena-business.md
        → --type strategy
        → Phase B0.1 Intensity Debate → deep decided (data accuracy is critical for market analysis)
        → Execute at deep intensity (includes market research + accuracy audit)
```

### Multi-Route: Business Plan + Landing Page
```
Request: "Write a business plan and then build a landing page based on it"

Step 1: Read docs/ directory for existing business docs
Step 2: Multi-route detected → Route G (business plan) then Route A (landing page)
Step 3:
  Sub-task 1: Read ${PLUGIN_DIR}/commands/arena-business.md
    → --type content
    → Phase B0.1 → deep → Execute full business pipeline
    → OUTPUT: completed business plan

  Sub-task 2: Read ${PLUGIN_DIR}/commands/arena.md
    → INPUT CONTEXT: business plan from Sub-task 1
    → Phase 0.1 → standard → Build landing page reflecting business plan
```

### Multi-Route: PR Review + Release Notes
```
Request: "Review PR #15 and draft release notes for the changes"

Step 1: gh pr view 15 → understand changes
Step 2: Multi-route detected → Route D (PR review) then Route G (release notes)
Step 3:
  Sub-task 1: Read ${PLUGIN_DIR}/commands/multi-review.md
    → --pr 15 → Execute code review pipeline
    → OUTPUT: review findings + change summary

  Sub-task 2: Read ${PLUGIN_DIR}/commands/arena-business.md
    → --type content --audience general
    → INPUT CONTEXT: PR changes + review findings from Sub-task 1
    → Write release notes based on actual changes
```
