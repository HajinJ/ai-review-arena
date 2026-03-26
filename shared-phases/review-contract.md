# Review Contract Generation

Phase 5.95 — executed before Phase 6 review entry for standard/deep/comprehensive intensity.

Generates a review contract that defines "what counts as a valid finding" for the current codebase, reducing false positives by codifying accepted patterns and known technical debt.

## Inputs

- `CONVENTIONS` (from Phase 0.5) — project coding conventions and patterns
- `STACK_DETECTION` (from Phase 1) — languages, frameworks, build tools
- `COMPLIANCE_GUIDELINES` (from Phase 3, if available) — applicable compliance rules
- Project-level `.ai-review-arena.json` overrides (if `review_contract` field exists)

## Contract Generation Steps

### Step 1: Auto-Detect Accepted Patterns

Analyze the codebase to extract patterns that are used consistently and intentionally:

```
FOR each pattern category:
  1. Naming conventions:
     - Scan 20+ identifiers to determine dominant style (camelCase vs snake_case)
     - Record frequency ratio (e.g., "camelCase: 95%, snake_case: 5%")
     - Dominant pattern (>80% usage) → accepted_pattern

  2. Error handling patterns:
     - Detect try/catch vs Result/Either vs error-first callback
     - Record which pattern is used in >70% of error sites
     - Dominant pattern → accepted_pattern

  3. Import style:
     - Relative vs absolute imports
     - Barrel exports (index.ts re-exports) usage
     - Named vs default exports preference

  4. State management:
     - Framework-specific patterns (useState, Redux, Vuex, etc.)
     - Data fetching patterns (fetch, axios, SWR, React Query)

  5. Test conventions:
     - Test file naming (*. test.* vs *.spec.*)
     - Test structure (describe/it vs test())
     - Mock/stub patterns
```

### Step 2: Merge with User Overrides

If the project contains `.ai-review-arena.json` with a `review_contract` field, merge it with auto-detected patterns:

```
User override fields:
  - accepted_patterns: string[]
    Patterns explicitly marked as acceptable (e.g., "any-style assertions in tests")

  - severity_overrides: { [category]: severity }
    Override default severity for specific categories
    (e.g., { "naming_convention": "low" } to deprioritize naming issues)

  - focus_areas: string[]
    Categories to prioritize (e.g., ["security", "data-integrity"])
    Findings in focus areas get +10 confidence boost

  - ignore_paths: string[]
    Glob patterns for paths excluded from review
    (e.g., ["scripts/legacy/**", "generated/**"])

  - known_debt: string[]
    Known technical debt items that should NOT be reported as findings
    (e.g., "TODO comments in auth module — tracked in JIRA-123")

Merge priority: user_overrides > auto_detected
Conflicts: user overrides always win
```

### Step 3: Generate Contract Document

Assemble the review contract from auto-detected patterns and user overrides:

```json
{
  "review_contract": {
    "accepted_patterns": [
      "camelCase naming for variables and functions",
      "PascalCase for classes and components",
      "try/catch error handling with custom error classes",
      "relative imports within module boundaries",
      "barrel exports via index.ts files"
    ],
    "severity_overrides": {},
    "focus_areas": [],
    "ignore_paths": [],
    "known_debt": [],
    "generated_at": "ISO 8601 timestamp",
    "source": "auto | user_override | auto+user_override"
  }
}
```

## Distribution

The contract is distributed to Phase 6 reviewers in their spawn context. Each reviewer MUST:

1. **Check accepted_patterns** before reporting a finding — if the code follows an accepted pattern, do NOT report it
2. **Apply severity_overrides** — if a category has an override, use the overridden severity
3. **Boost focus_areas** — findings in focus areas get +10 confidence
4. **Skip ignore_paths** — do not review files matching ignore patterns
5. **Skip known_debt** — do not report known technical debt items as new findings

## Output

The contract is stored as `REVIEW_CONTRACT` and passed to Phase 6 reviewer spawn prompts.

## Error Handling

- **No conventions detected** (Phase 0.5 skipped or empty): Generate contract with empty `accepted_patterns`; all patterns are fair game for review
- **No user overrides file**: Use auto-detected patterns only; set `source: "auto"`
- **Malformed user overrides**: Log warning, skip malformed fields, use auto-detected patterns for those fields
- **Empty codebase** (no files to analyze): Skip contract generation; Phase 6 proceeds without contract
