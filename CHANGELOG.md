# Changelog

All notable changes to AI Review Arena are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/).

## [3.2.0] - 2025

### Added
- Commit/PR Safety Protocol: mandatory review gate + user confirmation before `git commit` or `gh pr create`
- Phase 0.1-Pre: rule-based quick intensity pre-filter (saves ~$0.50 and ~30s for trivial requests)
- Phase-based cost estimation with per-phase token/cost tables (`cost-estimator.sh`)
- Shared phases (`shared-phases/`) for intensity debate, cost estimation, feedback routing
- Feedback-based routing: combined score (60% feedback + 40% benchmark F1) for model-category role assignment
- Context density filtering: role-based code filtering with 8,000 token budget per agent
- Memory tiers: 4-tier architecture (working/short-term 7d/long-term 90d/permanent)
- Pipeline evaluation: precision/recall/F1 metrics with LLM-as-Judge and position bias mitigation
- Agent hardening: Error Recovery Protocol on all 27 agents
- Positive framing on all agent specs (arxiv 2602.11988)
- Duplicate prompt technique for external CLI scripts (arxiv 2512.14982)
- Stale review detection: git-hash-based invalidation
- Prompt cache-aware cost estimation (`prompt_cache_discount` config)
- Codex structured output with 5 JSON schemas
- Codex multi-agent sub-agents: 5 TOML configs with dual-gated activation
- OpenAI WebSocket debate acceleration (~40% faster via persistent connection)
- Gemini CLI hooks cross-compatibility (AfterTool hook adapter)
- Agent responsibility matrix in config
- Config validation script (`scripts/validate-config.sh`)

### Changed
- Config loading now uses 3-level deep merge (default > global > project) via `load_config()`
- Core routing rule uses explicit exempt/non-exempt lists
- Benchmark scoring uses negation detection (`keyword_match_positive()`)
- Benchmark ground truth supports multiple formats (array-of-objects, single-object, flat-array)
- Hash collision resistance: `project_hash()` extended from 48-bit to 80-bit
- All prompts and metadata in routing/command files converted to English (i18n cleanup)
- Agents restructured from 24 to 27 (merged overlaps, added coverage)

### Fixed
- 14 critical bugs: broken pipelines, injection, scale mismatch, missing implementations
- 23 cross-validated findings: security, dedup, performance, compatibility
- 12 comprehensive review findings: performance, security, reliability

## [3.1.0] - 2025

### Added
- Business pipeline with Codex/Gemini external CLI integration (dual-mode scripts)
- Business model benchmarking (Phase B4): 12 planted-error test cases, F1 scoring
- Fallback framework: 6-level (code) / 5-level (business) graceful degradation
- Cost & time estimation (Phase 0.2 / B0.2)
- Code auto-fix loop (Phase 6.5) with test verification and full revert on failure
- Intensity checkpoints (Phase 2.9 / B2.9): bidirectional mid-pipeline adjustment
- Feedback loop: JSONL-based tracking with per-model/per-category accuracy reports
- Context forwarding: multi-route requests pass context with tiered token limits (20K hard limit)

### Changed
- `business-debate-arbitrator.md` updated with external model handling

## [2.7.0] - 2025

### Added
- Business content lifecycle orchestrator (`arena-business.md`)
- Routes G (content), H (strategy), I (communication)
- 5 business reviewer agents + business-debate-arbitrator
- Phases B0-B7: context extraction, market research, best practices, accuracy audit, strategy debate, review, report

### Changed
- ARENA-ROUTER.md updated with 9 routes (A-F code, G-I business)

## [2.6.0] - 2025

### Added
- 3-round cross-examination between Claude, Codex, and Gemini
- Round 2: each model evaluates other models' findings (agree/disagree/partial)
- Round 3: each model defends its findings against challenges (defend/concede/modify)
- Consensus synthesis with `cross_examination_trail` per finding
- `codex-cross-examine.sh`, `gemini-cross-examine.sh`
- Prompt templates: `cross-examine.txt`, `defend.txt`

## [2.5.0] - 2025

### Added
- Success criteria defined before implementation, verified in final report (PASS/FAIL)
- Scope reviewer agent for surgical change enforcement
- Inspired by Karpathy's coding principles

## [2.4.0] - 2025

### Added
- Agent Teams adversarial debate at 5 pipeline decision points

### Changed
- Replaced static keyword rules with agent reasoning

## [2.3.0] - 2025

### Fixed
- Pipeline loads command files via Read tool (fixes infinite recursion)

## [2.2.0] - 2025

### Added
- Intent-based routing (replaces keyword matching)
- Language-agnostic support (works in any language)
- Context Discovery phase

## [2.1.0] - 2025

### Added
- Always-on routing
- Codebase Analysis (Phase 0.5)
- MCP Dependency Detection

## [2.0.0] - 2025

### Added
- Full lifecycle orchestrator with research, stack detection, compliance, benchmarking

## [1.0.0] - 2025

### Added
- Multi-AI adversarial code review with Claude + Codex + Gemini
