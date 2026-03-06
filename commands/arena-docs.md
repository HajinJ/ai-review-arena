---
description: "Documentation review lifecycle orchestrator - documentation inventory, code-doc diff analysis, documentation standards research, cross-reference validation, and multi-agent adversarial documentation review"
argument-hint: "[task] [--category accuracy|completeness|freshness|readability|examples|consistency|all] [--mode review|generate] [--intensity quick|standard|deep|comprehensive] [--interactive] [--skip-cache]"
allowed-tools: [Bash, Glob, Grep, Read, Task, WebSearch, WebFetch, Teammate, SendMessage, TaskCreate, TaskUpdate, TaskList, TaskGet]
---

# AI Review Arena - Documentation Review Lifecycle Orchestrator (Agent Teams)

You are the **team lead** for the AI Review Arena documentation review lifecycle orchestrator. This command orchestrates the entire documentation review lifecycle: documentation inventory, code-doc diff analysis, documentation standards research, cross-reference validation, and multi-agent adversarial documentation review with Agent Teams and optional external CLI models (Codex, Gemini).

## Architecture

```
Team Lead (You - this session)
+-- Phase D0: Context & Configuration (+ MCP Dependency Detection)
+-- Phase D0.1: Intensity Decision (Agent Teams debate - MANDATORY)
|   +-- intensity-advocate     -> argues for higher intensity
|   +-- efficiency-advocate    -> argues for lower intensity
|   +-- risk-assessor          -> evaluates doc scope/staleness risk
|   +-- intensity-arbitrator   -> synthesizes consensus, decides intensity
+-- Phase D0.2: Cost & Time Estimation (user approval before proceeding)
+-- Phase D0.5: Documentation Inventory (doc-inventory.sh)
|   +-- Scan project for all doc files
|   +-- Classify by type (readme, api, tutorial, changelog, adr, runbook, etc.)
|   +-- Generate inventory with metadata (last modified, size, type)
+-- Phase D1: Code-Doc Diff Analysis (doc pipeline unique)
|   +-- git diff to find recent code changes
|   +-- Cross-reference with doc file modification dates
|   +-- Generate CODE_DOC_DRIFT map (code changed but docs didn't)
+-- Phase D2: Documentation Standards Research (deep+ only, with debate)
|   +-- Research Direction Debate
|       +-- researcher-standards   -> documentation standards (Diátaxis, etc.)
|       +-- researcher-tooling     -> doc tooling best practices
|       +-- researcher-audience    -> audience-specific doc guidelines
|       +-- research-arbitrator    -> prioritizes research agenda
+-- Phase D3: Cross-Reference Validation (deep+ only, with debate)
|   +-- Link Validation Debate
|       +-- link-validator         -> checks all internal/external links
|       +-- scope-challenger       -> argues against over-validation
|       +-- validation-arbitrator  -> decides validation scope
+-- Phase D4: Documentation Benchmarking (comprehensive only)
|   +-- Run benchmark-doc-models.sh against planted-error test cases
|   +-- Score each model per category (avg F1)
|   +-- Determine model role assignments for Phase D6
+-- Phase D5.5: Documentation Strategy Debate (standard+)
|   +-- doc-strategy-advocate    -> proposes documentation improvement strategy
|   +-- scope-challenger         -> challenges over-documentation
|   +-- accuracy-challenger      -> challenges based on code-doc drift data
|   +-- strategy-arbitrator      -> synthesizes documentation strategy
+-- Phase D6: Multi-Agent Doc Review (6 reviewers + arbitrator + Codex/Gemini, 3-round debate)
|   +-- Step D6.1.5: Determine external model participation
|   +-- Create team
|   +-- Spawn doc reviewer teammates (with doc context)
|   +-- Run external CLI Round 1 if assigned as primary
|   +-- Coordinate 3-round debate
|   +-- Run external CLI Round 2 cross-review
|   +-- Aggregate findings & generate consensus
+-- Phase D6.5: Apply Findings (auto-fix critical/high doc issues)
+-- Phase D6.6: Example Code Validation (standard+)
|   +-- Extract code blocks from documentation
|   +-- Syntax check each code block
|   +-- Verify imports exist
|   +-- Flag deprecated API usage
+-- Phase D7: Final Report & Cleanup (+ consistency validation)
|   +-- Cross-doc consistency validation
|   +-- Generate enriched documentation review report
|   +-- Shutdown all teammates
|   +-- Cleanup team

Doc Reviewer Teammates (from config docs_intensity_presets.{INTENSITY}.reviewer_roles)
+-- doc-accuracy-reviewer        --+
+-- doc-completeness-reviewer    --+-- SendMessage <-> each other (debate)
+-- doc-freshness-reviewer       --+-- SendMessage -> doc-debate-arbitrator
+-- doc-readability-reviewer     --+-- SendMessage -> team lead (findings)
+-- doc-example-reviewer         --+
+-- doc-consistency-reviewer     --+
+-- doc-debate-arbitrator        ------ Receives challenges/supports -> synthesizes consensus

External CLI Models
+-- Codex CLI (codex-doc-review.sh)
+-- Gemini CLI (gemini-doc-review.sh)
```

## Constants

```
PLUGIN_DIR="~/.claude/plugins/ai-review-arena"
SCRIPTS_DIR="${PLUGIN_DIR}/scripts"
CONFIG_DIR="${PLUGIN_DIR}/config"
CACHE_DIR="${PLUGIN_DIR}/cache"
AGENTS_DIR="${PLUGIN_DIR}/agents"
DEFAULT_CONFIG="${CONFIG_DIR}/default-config.json"
SESSION_DIR="$(mktemp -d /tmp/ai-review-arena-docs.XXXXXXXXXX)"
```

## Phase D0: Context & Configuration

Establish documentation context, load configuration, and prepare the session environment.

**Steps:**

1. Detect project root:
   ```bash
   PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
   echo "project_root: ${PROJECT_ROOT}"
   ```

2. Load configuration (resolution order: later overrides earlier):
   a. Read the default config:
      ```bash
      cat "${PLUGIN_DIR}/config/default-config.json"
      ```
   b. Check for global user config:
      ```bash
      test -f ~/.claude/.ai-review-arena.json && cat ~/.claude/.ai-review-arena.json || echo "{}"
      ```
   c. Check for project config:
      ```bash
      test -f "${PROJECT_ROOT}/.ai-review-arena.json" && cat "${PROJECT_ROOT}/.ai-review-arena.json" || echo "{}"
      ```

3. Parse arguments from `$ARGUMENTS`:
   - Extract `--category` value (default: "all"). Valid values: `accuracy`, `completeness`, `freshness`, `readability`, `examples`, `consistency`, `all`
   - Extract `--mode` value (default: "review"). Valid values: `review`, `generate`
   - Extract `--skip-cache` flag (default: false)
   - Extract `--interactive` flag (default: from config `arena.interactive_by_default`)
   - Extract `--intensity` value (default: from config `review.intensity`)
   - Remaining arguments are treated as the documentation task description (the docs to review, update, or generate)

4. Check that `docs.enabled` is true in config. If false:
   - Display: "AI Review Arena docs pipeline is disabled in configuration. Enable it with: `/arena-config set docs.enabled true`"
   - Exit early.

5. Create session directory:
   ```bash
   mkdir -p "${SESSION_DIR}/findings" "${SESSION_DIR}/research" "${SESSION_DIR}/reports"
   echo "session: ${SESSION_DIR}"
   ```

6. Determine documentation category focus areas based on `--category`:
   - `accuracy` (code-doc alignment): emphasize doc-accuracy-reviewer and doc-example-reviewer
     - Phase D0.5: Full inventory
     - Phase D1: Code-doc drift analysis with emphasis on accuracy
     - Phase D2 (deep+): Documentation accuracy standards
     - Phase D5.5: Accuracy-first strategy debate
     - Phase D6: All reviewers with emphasis scoring on doc-accuracy-reviewer and doc-example-reviewer
   - `completeness` (coverage gaps): emphasize doc-completeness-reviewer and doc-consistency-reviewer
     - Phase D0.5: Full inventory with gap analysis
     - Phase D1: Code-doc drift analysis with emphasis on missing docs
     - Phase D2 (deep+): Documentation coverage standards
     - Phase D5.5: Coverage-first strategy debate
     - Phase D6: All reviewers with emphasis scoring on doc-completeness-reviewer and doc-consistency-reviewer
   - `freshness` (staleness detection): emphasize doc-freshness-reviewer and doc-completeness-reviewer
     - Phase D0.5: Full inventory with age analysis
     - Phase D1: Code-doc drift analysis with emphasis on stale docs
     - Phase D2 (deep+): Documentation maintenance best practices
     - Phase D5.5: Freshness-first strategy debate
     - Phase D6: All reviewers with emphasis scoring on doc-freshness-reviewer and doc-completeness-reviewer
   - `readability` (clarity & structure): emphasize doc-readability-reviewer and doc-consistency-reviewer
     - Phase D0.5: Full inventory
     - Phase D1: Code-doc drift analysis (light)
     - Phase D2 (deep+): Documentation readability standards (Diátaxis, etc.)
     - Phase D5.5: Readability-first strategy debate
     - Phase D6: All reviewers with emphasis scoring on doc-readability-reviewer and doc-consistency-reviewer
   - `examples` (code examples quality): emphasize doc-example-reviewer and doc-accuracy-reviewer
     - Phase D0.5: Full inventory with code block scan
     - Phase D1: Code-doc drift analysis with emphasis on example code
     - Phase D2 (deep+): Code example best practices
     - Phase D5.5: Examples-first strategy debate
     - Phase D6: All reviewers with emphasis scoring on doc-example-reviewer and doc-accuracy-reviewer
   - `consistency` (cross-doc alignment): emphasize doc-consistency-reviewer and doc-readability-reviewer
     - Phase D0.5: Full inventory with terminology scan
     - Phase D1: Code-doc drift analysis (light)
     - Phase D2 (deep+): Documentation consistency standards
     - Phase D5.5: Consistency-first strategy debate
     - Phase D6: All reviewers with emphasis scoring on doc-consistency-reviewer and doc-readability-reviewer
   - `all` (default): all reviewers with equal emphasis
     - All phases run with balanced focus

7. Determine which phases to execute based on intensity:

   **Intensity determines Phase scope** (decided by Phase D0.1 debate or `--intensity` flag):
   - `quick`: Phase D0 -> D0.1 -> D0.5 only (Claude solo, no Agent Team)
   - `standard`: Phase D0 -> D0.1 -> D0.2 -> D0.5 -> D1 -> D5.5 -> D6 -> D6.5 -> D6.6 -> D7
   - `deep`: Phase D0 -> D0.1 -> D0.2 -> D0.5 -> D1 -> D2(+debate) -> D3(+debate) -> D5.5 -> D6 -> D6.5 -> D6.6 -> D7
   - `comprehensive`: Phase D0 -> D0.1 -> D0.2 -> D0.5 -> D1 -> D2(+debate) -> D3(+debate) -> D4(benchmark) -> D5.5 -> D6 -> D6.5 -> D6.6 -> D7

   **Quick Intensity Mode** (`--intensity quick` or decided by Phase D0.1):
   - Run Phase D0 + Phase D0.1 + Phase D0.5 only
   - Skip all other phases (D1-D7)
   - Claude executes the task solo using documentation inventory results
   - After task completion, perform simplified self-review (no Agent Team)
   - No team spawning

8. If `--interactive` is set, display the execution plan:
   ```
   ## Arena Docs Execution Plan
   - Category: {category}
   - Mode: {mode}
   - Phases: {list of phases to execute}
   - Intensity: {intensity}
   - Cache: {enabled/disabled}

   Proceed? (y/n)
   ```
   Wait for user confirmation before continuing.

9. **MCP Dependency Detection**:

    Detect if the user's request requires MCP servers that may not be installed.

    a. **Notion MCP Detection**:
       - Check if request contains: "Notion", "notion page", "notion doc"
       - If detected:
         ```
         ToolSearch(query: "notion")
         ```
       - If Notion MCP not found in results:
         ```
         Display:
         "Notion MCP server is not installed.
          Your request references Notion content. Install the Notion MCP for direct access?

          [Install and continue] [Continue without Notion] [Cancel]"
         ```
         Use AskUserQuestion to get user's choice:
         - **Install**: Execute installation via Bash, verify with ToolSearch, then proceed
         - **Skip**: Continue without Notion access
         - **Cancel**: Abort arena-docs execution

    b. **Figma MCP Detection** (for design documentation):
       - Check if request contains: figma.com URL, "design docs", "component documentation"
       - If detected:
         ```
         ToolSearch(query: "figma")
         ```
       - If not found: Inform user and suggest installation, continue without it

    c. Record MCP availability status for session:
       ```json
       {
         "notion_mcp": "available|installed|unavailable",
         "figma_mcp": "available|installed|unavailable"
       }
       ```

---

## Phase D0.1: Intensity Decision (Agent Teams Debate)

> **Shared Phase**: Full definition at `${PLUGIN_DIR}/shared-phases/intensity-decision.md`
> Set variables: `PIPELINE_TYPE=docs`, `TEAM_PREFIX=doc-intensity-decision`

**MANDATORY for all requests.** Determine the appropriate intensity level through adversarial debate among Claude agents. Skip only if user explicitly specified `--intensity`.

**Purpose**: Prevent both under-processing (missing stale docs in a large codebase) and over-processing (running full pipeline for a single typo fix). No single Claude instance can reliably judge documentation review complexity alone.

**Steps:**

1. **Create Decision Team**:
   ```
   Teammate(
     operation: "spawnTeam",
     team_name: "doc-intensity-decision-{YYYYMMDD-HHMMSS}",
     description: "Documentation review intensity level determination debate"
   )
   ```

2. **Create Debate Tasks**:
   ```
   TaskCreate(
     subject: "Advocate for higher documentation review intensity",
     description: "Argue for the highest reasonable intensity level for this documentation review request. Consider: documentation scope, code-doc drift risk, audience exposure, staleness indicators, cross-reference complexity. Provide specific reasoning.",
     activeForm: "Advocating for higher intensity"
   )

   TaskCreate(
     subject: "Advocate for lower documentation review intensity",
     description: "Argue for the lowest reasonable intensity level for this documentation review request. Consider: single file vs project-wide, minor edit vs full audit, internal vs external docs, existing doc quality, time sensitivity. Provide specific reasoning.",
     activeForm: "Advocating for lower intensity"
   )

   TaskCreate(
     subject: "Assess documentation scope and staleness risk",
     description: "Evaluate the documentation scope, staleness risk, audience exposure, and cross-reference complexity of this documentation review request. Consider: how many docs are affected? How critical is accuracy? What is the audience? How stale might the docs be? Provide risk assessment with severity rating.",
     activeForm: "Assessing documentation scope and staleness risk"
   )

   TaskCreate(
     subject: "Arbitrate documentation review intensity decision",
     description: "Wait for all three advocates to present their arguments. Weigh the merits of each position. Decide the final intensity level (quick/standard/deep/comprehensive) with clear justification. Send the decision to the team lead.",
     activeForm: "Arbitrating intensity decision"
   )
   ```

3. **Spawn Debate Agents** (all in parallel):
   ```
   Task(
     subagent_type: "general-purpose",
     team_name: "doc-intensity-decision-{session}",
     name: "intensity-advocate",
     prompt: "You are the Intensity Advocate for documentation review. Your role is to argue for the HIGHEST reasonable intensity level.

     USER REQUEST: {user_request}
     CATEGORY: {category}
     MODE: {mode}
     PROJECT CONTEXT: {discovered_context_from_step1}

     Analyze this request and argue why it needs a higher intensity level. Consider:
     - Documentation Scope: Single file has low scope. Multiple files or directories are medium. Project-wide documentation audit is high. Full documentation system overhaul is critical.
     - Code-Doc Drift Risk: Recently changed code with no doc updates indicates drift. Large codebases with infrequent doc updates have high drift risk. Docs for deprecated APIs need urgent attention.
     - Audience Exposure: Internal developer docs are lower risk. Public API documentation is medium. Open-source project documentation is high. Regulatory or compliance documentation is critical.
     - Staleness Indicators: Docs not updated in 30+ days with active code changes indicate staleness. References to deprecated APIs or removed features are high risk.
     - Cross-Reference Complexity: Docs with many internal links and code references need thorough validation. Tutorial sequences with dependencies need comprehensive checking.
     - Example Code Risk: Documentation with runnable code examples needs validation against current API. Security-sensitive examples need extra scrutiny.

     Present your argument to intensity-arbitrator via SendMessage.
     Then engage with efficiency-advocate's counter-arguments.
     Continue debating until intensity-arbitrator makes a decision."
   )

   Task(
     subagent_type: "general-purpose",
     team_name: "doc-intensity-decision-{session}",
     name: "efficiency-advocate",
     prompt: "You are the Efficiency Advocate for documentation review. Your role is to argue for the LOWEST reasonable intensity level.

     USER REQUEST: {user_request}
     CATEGORY: {category}
     MODE: {mode}
     PROJECT CONTEXT: {discovered_context_from_step1}

     Analyze this request and argue why a lower intensity is sufficient. Consider:
     - Is this a single file typo or formatting fix? Single-file edits rarely need multi-agent review.
     - Is the documentation internal-only? Internal docs face less scrutiny than public docs.
     - Is this a minor README update? Simple README changes are low risk.
     - Are the docs auto-generated? Auto-generated docs (JSDoc, Swagger) have lower manual review burden.
     - Is this a routine changelog update? Changelog entries follow established patterns.
     - Will the docs go through additional human review anyway?
     - Would higher intensity waste resources without proportional improvement in quality?

     Present your argument to intensity-arbitrator via SendMessage.
     Then engage with intensity-advocate's counter-arguments.
     Continue debating until intensity-arbitrator makes a decision."
   )

   Task(
     subagent_type: "general-purpose",
     team_name: "doc-intensity-decision-{session}",
     name: "risk-assessor",
     prompt: "You are the Risk Assessor for documentation review. Your role is to provide an objective risk evaluation.

     USER REQUEST: {user_request}
     CATEGORY: {category}
     MODE: {mode}
     PROJECT CONTEXT: {discovered_context_from_step1}

     Evaluate along these dimensions:

     1. Documentation Scope:
        - Single file edit -> LOW
        - Multiple file edits -> LOW-MEDIUM
        - Directory-level review -> MEDIUM
        - Project-wide audit -> HIGH
        - Full documentation system overhaul -> CRITICAL

     2. Code-Doc Drift Risk:
        - Docs recently updated with code -> LOW
        - Some drift detected -> MEDIUM
        - Significant drift (30+ days) -> HIGH
        - Major code refactor without doc updates -> CRITICAL

     3. Audience Exposure:
        - Internal developer notes -> LOW
        - Internal team docs -> LOW-MEDIUM
        - Partner/vendor docs -> MEDIUM
        - Public API documentation -> HIGH
        - Open-source project docs -> HIGH
        - Regulatory/compliance docs -> CRITICAL

     4. Example Code Risk:
        - No code examples -> LOW
        - Simple snippets -> LOW-MEDIUM
        - Runnable examples -> MEDIUM
        - Security-sensitive examples -> HIGH
        - Production deployment examples -> CRITICAL

     Rate overall risk as: LOW / MEDIUM / HIGH / CRITICAL
     Send your assessment to intensity-arbitrator via SendMessage."
   )

   Task(
     subagent_type: "general-purpose",
     team_name: "doc-intensity-decision-{session}",
     name: "intensity-arbitrator",
     prompt: "You are the Intensity Arbitrator for documentation review. Your role is to make the FINAL intensity decision.

     Wait for arguments from:
     1. intensity-advocate (argues for higher intensity)
     2. efficiency-advocate (argues for lower intensity)
     3. risk-assessor (provides risk evaluation)

     After receiving all arguments:
     1. Weigh the merits of each position
     2. Consider the risk assessment dimensions
     3. Decide: quick, standard, deep, or comprehensive
     4. Provide clear justification for your decision

     Intensity guidelines for documentation review:
     - quick: 단일 문서 타이포 수정, 간단한 README 업데이트
     - standard: 여러 문서 리뷰, API 문서 검토, CHANGELOG 업데이트
     - deep: 전체 문서 감사, 문서 재구성, 대규모 리팩토링 후 문서 검토
     - comprehensive: 문서 시스템 전면 개편, 오픈소스 릴리즈 준비, 규제 문서 감사

     Send your final decision to the team lead via SendMessage in this format:
     INTENSITY_DECISION: {level}
     JUSTIFICATION: {reasoning}
     RISK_LEVEL: {from risk-assessor}
     KEY_FACTORS: {bullet points}"
   )
   ```

4. **Assign Tasks**:
   ```
   TaskUpdate(taskId: "{advocate_task}", owner: "intensity-advocate")
   TaskUpdate(taskId: "{efficiency_task}", owner: "efficiency-advocate")
   TaskUpdate(taskId: "{risk_task}", owner: "risk-assessor")
   TaskUpdate(taskId: "{arbitrator_task}", owner: "intensity-arbitrator")
   ```

5. **Wait for Decision**: Wait for intensity-arbitrator to send the final decision via SendMessage.

6. **Shutdown Decision Team**:
   ```
   SendMessage(type: "shutdown_request", recipient: "intensity-advocate", content: "Decision made.")
   SendMessage(type: "shutdown_request", recipient: "efficiency-advocate", content: "Decision made.")
   SendMessage(type: "shutdown_request", recipient: "risk-assessor", content: "Decision made.")
   SendMessage(type: "shutdown_request", recipient: "intensity-arbitrator", content: "Decision made.")
   ```
   **Wait for all shutdown confirmations** before proceeding to cleanup.
   Each teammate must respond with `shutdown_response` (approve: true) before cleanup.
   ```
   Teammate(operation: "cleanup")
   ```

7. **Apply Decision**: Set the intensity for all subsequent phases based on the arbitrator's decision.

8. **Display Decision**:
   ```
   ## Intensity Decision (Phase D0.1)
   - Decision: {intensity_level}
   - Risk Level: {risk_level}
   - Key Factors: {key_factors}
   - Justification: {justification}
   ```

**Error Handling:**
- If Agent Teams are unavailable: fall back to Claude solo judgment with explicit reasoning logged.
- If debate times out (>60 seconds): use the last available position from the arbitrator, or default to `standard`.
- If no consensus reached: default to `standard` (err on the side of thoroughness for documentation).

---

## Phase D0.2: Cost & Time Estimation

> **Shared Phase**: Full definition at `${PLUGIN_DIR}/shared-phases/cost-estimation.md`
> Uses `cost-estimator.sh --intensity ${INTENSITY} --pipeline docs`

Based on the decided intensity, estimate costs and time before proceeding. This phase runs immediately after intensity decision for ALL intensity levels.

**Purpose**: Give the user visibility into expected resource usage before committing to execution.

### Estimation Formula

Sum the applicable components based on decided intensity:

| Component | Applies At | Token Estimate | Est. Cost |
|-----------|-----------|---------------|-----------|
| Phase D0.5 Documentation Inventory | all | ~8K | ~$0.40 |
| Phase D1 Code-Doc Diff Analysis | standard+ | ~12K | ~$0.60 |
| Phase D2 Standards Research | deep+ | ~20K | ~$1.00 |
| Phase D3 Cross-Reference Validation | deep+ | ~18K | ~$0.90 |
| Phase D4 Benchmarking | comprehensive | ~40K | ~$2.00 |
| Phase D5.5 Strategy Debate | standard+ | ~25K | ~$1.25 |
| Phase D6 Review (6 agents) | standard+ | ~72K | ~$3.60 |
| Phase D6 External CLI (if enabled) | standard+ | ~16K | ~$0.26 |
| Phase D6 Debate Rounds 2+3 | standard+ | ~60K | ~$3.00 |
| Phase D6.5 Auto-Fix | standard+ | ~15K | ~$0.75 |
| Phase D6.6 Example Code Validation | standard+ | ~10K | ~$0.50 |
| Phase D7 Report | all | ~8K | ~$0.40 |

### Calculation

```
total_tokens = SUM(applicable_components)
total_cost = SUM(component_tokens * config.cost_estimation.token_cost_per_1k)
est_time_minutes = CEIL(total_tokens / 15000)  # ~15K tokens per minute throughput
```

### Display to User

```
## Cost & Time Estimate (Phase D0.2)

Intensity: {intensity}
Category: {category}
Mode: {mode}
Phases: {phase_list}
Claude Agents: {N} reviewers + arbitrator
External CLIs: {available models}

Est. Tokens: ~{total}K
Est. Cost:   ~${cost}
Est. Time:   ~{minutes} min

[Proceed / Adjust intensity / Cancel]
```

### Decision

- IF `--non-interactive` OR cost <= `config.cost_estimation.auto_proceed_under_dollars`: Proceed automatically
- IF user selects "Cancel": Stop pipeline, display summary of what was gathered so far
- IF user selects "Adjust intensity": Prompt for new intensity level, skip back to Phase D0.1 with `--intensity` override
- IF user selects "Proceed": Continue to Phase D0.5

---

## Phase D0.5: Documentation Inventory

Scan the project for all documentation files, classify by type, and generate a comprehensive inventory. This phase runs for ALL intensity levels including `quick`. Results are passed as context to all subsequent phases.

**Purpose**: Build a complete map of all documentation in the project to identify gaps, staleness, and coverage issues. Provides the foundation for all downstream analysis.

**Steps:**

1. **Run Documentation Inventory Script**:
   ```bash
   bash "${SCRIPTS_DIR}/doc-inventory.sh" "${PROJECT_ROOT}" --format json
   ```
   The script scans for all documentation files and outputs structured JSON.

2. **If script is unavailable**, fall back to manual scan:

   a. **Documentation File Scan** (Glob):
      ```
      Glob(pattern: "**/*.md", path: "${PROJECT_ROOT}")
      Glob(pattern: "**/*.txt", path: "${PROJECT_ROOT}")
      Glob(pattern: "**/*.rst", path: "${PROJECT_ROOT}")
      Glob(pattern: "**/*.adoc", path: "${PROJECT_ROOT}")
      Glob(pattern: "**/docs/**/*", path: "${PROJECT_ROOT}")
      Glob(pattern: "**/doc/**/*", path: "${PROJECT_ROOT}")
      Glob(pattern: "**/*.mdx", path: "${PROJECT_ROOT}")
      ```

   b. **Classify Each File by Type**:
      Match files against these patterns:
      - `README*` → readme
      - `*api*`, `*swagger*`, `*openapi*` → api
      - `*tutorial*`, `*guide*`, `*getting-started*`, `*quickstart*` → tutorial
      - `CHANGELOG*`, `HISTORY*`, `CHANGES*` → changelog
      - `adr-*`, `*decision*record*` → adr (architecture decision record)
      - `*runbook*`, `*playbook*`, `*ops*` → runbook
      - `*contributing*`, `CONTRIBUTING*` → contributing
      - `*license*`, `LICENSE*` → license
      - `*config*`, `*setup*`, `*install*` → setup
      - `*architecture*`, `*design*` → architecture
      - `*migration*`, `*upgrade*` → migration
      - `*troubleshoot*`, `*faq*`, `*debug*` → troubleshooting
      - `*security*` → security
      - `*test*` → testing
      - Everything else → general

   c. **Gather Metadata for Each File**:
      ```bash
      # For each doc file:
      stat -f "%m %z" "${doc_file}" 2>/dev/null || stat -c "%Y %s" "${doc_file}" 2>/dev/null
      ```
      Record: file path, last modified timestamp, file size, doc type, extension.

3. **Generate DOC_INVENTORY Summary**:
   ```
   === DOCUMENTATION INVENTORY ===

   TOTAL FILES: {count}
   BY TYPE:
   - readme: {count}
   - api: {count}
   - tutorial: {count}
   - changelog: {count}
   - adr: {count}
   - runbook: {count}
   - contributing: {count}
   - architecture: {count}
   - migration: {count}
   - troubleshooting: {count}
   - security: {count}
   - testing: {count}
   - general: {count}

   BY EXTENSION:
   - .md: {count}
   - .rst: {count}
   - .txt: {count}
   - .adoc: {count}
   - .mdx: {count}

   STALENESS INDICATORS:
   - Updated within 7 days: {count}
   - Updated within 30 days: {count}
   - Updated within 90 days: {count}
   - Not updated in 90+ days: {count} (STALE)

   FILE LIST:
   {path} | {type} | {size} | {last_modified} | {days_since_update}
   ...

   === END DOCUMENTATION INVENTORY ===
   ```

4. **For `--mode generate`**: Identify code files without corresponding documentation:
   ```
   Glob(pattern: "**/*.{ts,js,py,go,rs,java,rb,swift,kt}", path: "${PROJECT_ROOT}")
   ```
   Cross-reference with doc inventory to find undocumented modules.

   ```
   UNDOCUMENTED MODULES:
   - {module_path}: no corresponding documentation found
   - {module_path}: README exists but no API docs
   ...
   ```

5. **Save Inventory to Session**:
   ```bash
   echo '${DOC_INVENTORY}' > "${SESSION_DIR}/research/doc-inventory.md"
   ```

6. **Display Inventory Summary**:
   ```
   ## Documentation Inventory (Phase D0.5)

   ### Overview
   - Total documentation files: {N}
   - By type: {breakdown}
   - By extension: {breakdown}

   ### Staleness
   - Fresh (< 7 days): {N}
   - Recent (< 30 days): {N}
   - Aging (< 90 days): {N}
   - Stale (90+ days): {N}

   ### Gaps (if --mode generate)
   - Undocumented modules: {N}
   ```

7. **Quick Mode Execution** (if `--intensity quick`):
   After documentation inventory, execute the user's task directly:
   - Use inventory data to inform documentation work
   - Apply project documentation patterns detected from inventory
   - Ensure consistency with existing documentation structure
   - Perform simplified self-review:
     ```
     Self-Review Checklist:
     - Consistent with existing documentation structure
     - Follows project documentation conventions
     - Accurate relative to codebase
     - Appropriate for target audience
     - No broken internal references
     ```
   - Display completion summary and exit (skip remaining phases)

**Error Handling:**
- If doc-inventory.sh fails: fall back to manual Glob-based scan.
- If Glob returns no documentation files: warn "No documentation files found. Documentation inventory will be empty." Proceed with empty inventory.
- If metadata gathering fails for some files: skip those files, proceed with available data.

---

## Phase D1: Code-Doc Diff Analysis

Cross-reference recent code changes with documentation modification dates to identify documentation drift. This phase is unique to the documentation pipeline.

**Purpose**: Detect areas where code has changed but documentation has not been updated, producing a CODE_DOC_DRIFT map that guides review prioritization.

**Steps:**

1. **Find Recently Changed Code Files**:
   ```bash
   git log --since="30 days ago" --name-only --diff-filter=M --format="" | sort -u
   ```
   This produces a list of code files modified in the last 30 days.

2. **Find Recently Changed Code Files (extended for deep+)**:
   If intensity is deep or comprehensive, extend the window:
   ```bash
   git log --since="90 days ago" --name-only --diff-filter=M --format="" | sort -u
   ```

3. **Cross-Reference with Documentation**:
   For each changed code file:
   a. Identify related documentation files:
      - Same directory README.md
      - Docs that reference the code file (by filename or module name)
      - API docs for the module
      - Tutorial/guide docs that use the module
   b. Check documentation last modified date against code last modified date
   c. Calculate drift in days

4. **Generate CODE_DOC_DRIFT Map**:
   ```
   === CODE-DOC DRIFT MAP ===

   HIGH DRIFT (code changed, docs not updated 30+ days):
   - {code_file}
     Last code change: {date}
     Related docs:
     - {doc_file}: last updated {date}, drift: {days} days
     - {doc_file}: last updated {date}, drift: {days} days

   MEDIUM DRIFT (code changed, docs not updated 7-30 days):
   - {code_file}
     Last code change: {date}
     Related docs:
     - {doc_file}: last updated {date}, drift: {days} days

   LOW DRIFT (code changed, docs updated within 7 days):
   - {code_file}
     Last code change: {date}
     Related docs:
     - {doc_file}: last updated {date}, drift: {days} days

   NO DOCS FOUND (code changed, no related docs exist):
   - {code_file}: no related documentation found

   SUMMARY:
   - Total code files changed: {N}
   - High drift: {N} files
   - Medium drift: {N} files
   - Low drift: {N} files
   - No docs: {N} files

   === END CODE-DOC DRIFT MAP ===
   ```

5. **For `--mode generate`**: The high-drift and no-docs files become the primary targets for documentation generation.

6. **Save Drift Map to Session**:
   ```bash
   echo '${CODE_DOC_DRIFT}' > "${SESSION_DIR}/research/code-doc-drift.md"
   ```

7. **Display Drift Summary**:
   ```
   ## Code-Doc Diff Analysis (Phase D1)

   ### Drift Summary
   - Code files changed (last {30|90} days): {N}
   - High drift (30+ days stale): {N}
   - Medium drift (7-30 days): {N}
   - Low drift (< 7 days): {N}
   - Missing documentation: {N}

   ### Top Drift Files
   1. {code_file} — drift: {days} days — related docs: {doc_files}
   2. {code_file} — drift: {days} days — related docs: {doc_files}
   3. {code_file} — drift: {days} days — related docs: {doc_files}
   ```

8. If `--interactive`: ask user to confirm or supplement drift analysis.
   ```
   Code-doc drift analysis complete. Add additional context or proceed? (Enter to proceed, or type additions)
   ```

**Error Handling:**
- If not a git repository: warn "Not a git repository — code-doc drift analysis unavailable." Set `code_doc_drift_available = false`. Proceed with documentation inventory only.
- If git log fails: warn and proceed without drift data.
- If no code changes found: report "No code changes in the analysis window. Documentation may be up to date."

---

## Phase D2: Documentation Standards Research (deep/comprehensive intensity only)

Gather documentation best practices and standards specific to the project type and audience. Requires deep or comprehensive intensity.

**Pre-Step: Research Direction Debate** (deep/comprehensive intensity only):

Before executing searches, debate what to research:

1. **Create Research Direction Team**:
   ```
   Teammate(
     operation: "spawnTeam",
     team_name: "doc-research-direction-{YYYYMMDD-HHMMSS}",
     description: "Documentation standards research direction debate"
   )
   ```

2. **Create Research Tasks**:
   ```
   TaskCreate(
     subject: "Research documentation standards and frameworks",
     description: "Propose research directions for documentation standards like Diátaxis, documentation maturity models, and project-type-specific standards. Consider the project's technology stack and documentation needs.",
     activeForm: "Proposing documentation standards research"
   )

   TaskCreate(
     subject: "Research documentation tooling best practices",
     description: "Propose research directions for documentation tooling, linting, CI integration, auto-generation, and maintenance automation. Consider what tools would improve documentation quality for this project.",
     activeForm: "Proposing documentation tooling research"
   )

   TaskCreate(
     subject: "Research audience-specific documentation guidelines",
     description: "Propose research directions for audience-specific documentation writing guidelines. Consider who reads these docs (developers, end-users, operators, contributors) and what they need.",
     activeForm: "Proposing audience-specific doc research"
   )

   TaskCreate(
     subject: "Arbitrate documentation research direction priorities",
     description: "Wait for all three researcher proposals. Evaluate and prioritize the research agenda. Select top 3-5 research topics that will most improve documentation quality. Send the prioritized agenda to the team lead.",
     activeForm: "Arbitrating research direction"
   )
   ```

3. **Spawn Research Direction Agents** (all in parallel):
   ```
   Task(
     subagent_type: "general-purpose",
     team_name: "doc-research-direction-{session}",
     name: "researcher-standards",
     prompt: "You are the Documentation Standards Researcher. Propose research directions for documentation standards and frameworks.

     USER REQUEST: {user_request}
     CATEGORY: {category}
     DOC INVENTORY: {doc_inventory_summary}
     PROJECT CONTEXT: {project_context}

     Propose 3-5 research topics related to:
     - Diátaxis documentation framework (tutorials, how-to guides, reference, explanation)
     - Documentation maturity models and assessment criteria
     - Project-type-specific documentation standards (API docs, library docs, application docs)
     - Industry documentation standards (OpenAPI, JSDoc, docstrings, etc.)
     - Documentation quality metrics and measurement

     For each topic, provide:
     - Topic title
     - Why it matters for this specific project
     - Suggested search queries
     - Expected impact on documentation quality

     Send your proposals to research-arbitrator via SendMessage.
     Engage with other researchers' proposals — challenge or support their priorities."
   )

   Task(
     subagent_type: "general-purpose",
     team_name: "doc-research-direction-{session}",
     name: "researcher-tooling",
     prompt: "You are the Documentation Tooling Researcher. Propose research directions for documentation tooling best practices.

     USER REQUEST: {user_request}
     CATEGORY: {category}
     DOC INVENTORY: {doc_inventory_summary}
     PROJECT CONTEXT: {project_context}

     Propose 3-5 research topics related to:
     - Documentation linting tools (markdownlint, vale, etc.)
     - Documentation CI/CD integration (doc build, link checking, spell checking)
     - Auto-generation from code (JSDoc, Swagger, rustdoc, pydoc)
     - Documentation hosting and versioning (Docusaurus, MkDocs, GitBook)
     - Documentation maintenance automation (stale doc detection, freshness alerts)

     For each topic, provide:
     - Topic title
     - Why it matters for this specific project
     - Suggested search queries
     - Expected impact on documentation quality

     Send your proposals to research-arbitrator via SendMessage.
     Engage with other researchers' proposals — challenge or support their priorities."
   )

   Task(
     subagent_type: "general-purpose",
     team_name: "doc-research-direction-{session}",
     name: "researcher-audience",
     prompt: "You are the Audience Documentation Researcher. Propose research directions for audience-specific documentation writing guidelines.

     USER REQUEST: {user_request}
     CATEGORY: {category}
     DOC INVENTORY: {doc_inventory_summary}
     PROJECT CONTEXT: {project_context}

     Propose 3-5 research topics related to:
     - Developer documentation writing guidelines (API consumers, library users)
     - End-user documentation standards (non-technical audiences)
     - Operator/DevOps documentation standards (runbooks, playbooks)
     - Contributor documentation standards (onboarding, code of conduct)
     - Multi-audience documentation strategies (serving different readers)

     For each topic, provide:
     - Topic title
     - Why it matters for this specific project
     - Suggested search queries
     - Expected impact on documentation quality

     Send your proposals to research-arbitrator via SendMessage.
     Engage with other researchers' proposals — challenge or support their priorities."
   )

   Task(
     subagent_type: "general-purpose",
     team_name: "doc-research-direction-{session}",
     name: "research-arbitrator",
     prompt: "You are the Research Arbitrator. Prioritize the research agenda for documentation standards best practices.

     Wait for proposals from:
     1. researcher-standards (documentation standards and frameworks)
     2. researcher-tooling (documentation tooling best practices)
     3. researcher-audience (audience-specific documentation guidelines)

     After receiving all proposals:
     1. Evaluate each proposed topic for relevance and impact
     2. Identify overlaps and dependencies between proposals
     3. Prioritize the top 3-5 research topics
     4. Consider the category ({category}) and mode ({mode}) when prioritizing

     Send your prioritized research agenda to the team lead via SendMessage:
     RESEARCH_AGENDA:
     1. {topic} - Priority: HIGH - Reason: {why} - Queries: {search_queries}
     2. {topic} - Priority: HIGH - Reason: {why} - Queries: {search_queries}
     3. {topic} - Priority: MEDIUM - Reason: {why} - Queries: {search_queries}
     ..."
   )
   ```

4. **Assign Tasks**:
   ```
   TaskUpdate(taskId: "{standards_task}", owner: "researcher-standards")
   TaskUpdate(taskId: "{tooling_task}", owner: "researcher-tooling")
   TaskUpdate(taskId: "{audience_task}", owner: "researcher-audience")
   TaskUpdate(taskId: "{arbitrator_task}", owner: "research-arbitrator")
   ```

5. **Wait for Research Agenda**: Wait for research-arbitrator to send the prioritized agenda via SendMessage.

6. **Shutdown Research Direction Team**:
   ```
   SendMessage(type: "shutdown_request", recipient: "researcher-standards", content: "Research direction decided.")
   SendMessage(type: "shutdown_request", recipient: "researcher-tooling", content: "Research direction decided.")
   SendMessage(type: "shutdown_request", recipient: "researcher-audience", content: "Research direction decided.")
   SendMessage(type: "shutdown_request", recipient: "research-arbitrator", content: "Research direction decided.")
   Teammate(operation: "cleanup")
   ```

7. **Display Research Direction Decision**:
   ```
   ## Research Direction (Phase D2 Debate Result)
   {research_agenda}
   ```

---

Now execute the main research steps using the debate-determined agenda:

8. **Execute Research Queries**:
   For each prioritized research topic from the agenda:
   ```
   WebSearch(query: "{search_query_1}")
   WebSearch(query: "{search_query_2}")
   ```
   Compile results for each topic.

9. **Compile Documentation Standards Brief**:
   ```
   === DOCUMENTATION STANDARDS BRIEF ===

   TOPIC 1: {topic_title}
   Priority: {priority}
   Key Findings:
   - {finding_1}
   - {finding_2}
   - {finding_3}
   Actionable Guidelines:
   - {guideline_1}
   - {guideline_2}
   Sources: {sources}

   TOPIC 2: {topic_title}
   Priority: {priority}
   Key Findings:
   - {finding_1}
   - {finding_2}
   Actionable Guidelines:
   - {guideline_1}
   Sources: {sources}

   ...

   === END DOCUMENTATION STANDARDS BRIEF ===
   ```

10. **Cache Results**:
    ```bash
    echo '${DOC_STANDARDS_BRIEF}' | bash "${SCRIPTS_DIR}/cache-manager.sh" write "${PROJECT_ROOT}" market-research doc-standards --ttl 3
    ```

11. **Save to Session**:
    ```bash
    echo '${DOC_STANDARDS_BRIEF}' > "${SESSION_DIR}/research/doc-standards-brief.md"
    ```

12. **Display Standards Summary**:
    ```
    ## Documentation Standards Research (Phase D2)

    ### {Topic 1}
    - Key findings: {bullet points}
    - Guidelines: {bullet points}

    ### {Topic 2}
    - Key findings: {bullet points}
    - Guidelines: {bullet points}

    ...
    ```

13. If `--interactive`: ask user to proceed or adjust focus.
    ```
    Documentation standards research complete. Proceed to cross-reference validation? (y/n)
    ```

**Error Handling:**
- If research direction debate fails: use default research topics based on project type and category.
- If WebSearch returns no results for a topic: note the gap and continue with other topics.
- If all research fails: warn "Documentation standards research unavailable - proceeding without standards context." Set `doc_standards_available = false` for downstream phases.

---

## Phase D3: Cross-Reference Validation (deep/comprehensive intensity only)

Validate all internal document links, code references, and cross-document references. Requires deep or comprehensive intensity.

**Pre-Step: Validation Scope Debate** (deep/comprehensive intensity only):

Before executing validation, debate what scope to cover:

1. **Create Validation Scope Team**:
   ```
   Teammate(
     operation: "spawnTeam",
     team_name: "doc-validation-scope-{YYYYMMDD-HHMMSS}",
     description: "Documentation cross-reference validation scope debate"
   )
   ```

2. **Create Scope Tasks**:
   ```
   TaskCreate(
     subject: "Advocate for comprehensive link and reference validation",
     description: "Argue for validating all internal links, external links, code references, image references, and cross-document references. Consider the risk of broken links and stale references for users.",
     activeForm: "Advocating for comprehensive validation"
   )

   TaskCreate(
     subject: "Challenge over-validation scope",
     description: "Argue against validating everything. Consider which links are stable, which references are auto-generated, and which validations would waste resources. Propose a focused validation scope.",
     activeForm: "Challenging over-validation"
   )

   TaskCreate(
     subject: "Arbitrate validation scope",
     description: "Wait for arguments from link-validator and scope-challenger. Decide the final validation scope: which reference types must be validated, which can be spot-checked, and which can be skipped. Send the decision to the team lead.",
     activeForm: "Arbitrating validation scope"
   )
   ```

3. **Spawn Scope Agents** (all in parallel):
   ```
   Task(
     subagent_type: "general-purpose",
     team_name: "doc-validation-scope-{session}",
     name: "link-validator",
     prompt: "You are the Link Validator. Argue for comprehensive cross-reference validation.

     USER REQUEST: {user_request}
     DOC INVENTORY: {doc_inventory_summary}
     CODE-DOC DRIFT: {code_doc_drift_summary}

     Argue for validating:
     - ALL internal document links (relative and absolute)
     - ALL code references in documentation (function names, class names, file paths)
     - ALL cross-document references (doc A references doc B)
     - ALL image and asset references
     - ALL external links (URLs to external resources)
     - ALL code example imports (do referenced modules exist?)

     For each category, explain the risk of NOT validating.
     Consider: user trust, documentation reliability, developer experience.

     Send your argument to validation-arbitrator via SendMessage.
     Engage with scope-challenger's counter-arguments."
   )

   Task(
     subagent_type: "general-purpose",
     team_name: "doc-validation-scope-{session}",
     name: "scope-challenger",
     prompt: "You are the Scope Challenger. Argue against over-validation of documentation references.

     USER REQUEST: {user_request}
     DOC INVENTORY: {doc_inventory_summary}

     Argue for a focused validation scope. Consider:
     - External links change frequently and validation is slow — spot-check is sufficient
     - Auto-generated documentation links are typically correct
     - Image references in version-controlled repos rarely break
     - License and legal document links are stable
     - Over-validation wastes resources and delays review

     Propose a minimum validation scope that catches material broken references.

     Send your argument to validation-arbitrator via SendMessage.
     Engage with link-validator's counter-arguments."
   )

   Task(
     subagent_type: "general-purpose",
     team_name: "doc-validation-scope-{session}",
     name: "validation-arbitrator",
     prompt: "You are the Validation Arbitrator. Decide the final cross-reference validation scope.

     Wait for arguments from:
     1. link-validator (argues for comprehensive validation)
     2. scope-challenger (argues against over-validation)

     After receiving both arguments:
     1. Weigh the risk of each reference type against validation cost
     2. Consider the documentation inventory and code-doc drift data
     3. Decide for each reference type: VALIDATE, SPOT-CHECK, or SKIP

     Send your decision to the team lead via SendMessage:
     VALIDATION_SCOPE:
     VALIDATE (full check):
     - {reference_type}: {reason}
     SPOT-CHECK (sample):
     - {reference_type}: {reason}
     SKIP (not needed):
     - {reference_type}: {reason}"
   )
   ```

4. **Assign Tasks**:
   ```
   TaskUpdate(taskId: "{link_validator_task}", owner: "link-validator")
   TaskUpdate(taskId: "{scope_challenger_task}", owner: "scope-challenger")
   TaskUpdate(taskId: "{validation_arbitrator_task}", owner: "validation-arbitrator")
   ```

5. **Wait for Scope Decision**: Wait for validation-arbitrator to send the decision via SendMessage.

6. **Shutdown Validation Scope Team**:
   ```
   SendMessage(type: "shutdown_request", recipient: "link-validator", content: "Scope decided.")
   SendMessage(type: "shutdown_request", recipient: "scope-challenger", content: "Scope decided.")
   SendMessage(type: "shutdown_request", recipient: "validation-arbitrator", content: "Scope decided.")
   Teammate(operation: "cleanup")
   ```

7. **Display Validation Scope Decision**:
   ```
   ## Validation Scope (Phase D3 Debate Result)
   Validate: {list}
   Spot-Check: {list}
   Skip: {list with reasons}
   ```

---

Now execute the main cross-reference validation using the debate-determined scope:

8. **Validate Internal Document Links**:
   For each doc file in inventory, extract internal links:
   ```
   Grep(pattern: "\\[.*?\\]\\((?!https?://)(.*?)\\)", path: "${doc_file}", output_mode: "content")
   ```
   For each internal link, check if the target file exists:
   ```bash
   test -f "${resolved_path}" && echo "valid" || echo "broken"
   ```

9. **Validate Code References**:
   For each doc file, extract code references (backtick-quoted identifiers):
   ```
   Grep(pattern: "`[a-zA-Z_][a-zA-Z0-9_.]*`", path: "${doc_file}", output_mode: "content")
   ```
   Cross-reference against codebase:
   ```
   Grep(pattern: "{identifier}", path: "${PROJECT_ROOT}", glob: "*.{ts,js,py,go,rs,java,rb}")
   ```

10. **Validate Cross-Document References**:
    For each doc that references another doc, verify the referenced doc exists and the referenced section/heading exists.

11. **Compile Validation Results**:
    ```
    === CROSS-REFERENCE VALIDATION RESULTS ===

    BROKEN INTERNAL LINKS:
    - {doc_file}:{line} -> {target} (BROKEN)
    - {doc_file}:{line} -> {target} (BROKEN)

    STALE CODE REFERENCES:
    - {doc_file}:{line} references `{identifier}` — not found in codebase
    - {doc_file}:{line} references `{identifier}` — found but deprecated

    BROKEN CROSS-DOC REFERENCES:
    - {doc_file}:{line} references {other_doc}#{section} — section not found

    BROKEN IMAGE REFERENCES:
    - {doc_file}:{line} -> {image_path} (MISSING)

    SUMMARY:
    - Internal links checked: {N}, broken: {N}
    - Code references checked: {N}, stale: {N}
    - Cross-doc references checked: {N}, broken: {N}
    - Image references checked: {N}, missing: {N}

    === END CROSS-REFERENCE VALIDATION RESULTS ===
    ```

12. **Save Validation Results to Session**:
    ```bash
    echo '${VALIDATION_RESULTS}' > "${SESSION_DIR}/research/cross-ref-validation.md"
    ```

13. **Display Validation Summary**:
    ```
    ## Cross-Reference Validation (Phase D3)

    ### Internal Links
    - Checked: {N}, Broken: {N}

    ### Code References
    - Checked: {N}, Stale: {N}

    ### Cross-Doc References
    - Checked: {N}, Broken: {N}

    ### Image References
    - Checked: {N}, Missing: {N}
    ```

14. If `--interactive`: ask user to review broken references before proceeding.
    ```
    Cross-reference validation complete. {N} broken references found. Review before proceeding? (y/n)
    ```

**Error Handling:**
- If validation scope debate fails: default to VALIDATE for internal links and code references, SPOT-CHECK for external links, SKIP for image references.
- If Grep fails for a file: skip that file and continue.
- If all validation fails: warn "Cross-reference validation could not be completed." Set `cross_ref_validation_available = false` for downstream phases.

---

## Phase D4: Documentation Benchmarking (comprehensive intensity only)

**Applies to**: comprehensive intensity only. Skip for quick, standard, deep. Can be forced with `--force-benchmark`.

**Purpose**: Benchmark Claude, Codex, and Gemini on planted-error documentation test cases to determine which model is best at catching each category of documentation issues. Results drive model role assignments in Phase D6 — the highest-scoring model for each category becomes the Round 1 primary reviewer for that category.

**Steps:**

1. **Check benchmark cache**:
   ```bash
   BENCHMARK_CACHE=$("${SCRIPTS_DIR}/cache-manager.sh" read "${PROJECT_ROOT}" "benchmarks" "doc-model-scores" 2>/dev/null)
   ```
   Cache TTL: 14 days (from `config.cache.ttl_overrides.benchmarks`).

2. **Run benchmarks if cache miss or stale**:
   ```bash
   BENCHMARK_RESULTS=$(bash "${SCRIPTS_DIR}/benchmark-doc-models.sh" \
     --category all \
     --models "codex,gemini,claude" \
     --config "${DEFAULT_CONFIG}")
   ```

3. **Handle Claude benchmarks** (Claude cannot be called via CLI):

   The script outputs `claude_benchmark_needed: true` with test cases. For each test case:
   ```
   Task(
     subagent_type: "general-purpose",
     prompt: "You are a documentation reviewer specializing in {category}.
     Review this documentation and return findings JSON.

     DOCUMENTATION:
     {test_case_content}

     Return JSON: {model: 'claude', role: '{category}', findings: [{severity, confidence, section, title, category, description, suggestion}]}"
   )
   ```

   Score Claude findings against ground_truth using the same matching algorithm as the script (section match + keyword majority). Compute F1 per test case, average per category.

4. **Parse results and determine model role assignments**:

   ```
   FOR each review category (accuracy, completeness, freshness, readability, examples, consistency):
     scores = {
       claude: benchmark_results.scores.claude[category],
       codex: benchmark_results.scores.codex[category],
       gemini: benchmark_results.scores.gemini[category]
     }

     best_model = model with highest score
     min_score = config.docs_benchmarks.min_score_for_role (default: 60)

     IF best_model is an external model (codex or gemini) AND score >= min_score:
       Assign external model as Round 1 PRIMARY reviewer for this category
       Claude still participates as Round 2 cross-reviewer for this category
     ELSE:
       Claude is Round 1 primary (default)
       External models participate as Round 2 cross-reviewers
   ```

5. **Store role assignments**:
   ```bash
   echo '${ROLE_ASSIGNMENTS_JSON}' > "${SESSION_DIR}/benchmark-role-assignments.json"
   ```

   Role assignments JSON format:
   ```json
   {
     "accuracy": { "primary": "claude|codex|gemini", "cross_reviewers": ["codex", "gemini"] },
     "completeness": { "primary": "claude|codex|gemini", "cross_reviewers": ["codex", "gemini"] },
     "freshness": { "primary": "claude|codex|gemini", "cross_reviewers": ["codex", "gemini"] },
     "readability": { "primary": "claude|codex|gemini", "cross_reviewers": ["codex", "gemini"] },
     "examples": { "primary": "claude|codex|gemini", "cross_reviewers": ["codex", "gemini"] },
     "consistency": { "primary": "claude|codex|gemini", "cross_reviewers": ["codex", "gemini"] }
   }
   ```

6. **Display benchmark results**:
   ```
   DOC MODEL BENCHMARK RESULTS
   | Category      | Claude | Codex | Gemini | Primary Reviewer |
   |--------------|--------|-------|--------|-----------------|
   | accuracy      | {f1}   | {f1}  | {f1}   | {best_model}    |
   | completeness  | {f1}   | {f1}  | {f1}   | {best_model}    |
   | freshness     | {f1}   | {f1}  | {f1}   | {best_model}    |
   | readability   | {f1}   | {f1}  | {f1}   | {best_model}    |
   | examples      | {f1}   | {f1}  | {f1}   | {best_model}    |
   | consistency   | {f1}   | {f1}  | {f1}   | {best_model}    |
   ```

7. **Cache results**:
   ```bash
   echo '${BENCHMARK_RESULTS}' | "${SCRIPTS_DIR}/cache-manager.sh" write "${PROJECT_ROOT}" "benchmarks" "doc-model-scores" 2>/dev/null
   ```

**Error Handling:**
- If benchmark script fails: use default assignments (Claude primary for all, externals as cross-reviewers). Set `FALLBACK_LEVEL = max(FALLBACK_LEVEL, 1)`.
- If one external model fails benchmarking: exclude that model, use remaining models.
- If Claude benchmark Task fails: use score of 70 (assumed baseline) for Claude in that category.

---

## Phase D5.5: Documentation Strategy Debate (standard/deep/comprehensive intensity)

**Applies to**: standard, deep, comprehensive intensity. Skip for quick.

**Purpose**: Before reviewing or generating documentation, debate the best documentation strategy. Prevents wasted effort by catching strategy issues before detailed review begins.

**Steps:**

1. **Create Strategy Team**:
   ```
   Teammate(
     operation: "spawnTeam",
     team_name: "doc-strategy-decision-{YYYYMMDD-HHMMSS}",
     description: "Documentation strategy debate"
   )
   ```

2. **Prepare Context**: Compile all information gathered so far:
   - User's original request and task description
   - Documentation Inventory (Phase D0.5)
   - Code-Doc Drift Map (Phase D1)
   - Documentation Standards Brief (Phase D2, if executed)
   - Cross-Reference Validation Results (Phase D3, if executed)
   - Category and mode settings

3. **Create Strategy Tasks**:
   ```
   TaskCreate(
     subject: "Propose documentation improvement strategy",
     description: "Propose the best documentation strategy for this review/generation task. Include priority areas, documentation structure recommendations, and quality targets. Use all available context from inventory, drift analysis, and standards research.",
     activeForm: "Proposing documentation strategy"
   )

   TaskCreate(
     subject: "Challenge over-documentation scope",
     description: "Challenge whether the proposed strategy over-documents. Evaluate if all proposed documentation is necessary, if existing docs are sufficient for some areas, and if the scope is realistic.",
     activeForm: "Challenging documentation scope"
   )

   TaskCreate(
     subject: "Challenge based on code-doc drift data",
     description: "Challenge the proposed strategy based on code-doc drift analysis. Ensure the strategy prioritizes the areas with the highest drift and the most critical documentation gaps.",
     activeForm: "Challenging based on drift data"
   )

   TaskCreate(
     subject: "Arbitrate documentation strategy",
     description: "Wait for the strategy proposal and both challenges. Synthesize the best documentation strategy incorporating all perspectives. Output the final strategy with priorities, structure, and success criteria. Send to team lead.",
     activeForm: "Arbitrating documentation strategy"
   )
   ```

4. **Spawn Strategy Agents** (all in parallel):
   ```
   Task(
     subagent_type: "general-purpose",
     team_name: "doc-strategy-decision-{session}",
     name: "doc-strategy-advocate",
     prompt: "You are the Documentation Strategy Advocate. Propose the best documentation strategy for this task.

     REQUEST: {user_request}
     CATEGORY: {category}
     MODE: {mode}
     DOC INVENTORY: {doc_inventory}
     CODE-DOC DRIFT: {code_doc_drift}
     DOC STANDARDS: {doc_standards_if_available}
     CROSS-REF VALIDATION: {cross_ref_validation_if_available}

     Propose:
     1. Priority Areas: Which documentation needs the most attention (based on drift, staleness, gaps)
     2. Documentation Structure: Recommended organization and hierarchy
     3. Quality Targets: Specific quality criteria for each doc type
     4. Coverage Gaps: What documentation is missing and should be created
     5. Update Priorities: Which existing docs need updates first
     6. Style Guidelines: Consistent style and formatting recommendations

     Consider:
     - What docs have the highest drift from current code?
     - What audience needs are unmet by current documentation?
     - What doc types are missing entirely?
     - What is the best Diátaxis classification for the project's docs?

     Send your proposal to strategy-arbitrator via SendMessage.
     Engage with challenges from other agents."
   )

   Task(
     subagent_type: "general-purpose",
     team_name: "doc-strategy-decision-{session}",
     name: "scope-challenger",
     prompt: "You are the Scope Challenger. Challenge the proposed documentation strategy for over-documentation.

     REQUEST: {user_request}
     CATEGORY: {category}
     DOC INVENTORY: {doc_inventory}

     Wait for doc-strategy-advocate's proposal, then:
     1. Challenge unnecessary documentation: Are all proposed docs necessary?
     2. Challenge scope: Is the documentation scope realistic for the project size?
     3. Challenge coverage: Are some areas already well-documented and don't need changes?
     4. Challenge structure: Would a simpler structure serve just as well?
     5. Challenge maintenance burden: Will the proposed docs be maintainable long-term?
     6. Suggest a more focused approach

     Send challenges to strategy-arbitrator via SendMessage.
     Engage in debate with doc-strategy-advocate."
   )

   Task(
     subagent_type: "general-purpose",
     team_name: "doc-strategy-decision-{session}",
     name: "accuracy-challenger",
     prompt: "You are the Accuracy Challenger. Challenge the proposed strategy based on code-doc drift data.

     REQUEST: {user_request}
     DOC INVENTORY: {doc_inventory}
     CODE-DOC DRIFT: {code_doc_drift}
     CROSS-REF VALIDATION: {cross_ref_validation_if_available}

     Wait for doc-strategy-advocate's proposal, then:
     1. Challenge priority ordering: Does the strategy prioritize the highest-drift areas?
     2. Challenge gap assessment: Does the strategy address the most critical missing docs?
     3. Challenge accuracy claims: Does the drift data support the proposed improvements?
     4. Challenge broken references: Are the most critical broken references prioritized?
     5. Flag areas where the strategy ignores high-drift files
     6. Suggest drift-data-driven reprioritization

     Send challenges to strategy-arbitrator via SendMessage.
     Engage in debate with doc-strategy-advocate."
   )

   Task(
     subagent_type: "general-purpose",
     team_name: "doc-strategy-decision-{session}",
     name: "strategy-arbitrator",
     prompt: "You are the Strategy Arbitrator. Synthesize the best documentation strategy.

     Wait for:
     1. doc-strategy-advocate's proposal (documentation strategy)
     2. scope-challenger's challenges (over-documentation concerns)
     3. accuracy-challenger's challenges (code-doc drift alignment)

     Then:
     1. Weigh each position on its merits
     2. Resolve conflicts between coverage and maintainability
     3. Ensure the final strategy addresses the highest-drift areas first
     4. Ensure the strategy is realistic and maintainable
     5. Produce a concrete documentation strategy

     Send your decision to the team lead via SendMessage in this EXACT format:
     DOC_STRATEGY:
     Priority Areas:
     1. {area_1}: {reason} (drift: {days})
     2. {area_2}: {reason} (drift: {days})
     3. {area_3}: {reason}
     Documentation Structure: {recommended_structure}
     Coverage Gaps:
     - {gap_1}: {recommended_action}
     - {gap_2}: {recommended_action}
     Quality Targets:
     - {doc_type}: {quality_criteria}
     - {doc_type}: {quality_criteria}
     Success Criteria:
     1. {criterion_1} -> verify: {how_to_check}
     2. {criterion_2} -> verify: {how_to_check}
     3. {criterion_3} -> verify: {how_to_check}
     4. {criterion_4} -> verify: {how_to_check}
     5. {criterion_5} -> verify: {how_to_check}

     IMPORTANT: Success Criteria must be concrete and verifiable.
     Good: 'All API endpoints have corresponding documentation -> verify: cross-reference routes with doc index'
     Bad: 'Documentation is comprehensive' (not verifiable)"
   )
   ```

5. **Assign Tasks**:
   ```
   TaskUpdate(taskId: "{strategy_task}", owner: "doc-strategy-advocate")
   TaskUpdate(taskId: "{scope_task}", owner: "scope-challenger")
   TaskUpdate(taskId: "{accuracy_task}", owner: "accuracy-challenger")
   TaskUpdate(taskId: "{arbitrator_task}", owner: "strategy-arbitrator")
   ```

6. **Wait for Strategy Decision**: Wait for strategy-arbitrator to send the final strategy via SendMessage.

7. **Shutdown Strategy Team**:
   ```
   SendMessage(type: "shutdown_request", recipient: "doc-strategy-advocate", content: "Strategy decided.")
   SendMessage(type: "shutdown_request", recipient: "scope-challenger", content: "Strategy decided.")
   SendMessage(type: "shutdown_request", recipient: "accuracy-challenger", content: "Strategy decided.")
   SendMessage(type: "shutdown_request", recipient: "strategy-arbitrator", content: "Strategy decided.")
   Teammate(operation: "cleanup")
   ```

8. **Apply Strategy**: Use the arbitrator's decision as the documentation review/generation plan. Pass it as context to Phase D6 reviewers so they can verify documentation follows the agreed strategy. **Pass Success Criteria to Phase D7 for post-review verification.**

9. **Implement**: Execute the documentation review or generation following the decided strategy. Apply documentation standards from Phase D2 (if available). Use code-doc drift data from Phase D1. Address cross-reference issues from Phase D3 (if available). **Only address areas listed in the strategy. If additional areas are needed, document the deviation.**

10. **Display Strategy Decision**:
    ```
    ## Documentation Strategy (Phase D5.5 Debate Result)
    - Priority Areas: {areas}
    - Documentation Structure: {structure}
    - Coverage Gaps: {gaps}
    - Quality Targets: {targets}
    - Success Criteria:
      1. {criterion_1} -> verify: {check}
      2. {criterion_2} -> verify: {check}
      3. {criterion_3} -> verify: {check}
    ```

**Error Handling:**
- If Agent Teams are unavailable: fall back to Claude solo strategy with explicit reasoning.
- If debate times out: use doc-strategy-advocate's initial proposal with accuracy-challenger's concerns noted.
- If no consensus: err on the side of addressing high-drift areas first (accuracy-challenger's position takes precedence on drift matters).

---

## Phase D6: Multi-Agent Documentation Review (standard/deep/comprehensive intensity)

> **Feedback Routing**: If `feedback.use_for_routing` is true, read `${PLUGIN_DIR}/shared-phases/feedback-routing.md` and apply feedback-based model-category role assignments before spawning reviewers.

This phase deploys 6 specialized documentation reviewer teammates plus a debate arbitrator, with optional external CLI models (Codex, Gemini), to perform a comprehensive multi-perspective review of the documentation. Each reviewer examines the documentation from their domain expertise, then they cross-review each other's findings in a structured 3-round debate. External models participate as either Round 1 primary reviewers (if benchmark-assigned at comprehensive intensity) or Round 2 cross-reviewers (default at standard/deep).

### Step D6.1: Create Agent Team

Create a new Agent Team for this documentation review session:

```
Teammate(
  operation: "spawnTeam",
  team_name: "doc-review-{YYYYMMDD-HHMMSS}",
  description: "AI Review Arena - Documentation review session"
)
```

### Step D6.1.5: Determine External Model Participation

Determine which external models (Codex, Gemini) will participate and in what role, based on intensity and benchmark results.

**Role Assignment Logic:**

```
IF intensity == "comprehensive" AND Phase D4 benchmark results exist:
  Load role assignments from "${SESSION_DIR}/benchmark-role-assignments.json"

  FOR each review category (accuracy, completeness, freshness, readability, examples, consistency):
    IF role_assignments[category].primary is an external model:
      Mark that external model as Round 1 PRIMARY for this category
      The corresponding Claude reviewer still participates but with CROSS-REVIEWER role
    ELSE:
      External models participate as Round 2 cross-reviewers only (default)

ELIF intensity in ["standard", "deep"]:
  # No benchmarking data available — all external models are Round 2 cross-reviewers only
  FOR each available external model (codex, gemini):
    IF config.docs_models[model].enabled AND CLI is available:
      Assign as Round 2 cross-reviewer

ELSE:
  # quick intensity — no external models
  Skip external model participation
```

**Check CLI availability:**
```bash
# Check Codex
command -v codex &>/dev/null && echo "codex_available=true" || echo "codex_available=false"

# Check Gemini
command -v gemini &>/dev/null && echo "gemini_available=true" || echo "gemini_available=false"
```

**Store participation plan:**
```
EXTERNAL_PARTICIPATION = {
  "codex": {
    "available": true|false,
    "role": "round1_primary|round2_cross|none",
    "primary_categories": ["accuracy", ...] or [],
    "cross_review_categories": ["completeness", ...] or ["all"]
  },
  "gemini": {
    "available": true|false,
    "role": "round1_primary|round2_cross|none",
    "primary_categories": [...] or [],
    "cross_review_categories": [...] or ["all"]
  }
}
```

### Step D6.2: Create Review Tasks

Create tasks in the shared task list for each of the 6 documentation reviewers:

```
TaskCreate(
  subject: "Documentation accuracy review",
  description: "Review documentation for accuracy against the codebase. Validate all code references, API descriptions, parameter documentation, return value documentation, and technical claims. Send findings to team lead via SendMessage when complete.",
  activeForm: "Reviewing documentation accuracy"
)

TaskCreate(
  subject: "Documentation completeness review",
  description: "Review documentation for completeness. Identify missing sections, undocumented features, incomplete API coverage, missing error documentation, and gaps in getting-started guides. Send findings to team lead via SendMessage when complete.",
  activeForm: "Reviewing documentation completeness"
)

TaskCreate(
  subject: "Documentation freshness review",
  description: "Review documentation for freshness. Identify stale content, outdated references, deprecated API usage in docs, and docs that haven't been updated to reflect recent code changes. Send findings to team lead via SendMessage when complete.",
  activeForm: "Reviewing documentation freshness"
)

TaskCreate(
  subject: "Documentation readability review",
  description: "Review documentation for readability. Evaluate structure, clarity, formatting, navigation, heading hierarchy, writing quality, and audience appropriateness. Send findings to team lead via SendMessage when complete.",
  activeForm: "Reviewing documentation readability"
)

TaskCreate(
  subject: "Documentation example code review",
  description: "Review all code examples in documentation. Validate syntax correctness, import accuracy, API usage correctness, security practices, and whether examples are runnable. Send findings to team lead via SendMessage when complete.",
  activeForm: "Reviewing documentation examples"
)

TaskCreate(
  subject: "Documentation consistency review",
  description: "Review documentation for cross-document consistency. Check terminology consistency, formatting consistency, style consistency, naming conventions, and cross-reference accuracy. Send findings to team lead via SendMessage when complete.",
  activeForm: "Reviewing documentation consistency"
)
```

### Step D6.3: Spawn Doc Reviewer Teammates + External CLI Round 1

For each reviewer in REVIEWER_ROLES, read the agent definition file and spawn a teammate with ENRICHED documentation context. **Spawn ALL reviewers + arbitrator in parallel** by making multiple Task tool calls in a single message.

**External CLI Round 1 (if assigned as primary):**

If any external model was assigned as Round 1 primary for a category in Step D6.1.5, run the corresponding CLI script **in parallel** with Claude teammate spawning:

```bash
# For each external model assigned as Round 1 primary:
IF EXTERNAL_PARTICIPATION.codex.role == "round1_primary":
  FOR category IN EXTERNAL_PARTICIPATION.codex.primary_categories:
    echo "$DOC_CONTENT_WITH_CONTEXT" | \
      "${SCRIPTS_DIR}/codex-doc-review.sh" "${DEFAULT_CONFIG}" --mode round1 --category "$category" \
      > "${SESSION_DIR}/findings/round1-codex-${category}.json" 2>/dev/null &

IF EXTERNAL_PARTICIPATION.gemini.role == "round1_primary":
  FOR category IN EXTERNAL_PARTICIPATION.gemini.primary_categories:
    echo "$DOC_CONTENT_WITH_CONTEXT" | \
      "${SCRIPTS_DIR}/gemini-doc-review.sh" "${DEFAULT_CONFIG}" --mode round1 --category "$category" \
      > "${SESSION_DIR}/findings/round1-gemini-${category}.json" 2>/dev/null &
```

Where `$DOC_CONTENT_WITH_CONTEXT` includes the documentation content plus enriched context (inventory, drift map, standards research if available). Wait for external CLIs to complete alongside Claude teammates.

**Merging external Round 1 results**: After external CLI Round 1 completes, parse the JSON output and merge into the findings aggregation alongside Claude reviewer results. Each external finding follows the same schema: `{model, role, mode, findings: [{severity, confidence, section, title, category, description, suggestion}]}`.

**NOTE**: When an external model is Round 1 primary for a category, the corresponding Claude reviewer for that category still runs independently. Both sets of findings are included in Round 2 cross-review and debate. This provides redundancy — if the external CLI fails, the Claude reviewer's findings are still available.

Read REVIEWER_ROLES from config docs_intensity_presets.{INTENSITY}.reviewer_roles.
Fallback if missing: ["doc-accuracy-reviewer", "doc-completeness-reviewer", "doc-freshness-reviewer", "doc-readability-reviewer", "doc-example-reviewer", "doc-consistency-reviewer"]

For each role in REVIEWER_ROLES:

1. Read the agent definition:
   ```
   Read(file_path: "${AGENTS_DIR}/{role}.md")
   ```

2. Spawn as teammate with ENRICHED context:
   ```
   Task(
     subagent_type: "general-purpose",
     team_name: "doc-review-{session_id}",
     name: "{role}",
     prompt: "{contents of agents/{role}.md}

     --- REVIEW TASK ---
     Task ID: {task_id}
     Category: {category}
     Mode: {mode}

     === ENRICHED CONTEXT (from Arena Docs Lifecycle) ===

     DOC INVENTORY:
     {doc_inventory_from_phase_d0_5}

     CODE-DOC DRIFT:
     {code_doc_drift_from_phase_d1}

     DOC STANDARDS:
     {doc_standards_from_phase_d2_if_available}

     CROSS-REF VALIDATION:
     {cross_ref_validation_from_phase_d3_if_available}

     DOC STRATEGY:
     {doc_strategy_from_phase_d5_5}

     === END ENRICHED CONTEXT ===

     DOCUMENTATION TO REVIEW:
     {the_documentation_being_reviewed}
     --- END DOCUMENTATION ---

     INSTRUCTIONS:
     1. Review the documentation above following your agent instructions
     2. USE the enriched context to inform your review
     3. Send your findings JSON to the team lead using SendMessage
     4. Mark your task as completed using TaskUpdate
     5. Stay active for the 3-round debate:
        Round 2: You will receive other reviewers' findings and provide challenge/support responses
        Round 3: You will defend your challenged findings or withdraw/revise them"
   )
   ```

**CRITICAL: Launch ALL reviewers simultaneously.** Use multiple Task tool calls in a single message to maximize parallelism. Do NOT wait for one teammate to finish before spawning the next.

**Spawn doc-debate-arbitrator:**
```
Read(file_path: "${AGENTS_DIR}/doc-debate-arbitrator.md")

Task(
  subagent_type: "general-purpose",
  team_name: "doc-review-{session_id}",
  name: "doc-debate-arbitrator",
  prompt: "{contents of agents/doc-debate-arbitrator.md}

  --- DEBATE CONTEXT ---
  Session: {session_id}
  Category: {category}
  Mode: {mode}
  Active reviewers: {REVIEWER_ROLES list — the roles spawned for this session}
  Cross-review rounds: 3

  DOC STRATEGY (from Phase D5.5):
  {doc_strategy_from_phase_d5_5}

  You will receive:
  1. Round 1 findings from all reviewers (forwarded by team lead)
  2. Round 2 cross-review responses from all 6 reviewers (sent directly to you)
  3. A 'ROUND 2 COMPLETE' signal from the team lead
  4. Round 3 defense responses from reviewers whose findings were challenged
  5. A 'ROUND 3 COMPLETE' signal from the team lead

  After Round 3 completes, apply the consensus algorithm (including defense data) and send the final consensus JSON to the team lead.
  --- END CONTEXT ---"
)
```

**CRITICAL: Launch ALL 6 reviewers + arbitrator simultaneously.** Use multiple Task tool calls in a single message to maximize parallelism. Do NOT wait for one teammate to finish before spawning the next.

### Step D6.4: Assign Tasks to Teammates

After spawning, assign each task to its corresponding teammate:

```
TaskUpdate(taskId: "{accuracy_task_id}", owner: "doc-accuracy-reviewer")
TaskUpdate(taskId: "{completeness_task_id}", owner: "doc-completeness-reviewer")
TaskUpdate(taskId: "{freshness_task_id}", owner: "doc-freshness-reviewer")
TaskUpdate(taskId: "{readability_task_id}", owner: "doc-readability-reviewer")
TaskUpdate(taskId: "{example_task_id}", owner: "doc-example-reviewer")
TaskUpdate(taskId: "{consistency_task_id}", owner: "doc-consistency-reviewer")
```

### Step D6.5: Collect Round 1 Results

Wait for all 6 reviewers to send their findings via SendMessage. Messages are delivered to you (the team lead) as they complete. Wait for all active reviewer teammates to report.

For each reviewer, expect:
- doc-accuracy-reviewer: findings JSON with code-doc accuracy issues
- doc-completeness-reviewer: findings JSON with coverage gaps + completeness_scorecard
- doc-freshness-reviewer: findings JSON with staleness issues + freshness_scorecard
- doc-readability-reviewer: findings JSON with readability issues + readability_scorecard
- doc-example-reviewer: findings JSON with code example issues + example_scorecard
- doc-consistency-reviewer: findings JSON with consistency issues + consistency_scorecard

Parse and validate all findings. Skip invalid JSON with a warning.

### Step D6.6: Findings Aggregation

Merge and deduplicate findings from all 6 reviewers:

1. **Combine all findings**: Collect findings from all 6 reviewer SendMessage responses.

2. **Deduplicate**:
   - Group by section + category (within same section AND similar issue category)
   - Cross-validated findings (same section flagged by 2+ reviewers): average confidence + 10% boost
   - Keep most detailed description, note which reviewers agreed
   - Merge suggestions: take the most specific and actionable remediation

3. **Filter by confidence threshold**: Use `review.confidence_threshold` from config (default: 40 for documentation).

4. **Sort**: severity (critical > high > medium > low) > confidence > section

5. **Display intermediate results**:
   ```
   ## Findings Summary (Pre-Debate)
   - Total findings: {N}
   - By severity: {X} critical, {Y} high, {Z} medium, {W} low
   - By category: Accuracy: {A}, Completeness: {B}, Freshness: {C}, Readability: {D}, Examples: {E}, Consistency: {F}
   - Cross-validated: {M} findings confirmed by 2+ reviewers
   ```

6. **Forward aggregated findings to doc-debate-arbitrator**:
   ```
   SendMessage(
     type: "message",
     recipient: "doc-debate-arbitrator",
     content: "ROUND 1 AGGREGATED FINDINGS:
     {aggregated_findings_json}

     ROUND 1 FINDINGS BY REVIEWER:
     doc-accuracy-reviewer: {accuracy_findings_json}
     doc-completeness-reviewer: {completeness_findings_json}
     doc-freshness-reviewer: {freshness_findings_json}
     doc-readability-reviewer: {readability_findings_json}
     doc-example-reviewer: {example_findings_json}
     doc-consistency-reviewer: {consistency_findings_json}",
     summary: "Round 1 complete - {N} total findings from 6 reviewers"
   )
   ```

### Step D6.7: 3-Round Debate

**Round 1**: Independent review (already completed in Steps D6.3-D6.5).

**Round 2**: Cross-review -- each reviewer evaluates other reviewers' findings.

Send each reviewer the OTHER five reviewers' findings:

**Send to doc-accuracy-reviewer:**
```
SendMessage(
  type: "message",
  recipient: "doc-accuracy-reviewer",
  content: "CROSS-REVIEW -- Round 2 of 3

  Evaluate findings from the other 5 documentation reviewers from your ACCURACY expertise perspective.

  DOC-COMPLETENESS-REVIEWER FINDINGS:
  {completeness_findings_json}

  DOC-FRESHNESS-REVIEWER FINDINGS:
  {freshness_findings_json}

  DOC-READABILITY-REVIEWER FINDINGS:
  {readability_findings_json}

  DOC-EXAMPLE-REVIEWER FINDINGS:
  {example_findings_json}

  DOC-CONSISTENCY-REVIEWER FINDINGS:
  {consistency_findings_json}

  For EACH finding relevant to your domain:
  1. SUPPORT if the finding is valid from an accuracy perspective -- cite corroborating evidence, confidence_adjustment (+N)
  2. CHALLENGE if the finding is incorrect or misrepresents the documentation -- cite counter-evidence, confidence_adjustment (-N)

  You may add NEW OBSERVATIONS that other reviewers missed from your accuracy perspective.

  Send each response to doc-debate-arbitrator via SendMessage as JSON:
  {\"finding_id\":\"<section:title>\", \"action\":\"challenge|support\", \"confidence_adjustment\":-20 to +20, \"reasoning\":\"<detailed reasoning>\", \"evidence\":\"<evidence>\"}

  When done: send 'doc-accuracy-reviewer debate evaluation complete' to doc-debate-arbitrator.",
  summary: "Round 2: cross-review other reviewers' findings"
)
```

**Send to doc-completeness-reviewer:**
```
SendMessage(
  type: "message",
  recipient: "doc-completeness-reviewer",
  content: "CROSS-REVIEW -- Round 2 of 3

  Evaluate findings from the other 5 documentation reviewers from your COMPLETENESS expertise perspective.

  DOC-ACCURACY-REVIEWER FINDINGS:
  {accuracy_findings_json}

  DOC-FRESHNESS-REVIEWER FINDINGS:
  {freshness_findings_json}

  DOC-READABILITY-REVIEWER FINDINGS:
  {readability_findings_json}

  DOC-EXAMPLE-REVIEWER FINDINGS:
  {example_findings_json}

  DOC-CONSISTENCY-REVIEWER FINDINGS:
  {consistency_findings_json}

  For EACH finding relevant to your domain:
  1. SUPPORT if the finding involves a documentation coverage gap -- cite missing content, confidence_adjustment (+N)
  2. CHALLENGE if the finding misidentifies something as missing that exists elsewhere -- cite where it exists, confidence_adjustment (-N)

  You may add NEW OBSERVATIONS that other reviewers missed from your completeness perspective.

  Send each response to doc-debate-arbitrator via SendMessage as JSON:
  {\"finding_id\":\"<section:title>\", \"action\":\"challenge|support\", \"confidence_adjustment\":-20 to +20, \"reasoning\":\"<detailed reasoning>\", \"evidence\":\"<evidence>\"}

  When done: send 'doc-completeness-reviewer debate evaluation complete' to doc-debate-arbitrator.",
  summary: "Round 2: cross-review other reviewers' findings"
)
```

**Send to doc-freshness-reviewer:**
```
SendMessage(
  type: "message",
  recipient: "doc-freshness-reviewer",
  content: "CROSS-REVIEW -- Round 2 of 3

  Evaluate findings from the other 5 documentation reviewers from your FRESHNESS expertise perspective.

  DOC-ACCURACY-REVIEWER FINDINGS:
  {accuracy_findings_json}

  DOC-COMPLETENESS-REVIEWER FINDINGS:
  {completeness_findings_json}

  DOC-READABILITY-REVIEWER FINDINGS:
  {readability_findings_json}

  DOC-EXAMPLE-REVIEWER FINDINGS:
  {example_findings_json}

  DOC-CONSISTENCY-REVIEWER FINDINGS:
  {consistency_findings_json}

  For EACH finding relevant to your domain:
  1. SUPPORT if the finding involves stale or outdated content -- cite staleness evidence, confidence_adjustment (+N)
  2. CHALLENGE if the finding flags content as stale when it is actually current -- cite current evidence, confidence_adjustment (-N)

  You may add NEW OBSERVATIONS that other reviewers missed from your freshness perspective.

  Send each response to doc-debate-arbitrator via SendMessage as JSON:
  {\"finding_id\":\"<section:title>\", \"action\":\"challenge|support\", \"confidence_adjustment\":-20 to +20, \"reasoning\":\"<detailed reasoning>\", \"evidence\":\"<evidence>\"}

  When done: send 'doc-freshness-reviewer debate evaluation complete' to doc-debate-arbitrator.",
  summary: "Round 2: cross-review other reviewers' findings"
)
```

**Send to doc-readability-reviewer:**
```
SendMessage(
  type: "message",
  recipient: "doc-readability-reviewer",
  content: "CROSS-REVIEW -- Round 2 of 3

  Evaluate findings from the other 5 documentation reviewers from your READABILITY expertise perspective.

  DOC-ACCURACY-REVIEWER FINDINGS:
  {accuracy_findings_json}

  DOC-COMPLETENESS-REVIEWER FINDINGS:
  {completeness_findings_json}

  DOC-FRESHNESS-REVIEWER FINDINGS:
  {freshness_findings_json}

  DOC-EXAMPLE-REVIEWER FINDINGS:
  {example_findings_json}

  DOC-CONSISTENCY-REVIEWER FINDINGS:
  {consistency_findings_json}

  For EACH finding relevant to your domain:
  1. SUPPORT if the finding involves a readability or clarity issue -- cite readability standard, confidence_adjustment (+N)
  2. CHALLENGE if the finding conflates content accuracy with readability quality -- cite distinction, confidence_adjustment (-N)

  You may add NEW OBSERVATIONS that other reviewers missed from your readability and structure expertise.

  Send each response to doc-debate-arbitrator via SendMessage as JSON:
  {\"finding_id\":\"<section:title>\", \"action\":\"challenge|support\", \"confidence_adjustment\":-20 to +20, \"reasoning\":\"<detailed reasoning>\", \"evidence\":\"<evidence>\"}

  When done: send 'doc-readability-reviewer debate evaluation complete' to doc-debate-arbitrator.",
  summary: "Round 2: cross-review other reviewers' findings"
)
```

**Send to doc-example-reviewer:**
```
SendMessage(
  type: "message",
  recipient: "doc-example-reviewer",
  content: "CROSS-REVIEW -- Round 2 of 3

  Evaluate findings from the other 5 documentation reviewers from your CODE EXAMPLE expertise perspective.

  DOC-ACCURACY-REVIEWER FINDINGS:
  {accuracy_findings_json}

  DOC-COMPLETENESS-REVIEWER FINDINGS:
  {completeness_findings_json}

  DOC-FRESHNESS-REVIEWER FINDINGS:
  {freshness_findings_json}

  DOC-READABILITY-REVIEWER FINDINGS:
  {readability_findings_json}

  DOC-CONSISTENCY-REVIEWER FINDINGS:
  {consistency_findings_json}

  For EACH finding relevant to your domain:
  1. SUPPORT if the finding involves a code example issue -- cite code validation result, confidence_adjustment (+N)
  2. CHALLENGE if the finding misidentifies working code as broken or applies wrong language standards -- cite correct interpretation, confidence_adjustment (-N)

  You may add NEW OBSERVATIONS that other reviewers missed from your code example expertise.

  Send each response to doc-debate-arbitrator via SendMessage as JSON:
  {\"finding_id\":\"<section:title>\", \"action\":\"challenge|support\", \"confidence_adjustment\":-20 to +20, \"reasoning\":\"<detailed reasoning>\", \"evidence\":\"<evidence>\"}

  When done: send 'doc-example-reviewer debate evaluation complete' to doc-debate-arbitrator.",
  summary: "Round 2: cross-review other reviewers' findings"
)
```

**Send to doc-consistency-reviewer:**
```
SendMessage(
  type: "message",
  recipient: "doc-consistency-reviewer",
  content: "CROSS-REVIEW -- Round 2 of 3

  Evaluate findings from the other 5 documentation reviewers from your CONSISTENCY expertise perspective.

  DOC-ACCURACY-REVIEWER FINDINGS:
  {accuracy_findings_json}

  DOC-COMPLETENESS-REVIEWER FINDINGS:
  {completeness_findings_json}

  DOC-FRESHNESS-REVIEWER FINDINGS:
  {freshness_findings_json}

  DOC-READABILITY-REVIEWER FINDINGS:
  {readability_findings_json}

  DOC-EXAMPLE-REVIEWER FINDINGS:
  {example_findings_json}

  For EACH finding relevant to your domain:
  1. SUPPORT if the finding involves a cross-document consistency issue -- cite inconsistency evidence, confidence_adjustment (+N)
  2. CHALLENGE if the finding identifies an intentional variation as inconsistency -- cite design rationale, confidence_adjustment (-N)

  You may add NEW OBSERVATIONS that other reviewers missed from your consistency expertise.

  Send each response to doc-debate-arbitrator via SendMessage as JSON:
  {\"finding_id\":\"<section:title>\", \"action\":\"challenge|support\", \"confidence_adjustment\":-20 to +20, \"reasoning\":\"<detailed reasoning>\", \"evidence\":\"<evidence>\"}

  When done: send 'doc-consistency-reviewer debate evaluation complete' to doc-debate-arbitrator.",
  summary: "Round 2: cross-review other reviewers' findings"
)
```

**Wait for all Claude Round 2 responses**: All 6 Claude reviewers send their challenge/support responses directly to doc-debate-arbitrator via SendMessage. Wait for each reviewer to send their completion message.

**Step D6.7.2: External CLI Cross-Review (Round 2)**

Run external CLI cross-review **in parallel** with Claude Round 2 responses. External models that are NOT assigned as Round 1 primary participate as Round 2 cross-reviewers:

```bash
# Prepare aggregated Round 1 findings for external CLI input
ALL_ROUND1_FINDINGS=$(jq -s '.' "${SESSION_DIR}"/findings/round1-*.json 2>/dev/null)

# Codex Round 2 cross-review (if available and configured as cross-reviewer for any category)
IF config.docs_models.codex.enabled AND codex_available AND codex has cross_review_categories:
  echo "$ALL_ROUND1_FINDINGS" | \
    "${SCRIPTS_DIR}/codex-doc-review.sh" "${DEFAULT_CONFIG}" --mode round2 \
    > "${SESSION_DIR}/debate/round2-codex-doc.json" 2>/dev/null &

# Gemini Round 2 cross-review
IF config.docs_models.gemini.enabled AND gemini_available AND gemini has cross_review_categories:
  echo "$ALL_ROUND1_FINDINGS" | \
    "${SCRIPTS_DIR}/gemini-doc-review.sh" "${DEFAULT_CONFIG}" --mode round2 \
    > "${SESSION_DIR}/debate/round2-gemini-doc.json" 2>/dev/null &

wait  # Wait for external CLIs (parallel with Claude Round 2)
```

**Merge external Round 2 responses**: Parse external CLI cross-review JSON and forward to doc-debate-arbitrator alongside Claude Round 2 data:

```
FOR each external_model_round2_file IN "${SESSION_DIR}/debate/round2-*-doc.json":
  Parse JSON responses
  IF valid AND has responses array:
    Forward to doc-debate-arbitrator via SendMessage:
    SendMessage(
      type: "message",
      recipient: "doc-debate-arbitrator",
      content: "External model cross-review (Round 2):
      Model: {model_name}
      {external_round2_json}",
      summary: "External {model} Round 2 cross-review results"
    )
```

**Error handling for external Round 2:**
- If external CLI times out: skip that model's cross-review, note in report
- If external CLI returns invalid JSON: skip, note in report
- External cross-review failure does NOT block the debate — Claude Round 2 is sufficient

**Signal Round 2 complete to arbitrator:**
```
SendMessage(
  type: "message",
  recipient: "doc-debate-arbitrator",
  content: "ROUND 2 COMPLETE. All cross-review responses received from all 6 Claude reviewers + {N} external model(s). Hold for Round 3 defense responses.",
  summary: "Round 2 cross-review complete -- preparing Round 3"
)
```

**Round 3**: Defense -- original reviewers defend challenged findings or withdraw/revise them.

After Round 2, identify which findings received challenges. For each reviewer that had findings challenged, send them the challenges and ask for a defense:

**Send defense requests to each reviewer whose findings were challenged:**
```
SendMessage(
  type: "message",
  recipient: "{reviewer-name}",
  content: "DEFENSE ROUND -- Round 3 of 3

  The following findings from your Round 1 review were CHALLENGED by other reviewers during cross-review.

  CHALLENGES AGAINST YOUR FINDINGS:
  {list of challenges targeting this reviewer's findings, including:
   - finding_id
   - challenger name
   - challenge reasoning
   - confidence_adjustment
   - counter-evidence}

  For EACH challenged finding, respond with ONE of:
  1. DEFEND -- maintain your finding with additional evidence or stronger reasoning
  2. REVISE -- adjust severity or confidence based on valid challenger points
  3. WITHDRAW -- concede the finding was incorrect or overstated

  Send each response to doc-debate-arbitrator via SendMessage as JSON:
  {\"finding_id\":\"<section:title>\", \"action\":\"defend|withdraw|revise\", \"original_severity\":\"<original>\", \"revised_severity\":\"<same or adjusted>\", \"revised_confidence\":0-100, \"defense_reasoning\":\"<why finding should stand, or why revising/withdrawing>\", \"additional_evidence\":\"<new evidence if any>\"}

  When done: send '{reviewer-name} defense round complete' to doc-debate-arbitrator.",
  summary: "Round 3: defend your challenged findings"
)
```

**NOTE**: Only send defense requests to Claude reviewers who had at least one finding challenged. Reviewers with zero challenges skip Round 3.

**External model Round 3 defense**: If an external model participated as Round 1 primary and its findings were challenged, the external model **cannot** defend (no interactive CLI capability). In this case:
- The finding receives `defense_status = "implicit_defend"` in the arbitrator
- The finding stands at its post-Round 2 confidence (no recovery)
- The arbitrator should note "external model — no interactive defense capability"

**Wait for all Round 3 responses**: All challenged Claude reviewers send their defend/withdraw/revise responses directly to doc-debate-arbitrator via SendMessage. External model findings with challenges use implicit defense.

**Signal Round 3 complete to arbitrator:**
```
SendMessage(
  type: "message",
  recipient: "doc-debate-arbitrator",
  content: "ROUND 3 COMPLETE. All defense responses received. Synthesize the final consensus from all 3 rounds.",
  summary: "Round 3 defense complete -- synthesize final consensus"
)
```

### Step D6.8: Collect Consensus

Wait for doc-debate-arbitrator to send the final consensus JSON via SendMessage. The consensus includes:

- Accepted findings with agreement levels (unanimous, majority, single-source-validated, conflict-resolved)
- Rejected findings with reasons
- Disputed findings with all perspectives
- Quality scorecard aggregated from all reviewers
- Debate statistics

Parse the consensus JSON. If invalid, request re-send from arbitrator.

Store consensus results:
```bash
echo '${CONSENSUS_JSON}' > "${SESSION_DIR}/findings/consensus.json"
```

**Debate Error Handling:**
- If a reviewer does not respond to Round 2 within 60 seconds: proceed without their cross-review. Note in report.
- If a reviewer does not respond to Round 3 within 60 seconds: treat their challenged findings as unchanged (implicit defend). Note in report.
- If doc-debate-arbitrator fails: collect whatever challenge/support/defense messages were received. Synthesize consensus manually using the aggregated Round 1 findings with Round 2 and Round 3 adjustments.
- If no cross-review responses at all: skip debate rounds 2 and 3, use Round 1 aggregated findings as final results.

---

## Phase D6.5: Apply Findings (Review -> Fix Loop)

After the debate consensus is reached, automatically apply fixes for critical and high severity findings.

**Trigger condition**: At least 1 accepted finding with severity `critical` or `high` in the consensus.

**If no critical/high findings**: Skip Phase D6.5, proceed directly to Phase D6.6.

### Step D6.5.1: Identify Actionable Findings

From the consensus results, extract all accepted findings with severity `critical` or `high`:

```
actionable_findings = consensus.accepted.filter(f =>
  f.severity == "critical" OR f.severity == "high"
)
```

Sort by severity (critical first), then by confidence (descending).

### Step D6.5.2: Auto-Revise Documentation

For each actionable finding, apply the suggested fix to the documentation:

```
FOR each finding IN actionable_findings:
  1. Locate the section referenced by finding.section
  2. Apply the finding.suggestion as a documentation revision
  3. Track the change: {finding_id, original_text, revised_text, applied_suggestion}

  Revision rules:
  - ACCURACY findings: correct code references, fix API descriptions, update parameter docs
  - COMPLETENESS findings: add missing sections, document undocumented features, fill gaps
  - FRESHNESS findings: update outdated content, replace deprecated references, refresh examples
  - READABILITY findings: restructure for clarity, fix formatting, improve navigation
  - EXAMPLE findings: fix code syntax, update imports, replace deprecated API usage
  - CONSISTENCY findings: unify terminology, align formatting, fix cross-references
```

### Step D6.5.3: Verify Fixes

After applying all revisions, do a quick self-verification:

```
FOR each applied revision:
  1. Does the revised text address the original finding?
  2. Does the revision maintain consistency with surrounding content?
  3. Does the revision preserve the intended documentation purpose?
  4. Does the revision not introduce NEW issues?

  IF verification fails for any revision:
    Revert that specific revision and flag it for manual review
```

### Step D6.5.4: Display Applied Changes

```markdown
## Applied Fixes (Phase D6.5)

{N} critical/high findings auto-revised:

| # | Severity | Section | Finding | Status |
|---|----------|---------|---------|--------|
| 1 | {severity} | {section} | {title} | Applied / Reverted (manual review needed) |
| 2 | ... | ... | ... | ... |

### Revision Details

**[{severity}] {title}**
- Section: {section}
- Original: "{original_text_snippet}"
- Revised: "{revised_text_snippet}"
- Based on: {reviewer attribution}
```

**NOTE**: Medium and low severity findings are reported but NOT auto-applied. They appear in the final report as recommendations for the user to review.

---

## Phase D6.6: Example Code Validation (standard/deep/comprehensive intensity)

**Applies to**: standard, deep, comprehensive intensity. Skip for quick. This phase is unique to the documentation pipeline.

**Purpose**: Extract all code blocks from documentation and validate them for correctness, ensuring code examples actually work and don't mislead readers.

**Steps:**

1. **Extract Code Blocks**:
   For each documentation file in the inventory, extract fenced code blocks:
   ```
   Grep(pattern: "```(\\w+)?", path: "${doc_file}", output_mode: "content", -n: true)
   ```
   Parse language identifier and content of each code block.

2. **For Each Code Block, Validate**:

   a. **Language Detection**:
      - Use the fenced code block language identifier (```javascript, ```python, etc.)
      - If no identifier, attempt auto-detection from content

   b. **Syntax Check** (if tooling available):
      ```bash
      # JavaScript/TypeScript
      echo "${code_block}" | node --check - 2>&1

      # Python
      echo "${code_block}" | python3 -c "import ast; ast.parse(open('/dev/stdin').read())" 2>&1

      # Shell
      echo "${code_block}" | bash -n 2>&1
      ```
      Record: pass/fail + error message

   c. **Import Verification**:
      Extract import/require statements from the code block:
      ```
      Grep(pattern: "^(import |from |require\\(|use )", output_mode: "content")
      ```
      For each import, check if the referenced module exists:
      ```
      Grep(pattern: "{module_name}", path: "${PROJECT_ROOT}", glob: "package.json")
      Grep(pattern: "{module_name}", path: "${PROJECT_ROOT}", glob: "requirements.txt")
      ```

   d. **Deprecated API Detection**:
      Check if the code block uses deprecated APIs:
      ```
      Grep(pattern: "@deprecated|DEPRECATED|deprecated", path: "${PROJECT_ROOT}/node_modules/{module}")
      ```

   e. **Security Check**:
      Flag potential security issues in code examples:
      - Hardcoded credentials or API keys
      - Insecure protocols (http:// instead of https://)
      - eval() or exec() usage
      - SQL string concatenation

3. **Compile Validation Results**:
   ```
   === EXAMPLE CODE VALIDATION RESULTS ===

   TOTAL CODE BLOCKS: {N}
   BY LANGUAGE: {breakdown}

   SYNTAX ERRORS:
   - {doc_file}:{line} ({language}): {error_message}
   - {doc_file}:{line} ({language}): {error_message}

   IMPORT ISSUES:
   - {doc_file}:{line}: imports `{module}` — module not found in project
   - {doc_file}:{line}: imports `{module}` — module deprecated

   DEPRECATED API USAGE:
   - {doc_file}:{line}: uses `{api}` — deprecated since {version}

   SECURITY CONCERNS:
   - {doc_file}:{line}: hardcoded credential detected
   - {doc_file}:{line}: insecure protocol usage

   SUMMARY:
   - Total code blocks: {N}
   - Syntax errors: {N}
   - Import issues: {N}
   - Deprecated APIs: {N}
   - Security concerns: {N}
   - Valid: {N}

   === END EXAMPLE CODE VALIDATION RESULTS ===
   ```

4. **Save to Session**:
   ```bash
   echo '${CODE_VALIDATION_RESULTS}' > "${SESSION_DIR}/research/example-code-validation.md"
   ```

5. **Display Validation Summary**:
   ```
   ## Example Code Validation (Phase D6.6)

   ### Summary
   - Total code blocks: {N}
   - Syntax errors: {N}
   - Import issues: {N}
   - Deprecated APIs: {N}
   - Security concerns: {N}
   - Valid: {N}

   ### Issues
   {list of issues with file:line references}
   ```

**Error Handling:**
- If syntax check tooling is unavailable for a language: skip syntax check for that language, note in results.
- If import verification fails: mark as "unverified" and continue.
- If no code blocks found: report "No code blocks found in documentation."

---

## Phase D7: Final Report & Cleanup

### Step D7.0: Cross-Documentation Consistency Validation (all intensities except quick)

Before generating the final report, perform cross-documentation consistency checks:

1. **Terminology Consistency**: Check that the same concepts use the same terms across documents:
   - Product name → must be consistent across all docs
   - Feature names → must use consistent naming
   - API endpoint names → must match actual codebase

2. **Formatting Consistency**: Verify consistent formatting throughout:
   - Heading hierarchy → consistent across docs
   - Code block language identifiers → consistent usage
   - Link formatting → consistent style
   - List formatting → consistent style

3. **Content Consistency**: Verify information doesn't contradict across documents:
   - Version numbers → must match across docs
   - Configuration options → must be consistent
   - API parameters → must match between reference and tutorial docs
   - Installation instructions → must be consistent

**Output**:
```
## Cross-Doc Consistency Check
- Terminology: {pass/fail} — {issues if any}
- Formatting: {pass/fail} — {inconsistencies if any}
- Content: {pass/fail} — {contradictions if any}
```

If `config.consistency_validation.fail_on_inconsistency` is true AND any check fails, flag for user attention before generating report. Otherwise, include inconsistencies as warnings in the report.

### Step D7.1: Generate Documentation Review Report

Build the complete documentation review report:

```markdown
# AI Review Arena - Documentation Review Report

**Date:** {timestamp}
**Category:** {category}
**Mode:** {mode}
**Intensity:** {intensity_level}
**Mode:** Agent Teams (documentation lifecycle with enriched context)

---

## Documentation Inventory Summary

{from Phase D0.5 - abbreviated inventory}

---

## Executive Summary

{key findings from consensus, overall documentation quality assessment, top 3 priorities for improvement, code-doc drift status}

---

## Quality Scorecard

| Category | Score | Key Issues |
|----------|-------|------------|
| Accuracy | {score}% | {brief_summary} |
| Completeness | {score}% | {brief_summary} |
| Freshness | {score}% | {brief_summary} |
| Readability | {score}% | {brief_summary} |
| Examples | {score}% | {brief_summary} |
| Consistency | {score}% | {brief_summary} |
| **Overall** | **{score}%** | |

---

## Code-Doc Drift Summary (if Phase D1 ran)

- Code files changed: {N}
- High drift: {N} | Medium drift: {N} | Low drift: {N}
- Missing documentation: {N}
- **Top drift areas:** {list}

---

## Documentation Standards (if Phase D2 ran)

- **Standards Applied:** {list}
- **Key Recommendations:** {bullet points}

---

## Cross-Reference Validation (if Phase D3 ran)

- Internal links: {checked}/{broken}
- Code references: {checked}/{stale}
- Cross-doc references: {checked}/{broken}
- Image references: {checked}/{missing}

---

## Example Code Validation (if Phase D6.6 ran)

- Total code blocks: {N}
- Syntax errors: {N}
- Import issues: {N}
- Deprecated APIs: {N}
- Security concerns: {N}

---

## Cross-Doc Consistency Validation

- Terminology: {pass/fail}
- Formatting: {pass/fail}
- Content: {pass/fail}
- {Details of any inconsistencies found}

---

## Critical & High Priority Findings

### [{severity}] {title}
- **Section:** {section}
- **Category:** {category}
- **Confidence:** {confidence}% {cross-validated badge if applicable}
- **Found by:** {reviewer(s)}
- **Agreement:** {unanimous|majority|single-source-validated|conflict-resolved}

**Description:** {description}

**Suggestion:** {remediation}

---

## Success Criteria Verification

| # | Criterion | Verification Check | Result |
|---|-----------|-------------------|--------|
| 1 | {criterion_from_phase_d5_5} | {verification_method} | PASS/FAIL |
| 2 | {criterion} | {verification_method} | PASS/FAIL |
| 3 | {criterion} | {verification_method} | PASS/FAIL |
| 4 | {criterion} | {verification_method} | PASS/FAIL |
| 5 | {criterion} | {verification_method} | PASS/FAIL |

---

## Medium & Low Priority Findings

| Severity | Section | Title | Category | Confidence | Reviewer | Agreement |
|----------|---------|-------|----------|------------|----------|-----------|
| {severity} | {section} | {title} | {category} | {confidence}% | {reviewer} | {agreement} |

---

## Disputed Findings (Human Review Required)

{For each disputed finding:}

### {title}
- **Section:** {section}

**Perspectives:**
{all reviewer perspectives on this finding, what each reviewer argued}

**Unresolved Questions:**
- {question_1}
- {question_2}

**Recommended Action:** {what the human should investigate or decide}

---

## Debate Summary

### Round 1: Independent Review
- Total findings: {N}
- By reviewer: Accuracy: {A}, Completeness: {B}, Freshness: {C}, Readability: {D}, Examples: {E}, Consistency: {F}

### Round 2: Cross-Review
- Total responses: {N}
- Supports: {N}
- Challenges: {N}
- New observations: {N}

### Round 3: Defense
- Findings challenged: {N}
- Defended: {N}
- Revised: {N}
- Withdrawn: {N}

### Consensus
- Findings accepted: {N}
- Findings rejected: {N}
- Findings disputed: {N}
- Confidence increased: {N}
- Confidence decreased: {N}
- Confidence unchanged: {N}

## Applied Fixes (Phase D6.5)
- Critical/high findings auto-revised: {N}
- Successfully applied: {N}
- Reverted (manual review needed): {N}

---

## Cost Summary

| Component | Teammates | Est. Tokens | Est. Cost |
|-----------|-----------|-------------|-----------|
| **Phase D0.1: Intensity Decision** | | | |
| Intensity Debate Agents | 4 teammates | ~{X}K | ~${A.AA} |
| **Phase D2: Standards Research** | | | |
| Research Direction Debate | {0 or 4} teammates | ~{X}K | ~${B.BB} |
| **Phase D3: Cross-Reference Validation** | | | |
| Validation Scope Debate | {0 or 3} teammates | ~{X}K | ~${C.CC} |
| **Phase D5.5: Documentation Strategy** | | | |
| Strategy Debate Agents | 4 teammates | ~{X}K | ~${D.DD} |
| **Phase D6: Documentation Review** | | | |
| doc-accuracy-reviewer | 1 teammate | ~{X}K | ~${E.EE} |
| doc-completeness-reviewer | 1 teammate | ~{X}K | ~${F.FF} |
| doc-freshness-reviewer | 1 teammate | ~{X}K | ~${G.GG} |
| doc-readability-reviewer | 1 teammate | ~{X}K | ~${H.HH} |
| doc-example-reviewer | 1 teammate | ~{X}K | ~${I.II} |
| doc-consistency-reviewer | 1 teammate | ~{X}K | ~${J.JJ} |
| doc-debate-arbitrator | 1 teammate | ~{X}K | ~${K.KK} |
| **Total** | | | **~${L.LL}** |
```

**Output Steps:**
1. Generate report in configured language (`output.language`)
2. Display the formatted report to the user
3. Save report: write to `${SESSION_DIR}/reports/doc-review-report.md`
4. If output path was specified in config:
   ```bash
   cp "${SESSION_DIR}/reports/doc-review-report.md" "${OUTPUT_PATH}"
   ```

### Step D7.2: Shutdown All Teammates

Send shutdown requests to ALL active teammates. Wait for each confirmation before proceeding.

```
For each role in REVIEWER_ROLES (the roles that were spawned in Phase D6):
  SendMessage(type: "shutdown_request", recipient: "{role}", content: "Documentation review session complete. Thank you.")
SendMessage(type: "shutdown_request", recipient: "doc-debate-arbitrator", content: "Documentation review session complete. Thank you.")
```

Only send shutdown to teammates that were actually spawned in this session.
Wait for all shutdown confirmations before cleanup.

### Step D7.3: Cleanup Team & Sessions

After ALL teammates have confirmed shutdown:

```
Teammate(operation: "cleanup")
```

Clean up stale session directories from previous runs:
```bash
bash "${SCRIPTS_DIR}/cache-manager.sh" cleanup-sessions --max-age 24
```

**IMPORTANT:** Team cleanup will fail if active teammates still exist. Always shutdown all teammates first.

### Step D7.4: Display Session Reference

```
## Session Complete
- Session directory: ${SESSION_DIR}
- Report: ${SESSION_DIR}/reports/doc-review-report.md
- Doc Inventory: ${SESSION_DIR}/research/doc-inventory.md
- Code-Doc Drift: ${SESSION_DIR}/research/code-doc-drift.md
- Doc Standards: ${SESSION_DIR}/research/doc-standards-brief.md
- Cross-Ref Validation: ${SESSION_DIR}/research/cross-ref-validation.md
- Example Validation: ${SESSION_DIR}/research/example-code-validation.md
- Consensus: ${SESSION_DIR}/findings/consensus.json
```

### Step D7.5: Feedback Collection (Optional)

**Applies when**: `config.feedback.enabled == true` AND `--interactive` mode.

After displaying the report, prompt the user for feedback on the top findings:

```
DOCUMENTATION REVIEW QUALITY FEEDBACK (optional — helps improve future reviews)

Top findings from this review:
1. [{severity}] {title} (by {reviewer}, {confidence}%)
2. [{severity}] {title} (by {reviewer}, {confidence}%)
3. [{severity}] {title} (by {reviewer}, {confidence}%)
4. [{severity}] {title} (by {reviewer}, {confidence}%)
5. [{severity}] {title} (by {reviewer}, {confidence}%)

For each finding, rate: useful / not useful / false positive
Or: skip (no feedback this session)
```

Record feedback:
```bash
FOR each rated finding:
  bash "${SCRIPTS_DIR}/feedback-tracker.sh" record \
    "${SESSION_ID}" \
    "${FINDING_ID}" \
    "${VERDICT}" \
    --model "${MODEL}" \
    --category "${CATEGORY}" \
    --severity "${SEVERITY}"
```

---

## Fallback Framework

Track the current fallback level throughout execution. Initialize at Level 0 and escalate as failures occur.

```
FALLBACK_LEVEL=0
FALLBACK_LOG=[]
```

### Fallback Level Definitions

| Level | Name | Trigger | Action | Report Impact |
|-------|------|---------|--------|---------------|
| 0 | Full Operation | — | All phases, all Agent Teams, full 6-reviewer debate | None |
| 1 | Research Failure | Phase D1 or D2 fails | Proceed without drift/research context | "Drift analysis: unavailable" or "Research: unavailable" |
| 1.5 | Benchmark Failure | Phase D4 fails | Use default role assignments (Claude primary for all, externals as cross-reviewers) | "Benchmarks: defaults used" |
| 2 | Validation Failure | Phase D3 fails | Skip cross-reference pre-validation, reviewers work without pre-validated references | "Cross-refs: not pre-validated" |
| 2.5 | External CLI Failure | Codex/Gemini CLI fails | Proceed with Claude reviewers only | "External models: unavailable" |
| 3 | Agent Teams Failure | Teammate spawn fails | Fall back to Task subagents (no debate, sequential) | "Mode: subagent (no debate)" |
| 4 | All Failure | Agent Teams AND subagents fail | Claude solo inline analysis with self-review checklist | "Mode: solo inline" |

### Per-Phase Fallback Rules

| Phase | On Failure | Fallback Behavior | Level Escalation |
|-------|-----------|-------------------|-----------------|
| Phase D0.5 (Inventory) | Glob/Script fails | Use minimal inventory from user request only | Stay at current level |
| Phase D1 (Drift) | git log or cross-ref fails | Skip drift analysis, warn reviewers | Escalate to Level 1 |
| Phase D2 (Research) | Debate or WebSearch fails | Skip standards research, note in report | Escalate to Level 1 if not already |
| Phase D3 (Validation) | Validation debate fails | Skip pre-validation | Escalate to Level 2 |
| Phase D4 (Benchmark) | Script or Claude scoring fails | Use default role assignments | Escalate to Level 1.5 |
| Phase D5.5 (Strategy) | Strategy debate agents fail | Skip strategy, proceed to review | Stay at current level |
| Phase D6 (External CLI) | Codex/Gemini CLI fails | Proceed with Claude reviewers only | Escalate to Level 2.5 |
| Phase D6 (Review) | Teammate spawn fails | Try Task subagents; if that fails, solo | Escalate to Level 3 or 4 |
| Phase D6 (Debate) | Arbitrator fails | Manual consensus from available responses | Stay at current level |
| Phase D6.5 (Auto-Fix) | Fix verification fails | Revert all fixes, flag for manual review | Stay at current level |
| Phase D6.6 (Examples) | Syntax check tooling fails | Skip syntax checks, report as unverified | Stay at current level |

### Teammate Error Recovery

- **Teammate stops unexpectedly**: Check TaskList for incomplete tasks. Spawn replacement if total active < minimum required (4 reviewers minimum for valid debate).
- **Teammate not responding**: Send follow-up message. Wait 60s. If still no response, mark as failed and proceed with other teammates.
- **doc-debate-arbitrator fails**: Collect available challenge/support messages. Synthesize consensus manually: group by section+category, apply confidence adjustments, sort by severity then confidence.
- **JSON Parse Errors**: Attempt extraction via regex (first-`{`-to-last-`}`). If fails, discard and continue.

### Self-Review Checklist (Level 4 Fallback)

When all review infrastructure fails, apply this self-review checklist:
```
Self-Review Checklist (Fallback Mode):
- Documentation matches current codebase
- All code references are valid
- All internal links work
- Code examples are syntactically correct
- Terminology is consistent across documents
- Content is up to date with recent code changes
- Documentation structure follows project conventions
- No stale or deprecated references
```

### Cleanup on Error

If an error occurs mid-process, always attempt cleanup:
1. Send shutdown requests to all spawned teammates
2. Wait for confirmations (max 30s)
3. Run Teammate cleanup
4. Report the error with partial results if available
5. Save session data to `${SESSION_DIR}/` for debugging

### Report Integration

The final report MUST include a Fallback Status section:

```markdown
## Fallback Status

| Metric | Value |
|--------|-------|
| Final Level | {FALLBACK_LEVEL} — {level_name} |
| Phases Skipped | {list of skipped phases} |
| Context Available | {list: doc_inventory ✓, code_doc_drift ✗, standards ✓, cross_refs ✗, ...} |

### Fallback Log
{FALLBACK_LOG entries with timestamps}
```

IF FALLBACK_LEVEL >= 3:
  Add prominent warning at top of report:
  "This review ran at degraded capacity (Level {N}). Results may be less comprehensive than a full review."
