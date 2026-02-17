# AI Review Arena v3.1.0 - Development Rules

## Project Structure
- `.claude-plugin/` - Plugin manifest (v3.1.0)
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
- `scripts/` - Shell scripts (21 files)
  - Core: orchestrate-review.sh, codex-review.sh, gemini-review.sh
  - Business: codex-business-review.sh, gemini-business-review.sh
  - Review: aggregate-findings.sh, run-debate.sh, generate-report.sh, cost-estimator.sh
  - Arena: detect-stack.sh, cache-manager.sh, benchmark-models.sh, benchmark-business-models.sh, search-best-practices.sh, search-guidelines.sh
  - Feedback: feedback-tracker.sh
  - Utilities: utils.sh, setup.sh, setup-arena.sh
- `config/` - Configuration files
  - default-config.json - All settings (models, review, debate, arena, cache, benchmarks, compliance, routing, fallback, cost, feedback, context forwarding)
  - review-prompts/ - Role-specific review prompts (9 files)
  - compliance-rules.json - Feature→guideline mapping
  - tech-queries.json - Technology→search query mapping (31 technologies)
  - benchmarks/ - Model benchmark test cases (16 files: 4 code + 12 business)
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

## Configuration
- Project config: `.ai-review-arena.json` in project root
- Global config: `~/.claude/.ai-review-arena.json`
- Default config: `config/default-config.json`
- Environment variables override config file values
- Prefix: `MULTI_REVIEW_` (review), `ARENA_` (lifecycle)

## Testing
- Test with intentionally buggy code to verify detection
- Test model fallback by disabling CLIs
- Test debate by creating conflicting findings
- Test cache: write, read, TTL expiry, cleanup
- Test stack detection on various project types (Java, Node, Python, iOS, Android, Game)
- Test compliance detection: "login" → OAuth guidelines, "chat" → APNs guidelines
- Test benchmarks: known-vulnerability code → model scoring
