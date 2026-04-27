# AI Review Arena Architecture Modernization

Last updated: 2026-04-27

## Current assessment

AI Review Arena uses current agent-review ideas and is intentionally CLI-first. Its runtime is still partially dominated by Bash, Markdown command pipelines, temporary files, and loosely typed external CLI wrappers. That is acceptable for a plugin prototype, but it is fragile for a production-grade CLI orchestration system.

The repository now defaults to user-configured CLI models and stores current model names as explicit override recommendations, removes the deprecated Gemini 3 Pro preview default, enables the documented hook behavior, disables auto-fix by default, and removes `codex exec --full-auto` as the default Codex review path. See `docs/model-selection.md` for the exact inheritance and override policy.

## Target architecture

The long-term runtime should be split into these layers:

1. `runner`: a typed Python or TypeScript state machine that owns phases, retries, timeouts, state persistence, and error recovery.
2. `providers`: isolated CLI adapters for Claude Code, Codex, Gemini, and local/open-weight runners.
3. `schemas`: shared JSON Schemas or Pydantic/Zod models for findings, debates, challenges, defenses, reports, costs, and benchmark results.
4. `policy`: safety policy for tool allowlists, MCP approvals, auto-fix permissions, write scopes, and credential boundaries.
5. `observability`: structured traces for CLI calls, model calls, exit codes, output sizes, token/cost estimates, latency, cache hits, and confidence changes.
6. `compatibility`: shell scripts that preserve existing plugin commands while delegating complex work to the typed runner.

## Implemented runtime layer

The first typed runtime layer now lives in `arena_runtime/`:

1. `arena_runtime.orchestrator` handles Claude/Gemini-style hook payloads and writes structured pending-change and trace records.
2. `arena_runtime.providers` contains CLI-first provider adapters with timeout, environment, exit-code, command allowlist, and trace boundaries.
3. `arena_runtime.policy` enforces tool allowlists, command allowlists, side-effect approvals, scoped credential checks, and write-root boundaries.
4. `arena_runtime.evaluation` supports line-level matching, false-positive/false-negative counts, and severity-weighted scoring.
5. `arena_runtime.observability` writes JSONL traces for CLI calls, model calls, exit codes, output sizes, latency, cost estimates, and runtime events.
6. `arena_runtime.autofix` creates isolated patch artifacts instead of directly applying production edits.
7. `arena_runtime.core_cli` owns the former shell-only utility surface for severity normalization, config validation, provider-output validation, findings aggregation, and report generation.

Hook orchestration now goes directly through `scripts/arena-runtime.py` and `arena_runtime.orchestrator`. The old `scripts/orchestrate-review.sh` Bash entrypoint has been removed.

`config/runtime-pipeline.json` is the structured runtime phase plan. Markdown command files remain compatibility documentation and Claude Code command guidance, not the only source of runtime state.

Retired shell entrypoints:

- `scripts/orchestrate-review.sh`
- `scripts/gemini-hook-adapter.sh`
- `scripts/aggregate-findings.sh`
- `scripts/normalize-severity.sh`
- `scripts/generate-report.sh`
- `scripts/validate-config.sh`

## Provider rules

- Provider integrations are CLI-first. Do not add non-CLI execution paths unless the product direction explicitly changes.
- CLI calls must run through typed adapters that enforce command allowlists, timeout limits, environment pass-through, exit-code handling, and structured trace records.
- Codex and Gemini should inherit the user's default model unless an explicit override is configured for reproducible benchmarks.
- Claude workflows should use capability profiles and model-capability checks only after benchmark evidence exists.
- Open-weight models can be added through local CLI adapters, but they should not replace hosted frontier reviewers without benchmark evidence.

## MCP and tool security

MCP is useful for tool interoperability, but it is not a complete production security layer by itself. Any MCP integration in this project must add:

1. explicit allowed tool lists,
2. approval requirements for side-effecting tools,
3. scoped credentials per provider or connector,
4. structured tool errors that the runner can classify,
5. prompt-injection handling for repository content and external documents,
6. audit logs for tool calls and approvals.

## Auto-fix policy

Auto-fix is intentionally disabled by default. It can be enabled only when:

1. the finding has high confidence,
2. the patch is inside the user's requested write scope,
3. the change is low-risk or explicitly approved,
4. verification commands are provided by the user or project policy,
5. rollback behavior is deterministic.

## Migration rule

Do not expand the Bash orchestration surface. New features should either be configuration/documentation changes or should land in a typed runner with a compatibility wrapper.
