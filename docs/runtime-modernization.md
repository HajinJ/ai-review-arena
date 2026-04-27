# Runtime Modernization Notes

AI Review Arena is now CLI-first with Python runtime orchestration.

## Runtime boundaries

Shell scripts under `scripts/` are compatibility entrypoints. They should only parse the local script directory, set `ARENA_PLUGIN_DIR` when needed, and `exec` the Python runtime.

Core command dispatch lives in `arena_runtime.entrypoint` and is exposed by:

- `python3 scripts/arena-runtime.py <command>`
- `python3 -m arena_runtime <command>`
- `ai-review-arena <command>` after installing the package metadata from `pyproject.toml`

## Provider execution

`arena_runtime.provider_runner` owns common Codex/Gemini review execution:

- validates review roles
- respects user-default model settings
- builds prompts from `config/review-prompts/<role>.txt`
- normalizes CLI responses into `{model, role, file, findings, summary}`

`scripts/codex-review.sh` and `scripts/gemini-review.sh` are wrappers only.

## Benchmark scoring

`arena_runtime.benchmarking` owns benchmark scoring and benchmark execution.

Scoring is more precise than legacy keyword counting:

- negation-aware keyword matching avoids counting statements such as `no XSS issue`
- structured fallback matches finding type/category/location hints
- severity-weighted precision/recall/F1 highlights critical misses more strongly
- severity accuracy is reported separately from detection F1

Runtime commands:

- `benchmark-score`
- `benchmark-models`
- `run-benchmark`
- `run-solo-benchmark`
- `benchmark-doc-models`
- `benchmark-business-models`

Benchmark execution is profile-based:

- `smoke`: one case, short timeout
- `standard`: bounded representative sample
- `calibration`: larger deterministic sample for scorer tuning
- `full`: exhaustive live CLI run

Live external CLI calls are explicit. Use `--live` or `--full` to call Codex/Gemini. Default and CI-safe runs report `live_disabled` rows instead of silently launching slow model calls.

Each benchmark row has a status such as `scored`, `live_disabled`, `model_unavailable`, `preflight_timeout`, `review_timeout`, `parse_error`, or `manual_required`. Summary blocks include `status_counts` so availability/runtime failures are not confused with model quality.

## Domain review runtime

`arena_runtime.domain_runtime` now owns documentation and business-content review execution:

- `codex-doc-review`
- `gemini-doc-review`
- `codex-business-review`
- `gemini-business-review`

The corresponding shell files are wrappers only.

## RAG runtime

`rag-indexer` and `rag-retrieve` are Python runtime commands backed by deterministic local token indexes. They do not require hosted embeddings or API keys.

Provider review prompts now receive bounded RAG evidence directly when an index exists. Retrieved chunks are marked as read-only untrusted context, prompt-injection patterns are surfaced as boundary metadata, and normalized findings receive `evidence_chunks` so reports can explain why a model made a claim.

Additional RAG commands:

- `rag-evidence`: emits the exact evidence chunks that would be attached to a provider prompt.
- `retrieval-benchmark`: measures retrieval recall@k and MRR against benchmark case file hints.

Retrieval now uses a hybrid local ranker:

- BM25-style term scoring over indexed token counts
- symbol/function/class metadata
- import/dependency metadata
- optional changed-file neighborhood boosting through `ARENA_CHANGED_FILES`
- tree-sitter chunking when `tree_sitter_languages` is available, with a deterministic line-block fallback

## Harness event bus and OpenTelemetry export

`arena_runtime.harness` adds a run-scoped event bus:

- events are written to `cache/runs/<run_id>/events.jsonl`
- state checkpoints are written to `cache/runs/<run_id>/state.json`
- `otel-export` converts events to OpenTelemetry-compatible JSONL spans or OTLP/HTTP JSON payloads
- `otel-push` can POST OTLP JSON to a collector endpoint

Provider review, retrieval, completion, and failure events now carry a shared `run_id`, `trace_id`, `span_id`, phase, provider, role, file, latency/count fields where available, and redacted metadata.

## Harness ablation benchmarks

`benchmark-harness-ablation` compares deterministic harness scenarios:

- `review_only`
- `review_plus_rag`
- `review_plus_debate`
- `full_harness`

The command is intentionally CLI-safe. It does not call external models unless future live modes explicitly add that behavior.

## Extension export

`export-extension` generates installable/profile-ready assets for:

- Codex: `AGENTS.md`, `.codex/agents/*`, and a read-only config snippet
- Gemini: `gemini-extension.json`, `GEMINI.md`, and a custom command file
- Claude: `CLAUDE.md`, `.claude/agents/*`, and hook settings for `hook-post-tool-use`

The exporter keeps the project CLI-first and avoids embedding hosted API credentials.

`install-claude-integration` applies the Claude integration to the current project by merging `.claude/settings.json`, creating `.claude/agents/*`, and adding a CLAUDE.md integration note. This is the command that turns generated integration assets into active Claude Code project configuration.

## MCP boundary runtime

`mcp-tool-call` is the local MCP boundary runner. It checks configured server/tool allowlists, side-effect approval, scoped environment pass-through, and command availability before invoking a configured local tool command. Default configuration has no executable MCP tools, so MCP execution is opt-in.

## Diagnostics

`cli-diagnostics` reports provider availability, CLI versions, configured model inheritance, recommended model hints, and optional live preflight latency with `--live`.

`legacy-inventory` classifies shell files as `wrapper`, `support_shell`, or `legacy_runtime_logic` so cleanup can be enforced mechanically.

## Additional legacy ports

The remaining orchestration utilities now dispatch through Python runtime commands:

- `batch-worktree-review`
- `codex-batch-review`
- `codex-cross-examine`
- `gemini-cross-examine`
- `doc-inventory`
- `harness-stress-test`
- `ralph-loop`
- `review-daemon`
- `search-best-practices`
- `search-guidelines`
- `stream-monitor`
- `stream-orchestrator`

Their shell files remain only as compatibility launchers.

## Support runtime

`arena_runtime.support_runtime` owns former shared shell utility behavior:

- `support-utils`: config loading, JSON extraction, project hashing, cache path helpers, timestamp formatting, atomic writes, content injection checks
- `benchmark-utils`: text extraction, keyword matching, precision/recall/F1, severity weights
- `setup`
- `setup-arena`

`scripts/utils.sh` and `scripts/benchmark-utils.sh` are source-compatible shims for older tests and third-party wrappers. They delegate implementation to Python.

## Legacy policy

Keep shell when the script is only a thin external CLI compatibility launcher. Move logic to Python when it performs JSON parsing, scoring, state management, policy decisions, or multi-step orchestration.
