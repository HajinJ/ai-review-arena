# Commit/PR Safety Protocol

Commits and PRs affect shared state (repository history, team visibility). They require a mandatory review step and explicit user confirmation before execution.

## Commit Request

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

## PR Request

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
