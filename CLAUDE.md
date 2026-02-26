# AI Review Arena v3.2.0 - Development Rules

## Project Structure
- `.claude-plugin/` - Plugin manifest (v3.2.0)
- `hooks/` - PostToolUse hook for auto-review
- `commands/` - Slash commands (7 files)
  - `arena` - Full lifecycle orchestrator (research → compliance → benchmark → review → auto-fix)
  - `arena-business` - Business content lifecycle orchestrator
  - `arena-research` - Standalone pre-implementation research
  - `arena-stack` - Project stack detection + best practices
  - `multi-review` - Multi-AI adversarial code review
  - `multi-review-config` - Review config management
  - `multi-review-status` - Review status dashboard
- `agents/` - Claude agent definitions (16 agents)
  - Code review: security-reviewer, bug-detector, architecture-reviewer, performance-reviewer, test-coverage-reviewer, scale-advisor
  - Business review: domain-accuracy-reviewer, audience-fit-reviewer, competitive-positioning-reviewer, communication-clarity-reviewer, data-evidence-reviewer
  - Debate: debate-arbitrator, business-debate-arbitrator
  - Research: research-coordinator, design-analyzer
  - Compliance: compliance-checker
- `scripts/` - Shell scripts (22 files)
  - Core: orchestrate-review.sh, codex-review.sh, gemini-review.sh
  - Business: codex-business-review.sh, gemini-business-review.sh
  - Review: aggregate-findings.sh, run-debate.sh, generate-report.sh, cost-estimator.sh
  - Arena: detect-stack.sh, cache-manager.sh, benchmark-models.sh, benchmark-business-models.sh, search-best-practices.sh, search-guidelines.sh
  - Evaluation: evaluate-pipeline.sh
  - Feedback: feedback-tracker.sh
  - Utilities: utils.sh, setup.sh, setup-arena.sh
- `config/` - Configuration files
  - default-config.json - All settings (models, review, debate, arena, cache, benchmarks, compliance, routing, fallback, cost, feedback, context forwarding, context density, memory tiers, pipeline evaluation)
  - review-prompts/ - Role-specific review prompts (9 files)
  - compliance-rules.json - Feature→guideline mapping
  - tech-queries.json - Technology→search query mapping (31 technologies)
  - benchmarks/ - Model benchmark test cases (16 files: 4 code + 12 business) + pipeline/ subfolder
- `docs/` - Documentation and TODO files
  - TODO-external-integrations.md - Research-backed TODO items for external API integrations
- `shared-phases/` - Common phase definitions shared by code and business pipelines
  - `intensity-decision.md` - Phase 0.1/B0.1: Agent Teams intensity debate (shared template)
  - `cost-estimation.md` - Phase 0.2/B0.2: Cost & time estimation using cost-estimator.sh
  - `feedback-routing.md` - Feedback-based model-category role assignment for Phase 6/B6
- `cache/` - Runtime knowledge cache (gitignored, TTL-managed)

## Coding Rules
- Shell scripts: POSIX-compatible with bash extensions
- Constants at top of scripts
- Source `utils.sh` in all scripts (except utils.sh itself)
- Silent exit on non-critical errors (`exit 0`)
- Review results: stderr for user display, stdout JSON for Claude feedback
- All scripts must handle missing CLI tools gracefully
- JSON output must be valid and parseable by jq
- Support both Korean and English output via config `output.language`
- Cache operations use `cache-manager.sh` interface exclusively
- Config loading uses `load_config()` from utils.sh (deep merges default → global → project)
- Shared phases in `shared-phases/` should be referenced by both arena.md and arena-business.md

## Configuration
- Project config: `.ai-review-arena.json` in project root
- Global config: `~/.claude/.ai-review-arena.json`
- Default config: `config/default-config.json`
- Environment variables override config file values
- Prefix: `MULTI_REVIEW_` (review), `ARENA_` (lifecycle)
- Config merge: `load_config()` deep-merges default → global → project via jq
- Routing strategy: `feedback_benchmark` (60% feedback + 40% benchmark by default)
- Context density: role-based filtering with per-agent token budgets (8000 tokens default)
- Memory tiers: 4-tier architecture (working/short-term 7d/long-term 90d/permanent)
- Pipeline evaluation: precision/recall/F1 metrics with LLM-as-Judge and position bias mitigation

## Agent Design
- All 16 agents have three hardened sections before `## Rules`: `## When NOT to Report/Escalate/Research` + `## Error Recovery Protocol`
- "When NOT to Report" reduces false positives by listing domain-specific acceptable patterns
- "Error Recovery Protocol" ensures graceful degradation (retry, partial submit, team lead notification)
- Context density config (`context_density.role_filters`) provides per-role include patterns for focused agent context

## Testing
- Test with intentionally buggy code to verify detection
- Test model fallback by disabling CLIs
- Test debate by creating conflicting findings
- Test cache: write, read, TTL expiry, cleanup
- Test stack detection on various project types (Java, Node, Python, iOS, Android, Game)
- Test compliance detection: "login" → OAuth guidelines, "chat" → APNs guidelines
- Test benchmarks: known-vulnerability code → model scoring
- Test pipeline evaluation: `scripts/evaluate-pipeline.sh` with ground-truth test cases in `config/benchmarks/pipeline/`
