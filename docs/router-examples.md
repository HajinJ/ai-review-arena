# Arena Router Examples

Detailed routing examples for various request types.

## Issue-Based Work
```
Request: "Handle the next issue from my git issues"

Step 1: gh issue list → select next → gh issue view N → understand content
Step 2: Issue content says "Add lobby system" → Route A (Feature Implementation)
Step 3: Read ${PLUGIN_DIR}/commands/arena.md
        → Phase 0 → Phase 0.1 Intensity Debate
          intensity-advocate: "Multiplayer involves networking + security + concurrency. comprehensive needed"
          efficiency-advocate: "Lobby alone is manageable. deep is sufficient"
          risk-assessor: "Game service requires security + compliance attention"
          intensity-arbitrator: "deep. Lobby itself doesn't warrant comprehensive"
        → Execute subsequent phases at deep intensity
```

## Production Deadlock Fix
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

## Code Explanation
```
Request: "What does this code do?"

Step 1: Context Discovery → Read/Glob target file
Step 2: Code explanation → Route F
Step 3: Read ${PLUGIN_DIR}/commands/arena.md
        → Phase 0 → Phase 0.1-Pre: Code explanation → auto-quick (skip debate)
        → Execute Phase 0.5 (codebase analysis for context) → Claude explains
```

## Commit
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

## Create PR
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

## OAuth Implementation
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

## Code Review
```
Request: "Review PR 42 with focus on security"

Step 1: gh pr view 42 → understand PR diff
Step 2: Code review → Route D
Step 3: Read ${PLUGIN_DIR}/commands/multi-review.md
        → Execute review pipeline with --pr 42 --focus security
```

## Refactoring
```
Request: "Clean up this service code"

Step 1: Identify target files/directory
Step 2: Code improvement → Route E
Step 3: Read ${PLUGIN_DIR}/commands/arena.md
        → Phase 0 → Phase 0.1 Intensity Debate → decide intensity
        → Execute with --phase codebase,review
```

## Business Plan Writing
```
Request: "Write a business plan for TradeFlow AI"

Step 1: Read docs/ directory for existing business docs
Step 2: Business content creation → Route G
Step 3: Read ${PLUGIN_DIR}/commands/arena-business.md
        → Phase B0 → Phase B0.1 Intensity Debate
          intensity-advocate: "Business plan is core to fundraising. deep needed"
          efficiency-advocate: "Existing documents provide strong foundation. standard is sufficient"
          risk-assessor: "Investor-facing. High brand/trust risk"
          intensity-arbitrator: "deep. External exposure + strategic importance"
        → Execute at deep intensity
```

## Investor Q&A Response
```
Request: "An investor asked about our TAM. Draft a response"

Step 1: Gather context — existing business docs, market data
Step 2: Communication → Route I
Step 3: Read ${PLUGIN_DIR}/commands/arena-business.md
        → --type communication --audience investor
        → Phase B0.1 → standard decided → Execute
```

## Market Analysis
```
Request: "Analyze the customs automation market"

Step 1: WebSearch for market data
Step 2: Business analysis → Route H
Step 3: Read ${PLUGIN_DIR}/commands/arena-business.md
        → --type strategy → Phase B0.1 → deep decided
        → Execute at deep intensity (includes market research + accuracy audit)
```

## Multi-Route: Business Plan + Landing Page
```
Request: "Write a business plan and then build a landing page based on it"

Step 1: Read docs/ directory for existing business docs
Step 2: Multi-route detected → Route G then Route A
Step 3:
  Sub-task 1: Read ${PLUGIN_DIR}/commands/arena-business.md
    → --type content → deep → Execute full business pipeline
    → OUTPUT: completed business plan

  Sub-task 2: Read ${PLUGIN_DIR}/commands/arena.md
    → INPUT CONTEXT: business plan from Sub-task 1
    → Phase 0.1 → standard → Build landing page
```

## Multi-Route: PR Review + Release Notes
```
Request: "Review PR #15 and draft release notes for the changes"

Step 1: gh pr view 15 → understand changes
Step 2: Multi-route detected → Route D then Route G
Step 3:
  Sub-task 1: Read ${PLUGIN_DIR}/commands/multi-review.md
    → --pr 15 → Execute code review pipeline
    → OUTPUT: review findings + change summary

  Sub-task 2: Read ${PLUGIN_DIR}/commands/arena-business.md
    → --type content --audience general
    → INPUT CONTEXT: PR changes + review findings from Sub-task 1
    → Write release notes based on actual changes
```
