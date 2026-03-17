# TODO: External Integration Improvements

Research completed 2026-02-26. These items require external API changes or features that are not yet stable enough for production integration.

---

## 1. Codex Sub-Agent Integration

**Status**: Fully migrated (2026-03-17) — new-format custom agents, CSV batch review, per-agent model config
**Priority**: High
**Blocked by**: ~~Codex multi-agent feature graduating from experimental~~ GA as of March 2026

### Current State (Mar 2026)
- Codex CLI subagents now GA with full custom agent support
- Replaced `config/codex-agents/` with new `.codex/agents/` project-scoped format
- Per-agent model and reasoning effort configuration
- CSV batch review support via `spawn_agents_on_csv`
- Display nicknames for parallel agent UI readability

### Implementation History

**Phase 1 — Structured Output** (2026-02-26, active by default):
- Created 5 JSON schemas in `config/schemas/`
- Updated review scripts to use `--output-schema` + `-o` flags
- Controlled by `models.codex.structured_output` config (default: `true`)

**Phase 2 — New-Format Custom Agents** (2026-03-17, active by default):
- Created `.codex/config.toml` — project-level Codex config with `max_threads=6`, `max_depth=1`, `job_max_runtime_seconds=300`
- Created 5 new-format agents in `.codex/agents/` with top-level schema:
  - `security-reviewer.toml` — gpt-5.4, high reasoning, nicknames: Sentinel/Aegis/Guardian/Shield/Warden
  - `bug-detector.toml` — gpt-5.4, high reasoning, nicknames: Sherlock/Inspector/Tracker/Scout/Sleuth
  - `performance-reviewer.toml` — gpt-5.3-codex-spark, medium reasoning, nicknames: Flash/Turbo/Blaze/Nitro/Bolt
  - `architecture-reviewer.toml` — gpt-5.4, high reasoning, nicknames: Blueprint/Compass/Keystone/Pillar/Atlas
  - `test-coverage-reviewer.toml` — gpt-5.3-codex-spark, medium reasoning, nicknames: Validator/Prober/Checker/Verifier/Auditor
- Each agent has full `developer_instructions` inlined (no external prompt file dependency)
- Each agent includes duplicate prompt technique (arxiv 2512.14982) with `[CORE INSTRUCTION REPEAT]`
- Updated `codex-review.sh` — agent resolution: `.codex/agents/` (project) → `~/.codex/agents/` (user)
- Created `scripts/codex-batch-review.sh` — CSV batch review with `spawn_agents_on_csv` + parallel fallback
- Removed legacy `config/codex-agents/` directory

### Agent Resolution Priority
1. `.codex/agents/{agent-name}.toml` (project-scoped)
2. `~/.codex/agents/{agent-name}.toml` (user-scoped)

### Key Config Knobs
| Setting | Type | Purpose |
|---------|------|---------|
| `agents.max_threads` | number | Max concurrent agent threads (default: 6) |
| `agents.max_depth` | number | Max nesting depth (default: 1) |
| `agents.job_max_runtime_seconds` | number | Per-worker timeout for CSV batch jobs (default: 300) |
| `multi_agent.agents_dir` | string | Agent directory (default: `.codex/agents`) |
| `multi_agent.batch_review.enabled` | boolean | Enable CSV batch review (default: true) |
| `multi_agent.batch_review.max_files_per_batch` | number | Max files per batch (default: 50) |

### Limitations
- Sub-agents inherit parent sandbox; cannot escalate permissions
- Context window pollution across many files (each sub-agent has independent context)
- Cost scales linearly with sub-agent count
- `spawn_agents_on_csv` requires Codex GA; fallback uses parallel subprocesses

### Sources
- [Codex Subagents Documentation](https://developers.openai.com/codex/subagents/)
- [Codex Custom Agents](https://developers.openai.com/codex/custom-agents/)
- [Codex CLI Reference](https://developers.openai.com/codex/cli/reference/)
- [Codex Configuration Reference](https://developers.openai.com/codex/config-reference/)

---

## 2. OpenAI Responses API WebSocket Mode

**Status**: Implemented (2026-02-26) — feature-flagged, disabled by default
**Priority**: Medium
**Blocked by**: ~~Need to refactor debate scripts~~ Done — requires `pip install openai>=2.22.0`

### Current State (Feb 2026)
- WebSocket mode for Responses API released 2026-02-23 in OpenAI Python SDK v2.22.0
- Endpoint: `wss://api.openai.com/v1/responses`
- Connection limit: 60 minutes per connection
- Sequential processing only (one in-flight response per connection)

### Performance Gains
| Scenario | Improvement |
|----------|-------------|
| Tool-heavy workflows (20+ calls) | ~40% faster |
| Complex multi-file operations | ~39% faster |
| Simple tasks | ~15% faster |
| Best case | ~50% faster |

**Trade-off**: Initial WebSocket handshake adds slight TTFT overhead on short tasks.

### Implementation (2026-02-26)
- Created `scripts/openai-ws-debate.py`: WebSocket debate client using OpenAI Responses API
  - Runs all 3 debate rounds on single persistent connection via `previous_response_id`
  - Falls back to standard HTTP if WebSocket mode unavailable
  - Matches `run-debate.sh` output format: `{accepted, rejected, disputed}`
  - Compatible with `store=false` for Zero Data Retention
- Created `requirements.txt` with `openai>=2.22.0` dependency
- Added WebSocket fast path in `run-debate.sh` — checks Python 3, openai package, and `websocket.enabled` config
- Controlled by `websocket.enabled` config (default: `false`)
- No breaking changes: falls through to existing bash debate logic if any precondition fails

### Original Integration Plan
1. ~~Create WebSocket client~~ Done: `scripts/openai-ws-debate.py`
2. ~~Update debate scripts~~ Done: `run-debate.sh` WebSocket fast path
3. Compatible with `store=false` and Zero Data Retention (in-memory state only)

### Key Technical Details
- Server keeps one previous-response state in connection-local in-memory cache
- After disconnect: use `/responses/compact` endpoint for compacted context
- No multiplexing: use multiple connections for parallel runs

### Reconnection Strategies
1. Continue with `previous_response_id` (if `store=true`)
2. Start fresh with full input context
3. ~~Use compacted output from `/responses/compact`~~ **Implemented** (2026-03-06)

### Context Compaction on Reconnection (2026-03-06)

**Applied**: `compact_context()` function in `openai-ws-debate.py` implements E3 (Codex compaction) philosophy.

**Implementation**:
- On WebSocket connection failure during retry, if `compaction.enabled=true` and a `previous_response_id` exists, context is compacted via HTTP before reconnecting
- Compaction preserves: finding indices + status, key evidence, confidence adjustments
- Controlled by `websocket.compaction` config (default: enabled)
- Falls back to fresh reconnection if compaction fails

**Design Principles** (from knowledge-base E3):
- Compaction is information preservation, not simple summarization
- System prompt preserved identically through compaction
- Decision context and finding status are explicitly requested to be retained
- Intermediate reasoning is compressed, final assessments are preserved

### Sources
- [WebSocket Mode - OpenAI Official Docs](https://developers.openai.com/api/docs/guides/websocket-mode/)
- [OpenAI Python SDK v2.22.0](https://github.com/openai/openai-python/releases)
- [Cline WebSocket Test Results](https://x.com/cline/status/2026031848791630033)
- [H2S Media: WebSocket API Performance](https://www.how2shout.com/news/openai-websocket-api-agent-latency-40-percent-faster.html)

---

## 3. Claude Code Remote Control Session Monitoring

**Status**: Research Preview (Pro/Max plans only)
**Priority**: Low
**Blocked by**: No programmatic API for Remote Control sessions; interactive-only

### Current State (Feb 2026)
- `claude remote-control` or `/remote-control` starts a remote session
- Session runs locally; web/mobile interface is a window into it
- Reconnects automatically if laptop sleeps (10-minute timeout on network loss)
- One remote session per Claude Code instance

### What Exists
- **Claude Code Analytics Admin API**: `/v1/organizations/usage_report/claude_code` for daily aggregated metrics (not per-session)
- **OpenTelemetry integration**: For general observability (not Remote Control specific)
- **No status/progress endpoint** for individual Remote Control sessions

### Integration Plan (When API Available)
1. **Pipeline progress monitoring**: If Anthropic adds a Remote Control status API, we could:
   - Start Arena pipeline via Remote Control
   - Poll progress from mobile/web
   - Receive notifications when each phase completes
2. **Multi-device review**: Start review on desktop, approve findings from mobile
3. **Background pipeline execution**: Run Arena as a Remote Control session, monitor from phone

### Current Workarounds
- Third-party projects: [Claude-Code-Remote](https://github.com/JessyTsui/Claude-Code-Remote) (email/Discord/Telegram notifications)
- Community tool: [clauderc.com](https://www.clauderc.com/) (unofficial web interface)

### Limitations
- Pro/Max plans only (not Team/Enterprise)
- API keys not supported (requires `/login` auth)
- `--dangerously-skip-permissions` not supported in Remote Control mode
- Terminal must stay open

### Sources
- [Claude Code Remote Control - Official Docs](https://code.claude.com/docs/en/remote-control)
- [Simon Willison's Coverage](https://simonwillison.net/2026/Feb/25/claude-code-remote-control/)
- [VentureBeat](https://venturebeat.com/orchestration/anthropic-just-released-a-mobile-version-of-claude-code-called-remote)

---

## 4. Gemini CLI Hooks v0.26 Cross-Compatibility

**Status**: Implemented (2026-02-26) — feature-flagged, disabled by default
**Priority**: Medium
**Blocked by**: ~~Need to create Gemini-compatible hook wrappers~~ Done

### Current State (Feb 2026)
- Gemini CLI v0.26.0 added comprehensive hooks system with 11 event types
- Architecture very similar to Claude Code hooks but not identical
- "Should only take a few minutes to adapt an existing Claude hook to Gemini CLI"

### Gemini CLI Hook Events (11 total)
| Event | Claude Code Equivalent | Notes |
|-------|----------------------|-------|
| `SessionStart` | `PreToolUse` (partial) | Session lifecycle |
| `SessionEnd` | None | Advisory, CLI does not wait |
| `BeforeAgent` | None | After prompt, before planning |
| `AfterAgent` | None | Agent loop completes |
| `BeforeModel` | None | Before LLM request (unique to Gemini) |
| `AfterModel` | None | After LLM response (per-chunk streaming) |
| `BeforeToolSelection` | None | Filter available tools |
| `BeforeTool` | `PreToolUse` | Validate/block operations |
| `AfterTool` | `PostToolUse` | Process results |
| `PreCompress` | None | Before context compression |
| `Notification` | None | System alerts |

### Implementation (2026-02-26)
- Created `hooks/gemini-hooks.json`: Gemini-native AfterTool hook config targeting `write_file|replace_in_file|patch`
- Created `scripts/gemini-hook-adapter.sh`: Translates Gemini hook stdin JSON to orchestrate-review.sh format
  - Parses `toolName` and `toolInput.path` from Gemini's AfterTool JSON
  - Checks file extension against reviewable extensions
  - Checks `gemini_hooks.enabled` config before running
  - Defensive: exits 0 on any unexpected input
- Updated `install.sh` (step 6/6): Detects Gemini CLI, merges hooks into `~/.gemini/settings.json`
- Updated `uninstall.sh`: Removes Arena hook entries from Gemini settings
- Controlled by `gemini_hooks.enabled` config (default: `false`)

### Future Gemini-Unique Hooks (not yet implemented)
- `BeforeModel`: Inject context density-filtered content before LLM request
- `AfterModel`: Stream-level redaction of sensitive output
- `BeforeToolSelection`: Restrict tools based on review phase

### Gemini Hook Configuration Hierarchy (4 levels)
1. Project: `.gemini/settings.json`
2. User: `~/.gemini/settings.json`
3. System: `/etc/gemini-cli/settings.json`
4. Extensions: Installed extension hooks

### Ralph Loop Pattern (Potential Adoption)
The "Ralph Loop" uses `AfterAgent` hook for autonomous multi-turn improvement:
- Agent iterates on code, clearing conversational context between turns
- Persistent state via files/git; fresh LLM context each turn
- Could be adapted for Arena's auto-fix loop (Phase 6.5)

### Sources
- [Gemini CLI Hooks Documentation](https://geminicli.com/docs/hooks/)
- [Google Developers Blog](https://developers.googleblog.com/tailor-gemini-cli-to-your-workflow-with-hooks/)
- [Ralph Extension](https://github.com/gemini-cli-extensions/ralph)
- [The New Stack: Gemini CLI Hooks](https://thenewstack.io/gemini-cli-gets-its-hooks-into-the-agentic-development-loop/)

---

## 5. Agent Marketplace / Extension Bundling Pattern

**Status**: Design Phase
**Priority**: Low
**Blocked by**: Anthropic Cowork enterprise plugin marketplace not yet public

### Concept
Package AI Review Arena as a distributable extension that other teams can install, configure, and extend.

### Design Considerations
- Gemini CLI already has extension bundling with `gemini extensions install <url> --auto-update`
- Codex has `codex mcp-server` for MCP-based integration
- Claude Code has plugin system (`.claude-plugin/`) but no public marketplace yet
- Anthropic announced "Cowork" enterprise suite with plugin ecosystem

### Integration Plan (When Platform Available)
1. **Package as installable extension** for all 3 platforms:
   - Claude Code: Already works via `.claude-plugin/plugin.json`
   - Gemini CLI: Create extension manifest with hooks
   - Codex: Create MCP server wrapper
2. **Shared configuration schema** across all platforms
3. **Auto-update mechanism** for extension updates

---

---

## 6. Applied Research Findings (2026-02-26)

These research findings have been applied to the current codebase:

### 6a. Pink Elephant Effect Mitigation (arxiv 2602.11988)

**Applied**: All 27 agent specs reframed from negative ("When NOT to Report") to positive ("Reporting Threshold") framing.

**Evidence**: LLM-generated context files with negative instructions decrease SWE-bench success by 0.5%, AgentBench by 2%, and increase inference cost 20-23%. The "pink elephant effect" causes agents to focus MORE on what they're told NOT to do.

**Our approach**: Positive criteria ("report ONLY when exploitable + unmitigated + production-reachable") with recognized patterns listed as confirmations of mitigation, not prohibitions.

### 6b. Duplicate Prompt Technique (arxiv 2512.14982)

**Applied**: Core review instructions repeated in codex-review.sh, gemini-review.sh, and business variants.

**Evidence**: 47/70 benchmark wins, 0 losses for non-reasoning LLMs. Gemini Flash-Lite accuracy improved from 21.33% to 97.33% on NameIndex. No output token or latency increase. Effect diminishes with 3x repetition vs 2x.

**Limitation**: Only effective for non-reasoning mode. Claude agents using extended thinking do not benefit (5 wins, 1 loss, 22 ties in reasoning mode).

### 6c. Stale Review Invalidation (Code Factory)

**Applied**: Git-hash-based review freshness check in orchestrate-review.sh + aggregate-findings.sh.

**Mechanism**: Commit hash stored when review starts. Before aggregation, current HEAD is compared. If changed, findings are marked `stale: true` with warning banner in generated reports.

### 6d. Prompt Cache-Aware Cost Estimation

**Applied**: `cost_estimation.prompt_cache_discount` config in default-config.json. Cost estimator applies discount to input token pricing.

**Background**: Claude prompt caching (prefix-matching) can reduce input costs by up to 90%. Agent workflows with stable system prompts typically achieve 40-60% effective discount. Default is 0.0 (conservative).

### 6e. Visual Feedback Verification (C2: Agentation Philosophy)

**Applied**: Phase 6.7 (visual-verification) added to the code review pipeline.

**Evidence**: Frontend AI coding bottlenecks stem from feedback delivery accuracy, not model performance (Benji Taylor / Agentation). CSS selector extraction provides 10x more precise UI change feedback than natural language descriptions.

**Our approach**: Phase 6.7 detects frontend files, extracts CSS selectors from affected components, generates visual regression checklists with risk assessment, and integrates with Agentation MCP when available.

### 6f. BM25 Memory Search (C3: QMD Philosophy)

**Applied**: `feedback-tracker.sh search` command with BM25-style term frequency scoring across feedback data and memory tiers.

**Evidence**: QMD's BM25 search resolves 300-file searches in 1 second vs 3 minutes for grep (Artem Zhutov). Applied to feedback routing: instead of naive file grep, BM25 scores feedback records by term relevance, enabling pattern-based model routing from accumulated review history.

**Our approach**: `cmd_search()` implements BM25 with k1=1.2, b=0.75 standard parameters. Searches across feedback JSONL and all configured memory tiers (short-term/long-term/permanent). Returns top-N results ranked by relevance score.

### 6g. Context Compaction Strategy (E3: Codex Compaction Philosophy)

**Applied**: `compact_context()` in `openai-ws-debate.py` implements information-preserving compaction on WebSocket reconnection.

**Evidence**: Codex compaction research reveals that compaction should be treated as an "information preservation strategy," not simple summarization. Decision context and status must be explicitly preserved through compression.

**Our approach**: On WebSocket failure during debate retry, context is compacted via HTTP, explicitly preserving finding indices, challenge statuses, evidence, and confidence adjustments. Intermediate reasoning is compressed while final assessments are retained.

### Sources
- [AGENTS.md Benchmark Paper](https://arxiv.org/abs/2602.11988)
- [Duplicate Prompt Paper](https://arxiv.org/abs/2512.14982)
- [Code Factory Framework](https://ryancarson.com/code-factory/)
- [Claude Code Prompt Caching](https://www.anthropic.com/engineering/prompt-caching-in-claude-code)
- [Agentation (C2)](https://www.npmjs.com/package/agentation) — CSS selector extraction for visual feedback
- [QMD Memory System (C3)](https://github.com/tobias-shopify/qmd) — BM25 + semantic search for intelligent retrieval
- [Codex Compaction Internals (E3)](https://developers.openai.com/codex/compact/) — Context compression architecture

---

## 7. Documentation Review Pipeline (Route J-K)

**Status**: Implemented (2026-03-06) — active by default
**Priority**: High
**Blocked by**: None — implemented

### Implementation (2026-03-06)

Added complete documentation review pipeline with 6 specialized review agents and full lifecycle orchestration:

**Pipeline Command**: `commands/arena-docs.md`
- 12 phases (D0 through D7) following business pipeline pattern
- Doc-specific phases: D0.5 (Documentation Inventory), D1 (Code-Doc Diff Analysis), D6.6 (Example Code Validation)
- Intensity levels: quick/standard/deep/comprehensive
- Arguments: `--category`, `--mode review|generate`

**6 Review Agents** (all with hardened reporting threshold + error recovery + rules):
- `doc-accuracy-reviewer`: Code-documentation alignment, API signature verification
- `doc-completeness-reviewer`: Undocumented public APIs, missing sections/params/errors
- `doc-freshness-reviewer`: Deprecated references, stale versions, dead links, tech drift
- `doc-readability-reviewer`: Progressive disclosure, audience fit, structure, scannability
- `doc-example-reviewer`: Code example runnability, output accuracy, security
- `doc-consistency-reviewer`: Terminology, cross-references, naming conventions, tone
- `doc-debate-arbitrator`: Synthesizes consensus with category-specific weighting

**External CLI Integration**:
- `scripts/codex-doc-review.sh`: Codex CLI wrapper with 6 doc categories, structured output schema
- `scripts/gemini-doc-review.sh`: Gemini CLI wrapper with 6 doc categories
- `scripts/benchmark-doc-models.sh`: Doc-specific benchmarking with `doc-` prefix test cases
- `scripts/doc-inventory.sh`: Documentation inventory scanner with type classification

**Schemas**: `codex-doc-review.json`, `codex-doc-cross-review.json`
- Doc-specific `location` object (file + section + line) instead of flat section string
- `doc_type` and `related_source` fields for code-doc correlation

**Benchmarks**: 8 test cases covering all 6 categories
- doc-accuracy-test-01/02: Signature/config mismatch detection
- doc-completeness-test-01: Undocumented endpoint detection
- doc-freshness-test-01: Stale tooling/version detection
- doc-readability-test-01: Audience mismatch detection
- doc-example-test-01: Security/import/method issues in code examples
- doc-consistency-test-01/02: Terminology conflicts, command inconsistencies

**Review Prompts**: 6 category-specific prompts for Codex CLI

**Config**: `docs`, `docs_intensity_presets`, `docs_debate`, `docs_models`, `docs_benchmarks` + agent responsibility matrix + context density role filters

**Router**: Routes J (Documentation Review) and K (Documentation Generation) added to ARENA-ROUTER.md. Multi-route execution order: Code → Documentation → Business.

---

## Summary: Priority Matrix

| Item | Priority | Status | Can Start Now? |
|------|----------|--------|----------------|
| Codex `--output-schema` | High | **Done** | Implemented (active by default) |
| Codex sub-agent roles | High | **Done** | Implemented (feature-flagged) |
| WebSocket debate acceleration | Medium | **Done** | Implemented (feature-flagged) |
| Gemini hook adapter | Medium | **Done** | Implemented (feature-flagged) |
| Remote Control monitoring | Low | No API | No |
| Agent marketplace | Low | Design phase | No |
| Pink elephant fix | **Done** | Applied | Completed |
| Duplicate prompt | **Done** | Applied | Completed |
| Stale review invalidation | **Done** | Applied | Completed |
| Cache-aware cost estimation | **Done** | Applied | Completed |
| WebSocket compaction on reconnect | **Done** | Applied | Completed |
| BM25 feedback search | **Done** | Applied | Completed |
| Visual verification phase | **Done** | Applied | Completed |
| Documentation review pipeline (Route J-K) | High | **Done** | Implemented (active by default) |
