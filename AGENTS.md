# AI Review Arena Agent Guide

This repository is a multi-model review plugin for Claude Code, Codex, and Gemini. Treat it as an agent orchestration system, not as a normal application server.

## Current model policy

- Use the user's Codex default model unless an explicit override is requested. Recommended explicit override for high-stakes Codex review, arbitration, architecture, security, and bug-finding work: `gpt-5.5`.
- Recommended explicit override for cost-sensitive Codex reviewer roles such as performance and test coverage: `gpt-5.4-mini`.
- Use the user's Gemini default model unless an explicit override is requested. Recommended explicit override: `gemini-3.1-pro-preview` or a newer Gemini 3.1 successor. Do not reintroduce the retired `gemini-3-pro-preview` default.
- Use Claude capability profiles keyed by current model IDs such as `claude-opus-4-7` and `claude-sonnet-4-6`.
- Prefer pinned model IDs for reproducible benchmarks and aliases only for interactive use.

## Safety rules

- Do not use `codex exec --full-auto` as a default review path. Review prompts contain untrusted repository content.
- Keep reviewer agents read-only unless a user explicitly asks for edits.
- Keep auto-fix opt-in. Require human approval for any generated patch that changes production code.
- Tool and MCP integrations must use explicit tool allowlists, scoped credentials, and approval gates for side-effecting operations.
- Structured output should be enforced by CLI schema flags or post-run schema validation, not by prompt text alone.

## Architecture direction

- Bash scripts remain compatibility wrappers. Do not add new complex orchestration logic to Bash.
- New provider integrations should be CLI-first and use `arena_runtime.providers` for timeout, env, exit-code, and trace boundaries.
- The default hook orchestration path is `arena_runtime.orchestrator`; legacy Bash orchestration has been removed from the core path.
- Long-running or multi-turn provider workflows should preserve structured CLI outputs and trace state rather than relying on ad-hoc transcript parsing.
- Findings should carry evidence, source model, role, confidence, severity, file, line, and validation status.
- Evaluation work should measure false positives, false negatives, severity calibration, cost, and latency by model version.

## Important paths

- `config/default-config.json` - default runtime configuration.
- `.codex/config.toml` - project-level Codex defaults.
- `.codex/agents/` - Codex custom reviewer roles.
- `agents/` - Claude reviewer role prompts.
- `scripts/` - CLI runtime wrappers and orchestration utilities.
- `arena_runtime/` - typed runtime for orchestration, providers, policy, observability, evaluation, and isolated patches.
- `commands/` - Claude Code command pipelines.
- `docs/architecture-modernization.md` - target architecture and migration rules.
- `docs/model-selection.md` - user-default model behavior and explicit override policy.
