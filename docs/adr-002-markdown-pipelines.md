# ADR-002: Markdown Pipeline Definitions

## Status

Accepted

## Context

AI Review Arena defines its code pipeline (`arena.md`, ~2500 lines) and business pipeline (`arena-business.md`, ~2900 lines) as markdown files that Claude reads and executes. This is unconventional — most build pipelines are defined in code (YAML, HCL, Python).

## Decision

Pipeline definitions are markdown files read by Claude via the Read tool at execution time.

## Rationale

### Why markdown

1. **Claude is the executor.** Unlike CI/CD where a deterministic engine runs the pipeline, Arena's executor is Claude — an LLM that reads natural language. Markdown is its native input format. Writing the pipeline in Python would mean Claude has to interpret Python semantics; writing it in markdown means Claude reads instructions directly.

2. **Agent Teams coordination.** Phases that spawn agent debates (intensity decision, strategy debate, review) describe complex multi-agent interactions. These are naturally expressed as structured natural language ("spawn 3 agents: intensity-advocate argues for X, efficiency-advocate argues for Y, arbitrator decides"), not as code.

3. **Phase-level granularity.** Each phase is a self-contained section with pre-conditions, actions, and post-conditions. Claude reads the relevant section and executes it. Skipping a phase is just skipping a section, not commenting out code.

4. **User-readable pipeline.** Users can open `commands/arena.md` and understand what happens at each phase without knowing a programming language or framework.

### Trade-offs accepted

1. **Not debuggable with traditional tools.** You can't set breakpoints in a markdown file. When a phase fails, debugging means reading Claude's output and inferring what went wrong.

2. **No static analysis.** A Python pipeline can be linted, type-checked, and unit-tested. A markdown pipeline can only be tested end-to-end.

3. **Large files.** At 2500-2900 lines, the pipeline files are substantial. This is mitigated by shared phases (`shared-phases/`) that extract common logic.

4. **Claude interpretation variance.** The same markdown instructions may be interpreted slightly differently across Claude model versions. We mitigate this with explicit, unambiguous instructions and concrete examples.

5. **Context window cost.** Claude must read the entire pipeline file (~2500+ lines) into its context window. At ~4 tokens per line, this costs ~10K tokens just for pipeline instructions.

## Alternatives Considered

### YAML/JSON pipeline definition

Would provide structured, parseable pipeline definitions. Rejected because Claude would need a separate interpreter to process them, and the expressiveness needed for agent debates doesn't fit a declarative format.

### Python orchestrator

Would provide debuggability and testability. Rejected because it adds a runtime dependency and moves the intelligence from Claude's natural language understanding to explicit code paths, losing the flexibility of LLM-based execution.

### Hybrid (markdown phases + code execution)

The current approach already uses this for external operations — bash scripts handle CLI calls, JSON processing, and file I/O while markdown handles orchestration and decision-making. This division works well.

## Consequences

- Pipeline files should be kept as concise as possible (P1 slimmed the router from 694 to ~180 lines)
- Common phase logic should be extracted to `shared-phases/` to avoid duplication
- Each phase must be clearly delineated with explicit pre-conditions and expected outputs
- Pipeline changes should be tested via end-to-end benchmark runs, not unit tests
