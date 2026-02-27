# Configuration Reference

All settings for AI Review Arena. Every key has a default in `config/default-config.json`. Override at project or global level.

## Config Merge Order

Settings are deep-merged via `load_config()` in `utils.sh` using `jq -s '.[0] * .[1] * .[2]'`:

```
1. config/default-config.json          (built-in defaults, never edit)
2. ~/.claude/.ai-review-arena.json     (global overrides, all projects)
3. .ai-review-arena.json               (project-level overrides)
```

Later files win. Deep merge means you only need to specify the keys you want to change:

```json
// .ai-review-arena.json -- only overrides what you need
{
  "models": { "gemini": { "enabled": false } },
  "output": { "language": "en" }
}
```

Environment variables override config file values (see [Environment Variables](#environment-variables)).

---

## `models`

AI model configuration. Three model families: `claude`, `codex`, `gemini`.

### `models.claude`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Enable Claude agents for review |
| `roles` | string[] | `["security", "bugs", "architecture"]` | Review categories assigned to Claude |
| `agent_model` | string | `"sonnet"` | Claude model variant for agent tasks |
| `max_parallel_agents` | int | `3` | Max agents running concurrently |

### `models.codex`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Enable OpenAI Codex CLI |
| `roles` | string[] | `["bugs", "performance"]` | Review categories assigned to Codex |
| `command` | string | `"codex exec --full-auto"` | CLI command to invoke Codex |
| `timeout_seconds` | int | `120` | Max seconds per Codex invocation |
| `model_variant` | string | `"gpt-5.3-codex-spark"` | Codex model to use |
| `structured_output` | bool | `true` | Use `--output-schema` for guaranteed-valid JSON |
| `multi_agent.enabled` | bool | `true` | Enable Codex multi-agent sub-agents (5 TOML configs). Dual-gated: config AND runtime feature check |
| `multi_agent.max_threads` | int | `3` | Max parallel Codex sub-agent threads |
| `multi_agent.max_depth` | int | `1` | Max sub-agent nesting depth |
| `multi_agent.agents_dir` | string | `"config/codex-agents"` | Directory containing TOML agent configs |

### `models.gemini`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Enable Google Gemini CLI |
| `roles` | string[] | `["architecture", "testing"]` | Review categories assigned to Gemini |
| `command` | string | `"gemini"` | CLI command to invoke Gemini |
| `timeout_seconds` | int | `120` | Max seconds per Gemini invocation |
| `model_variant` | string | `"gemini-3-pro-preview"` | Gemini model to use |

**Example: Disable Codex, run Claude + Gemini only**
```json
{ "models": { "codex": { "enabled": false } } }
```

---

## `review`

Core code review settings.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `intensity` | string | `"standard"` | Default intensity: `quick`, `standard`, `deep`, `comprehensive` |
| `focus_areas` | string[] | `["security", "bugs", "architecture", "performance", "testing"]` | Active review categories |
| `confidence_threshold` | int | `75` | Minimum confidence (0-100) for a finding to appear in final report |
| `max_file_lines` | int | `500` | Max lines per file to include in review context |
| `file_extensions` | string[] | `["ts", "tsx", "js", ...]` | File types to review (16 extensions) |
| `exclude_patterns` | string[] | `["*.test.*", "*.spec.*", ...]` | Glob patterns to skip |
| `severity_threshold_adjustments` | object | see below | Confidence adjustments by severity level |

Severity threshold adjustments lower the effective confidence threshold for higher-severity findings:

| Severity | Adjustment | Effective Threshold (at default 75) |
|----------|-----------|-------------------------------------|
| `critical` | `-30` | 45 |
| `high` | `-15` | 60 |
| `medium` | `0` | 75 |
| `low` | `+10` | 85 |

**Example: Only review security and bugs**
```json
{ "review": { "focus_areas": ["security", "bugs"] } }
```

---

## `debate`

Code pipeline cross-examination settings.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Enable 3-round cross-examination |
| `max_rounds` | int | `3` | Number of debate rounds (1=review only, 2=+cross-exam, 3=+defense) |
| `cross_examination_enabled` | bool | `true` | Enable Round 2 cross-examination |
| `challenge_threshold` | int | `60` | Confidence below this triggers a challenge in Round 2 |
| `consensus_threshold` | int | `80` | Confidence above this = consensus reached |
| `require_majority` | bool | `true` | Require majority agreement for consensus |
| `web_search_enabled` | bool | `true` | Allow models to use web search during debate |
| `round2_timeout_seconds` | int | `180` | Timeout for Round 2 (cross-examination) |
| `round3_timeout_seconds` | int | `180` | Timeout for Round 3 (defense) |

**Example: Reduce debate to 2 rounds (skip defense)**
```json
{ "debate": { "max_rounds": 2 } }
```

---

## `hook_mode`

Auto-review on file write (Claude Code PostToolUse hook).

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `false` | Enable automatic review on file writes |
| `batch_size` | int | `5` | Number of file changes to batch before triggering review |
| `min_lines_changed` | int | `10` | Minimum lines changed to trigger review |
| `debounce_writes` | int | `3` | Number of rapid writes to debounce before reviewing |

---

## `gemini_hooks`

Gemini CLI AfterTool hook adapter.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Enable Gemini hook-to-Arena adapter |
| `event_types` | string[] | `["AfterTool"]` | Gemini hook event types to intercept |
| `tool_matchers` | string[] | `["write_file", "replace_in_file", "patch"]` | Tool names that trigger review |

---

## `websocket`

OpenAI WebSocket debate acceleration.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Use WebSocket for debate rounds (~40% faster). Falls back to HTTP |
| `url` | string | `"wss://api.openai.com/v1/responses"` | WebSocket endpoint |
| `connection_timeout_seconds` | int | `30` | Connection establishment timeout |
| `max_connection_minutes` | int | `55` | Max connection lifetime before reconnect |
| `store` | bool | `false` | Store responses server-side (not needed for WebSocket chaining) |
| `model` | string | `"gpt-5.3-codex-spark"` | Model to use for WebSocket debate |

---

## `output`

Report and display settings.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `language` | string | `"ko"` | Output language: `"ko"` (Korean), `"en"` (English) |
| `format` | string | `"markdown"` | Report format: `"markdown"`, `"json"` |
| `show_cost_estimate` | bool | `true` | Show token/cost breakdown in report |
| `show_model_attribution` | bool | `true` | Show which model produced each finding |
| `show_confidence_scores` | bool | `true` | Show confidence scores on findings |
| `show_debate_log` | bool | `false` | Include full debate transcript in report |
| `post_to_github` | bool | `false` | Post review comments to GitHub PR |

**Example: English output with debate log**
```json
{ "output": { "language": "en", "show_debate_log": true } }
```

---

## `intensity_presets`

Code pipeline phase scope per intensity level. These control which phases run and which agents participate.

### `quick`

| Key | Default | Description |
|-----|---------|-------------|
| `phases` | `["codebase"]` | Only Phase 0.5 (codebase analysis) |
| `agent_team` | `false` | No Agent Team spawned |
| `models_active` | `0` | No external models |
| `focus_areas_max` | `2` | Max 2 focus areas |
| `debate_rounds` | `0` | No debate |
| `file_lines_max` | `200` | Smaller file context |
| `reviewer_roles` | `[]` | No reviewer agents |

### `standard`

| Key | Default | Description |
|-----|---------|-------------|
| `models_active` | `2` | 2 external models |
| `focus_areas_max` | `4` | Max 4 focus areas |
| `debate_rounds` | `3` | Full 3-round debate |
| `file_lines_max` | `500` | Standard file context |
| `reviewer_roles` | 6 agents | security, bug-detector, performance, scope, test-coverage, observability |

### `deep`

| Key | Default | Description |
|-----|---------|-------------|
| `models_active` | `3` | All 3 models |
| `focus_areas_max` | `5` | All focus areas |
| `debate_rounds` | `3` | Full 3-round debate |
| `file_lines_max` | `1000` | Large file context |
| `reviewer_roles` | 10 agents | standard + architecture, dependency, api-contract, data-integrity |

### `comprehensive`

| Key | Default | Description |
|-----|---------|-------------|
| `models_active` | `3` | All 3 models |
| `focus_areas_max` | `5` | All focus areas |
| `debate_rounds` | `3` | Full 3-round debate |
| `file_lines_max` | `2000` | Maximum file context |
| `reviewer_roles` | 12 agents | deep + accessibility, configuration |

---

## `arena`

Code lifecycle orchestrator settings.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Enable Arena orchestrator |
| `phases` | string[] | `["codebase", "stack", "research", "compliance", "benchmark", "review"]` | Available pipeline phases |
| `default_phase` | string | `"all"` | Which phases to run by default |
| `interactive_by_default` | bool | `false` | Prompt for user input at decision points |

---

## `cache`

Knowledge cache for stack detection, research, compliance, benchmarks.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Enable caching |
| `base_dir` | string | `"~/.claude/plugins/ai-review-arena/cache"` | Cache storage directory |
| `default_ttl_days` | int | `3` | Default time-to-live in days |
| `max_cache_size_mb` | int | `50` | Max total cache size |
| `cleanup_age_days` | int | `30` | Delete entries older than this |

TTL overrides by cache type:

| Cache Type | TTL (days) |
|-----------|-----------|
| `stack` | 7 |
| `research` | 3 |
| `compliance` | 7 |
| `benchmarks` | 14 |
| `figma` | 1 |

---

## `benchmarks`

Code model benchmarking (Phase 4).

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Enable model benchmarking |
| `auto_run` | bool | `true` | Auto-run benchmarks when cache expires |
| `rerun_threshold_days` | int | `14` | Days before re-benchmarking |
| `min_score_for_role` | int | `60` | Minimum F1 score (0-100) to qualify for a review role |
| `test_cases_dir` | string | `"config/benchmarks"` | Directory containing benchmark test cases |

---

## `compliance`

Compliance rule checking (Phase 3).

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Enable compliance checking |
| `auto_detect` | bool | `true` | Auto-detect applicable rules from feature keywords |
| `rules_file` | string | `"config/compliance-rules.json"` | Feature-to-guideline mapping file |

---

## `routing`

Model-to-category role assignment strategy.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Enable feedback/benchmark-based routing |
| `strategy` | string | `"feedback_benchmark"` | Routing strategy: `"feedback_benchmark"`, `"benchmark_only"`, `"feedback_only"`, `"default"` |
| `fallback` | string | `"default"` | Fallback when insufficient data |
| `feedback_weight` | float | `0.6` | Weight of feedback accuracy in combined score |
| `benchmark_weight` | float | `0.4` | Weight of benchmark F1 in combined score |
| `min_feedback_samples` | int | `5` | Minimum feedback entries before using feedback for routing |

---

## `business`

Business pipeline settings.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Enable business pipeline |
| `default_type` | string | `"content"` | Default business type: `"content"`, `"strategy"`, `"communication"` |
| `default_audience` | string | `"general"` | Default audience: `"general"`, `"investor"`, `"customer"`, `"partner"`, `"internal"` |
| `default_tone` | string | `"formal"` | Default tone: `"formal"`, `"casual"`, `"persuasive"`, `"analytical"` |
| `focus_areas` | string[] | `["accuracy-evidence", "audience-fit", "competitive-positioning", "communication-narrative", "market-fit"]` | Active business review categories |
| `confidence_threshold` | int | `70` | Minimum confidence (0-100) for business findings |

---

## `business_intensity_presets`

Business pipeline phase scope per intensity level.

### `quick`

| Key | Default |
|-----|---------|
| `phases` | `["context"]` |
| `agent_team` | `false` |
| `review_agents` | `0` |
| `debate_rounds` | `0` |

### `standard`

| Key | Default |
|-----|---------|
| `phases` | `["context", "market", "strategy", "review", "report"]` |
| `agent_team` | `true` |
| `review_agents` | `5` |
| `reviewer_roles` | accuracy-evidence, audience-fit, communication-narrative, competitive-positioning, market-fit |
| `external_models_cross_review` | `true` |
| `debate_rounds` | `3` |

### `deep`

| Key | Default |
|-----|---------|
| `phases` | `["context", "market", "research", "accuracy", "strategy", "review", "report"]` |
| `agent_team` | `true` |
| `review_agents` | `9` |
| `reviewer_roles` | standard + financial-credibility, legal-compliance, localization, investor-readiness |
| `external_models_cross_review` | `true` |
| `debate_rounds` | `3` |

### `comprehensive`

| Key | Default |
|-----|---------|
| `phases` | `["context", "market", "research", "accuracy", "benchmark", "strategy", "review", "report"]` |
| `agent_team` | `true` |
| `review_agents` | `10` |
| `reviewer_roles` | deep + conversion-impact |
| `external_models` | `true` |
| `debate_rounds` | `3` |

---

## `business_debate`

Business pipeline cross-examination settings.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Enable business debate |
| `max_rounds` | int | `3` | Number of debate rounds |
| `challenge_threshold` | int | `60` | Confidence below this triggers challenge |
| `consensus_threshold` | int | `75` | Confidence above this = consensus (lower than code's 80) |
| `require_majority` | bool | `true` | Require majority agreement |
| `web_search_enabled` | bool | `true` | Allow web search during debate |
| `round2_timeout_seconds` | int | `180` | Round 2 timeout |
| `round3_timeout_seconds` | int | `180` | Round 3 timeout |

---

## `fallback`

Graceful degradation when components fail.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `external_cli_timeout_seconds` | int | `120` | Timeout for external CLI calls |
| `external_cli_debate_timeout_seconds` | int | `180` | Timeout for external CLI debate rounds |
| `retry_attempts` | int | `1` | Number of retries on failure |
| `retry_delay_seconds` | int | `5` | Delay between retries |
| `strategy` | string | `"graceful_degradation"` | Fallback strategy |
| `report_impact` | bool | `true` | Show fallback level in final report |

Fallback levels (code pipeline):

| Level | Meaning |
|-------|---------|
| `level_0` | Full operation |
| `level_1` | Benchmark failure -- use default role assignments |
| `level_2` | Research failure -- skip context enrichment |
| `level_3` | Agent Teams failure -- use Task subagents (no debate) |
| `level_4` | External CLI failure -- Claude-only review |
| `level_5` | All failure -- inline Claude solo analysis |

---

## `business_models`

External model configuration for business reviews.

### `business_models.codex`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Enable Codex for business reviews |
| `role` | string | `"cross-reviewer"` | Role: `"cross-reviewer"` or `"primary"` (set by benchmarks) |
| `timeout_seconds` | int | `120` | Timeout per invocation |
| `script` | string | `"scripts/codex-business-review.sh"` | Script to execute |

### `business_models.gemini`

Same structure as `business_models.codex` with `scripts/gemini-business-review.sh`.

---

## `business_benchmarks`

Business model benchmarking (Phase B4).

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Enable business benchmarking |
| `auto_run` | bool | `true` | Auto-run when cache expires |
| `rerun_threshold_days` | int | `14` | Days before re-benchmarking |
| `min_score_for_role` | int | `60` | Minimum F1 score to qualify |
| `test_cases_dir` | string | `"config/benchmarks"` | Benchmark test case directory |
| `test_case_prefix` | string | `"business-"` | Filename prefix for business test cases |
| `script` | string | `"scripts/benchmark-business-models.sh"` | Benchmarking script |

---

## `cost_estimation`

Token cost estimation (Phase 0.2 / B0.2).

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Enable cost estimation |
| `show_before_execution` | bool | `true` | Show cost estimate before pipeline runs |
| `auto_proceed_under_dollars` | float | `5.0` | Auto-proceed without confirmation below this cost |
| `max_per_review_dollars` | float | `10.0` | Max cost per single review session |
| `max_daily_dollars` | float | `50.0` | Max total daily cost |
| `warn_threshold_percent` | int | `80` | Warn when daily spend reaches this % of max |
| `prompt_cache_discount` | float | `0.0` | Discount factor for prompt caching (0.0 = no discount, 0.9 = 90% discount on cached tokens) |

Token costs (per 1K tokens):

| Model | Input | Output |
|-------|-------|--------|
| `claude_input` | $0.003 | -- |
| `claude_output` | -- | $0.015 |
| `codex_input` | $0.003 | -- |
| `codex_output` | -- | $0.012 |
| `gemini_input` | $0.00125 | -- |
| `gemini_output` | -- | $0.005 |

**Example: Set auto-proceed threshold to $2**
```json
{ "cost_estimation": { "auto_proceed_under_dollars": 2.0 } }
```

---

## `intensity_checkpoints`

Mid-pipeline intensity adjustment (Phase 2.9 / B2.9).

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Enable intensity checkpoints |
| `check_after_phases` | string[] | `["research", "compliance"]` | Phases after which to re-evaluate intensity |
| `allow_upgrade` | bool | `true` | Allow upgrading intensity mid-pipeline |
| `allow_downgrade` | bool | `true` | Allow downgrading intensity mid-pipeline |
| `auto_adjust_threshold` | int | `7` | Score delta (0-10) required to trigger adjustment |
| `notify_user` | bool | `true` | Notify user when intensity changes |

---

## `feedback`

Review quality feedback tracking.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Enable feedback collection |
| `collect_interactive` | bool | `true` | Prompt user for feedback after review |
| `storage_dir` | string | `"cache/feedback"` | JSONL storage directory |
| `report_period_days` | int | `30` | Window for accuracy reports |
| `use_for_routing` | bool | `true` | Use feedback data in routing decisions |
| `min_samples_for_routing` | int | `5` | Minimum feedback entries before influencing routing |
| `routing_refresh_interval_hours` | int | `24` | Hours between routing recalculations |

---

## `context_forwarding`

Multi-route context passing (e.g., Route G output feeds into Route A input).

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Enable context forwarding between routes |
| `summarize_if_exceeds` | bool | `true` | Auto-summarize if fields exceed limits |

Token limits per field type:

| Field | Limit (tokens) | Examples |
|-------|---------------|---------|
| `summary_fields` | 2,000 | quality_scorecard, key_themes, severity_counts |
| `content_text` | 15,000 | Full document content |
| `metadata` | 1,000 | audience, tone, audience_fit_score |
| **`total_hard_limit`** | **20,000** | Entire forwarded context |

---

## `context_density`

Role-based code filtering for review agents.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Enable context density filtering |
| `role_based_filtering` | bool | `true` | Filter code by agent role |
| `agent_context_budget_tokens` | int | `8000` | Max tokens of code context per agent |
| `compression_strategy` | string | `"role_relevant_extract"` | How to compress large files |
| `fallback_on_small_files` | bool | `true` | Send full content for small files |
| `small_file_threshold_lines` | int | `200` | Files under this line count bypass filtering |

### `context_density.role_filters`

Each role has `include_patterns` (code patterns to match), `include_file_patterns` (file glob patterns), and `priority` (what the agent focuses on). See `default-config.json` for full pattern lists per role (security, bugs, performance, architecture, testing, dependency, scope, api_contract, observability, data_integrity, accessibility, configuration).

### `context_density.chunking`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Enable chunking for large files |
| `threshold_multiplier` | float | `2.0` | File exceeding budget * multiplier gets chunked |
| `max_chunks_per_role` | int | `4` | Max chunks per role per file |
| `overlap_lines` | int | `10` | Overlap between chunks for context continuity |
| `merge_dedup_line_proximity` | int | `3` | Merge findings within this line proximity |

---

## `agent_responsibility_matrix`

Defines primary and secondary responsibility areas per agent. Used for deduplication -- when two agents flag the same issue, the agent with primary responsibility takes ownership.

Each agent has:
- `primary`: Categories the agent owns (findings are attributed here)
- `secondary`: Categories the agent may notice but defers to primary owner

12 agents are defined: security-reviewer, bug-detector, architecture-reviewer, performance-reviewer, test-coverage-reviewer, scope-reviewer, dependency-reviewer, api-contract-reviewer, observability-reviewer, data-integrity-reviewer, accessibility-reviewer, configuration-reviewer.

---

## `memory_tiers`

4-tier memory architecture for cross-session learning.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Enable memory tiers |

### Tiers

| Tier | `storage_dir` | `ttl_days` | `max_entries_per_project` | Tracks |
|------|--------------|-----------|--------------------------|--------|
| `working_memory` | -- (session) | session | -- | Current pipeline context |
| `short_term` | `cache/short-term` | `7` | `100` | Recurring findings, recent review patterns |
| `long_term` | `cache/long-term` | `90` | `500` | Model accuracy by category, feedback trends |
| `permanent` | `cache/permanent` | `-1` (never) | `200` | Team coding standards, architecture decisions |

---

## `pipeline_evaluation`

Pipeline quality metrics using ground-truth test cases.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Enable pipeline evaluation |
| `test_cases_dir` | string | `"config/benchmarks/pipeline"` | Ground-truth test case directory |
| `metrics` | string[] | `["precision", "recall", "f1", "false_positive_rate", "time_to_finding"]` | Metrics to compute |
| `auto_run_after_review` | bool | `false` | Auto-evaluate after each review session |
| `report_dir` | string | `"cache/evaluation-reports"` | Where evaluation reports are stored |

### `pipeline_evaluation.llm_as_judge`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Use LLM-as-Judge for qualitative scoring |
| `position_bias_mitigation` | bool | `true` | Randomize finding order to reduce position bias |
| `judge_model` | string | `"sonnet"` | Model used for judging |
| `evaluation_criteria` | string[] | `["finding_accuracy", "severity_calibration", "suggestion_quality", "report_completeness"]` | What to evaluate |

---

## Environment Variables

Environment variables override config file values. Checked at runtime in orchestration scripts.

| Variable | Overrides | Example |
|----------|-----------|---------|
| `ARENA_INTENSITY` | `review.intensity` | `ARENA_INTENSITY=deep` -- force intensity, skip debate |
| `ARENA_SKIP_CACHE` | `cache.enabled` (inverted) | `ARENA_SKIP_CACHE=true` -- bypass all caches |
| `MULTI_REVIEW_INTENSITY` | `review.intensity` | `MULTI_REVIEW_INTENSITY=standard` |
| `MULTI_REVIEW_LANGUAGE` | `output.language` | `MULTI_REVIEW_LANGUAGE=en` |
| `MULTI_REVIEW_HOOK_ENABLED` | `hook_mode.enabled` | `MULTI_REVIEW_HOOK_ENABLED=false` |
| `MULTI_REVIEW_BATCH_SIZE` | `hook_mode.batch_size` | `MULTI_REVIEW_BATCH_SIZE=10` |
| `MULTI_REVIEW_CODEX_ENABLED` | `models.codex.enabled` | `MULTI_REVIEW_CODEX_ENABLED=false` |
| `MULTI_REVIEW_GEMINI_ENABLED` | `models.gemini.enabled` | `MULTI_REVIEW_GEMINI_ENABLED=false` |

---

## Common Override Examples

### Disable all external models (Claude-only)
```json
{
  "models": {
    "codex": { "enabled": false },
    "gemini": { "enabled": false }
  }
}
```

### Force deep intensity, skip debate
```json
{ "review": { "intensity": "deep" } }
```
Or via environment: `ARENA_INTENSITY=deep`

### Reduce cost (fewer agents, shorter debate)
```json
{
  "review": { "intensity": "standard" },
  "debate": { "max_rounds": 2 },
  "cost_estimation": { "auto_proceed_under_dollars": 2.0, "max_per_review_dollars": 5.0 }
}
```

### English output
```json
{ "output": { "language": "en" } }
```

### Increase agent context budget
```json
{ "context_density": { "agent_context_budget_tokens": 12000 } }
```

### Disable feedback prompts
```json
{ "feedback": { "collect_interactive": false } }
```

### Disable WebSocket, use HTTP fallback
```json
{ "websocket": { "enabled": false } }
```

### Business pipeline: investor audience, persuasive tone
```json
{
  "business": {
    "default_audience": "investor",
    "default_tone": "persuasive"
  }
}
```
