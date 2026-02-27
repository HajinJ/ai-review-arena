# ARENA-ROUTER.md - AI Review Arena Routing System v3.2

## Core Rule

**Every request goes through the Arena pipeline by default.** The pipeline runs unless the request matches one of the explicit exemptions below.

### Exempt Requests (NO pipeline — respond directly)

1. `--no-arena` flag is explicitly provided
2. User directly invokes a slash command (`/arena`, `/multi-review`, etc.)
3. **Meta questions about the Arena plugin itself** (e.g., "How does Arena work?")
4. **Pure conversational exchanges** with no task intent (e.g., "Hello", "Thanks")
5. **Claude Code CLI usage questions** (e.g., "/help", "How do I configure MCP?")

### NOT Exempt (MUST go through pipeline)

| Request | Route |
|---------|-------|
| "What does this code do?" / "Explain this function" | F (quick) |
| "Commit this" | F → Commit Safety Gate |
| "Create a PR" | D → PR Safety Gate |
| "Why is this erroring?" | F or A |
| "Run the tests" / "Update the README" | F (quick) |
| "Refactor this code" | E |
| "Analyze the market" | H |

**When in doubt: route it.**

---

## Plugin Directory

```
PLUGIN_DIR = ~/.claude/plugins/ai-review-arena
```

---

## Process: 3 Steps

1. **Context Discovery** — Gather external info (issues, PRs, Figma, files, git state)
2. **Route Selection** — Classify intent into one of 9 routes
3. **Pipeline Execution** — Read command file via Read tool, execute pipeline

### Step 1: Context Discovery

| Request Pattern | Discovery Action |
|----------------|-----------------|
| Issue/ticket reference | `gh issue list` → `gh issue view N` |
| PR reference | `gh pr view N` |
| Figma URL | Figma MCP |
| File/directory reference | Read/Glob target code |
| Ambiguous request | `git diff`, `git status` |
| External library mention | WebSearch for docs |
| Business document reference | Read docs/ directory |
| Competitor/market analysis | WebSearch for market data |

Skip discovery if the request already contains sufficient context.

### Step 2: Route Selection

Works regardless of language (Korean, English, Japanese, etc.).

#### Code Routes (A-F)

| Route | Intent |
|-------|--------|
| **A: Feature Implementation** | Build new features or add functionality |
| **B: Pre-Implementation Research** | Investigate methodologies, best practices, technology comparisons |
| **C: Stack Analysis** | Understand project technology stack |
| **D: Code Review** | Review existing code, PRs, find problems |
| **E: Refactoring** | Improve existing code structure, quality, performance |
| **F: Simple Change** | Small modifications, explanations, commits, trivial tasks |

#### Business Routes (G-I)

| Route | Intent |
|-------|--------|
| **G: Business Content** | Business plans, pitch decks, proposals, marketing copy |
| **H: Business Analysis** | Market research, SWOT, competitive analysis, strategy |
| **I: Communication** | Investor Q&A, customer emails, presentations |

#### Multi-Route Requests

Requests with 2+ distinct intents are decomposed and run sequentially with context forwarding. Business routes execute before code routes. See `docs/context-forwarding.md` for the forwarding interface and token limits.

#### Route Selection Principles

1. Clear intent → go directly to that route
2. Complex intent → choose the more comprehensive route (A over F, G over I)
3. Unknown code intent → default Route A; unknown business intent → default Route G
4. Multi-route detected → decompose and execute sequentially

### Step 3: Pipeline Execution

1. **Load command file** from the mapping table below using the **Read tool**
2. **Execute pipeline** following the Phases defined in the command file exactly
3. **Pass arguments** from Context Discovery and Route Selection

**Never invoke via slash commands. Always read the command file directly with the Read tool.**

#### Command File Mapping

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

#### Commit/PR Safety Protocol

Commits and PRs require **mandatory review + explicit user confirmation**. See `docs/safety-protocol.md` for the full protocol.

- **Commit**: Route F (quick) → Phase 0.5 → Commit Safety Gate → AskUserQuestion
- **PR**: Route D (standard+) → full review pipeline → PR Safety Gate → AskUserQuestion

---

## Intensity Decision

Determined in two stages: a **fast pre-filter**, then an **Agent Teams debate** if needed. See `shared-phases/intensity-decision.md` for the full debate protocol.

### Phase 0.1-Pre: Quick Pre-Filter (Rule-Based)

**Auto-assign `quick`** when Route F AND: single rename/typo/import fix, code explanation, docs minor edit, single function addition, test execution.

**Auto-assign `standard`** when: Route D with `--pr` and diff < 500 lines, or Route E with single file.

**Always require debate** for: Route A, B, C, G, H, I; auth/payment/security tasks; multi-module tasks; issue-based work.

Commits and PRs are NOT eligible for auto-quick — they always go through the Safety Protocol.

### Intensity Phase Scope

| Intensity | Code Phases | Business Phases |
|-----------|-------------|-----------------|
| `quick` | 0 → 0.1-Pre → 0.5 | B0 → B0.1-Pre → B0.5 |
| `standard` | 0 → 0.1 → 0.2 → 0.5 → 1 → 5.5 → 6 → 6.5 → 7 | B0 → B0.1 → B0.2 → B0.5 → B1 → B5.5 → B6 → B6.5 → B7 |
| `deep` | + Phase 2, 2.9, 3 | + B2, B2.9, B3 |
| `comprehensive` | + Phase 4, 5 | + B4 |

---

## Argument Extraction

| Target | Passed As |
|--------|-----------|
| Figma URL | `--figma <url>` |
| PR number | `--pr <number>` |
| Focus area | `--focus <area>` |
| Target paths | pipeline context |
| Explicit intensity | `--intensity <level>` |
| Business type | `--type <type>` |
| Target audience | `--audience <audience>` |
| Tone | `--tone <tone>` |

---

## MCP Dependency Detection

When an MCP is needed: check via ToolSearch → if missing, suggest install via AskUserQuestion.
Patterns: Figma URL → Figma MCP, test/E2E → Playwright MCP, Notion → Notion MCP.

---

## Examples

### Simple Rename
```
Request: "Rename this function to calculateScore"
→ Route F → Phase 0.1-Pre: auto-quick → Phase 0.5 → Claude solo
```

### Feature Implementation
```
Request: "Implement OAuth login system"
→ Route A → Phase 0.1 Debate → comprehensive (security-critical)
→ Execute all phases
```

For more examples, see `docs/router-examples.md`.
