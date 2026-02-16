---
description: "Full AI development lifecycle orchestrator - pre-research, stack detection, compliance, benchmarking, model routing, and multi-AI code review"
argument-hint: "[scope] [--figma <url>] [--phase codebase|codebase,review|stack|research|compliance|benchmark|review|all] [--skip-cache] [--force-benchmark] [--interactive] [--intensity quick|standard|deep|comprehensive] [--models claude,codex,gemini] [--focus <areas>]"
allowed-tools: [Bash, Glob, Grep, Read, Task, WebSearch, WebFetch, Teammate, SendMessage, TaskCreate, TaskUpdate, TaskList, TaskGet]
---

# AI Review Arena - Full Lifecycle Orchestrator (Agent Teams)

You are the **team lead** for the AI Review Arena full lifecycle orchestrator. This command orchestrates the entire development review lifecycle: stack detection, pre-implementation research, compliance checking, model benchmarking, Figma design analysis, and multi-AI adversarial code review with Agent Teams. Codex and Gemini participate via external CLI tools.

## Architecture

```
Team Lead (You - this session)
├── Phase 0: Context & Configuration (+ MCP Dependency Detection)
├── Phase 0.1: Intensity Decision (Agent Teams debate - MANDATORY)
│   ├── intensity-advocate     → argues for higher intensity
│   ├── efficiency-advocate    → argues for lower intensity
│   ├── risk-assessor          → evaluates production/security risk
│   └── intensity-arbitrator   → synthesizes consensus, decides intensity
├── Phase 0.2: Cost & Time Estimation (user approval before proceeding)
├── Phase 0.5: Codebase Analysis (conventions, reusable code, structure)
├── Phase 1: Stack Detection (detect-stack.sh)
├── Phase 2: Pre-Implementation Research (search-best-practices.sh + WebSearch)
│   └── Research Direction Debate (deep+ only)
│       ├── researcher agents  → propose different research angles
│       └── research-arbitrator → prioritizes research agenda
├── Phase 3: Compliance Detection (search-guidelines.sh + WebSearch)
│   └── Compliance Scope Debate (deep+ only)
│       ├── compliance-advocate → argues for more rules
│       ├── scope-challenger    → argues against over-application
│       └── compliance-arbitrator → decides actual scope
├── Phase 4: Model Benchmarking (benchmark-models.sh + Task subagents)
├── Phase 5: Figma Analysis (Figma MCP tools, optional)
├── Phase 5.5: Implementation Strategy (Agent Teams debate - standard+)
│   ├── architecture-advocate  → proposes design approach
│   ├── security-challenger    → challenges security implications
│   ├── pragmatic-challenger   → challenges complexity/feasibility
│   └── strategy-arbitrator    → synthesizes best approach
├── Phase 6: Agent Team Review (follows multi-review.md pattern)
│   ├── Create team (Teammate tool)
│   ├── Spawn reviewer teammates (Task tool with team_name)
│   ├── Spawn scale-advisor teammate (always included)
│   ├── Spawn compliance-checker teammate (if compliance detected)
│   ├── Spawn research-coordinator teammate (deep intensity only)
│   ├── Run external CLIs (Codex, Gemini via Bash)
│   ├── Coordinate debate phase
│   └── Aggregate findings & generate report
├── Phase 6.5: Apply Findings (auto-fix safe, high-confidence findings)
│   ├── Filter findings by strict auto-fix criteria
│   ├── Apply fixes
│   ├── Run test suite verification
│   └── Revert on test failure
├── Phase 7: Final Report & Cleanup
│   ├── Generate enriched report with compliance + scale sections
│   ├── Shutdown all teammates
│   └── Cleanup team
└── Fallback Framework (structured 6-level graceful degradation)

Claude Reviewer Teammates (independent Claude Code instances)
├── security-reviewer    ─┐
├── bug-detector         ─┤── SendMessage <-> each other (debate)
├── architecture-reviewer─┤── SendMessage -> debate-arbitrator
├── performance-reviewer ─┤── SendMessage -> team lead (findings)
├── test-reviewer        ─┤
├── scale-advisor        ─┤── scale/concurrency analysis
├── compliance-checker   ─┘── guideline compliance (conditional)
│
├── research-coordinator ─── deep intensity only
└── debate-arbitrator    ─── Receives challenges/supports -> synthesizes consensus

External CLIs (via Bash, not teammates)
├── Codex CLI -> JSON findings (role assigned by benchmark routing)
└── Gemini CLI -> JSON findings (role assigned by benchmark routing)
```

## Constants

```
PLUGIN_DIR="~/.claude/plugins/ai-review-arena"
SCRIPTS_DIR="${PLUGIN_DIR}/scripts"
CONFIG_DIR="${PLUGIN_DIR}/config"
CACHE_DIR="${PLUGIN_DIR}/cache"
AGENTS_DIR="${PLUGIN_DIR}/agents"
DEFAULT_CONFIG="${CONFIG_DIR}/default-config.json"
SESSION_DIR="/tmp/ai-review-arena/$(date +%Y%m%d-%H%M%S)"
```

## Phase 0: Context & Configuration

Establish project context, load configuration, and prepare the session environment.

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
   - Extract `--phase` value (default: from config `arena.default_phase`, typically "all")
   - Extract `--figma <url>` if present
   - Extract `--skip-cache` flag (default: false)
   - Extract `--force-benchmark` flag (default: false)
   - Extract `--interactive` flag (default: from config `arena.interactive_by_default`)
   - Extract `--intensity` value (default: from config `review.intensity`)
   - Extract `--models` comma-separated values (default: all enabled models)
   - Extract `--focus` comma-separated values (default: from config `review.focus_areas`)
   - Remaining arguments are treated as scope (file paths, directory paths, or --pr N)

4. Check that `arena.enabled` is true in config. If false:
   - Display: "AI Review Arena is disabled in configuration. Enable it with: `/arena-config set arena.enabled true`"
   - Exit early.

5. Create session directory:
   ```bash
   mkdir -p "${SESSION_DIR}/findings" "${SESSION_DIR}/research" "${SESSION_DIR}/compliance" "${SESSION_DIR}/benchmarks" "${SESSION_DIR}/reports"
   echo "session: ${SESSION_DIR}"
   ```

6. Determine which phases to execute based on `--phase`:
   - `all` (default): Run phases 0.1, 0.5, 1-7 in sequence (intensity determines which phases run)
   - `codebase`: Run Phase 0.5 only (codebase analysis)
   - `codebase,review`: Run Phase 0.5 + Phase 5.5 + Phase 6 + Phase 7 (refactoring mode)
   - `stack`: Run Phase 0.5 + Phase 1 only
   - `research`: Run Phase 0.1 + Phase 0.5 + Phase 1 + Phase 2
   - `compliance`: Run Phase 0.1 + Phase 0.5 + Phase 1 + Phase 3
   - `benchmark`: Run Phase 4 only
   - `review`: Run Phase 0.5 + Phase 1 (for context) + Phase 6 + Phase 7

   **Intensity determines Phase scope** (decided by Phase 0.1 debate or `--intensity` flag):
   - `quick`: Phase 0 → 0.1 → 0.5 only (Claude solo, no Agent Team)
   - `standard`: Phase 0 → 0.1 → 0.5 → 1(cached) → 5.5 → 6 → 7
   - `deep`: Phase 0 → 0.1 → 0.5 → 1 → 2(+debate) → 3(+debate) → 5.5 → 6 → 7
   - `comprehensive`: Phase 0 → 0.1 → 0.5 → 1 → 2(+debate) → 3(+debate) → 4 → 5 → 5.5 → 6 → 7

   **Quick Intensity Mode** (`--intensity quick` or decided by Phase 0.1):
   - Run Phase 0 + Phase 0.1 + Phase 0.5 only
   - Skip all other phases (1-6)
   - Claude executes the task solo using codebase analysis results
   - After task completion, perform simplified self-review (no Agent Team)
   - No external model calls, no team spawning

7. If `--interactive` is set, display the execution plan:
   ```
   ## Arena Execution Plan
   - Phases: {list of phases to execute}
   - Intensity: {intensity}
   - Models: {enabled models}
   - Focus: {focus areas}
   - Figma: {url or "not provided"}
   - Cache: {enabled/disabled}

   Proceed? (y/n)
   ```
   Wait for user confirmation before continuing.

8. Validate external CLI availability:
   ```bash
   command -v codex &>/dev/null && echo "codex:available" || echo "codex:unavailable"
   command -v gemini &>/dev/null && echo "gemini:available" || echo "gemini:unavailable"
   command -v jq &>/dev/null && echo "jq:available" || echo "jq:unavailable"
   command -v gh &>/dev/null && echo "gh:available" || echo "gh:unavailable"
   ```

9. Auto-disable unavailable models with a warning message.

10. **MCP Dependency Detection**:

    Detect if the user's request requires MCP servers that may not be installed.

    a. **Figma MCP Detection**:
       - Check if request contains: figma.com URL, "피그마", "디자인", "Figma" keywords
       - If detected:
         ```
         ToolSearch(query: "figma")
         ```
       - If Figma MCP not found in results:
         ```
         Display:
         "⚠️ Figma MCP 서버가 설치되어 있지 않습니다.
          Figma 디자인 분석(Phase 5)을 위해 설치하시겠습니까?

          설치 방법:
          claude mcp add figma -- npx -y figma-developer-mcp --figma-api-key=YOUR_KEY

          [설치하고 계속] [Figma 없이 계속] [취소]"
         ```
         Use AskUserQuestion to get user's choice:
         - **설치**: Execute installation via Bash, verify with ToolSearch, then proceed
         - **건너뛰기**: Set `skip_figma=true`, skip Phase 5
         - **취소**: Abort arena execution

    b. **Playwright MCP Detection**:
       - Check if request contains: "테스트", "E2E", "브라우저", "test", "e2e", "browser"
       - If detected:
         ```
         ToolSearch(query: "playwright")
         ```
       - If not found: Inform user and suggest installation, continue without it

    c. **Notion MCP Detection**:
       - Check if request contains: "노션", "Notion"
       - If detected:
         ```
         ToolSearch(query: "notion")
         ```
       - If not found: Inform user and suggest installation, continue without it

    d. Record MCP availability status for session:
       ```json
       {
         "figma_mcp": "available|installed|unavailable",
         "playwright_mcp": "available|installed|unavailable",
         "notion_mcp": "available|installed|unavailable"
       }
       ```

---

## Phase 0.1: Intensity Decision (Agent Teams Debate)

**MANDATORY for all requests.** Determine the appropriate intensity level through adversarial debate among Claude agents. Skip only if user explicitly specified `--intensity`.

**Purpose**: Prevent both under-engineering (missing critical issues) and over-engineering (wasting resources). No single Claude instance can reliably judge complexity alone.

**Steps:**

1. **Create Decision Team**:
   ```
   Teammate(
     operation: "spawnTeam",
     team_name: "intensity-decision-{YYYYMMDD-HHMMSS}",
     description: "Intensity level determination debate"
   )
   ```

2. **Create Debate Tasks**:
   ```
   TaskCreate(
     subject: "Advocate for higher intensity",
     description: "Argue for the highest reasonable intensity level for this request. Consider: worst-case scenarios, security implications, complexity hidden in seemingly simple tasks, production risk, cross-module impact, concurrency issues, data integrity risks. Provide specific technical reasoning.",
     activeForm: "Advocating for higher intensity"
   )

   TaskCreate(
     subject: "Advocate for lower intensity",
     description: "Argue for the lowest reasonable intensity level for this request. Consider: practical scope, cost efficiency, whether the task is well-understood, whether existing patterns can be reused, time constraints. Provide specific technical reasoning.",
     activeForm: "Advocating for lower intensity"
   )

   TaskCreate(
     subject: "Assess risk and impact",
     description: "Evaluate the production risk, security sensitivity, and failure impact of this request. Consider: is this production code? Could a bug cause data loss? Is this security-critical? What's the blast radius of a mistake? Provide risk assessment with severity rating.",
     activeForm: "Assessing risk and impact"
   )

   TaskCreate(
     subject: "Arbitrate intensity decision",
     description: "Wait for all three advocates to present their arguments. Weigh the technical merits of each position. Decide the final intensity level (quick/standard/deep/comprehensive) with clear justification. Send the decision to the team lead.",
     activeForm: "Arbitrating intensity decision"
   )
   ```

3. **Spawn Debate Agents** (all in parallel):
   ```
   Task(
     subagent_type: "general-purpose",
     team_name: "intensity-decision-{session}",
     name: "intensity-advocate",
     prompt: "You are the Intensity Advocate. Your role is to argue for the HIGHEST reasonable intensity level.

     USER REQUEST: {user_request}
     CONTEXT: {discovered_context_from_step1}
     PROJECT TYPE: {detected_from_codebase}

     Analyze this request and argue why it needs a higher intensity level. Consider:
     - Hidden complexity (e.g., deadlock bugs seem simple but are concurrency issues)
     - Security implications (e.g., any auth/payment touches are high-risk)
     - Production impact (e.g., a bug fix in production needs more scrutiny)
     - Cross-module effects (e.g., changes that ripple through the system)
     - Compliance requirements (e.g., features touching user data)

     Present your argument to intensity-arbitrator via SendMessage.
     Then engage with efficiency-advocate's counter-arguments.
     Continue debating until intensity-arbitrator makes a decision."
   )

   Task(
     subagent_type: "general-purpose",
     team_name: "intensity-decision-{session}",
     name: "efficiency-advocate",
     prompt: "You are the Efficiency Advocate. Your role is to argue for the LOWEST reasonable intensity level.

     USER REQUEST: {user_request}
     CONTEXT: {discovered_context_from_step1}
     PROJECT TYPE: {detected_from_codebase}

     Analyze this request and argue why a lower intensity is sufficient. Consider:
     - Is the scope truly limited? (single file, single function)
     - Are existing patterns reusable? (well-known solutions)
     - Is the risk actually low? (non-critical path, internal tool)
     - Would higher intensity waste resources without proportional benefit?

     Present your argument to intensity-arbitrator via SendMessage.
     Then engage with intensity-advocate's counter-arguments.
     Continue debating until intensity-arbitrator makes a decision."
   )

   Task(
     subagent_type: "general-purpose",
     team_name: "intensity-decision-{session}",
     name: "risk-assessor",
     prompt: "You are the Risk Assessor. Your role is to provide an objective risk evaluation.

     USER REQUEST: {user_request}
     CONTEXT: {discovered_context_from_step1}
     PROJECT TYPE: {detected_from_codebase}

     Evaluate:
     1. Production Risk: Is this production code? What happens if the change has a bug?
     2. Security Risk: Does this touch authentication, authorization, data handling, or network?
     3. Complexity Risk: Is this a concurrency issue, distributed system change, or state management problem?
     4. Data Risk: Could this cause data loss, corruption, or leaks?
     5. Blast Radius: How many users/systems are affected if something goes wrong?

     Rate overall risk as: LOW / MEDIUM / HIGH / CRITICAL
     Send your assessment to intensity-arbitrator via SendMessage."
   )

   Task(
     subagent_type: "general-purpose",
     team_name: "intensity-decision-{session}",
     name: "intensity-arbitrator",
     prompt: "You are the Intensity Arbitrator. Your role is to make the FINAL intensity decision.

     Wait for arguments from:
     1. intensity-advocate (argues for higher intensity)
     2. efficiency-advocate (argues for lower intensity)
     3. risk-assessor (provides risk evaluation)

     After receiving all arguments:
     1. Weigh the technical merits of each position
     2. Consider the risk assessment
     3. Decide: quick, standard, deep, or comprehensive
     4. Provide clear justification for your decision

     Intensity guidelines:
     - quick: Single element, obvious change, no risk
     - standard: Multi-file, moderate complexity, low-medium risk
     - deep: Complex logic, security-sensitive, high risk, compliance needed
     - comprehensive: System-wide, critical security (auth/payment), needs model benchmarking

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
   Teammate(operation: "cleanup")
   ```

7. **Apply Decision**: Set the intensity for all subsequent phases based on the arbitrator's decision.

8. **Display Decision**:
   ```
   ## Intensity Decision (Phase 0.1)
   - Decision: {intensity_level}
   - Risk Level: {risk_level}
   - Key Factors: {key_factors}
   - Justification: {justification}
   ```

**Error Handling:**
- If Agent Teams are unavailable: fall back to Claude solo judgment with explicit reasoning logged.
- If debate times out (>60 seconds): use the last available position from the arbitrator, or default to `standard`.
- If no consensus reached: default to `deep` (err on the side of caution).

---

## Phase 0.2: Cost & Time Estimation

Based on the decided intensity, estimate costs and time before proceeding. This phase runs immediately after intensity decision for ALL intensity levels.

**Purpose**: Give the user visibility into expected resource usage before committing to execution.

### Estimation Formula

Sum the applicable components based on decided intensity:

| Component | Applies At | Token Estimate | Est. Cost |
|-----------|-----------|---------------|-----------|
| Phase 0.5 Codebase Analysis | all | ~8K | ~$0.40 |
| Phase 1 Stack Detection | standard+ | ~3K | ~$0.06 |
| Phase 2 Research | deep+ | ~15K | ~$0.75 |
| Phase 3 Compliance | deep+ | ~12K | ~$0.60 |
| Phase 4 Benchmarking | comprehensive | ~40K | ~$2.00 |
| Phase 5 Figma (if URL provided) | standard+ | ~20K | ~$1.00 |
| Phase 5.5 Strategy Debate | standard+ | ~25K | ~$1.25 |
| Phase 6 Review per Claude agent | standard+ | ~12K | ~$0.60 |
| Phase 6 per Codex CLI call | standard+ | ~8K | ~$0.16 |
| Phase 6 per Gemini CLI call | standard+ | ~8K | ~$0.10 |
| Phase 6 Debate Rounds 2+3 | standard+ | ~60K | ~$3.00 |
| Phase 6.5 Auto-Fix | standard+ | ~10K | ~$0.50 |
| Phase 7 Report | all | ~5K | ~$0.25 |

### Calculation

```
total_tokens = SUM(applicable_components)
total_cost = SUM(component_tokens * config.cost_estimation.token_cost_per_1k)
est_time_minutes = CEIL(total_tokens / 15000)  # ~15K tokens per minute throughput
```

### Display to User

```
## Cost & Time Estimate (Phase 0.2)

Intensity: {intensity}
Phases: {phase_list}
Claude Agents: {N} teammates
External CLIs: Codex ({M} roles), Gemini ({K} roles)

Est. Tokens: ~{total}K
Est. Cost:   ~${cost}
Est. Time:   ~{minutes} min

[Proceed / Adjust intensity / Cancel]
```

### Decision

- IF `--non-interactive` OR cost <= `config.cost_estimation.auto_proceed_under_dollars`: Proceed automatically
- IF user selects "Cancel": Stop pipeline, display summary of what was gathered so far
- IF user selects "Adjust intensity": Prompt for new intensity level, skip back to Phase 0.1 with `--intensity` override
- IF user selects "Proceed": Continue to Phase 0.5

---

## Phase 0.5: Codebase Analysis

Analyze the existing codebase to extract conventions, identify reusable code, and understand project structure. This phase runs for ALL intensity levels including `quick`. Results are passed as context to all subsequent phases and to Claude's own task execution.

**Purpose**: Ensure that all code changes respect existing conventions and reuse existing code rather than creating duplicates.

**Steps:**

1. **Project Structure Scan** (Glob):
   ```
   Glob(pattern: "**/*", path: "${PROJECT_ROOT}")
   ```
   - Map directory structure (top 3 levels)
   - Identify main entry points (index.*, main.*, app.*, server.*)
   - Identify key directories (src/, lib/, utils/, services/, controllers/, models/, components/, hooks/, types/)

2. **Related Code Search** (Grep):
   Extract core keywords from user's request, then search for existing implementations:
   ```
   Grep(pattern: "<keyword1>", path: "${PROJECT_ROOT}", type: "<detected_language>")
   Grep(pattern: "<keyword2>", path: "${PROJECT_ROOT}", type: "<detected_language>")
   ```
   - Search for function/class/type names related to the request
   - Identify existing utility functions, helper modules, service classes
   - Find related test files

3. **Convention Extraction** (Read + Analysis):
   Read 3-5 representative files from the project to extract:
   - **Naming Patterns**: camelCase, snake_case, PascalCase, kebab-case
   - **Directory Structure Rules**: Where controllers, services, utils, types go
   - **Import Style**: Absolute paths (`@/utils`), relative paths (`../../utils`), aliases
   - **Error Handling Pattern**: try/catch style, Result types, error boundaries
   - **Test File Location**: co-located (`__tests__/`), separate (`tests/`), suffix (`.test.`, `.spec.`)
   - **Code Organization**: Function ordering, export patterns, file structure

4. **Reusable Code Inventory**:
   Compile a list of code that can be reused for the current task:
   - Related service/class files with their public methods
   - Utility/helper functions that could be leveraged
   - Type/interface definitions that should be reused
   - Configuration files that affect the task
   - Shared constants, enums, and mappings

5. **Save Analysis to Session Context**:
   Store the analysis results so they are available to all subsequent phases:
   ```
   Conventions discovered:
   - Naming: {pattern}
   - Imports: {style}
   - Error handling: {pattern}
   - File structure: {conventions}

   Reusable code identified:
   - {file}: {description of reusable elements}
   - {file}: {description of reusable elements}
   ...
   ```

6. **Mandatory Instructions for Subsequent Phases**:
   Append to all phase contexts and agent prompts:
   ```
   ⚠️ CODEBASE CONVENTIONS (MUST FOLLOW):
   {extracted conventions}

   ⚠️ REUSABLE CODE (MUST USE INSTEAD OF CREATING NEW):
   {reusable code inventory}

   Rules:
   1. Follow ALL naming conventions exactly as detected
   2. Use the same import style as existing code
   3. Place new files in the correct directory per project conventions
   4. Reuse existing utility functions instead of creating new ones
   5. Follow the same error handling pattern
   6. Match existing code organization and structure
   ```

7. **Quick Mode Execution** (if `--intensity quick`):
   After codebase analysis, execute the user's task directly:
   - Apply discovered conventions
   - Reuse identified code
   - Perform the requested change
   - Run a simplified self-review:
     ```
     Self-Review Checklist:
     ✅ Follows project naming conventions
     ✅ Uses correct import style
     ✅ Reuses existing utilities (no unnecessary new code)
     ✅ Placed in correct directory
     ✅ Error handling matches project pattern
     ✅ No obvious bugs introduced
     ```
   - Display completion summary and exit (skip remaining phases)

**Error Handling:**
- If Glob returns too many files: limit to `src/` or primary source directory
- If no representative files found: warn and proceed with generic conventions
- If keyword search returns no results: broaden search terms, proceed with available context

---

## Phase 1: Stack Detection

Detect the project's technology stack to inform research, compliance, and review phases.

**Steps:**

1. Check cache first (unless `--skip-cache`):
   ```bash
   bash "${SCRIPTS_DIR}/cache-manager.sh" check "${PROJECT_ROOT}" stack detection --ttl 7
   ```

2. If cache is fresh and not `--skip-cache`:
   - Read cached stack profile
   - Parse JSON output to extract technologies

3. If cache is stale or `--skip-cache`:
   a. Run stack detection:
      ```bash
      bash "${SCRIPTS_DIR}/detect-stack.sh" "${PROJECT_ROOT}" --deep --output json
      ```
   b. Parse JSON output to get:
      - `platform`: server, mobile, web, game, etc.
      - `languages`: detected programming languages with versions
      - `frameworks`: detected frameworks with versions
      - `databases`: detected database systems
      - `infrastructure`: Docker, Kubernetes, CI/CD tools
      - `build_tools`: build systems and package managers
   c. Cache the results:
      ```bash
      echo '${STACK_JSON}' | bash "${SCRIPTS_DIR}/cache-manager.sh" write "${PROJECT_ROOT}" stack detection --ttl 7
      ```

4. Display detected stack to user:
   ```
   ## Stack Detection Results
   Platform: {platform} ({primary_language})
   Languages: {languages with versions}
   Frameworks: {frameworks with versions}
   Databases: {databases with versions}
   Infrastructure: {infrastructure tools}
   Build Tools: {build tools}
   CI/CD: {ci/cd platform}
   ```

5. If `--interactive`: ask user to confirm or modify the detected stack.
   ```
   Is this stack detection correct? You can modify by specifying technologies.
   Press Enter to confirm, or type corrections.
   ```

6. Save stack profile to session:
   ```bash
   echo '${STACK_JSON}' > "${SESSION_DIR}/research/stack-profile.json"
   ```

**Error Handling:**
- If detect-stack.sh fails: attempt manual detection by reading package.json, pom.xml, build.gradle, requirements.txt, go.mod, Cargo.toml, etc. using Glob and Read tools.
- If no technologies detected: warn user and proceed with generic review (no technology-specific research).

---

## Phase 2: Pre-Implementation Research

Gather best practices and implementation patterns for each detected technology.

**Steps:**

**Pre-Step: Research Direction Debate** (deep/comprehensive intensity only):

Before executing searches, debate what to research:

1. Create a lightweight decision team:
   ```
   Teammate(
     operation: "spawnTeam",
     team_name: "research-direction-{YYYYMMDD-HHMMSS}",
     description: "Research direction debate"
   )
   ```

2. Spawn 3 researcher agents + arbitrator (all in parallel):
   - **researcher-tech**: Proposes research directions based on detected technology stack (frameworks, languages, versions)
   - **researcher-domain**: Proposes research directions based on the feature domain (security patterns, UX patterns, data patterns)
   - **researcher-risk**: Proposes research directions based on risk areas (what could go wrong, edge cases, failure modes)
   - **research-arbitrator**: Weighs all proposals, prioritizes the research agenda, decides top 3-5 research topics

3. Each researcher sends proposals to research-arbitrator via SendMessage. Researchers can challenge each other's priorities.

4. research-arbitrator sends final research agenda to team lead:
   ```
   RESEARCH_AGENDA:
   1. {topic} - Priority: HIGH - Reason: {why}
   2. {topic} - Priority: HIGH - Reason: {why}
   3. {topic} - Priority: MEDIUM - Reason: {why}
   ...
   ```

5. Shutdown research direction team and proceed with the prioritized research agenda.

6. Display research direction decision:
   ```
   ## Research Direction (Debate Result)
   {research_agenda}
   ```

---

Now execute the main research steps using the debate-determined agenda:

1. For each detected technology in the stack profile:
   a. Run the search-best-practices script:
      ```bash
      bash "${SCRIPTS_DIR}/search-best-practices.sh" "<technology>" --config "${CONFIG_DIR}/tech-queries.json"
      ```
   b. Parse the output:
      - If `cached=true`: read the cached content from the output path
      - If `cached=false`: the script returns `search_queries` array

   c. For non-cached technologies, execute WebSearch with each query:
      - Use the queries from search-best-practices.sh output
      - Substitute `{year}` with the current year
      - Substitute `{version}` with the detected version
      ```
      WebSearch(query: "Spring Boot 3.2 best practices production 2026")
      ```

   d. Compile search results into structured research content

   e. Cache the results:
      ```bash
      echo '${RESEARCH_CONTENT}' | bash "${SCRIPTS_DIR}/cache-manager.sh" write "${PROJECT_ROOT}" research "<technology>-best-practices" --ttl 3
      ```

2. If a feature description is provided (from arguments or extractable from git diff):
   a. Extract feature keywords from the description
   b. Search for feature-specific patterns and implementation guides:
      ```
      WebSearch(query: "<feature> implementation best practices <primary_framework> 2026")
      ```
   c. Include results in the research brief

3. Save compiled research to session:
   ```bash
   echo '${RESEARCH_BRIEF}' > "${SESSION_DIR}/research/research-brief.md"
   ```

4. Display research summary to user:
   ```
   ## Pre-Implementation Research Summary

   ### {Technology 1}
   - Key best practices: {bullet points}
   - Common pitfalls: {bullet points}
   - Recommended patterns: {bullet points}

   ### {Technology 2}
   ...

   ### Feature-Specific Research
   - {feature-specific findings}
   ```

5. If `--interactive`: ask user to proceed or modify focus areas.
   ```
   Research complete. Proceed to compliance check? (y/n)
   ```

**Error Handling:**
- If search-best-practices.sh fails for a technology: use WebSearch directly with generic queries.
- If WebSearch returns no results: note the gap and continue with other technologies.
- If all research fails: warn user and proceed to next phase with no research context.

---

## Phase 3: Compliance Detection

Identify applicable compliance guidelines based on feature keywords and detected platform.

**Steps:**

**Pre-Step: Compliance Scope Debate** (deep/comprehensive intensity only):

Before matching compliance rules, debate which rules actually apply:

1. Create a lightweight decision team:
   ```
   Teammate(
     operation: "spawnTeam",
     team_name: "compliance-scope-{YYYYMMDD-HHMMSS}",
     description: "Compliance scope debate"
   )
   ```

2. Spawn debate agents (all in parallel):
   - **compliance-advocate**: Argues for broader compliance scope. Considers regulations that might not be obvious (e.g., COPPA for games, GDPR for user data, accessibility laws). Errs on the side of inclusion.
   - **scope-challenger**: Argues against over-application. Considers the actual deployment context (internal vs. public, region, user base). Challenges unnecessary compliance burden.
   - **compliance-arbitrator**: Weighs both positions, decides which compliance rules actually apply. Considers legal risk vs. practical burden.

3. Agents debate via SendMessage until compliance-arbitrator reaches a decision.

4. compliance-arbitrator sends final scope to team lead:
   ```
   COMPLIANCE_SCOPE:
   APPLICABLE:
   - {rule}: {reason}
   - {rule}: {reason}
   NOT_APPLICABLE:
   - {rule}: {reason for exclusion}
   ```

5. Shutdown compliance scope team and proceed with the scoped compliance check.

6. Display compliance scope decision:
   ```
   ## Compliance Scope (Debate Result)
   Applicable: {list}
   Excluded: {list with reasons}
   ```

---

Now execute the main compliance steps using the debate-determined scope:

1. Extract feature keywords from multiple sources:
   a. User's description/arguments (from `$ARGUMENTS`)
   b. Changed file names (if git diff is available):
      ```bash
      git diff --staged --name-only 2>/dev/null || git diff HEAD --name-only 2>/dev/null || echo ""
      ```
   c. Code content keywords from changed files (scan for patterns like "auth", "payment", "camera", etc.)

2. Run compliance guideline search:
   ```bash
   bash "${SCRIPTS_DIR}/search-guidelines.sh" "<keywords>" "<detected-platform>" --config "${CONFIG_DIR}/compliance-rules.json"
   ```

3. Parse the output: for each matched guideline:
   a. If `cached=true`: include the cached content directly
   b. If `cached=false`: execute WebSearch with the search query:
      ```
      WebSearch(query: "{search_query with {year} substituted}")
      ```
   c. Cache the guideline content:
      ```bash
      echo '${GUIDELINE_CONTENT}' | bash "${SCRIPTS_DIR}/cache-manager.sh" write "${PROJECT_ROOT}" compliance "<guideline-name>" --ttl 7
      ```

4. Compile compliance requirements:
   - Match each guideline's `requirements` array against the code
   - Flag requirements that appear to be missing or partially implemented
   - Assign risk levels: CRITICAL (required by platform/regulation), HIGH (security/data), MEDIUM (best practice), LOW (recommendation)

5. Save compliance requirements to session:
   ```bash
   echo '${COMPLIANCE_REQUIREMENTS}' > "${SESSION_DIR}/compliance/requirements.md"
   ```

6. Display compliance requirements to user:
   ```
   ## Compliance Requirements Detected

   ### {Feature Pattern}: {Pattern Name}
   | Guideline | Platform | Risk | Status |
   |-----------|----------|------|--------|
   | {guideline_name} | {platform} | {risk_level} | {detected/missing/partial} |

   ### Detailed Requirements
   #### {Guideline Name}
   - {requirement 1}: {status}
   - {requirement 2}: {status}
   ...
   ```

7. If `--interactive`: ask user to proceed.
   ```
   {N} compliance guidelines detected. Proceed to benchmarking? (y/n)
   ```

**Error Handling:**
- If search-guidelines.sh fails: fall back to manual keyword matching against compliance-rules.json using Read tool.
- If WebSearch fails for a guideline: note as "unverified" and include the requirement name only.
- If no compliance patterns match: report "No specific compliance requirements detected" and proceed.

---

## Phase 4: Model Benchmarking

Benchmark available AI models to determine optimal role assignments. Skip if benchmark scores are cached and fresh.

**Steps:**

1. Check cache for existing benchmark scores:
   ```bash
   bash "${SCRIPTS_DIR}/cache-manager.sh" check "${PROJECT_ROOT}" benchmarks model-scores --ttl 14
   ```

2. If cached and fresh AND not `--force-benchmark`:
   - Load cached benchmark scores
   - Skip to step 5 (display and routing)

3. If stale or `--force-benchmark`:
   a. Determine which models to benchmark (from `--models` flag or config):
      ```bash
      # Check which external CLIs are available
      AVAILABLE_MODELS="claude"
      command -v codex &>/dev/null && AVAILABLE_MODELS="${AVAILABLE_MODELS},codex"
      command -v gemini &>/dev/null && AVAILABLE_MODELS="${AVAILABLE_MODELS},gemini"
      ```

   b. Run benchmark script for external models (Codex, Gemini):
      ```bash
      bash "${SCRIPTS_DIR}/benchmark-models.sh" --category all --models "${AVAILABLE_MODELS}" --config "${DEFAULT_CONFIG}"
      ```

   c. For Claude benchmarking (cannot self-invoke via CLI):
      - Read each benchmark test case from `${CONFIG_DIR}/benchmarks/`:
        ```bash
        ls "${CONFIG_DIR}/benchmarks/"*.json
        ```
      - For each test case, use the Task tool to spawn a subagent:
        ```
        Task(
          prompt: "Review the following code and report ALL issues you find.
          Return your findings as JSON array with objects: {severity, title, description, line, confidence}.

          CODE:
          {test_case_code}

          Report ONLY the issues. No preamble."
        )
        ```
      - Parse the subagent's findings against the ground truth in the test case
      - Score: (correct_findings / total_ground_truth) * 100, penalize false positives

   d. Cache the benchmark scores:
      ```bash
      echo '${BENCHMARK_SCORES_JSON}' | bash "${SCRIPTS_DIR}/cache-manager.sh" write "${PROJECT_ROOT}" benchmarks model-scores --ttl 14
      ```

4. Parse benchmark results into a score matrix:
   ```json
   {
     "claude": {"security": 92, "bugs": 88, "architecture": 95, "performance": 85, "testing": 87},
     "codex": {"security": 85, "bugs": 90, "architecture": 80, "performance": 88, "testing": 82},
     "gemini": {"security": 80, "bugs": 82, "architecture": 90, "performance": 83, "testing": 85}
   }
   ```

5. Display benchmark scores:
   ```
   ## Model Benchmark Scores
   | Category     | Claude | Codex  | Gemini |
   |-------------|--------|--------|--------|
   | Security    | {score} | {score} | {score} |
   | Bugs        | {score} | {score} | {score} |
   | Architecture| {score} | {score} | {score} |
   | Performance | {score} | {score} | {score} |
   | Testing     | {score} | {score} | {score} |

   Minimum score for role assignment: {min_score_for_role} (from config)
   ```

6. Generate routing decisions based on scores:
   - For each focus area, assign primary model (highest score) and secondary model (second highest)
   - Only assign models that meet `benchmarks.min_score_for_role` threshold
   - If a model scores below threshold for all areas, exclude from review

7. Display routing decisions:
   ```
   ## Model Routing (Benchmark-Based)
   | Focus Area   | Primary         | Secondary       |
   |-------------|-----------------|-----------------|
   | Security    | {model} ({score}) | {model} ({score}) |
   | Bugs        | {model} ({score}) | {model} ({score}) |
   | Architecture| {model} ({score}) | {model} ({score}) |
   | Performance | {model} ({score}) | {model} ({score}) |
   | Testing     | {model} ({score}) | {model} ({score}) |
   ```

8. Save routing decisions to session:
   ```bash
   echo '${ROUTING_JSON}' > "${SESSION_DIR}/benchmarks/routing-decisions.json"
   ```

**Error Handling:**
- If benchmark-models.sh fails: use default role assignments from config (Level 1 fallback).
- If Claude subagent benchmarking fails: use estimated scores based on historical averages.
- If no external models available: Claude-only routing with all roles assigned to Claude teammates.

---

## Phase 5: Figma Analysis (Optional)

Only execute this phase if `--figma <url>` was provided.

**Steps:**

1. Load Figma MCP tools using ToolSearch:
   ```
   ToolSearch(query: "select:mcp__claude_ai_Figma__get_screenshot")
   ToolSearch(query: "select:mcp__claude_ai_Figma__get_metadata")
   ToolSearch(query: "select:mcp__claude_ai_Figma__get_design_context")
   ToolSearch(query: "select:mcp__claude_ai_Figma__get_variable_defs")
   ```

2. Fetch design metadata:
   ```
   mcp__claude_ai_Figma__get_metadata(url: "{figma_url}")
   ```

3. Fetch screenshot of the design:
   ```
   mcp__claude_ai_Figma__get_screenshot(url: "{figma_url}")
   ```

4. Get design context (components, tokens, layout):
   ```
   mcp__claude_ai_Figma__get_design_context(url: "{figma_url}")
   ```

5. Get variable definitions (design tokens):
   ```
   mcp__claude_ai_Figma__get_variable_defs(url: "{figma_url}")
   ```

6. Analyze the design:
   - Components used and their hierarchy
   - Design tokens: colors, typography, spacing
   - Layout structure: grids, auto-layout, constraints
   - Interaction states: hover, pressed, disabled, focus
   - Responsive behavior indicators
   - Accessibility considerations: contrast ratios, text sizing

7. If multiple models are enabled and benchmarking shows design comprehension scores:
   - Compare model capabilities for design analysis accuracy
   - Select best model for UI implementation guidance
   - Note design-specific routing in session

8. Save analysis to session:
   ```bash
   echo '${FIGMA_ANALYSIS}' > "${SESSION_DIR}/research/figma-analysis.md"
   ```

9. Display design analysis summary:
   ```
   ## Figma Design Analysis
   - Components: {count} ({list of component names})
   - Design Tokens: {count} colors, {count} typography, {count} spacing
   - Layout: {layout description}
   - Interactions: {interaction states detected}
   - Accessibility Notes: {contrast issues, text sizing}
   ```

**Error Handling:**
- If Figma MCP tools fail to load: skip Figma analysis, warn user.
- If URL is invalid or inaccessible: report error and continue to review phase.
- If partial data retrieved: use what is available and note gaps.

---

## Phase 5.5: Implementation Strategy (Agent Teams Debate)

**Applies to**: standard, deep, comprehensive intensity. Skip for quick.

**Purpose**: Before implementing code, debate the best approach. Prevents costly rework by catching architectural issues, security concerns, and over-engineering before code is written.

**Steps:**

1. **Create Strategy Team**:
   ```
   Teammate(
     operation: "spawnTeam",
     team_name: "strategy-decision-{YYYYMMDD-HHMMSS}",
     description: "Implementation strategy debate"
   )
   ```

2. **Prepare Context**: Compile all information gathered so far:
   - User's original request
   - Codebase analysis results (Phase 0.5: conventions, reusable code)
   - Stack profile (Phase 1)
   - Research findings (Phase 2, if executed)
   - Compliance requirements (Phase 3, if executed)
   - Figma analysis (Phase 5, if executed)

3. **Spawn Strategy Agents** (all in parallel):
   ```
   Task(
     subagent_type: "general-purpose",
     team_name: "strategy-decision-{session}",
     name: "architecture-advocate",
     prompt: "You are the Architecture Advocate. Propose the best implementation approach.

     REQUEST: {user_request}
     CODEBASE CONVENTIONS: {phase_0.5_results}
     STACK: {phase_1_results}
     RESEARCH: {phase_2_results_if_available}
     COMPLIANCE: {phase_3_results_if_available}
     REUSABLE CODE: {identified_reusable_code}

     Propose:
     1. Overall architecture/design approach
     2. Which existing code to reuse vs. create new
     3. File structure and organization
     4. Key design patterns to apply
     5. Integration points with existing code

     Send your proposal to strategy-arbitrator via SendMessage.
     Engage with challenges from other agents."
   )

   Task(
     subagent_type: "general-purpose",
     team_name: "strategy-decision-{session}",
     name: "security-challenger",
     prompt: "You are the Security Challenger. Challenge the proposed implementation for security issues.

     REQUEST: {user_request}
     COMPLIANCE: {phase_3_results_if_available}

     Wait for architecture-advocate's proposal, then:
     1. Identify security vulnerabilities in the proposed approach
     2. Challenge unsafe patterns or missing security measures
     3. Suggest security-hardened alternatives
     4. Flag compliance gaps in the proposed design

     Send challenges to strategy-arbitrator via SendMessage.
     Engage in debate with architecture-advocate."
   )

   Task(
     subagent_type: "general-purpose",
     team_name: "strategy-decision-{session}",
     name: "pragmatic-challenger",
     prompt: "You are the Pragmatic Challenger. Challenge the proposed implementation for over-engineering and feasibility.

     REQUEST: {user_request}
     CODEBASE CONVENTIONS: {phase_0.5_results}
     REUSABLE CODE: {identified_reusable_code}

     Wait for architecture-advocate's proposal, then:
     1. Challenge unnecessary complexity
     2. Identify simpler alternatives that achieve the same goal
     3. Check if existing code/patterns are being ignored in favor of new code
     4. Flag YAGNI violations (building for hypothetical future needs)
     5. Consider maintenance burden of the proposed approach

     Send challenges to strategy-arbitrator via SendMessage.
     Engage in debate with architecture-advocate."
   )

   Task(
     subagent_type: "general-purpose",
     team_name: "strategy-decision-{session}",
     name: "strategy-arbitrator",
     prompt: "You are the Strategy Arbitrator. Synthesize the best implementation approach.

     Wait for:
     1. architecture-advocate's proposal
     2. security-challenger's challenges
     3. pragmatic-challenger's challenges

     Then:
     1. Weigh each position on its technical merits
     2. Resolve conflicts between security and pragmatism
     3. Ensure the final strategy follows existing codebase conventions
     4. Produce a concrete implementation plan

     Send your decision to the team lead via SendMessage:
     IMPLEMENTATION_STRATEGY:
     - Approach: {chosen approach with justification}
     - Architecture: {design decisions}
     - Security Measures: {required security patterns}
     - Files to Create: {list}
     - Files to Modify: {list}
     - Code to Reuse: {list}
     - Rejected Alternatives: {what was considered but not chosen, and why}
     - Success Criteria:
       1. {criterion_1} → verify: {how to check}
       2. {criterion_2} → verify: {how to check}
       3. {criterion_3} → verify: {how to check}

     IMPORTANT: Success Criteria must be concrete and verifiable.
     Good: 'API returns 200 for valid input → verify: curl test with sample payload'
     Bad: 'Code is clean and well-structured' (not verifiable)"
   )
   ```

4. **Assign Tasks and Wait for Decision**.

5. **Shutdown Strategy Team**:
   ```
   SendMessage(type: "shutdown_request", recipient: "architecture-advocate", content: "Strategy decided.")
   SendMessage(type: "shutdown_request", recipient: "security-challenger", content: "Strategy decided.")
   SendMessage(type: "shutdown_request", recipient: "pragmatic-challenger", content: "Strategy decided.")
   SendMessage(type: "shutdown_request", recipient: "strategy-arbitrator", content: "Strategy decided.")
   Teammate(operation: "cleanup")
   ```

6. **Apply Strategy**: Use the arbitrator's decision as the implementation plan. Pass it as context to Phase 6 reviewers so they can verify the implementation follows the agreed strategy. **Pass Success Criteria to Phase 7 for post-implementation verification.**

7. **Implement**: Execute the implementation following the decided strategy. Apply codebase conventions from Phase 0.5. Use reusable code identified earlier. **Only modify files listed in the strategy. If additional files need changes, document the deviation.**

8. **Display Strategy Decision**:
   ```
   ## Implementation Strategy (Phase 5.5 Debate Result)
   - Approach: {approach}
   - Architecture: {decisions}
   - Security: {measures}
   - Files: {create/modify list}
   - Success Criteria:
     1. {criterion_1} → verify: {check}
     2. {criterion_2} → verify: {check}
     3. {criterion_3} → verify: {check}
   ```

**Error Handling:**
- If Agent Teams are unavailable: fall back to Claude solo strategy with explicit reasoning.
- If debate times out: use architecture-advocate's initial proposal with security-challenger's concerns noted.
- If no consensus: err on the side of security (security-challenger's position takes precedence on security matters).

---

## Phase 6: Agent Team Review

This phase follows the same pattern as multi-review.md but with ENRICHED context from Phases 1-5. Reviewer teammates receive stack detection results, relevant best practices, compliance requirements, and scale considerations in addition to the code.

### Step 6.1: Scope Resolution

Resolve code scope exactly as in multi-review.md Phase 1:

1. Parse scope arguments:
   - No scope arguments: use `git diff --staged` (if staged changes exist) or `git diff HEAD`
   - `--pr <number>`: use `gh pr diff <number>`
   - Specific file/directory paths: review those directly

2. Resolve the diff/files:
   ```bash
   # For PR mode:
   gh pr diff $PR_NUMBER > "${SESSION_DIR}/diff.patch"

   # For git diff mode (default):
   git diff --staged > "${SESSION_DIR}/diff.patch"
   if [ ! -s "${SESSION_DIR}/diff.patch" ]; then
     git diff HEAD > "${SESSION_DIR}/diff.patch"
   fi
   if [ ! -s "${SESSION_DIR}/diff.patch" ]; then
     git diff > "${SESSION_DIR}/diff.patch"
   fi
   ```

3. List all changed files with line counts:
   ```bash
   grep '^diff --git' "${SESSION_DIR}/diff.patch" | sed 's|diff --git a/\(.*\) b/.*|\1|'
   ```

4. Filter files based on config (`review.file_extensions`, `review.exclude_patterns`, `max_file_lines`).

5. If no reviewable files found, report and exit early.

### Step 6.2: Cost Estimation

Estimate cost accounting for enriched context (larger prompts due to research/compliance data):

1. Calculate estimated token usage:
   - Code lines * 4 (tokens per line)
   - Research context: ~2000 tokens per technology
   - Compliance context: ~1000 tokens per guideline
   - Scale advisor context: ~1500 tokens
   - Per-teammate overhead: ~1000 tokens
   - Debate overhead: findings_count * 300 * debate_rounds

2. Display cost estimate:
   ```
   ## Cost Estimate
   - Files: {N} files, {M} total lines
   - Enriched context: +{X}K tokens (research, compliance, stack)
   - Agent Team: {N} Claude teammates + debate-arbitrator
   - External CLI calls: Codex: {B}, Gemini: {C}
   - Estimated cost: ~${X.XX} (enriched context increases per-teammate cost)
   ```

3. If `--interactive`: ask for confirmation before proceeding.

### Step 6.3: Create Agent Team

Create a new Agent Team for this review session:

```
Teammate(
  operation: "spawnTeam",
  team_name: "arena-review-{YYYYMMDD-HHMMSS}",
  description: "AI Review Arena - Full lifecycle review session"
)
```

### Step 6.4: Create Review Tasks

Create tasks in the shared task list for each active role. Include new Arena-specific roles:

```
TaskCreate(
  subject: "Security review of {scope_description}",
  description: "Review the code changes for security vulnerabilities with enriched stack/compliance context. Follow the security-reviewer agent instructions. Send findings to team lead via SendMessage when complete.",
  activeForm: "Reviewing security vulnerabilities"
)

TaskCreate(
  subject: "Bug detection for {scope_description}",
  description: "Review the code changes for bugs and logic errors with enriched stack context. Follow the bug-detector agent instructions. Send findings to team lead via SendMessage when complete.",
  activeForm: "Detecting bugs and logic errors"
)

TaskCreate(
  subject: "Architecture review of {scope_description}",
  description: "Review architectural patterns with enriched stack/research context. Follow the architecture-reviewer agent instructions. Send findings to team lead via SendMessage when complete.",
  activeForm: "Reviewing architecture patterns"
)

TaskCreate(
  subject: "Performance review of {scope_description}",
  description: "Review performance with enriched stack/research context. Follow the performance-reviewer agent instructions. Send findings to team lead via SendMessage when complete.",
  activeForm: "Reviewing performance characteristics"
)

TaskCreate(
  subject: "Test coverage review of {scope_description}",
  description: "Review test coverage with enriched context. Follow the test-coverage-reviewer agent instructions. Send findings to team lead via SendMessage when complete.",
  activeForm: "Reviewing test coverage"
)

TaskCreate(
  subject: "Scale readiness assessment of {scope_description}",
  description: "Assess scale readiness: concurrency handling, data volume patterns, observability, resource management. Send findings to team lead via SendMessage when complete.",
  activeForm: "Assessing scale readiness"
)

TaskCreate(
  subject: "Scope verification of {scope_description}",
  description: "Verify changes are surgical: only requested modifications were made, no drive-by refactors, no unrelated improvements. Compare implementation against Phase 5.5 strategy. Send findings to team lead via SendMessage when complete.",
  activeForm: "Verifying change scope"
)
```

If compliance requirements were detected in Phase 3:
```
TaskCreate(
  subject: "Compliance check of {scope_description}",
  description: "Verify code compliance against detected guidelines. Check each requirement from the compliance report. Send findings to team lead via SendMessage when complete.",
  activeForm: "Checking compliance requirements"
)
```

If intensity is `deep` or `comprehensive`:
```
TaskCreate(
  subject: "Research coordination for {scope_description}",
  description: "Cross-reference code against best practice research. Identify gaps between current implementation and recommended patterns. Send findings to team lead via SendMessage when complete.",
  activeForm: "Coordinating research-based review"
)
```

### Step 6.5: Spawn Claude Reviewer Teammates

For each active role, read the agent definition file and spawn a teammate. **Spawn ALL teammates in parallel** by making multiple Task tool calls in a single message.

For each standard role (security-reviewer, bug-detector, architecture-reviewer, performance-reviewer, test-coverage-reviewer, scope-reviewer):

1. Read the agent definition:
   ```
   Read(file_path: "${AGENTS_DIR}/{role}.md")
   ```

2. Spawn as teammate with ENRICHED context:
   ```
   Task(
     subagent_type: "general-purpose",
     team_name: "arena-review-{session_id}",
     name: "{role}",
     prompt: "{contents of agents/{role}.md}

   --- REVIEW TASK ---
   Task ID: {task_id}
   Scope: {scope_description}

   === ENRICHED CONTEXT (from Arena Lifecycle) ===

   STACK PROFILE:
   {stack_detection_json}

   RELEVANT BEST PRACTICES:
   {filtered_research_brief_for_this_role}

   COMPLIANCE REQUIREMENTS:
   {filtered_compliance_requirements_for_this_role}

   BENCHMARK ROUTING:
   This role was assigned to you because: {routing_reason}
   === END ENRICHED CONTEXT ===

   CODE TO REVIEW:
   {diff_content_or_file_contents}
   --- END CODE ---

   INSTRUCTIONS:
   1. Review the code above following your agent instructions
   2. USE the enriched context to inform your review - check against best practices and compliance requirements
   3. Send your findings JSON to the team lead using SendMessage
   4. Mark your task as completed using TaskUpdate
   5. Stay active for 3-round cross-examination:
      Round 2: You cross-examine Codex/Gemini findings (agree/disagree/partial)
      Round 3: You defend YOUR findings against Codex/Gemini challenges (defend/concede/modify)"
   )
   ```

**Spawn scale-advisor** (always included):
```
Task(
  subagent_type: "general-purpose",
  team_name: "arena-review-{session_id}",
  name: "scale-advisor",
  prompt: "You are a Scale Readiness Advisor. Analyze code for scalability concerns.

  Focus areas:
  - Concurrency: race conditions, thread safety, lock contention, deadlock potential
  - Data Volume: N+1 queries, unbounded collections, pagination, batch processing
  - Resource Management: connection pools, memory leaks, file handle leaks, cache sizing
  - Observability: logging sufficiency, metrics exposure, tracing support, health checks
  - Horizontal Scaling: stateless design, session affinity, distributed state

  --- REVIEW TASK ---
  Task ID: {task_id}
  Scope: {scope_description}

  STACK PROFILE:
  {stack_detection_json}

  CODE TO REVIEW:
  {diff_content_or_file_contents}
  --- END CODE ---

  INSTRUCTIONS:
  1. Analyze the code for scale readiness issues
  2. Categorize findings by: Concurrency, Data Volume, Resource Management, Observability, Horizontal Scaling
  3. Send findings as JSON to team lead using SendMessage with format:
     {\"findings\": [{\"category\": \"...\", \"severity\": \"...\", \"title\": \"...\", \"description\": \"...\", \"file\": \"...\", \"line\": N, \"confidence\": N, \"suggestion\": \"...\"}]}
  4. Mark your task as completed using TaskUpdate
  5. Stay active for debate phase"
)
```

**Spawn scope-reviewer** (always included):
```
Task(
  subagent_type: "general-purpose",
  team_name: "arena-review-{session_id}",
  name: "scope-reviewer",
  prompt: "You are a Scope Reviewer (Surgical Changes Checker). Your job is to ensure the implementation ONLY changes what was requested — nothing more.

  Principle: 'Surgical Changes' — Every change must be intentional and requested. Drive-by refactors, cosmetic fixes, and unrelated improvements are violations.

  --- REVIEW TASK ---
  Task ID: {task_id}
  Scope: {scope_description}

  IMPLEMENTATION STRATEGY (from Phase 5.5):
  {strategy_decision — including Files to Create, Files to Modify, and Success Criteria}

  CODE TO REVIEW:
  {diff_content_or_file_contents}
  --- END CODE ---

  INSTRUCTIONS:
  1. Compare EVERY changed file against the Phase 5.5 strategy:
     - Was this file listed in 'Files to Create' or 'Files to Modify'? If not → SCOPE_VIOLATION
     - Does each change directly serve the stated Approach? If not → UNNECESSARY_CHANGE
  2. For each modified file, check for:
     - Drive-by refactors: renaming variables, reformatting code, changing patterns not related to the task
     - Cosmetic changes: adding/removing whitespace, reordering imports, style-only edits
     - Unrelated improvements: adding error handling, type annotations, docstrings for unchanged code
     - Gold-plating: adding features, config options, or abstractions beyond what was requested
  3. Send findings as JSON to team lead using SendMessage with format:
     {\"scope_findings\": [{\"type\": \"SCOPE_VIOLATION|UNNECESSARY_CHANGE|DRIVE_BY_REFACTOR|GOLD_PLATING\", \"severity\": \"high|medium|low\", \"file\": \"...\", \"line\": N, \"description\": \"...\", \"justification\": \"Why this change was not in scope\"}]}
  4. If all changes are in scope, send: {\"scope_findings\": [], \"verdict\": \"CLEAN — all changes are surgical and in scope\"}
  5. Mark your task as completed using TaskUpdate
  6. Stay active for debate phase"
)
```

**Spawn compliance-checker** (if compliance requirements detected):
```
Task(
  subagent_type: "general-purpose",
  team_name: "arena-review-{session_id}",
  name: "compliance-checker",
  prompt: "You are a Compliance Checker. Verify code against platform and regulatory guidelines.

  --- REVIEW TASK ---
  Task ID: {task_id}
  Scope: {scope_description}

  COMPLIANCE REQUIREMENTS:
  {full_compliance_requirements_from_phase_3}

  STACK PROFILE:
  {stack_detection_json}

  CODE TO REVIEW:
  {diff_content_or_file_contents}
  --- END CODE ---

  INSTRUCTIONS:
  1. For EACH compliance requirement, check if the code satisfies it
  2. Mark each as: COMPLIANT, NON_COMPLIANT, PARTIAL, or NOT_APPLICABLE
  3. For NON_COMPLIANT items, provide specific code references and remediation steps
  4. Send findings as JSON to team lead using SendMessage with format:
     {\"compliance_results\": [{\"guideline\": \"...\", \"requirement\": \"...\", \"status\": \"...\", \"risk\": \"...\", \"evidence\": \"...\", \"remediation\": \"...\"}]}
  5. Mark your task as completed using TaskUpdate
  6. Stay active for debate phase"
)
```

**Spawn research-coordinator** (deep/comprehensive intensity only):
```
Task(
  subagent_type: "general-purpose",
  team_name: "arena-review-{session_id}",
  name: "research-coordinator",
  prompt: "You are a Research Coordinator. Cross-reference code against best practice research.

  --- REVIEW TASK ---
  Task ID: {task_id}
  Scope: {scope_description}

  RESEARCH BRIEF:
  {full_research_brief_from_phase_2}

  STACK PROFILE:
  {stack_detection_json}

  CODE TO REVIEW:
  {diff_content_or_file_contents}
  --- END CODE ---

  INSTRUCTIONS:
  1. Compare the code against each best practice in the research brief
  2. Identify gaps: practices recommended but not implemented
  3. Identify anti-patterns: code that contradicts best practices
  4. Send findings as JSON to team lead using SendMessage with format:
     {\"research_findings\": [{\"practice\": \"...\", \"status\": \"implemented|missing|anti-pattern\", \"severity\": \"...\", \"description\": \"...\", \"file\": \"...\", \"line\": N, \"recommendation\": \"...\"}]}
  5. Mark your task as completed using TaskUpdate
  6. Stay active for debate phase"
)
```

**CRITICAL: Launch ALL Claude reviewer teammates simultaneously.** Use multiple Task tool calls in a single message to maximize parallelism. Do NOT wait for one teammate to finish before spawning the next.

### Step 6.6: Assign Tasks to Teammates

After spawning, assign each task to its corresponding teammate:

```
TaskUpdate(taskId: "{security_task_id}", owner: "security-reviewer")
TaskUpdate(taskId: "{bug_task_id}", owner: "bug-detector")
TaskUpdate(taskId: "{arch_task_id}", owner: "architecture-reviewer")
TaskUpdate(taskId: "{perf_task_id}", owner: "performance-reviewer")
TaskUpdate(taskId: "{test_task_id}", owner: "test-coverage-reviewer")
TaskUpdate(taskId: "{scale_task_id}", owner: "scale-advisor")
TaskUpdate(taskId: "{scope_task_id}", owner: "scope-reviewer")
# If compliance-checker was spawned:
TaskUpdate(taskId: "{compliance_task_id}", owner: "compliance-checker")
# If research-coordinator was spawned:
TaskUpdate(taskId: "{research_task_id}", owner: "research-coordinator")
```

### Step 6.7: Launch External CLI Reviews (Parallel)

While Claude teammates work, run Codex and Gemini CLI reviews in parallel via Bash. Use benchmark routing to assign roles:

```bash
# Determine external model role assignments from benchmark routing
# Only assign roles where the external model is primary or secondary

for role in $CODEX_ROLES; do
  for file in $FILES; do
    cat "$file" | "${SCRIPTS_DIR}/codex-review.sh" "$file" "$CONFIG" "$role" \
      > "${SESSION_DIR}/findings/codex-${role}-$(basename $file).json" 2>/dev/null &
  done
done

for role in $GEMINI_ROLES; do
  for file in $FILES; do
    cat "$file" | "${SCRIPTS_DIR}/gemini-review.sh" "$file" "$CONFIG" "$role" \
      > "${SESSION_DIR}/findings/gemini-${role}-$(basename $file).json" 2>/dev/null &
  done
done

# Wait for all background jobs
wait
```

### Step 6.8: Collect All Results

Wait for all results from both sources:

1. **Claude teammates**: They will send findings via SendMessage automatically. Messages are delivered to you (the team lead) as they complete. Wait for all active reviewer teammates to report.

2. **External CLI results**: Read JSON output files from `${SESSION_DIR}/findings/`:
   ```bash
   ls "${SESSION_DIR}/findings/"*.json 2>/dev/null
   ```

3. Parse and validate all findings. Skip invalid JSON with a warning.

### Step 6.9: Findings Aggregation

Merge and deduplicate findings from all sources (same as multi-review.md Phase 5):

1. Combine all findings: teammate findings (via SendMessage) + external CLI findings (from JSON files)

2. Deduplicate:
   - Group by file + line number (within +/- 3 lines tolerance)
   - Cross-validated findings: average confidence + 10% boost
   - Keep most detailed description, note which models agreed

3. Filter by confidence threshold: `review.confidence_threshold`

4. Sort: severity (critical > high > medium > low) > confidence > file > line

5. Display intermediate results:
   ```
   ## Findings Summary (Pre-Debate)
   - Total findings: {N}
   - By severity: {X} critical, {Y} high, {Z} medium, {W} low
   - By model: Claude: {A}, Codex: {B}, Gemini: {C}
   - Cross-validated: {M} findings confirmed by 2+ models
   - Scale issues: {S} (from scale-advisor)
   - Compliance issues: {C} (from compliance-checker)
   - Best practice gaps: {G} (from research-coordinator)
   ```

6. **Save findings partitioned by model** for cross-examination:
   ```bash
   # Partition Round 1 findings by model source
   jq '[.[] | select(.model == "claude")]' aggregated.json > "${SESSION_DIR}/findings/round1-claude.json"
   jq '[.[] | select(.model == "codex")]' aggregated.json > "${SESSION_DIR}/findings/round1-codex.json"
   jq '[.[] | select(.model == "gemini")]' aggregated.json > "${SESSION_DIR}/findings/round1-gemini.json"
   ```

7. If `--interactive`: ask to proceed to cross-examination.

### Step 6.10: 3-Round Cross-Examination

Skip if `--no-debate` is set or `debate.enabled` is false.

All 3 AI model families participate symmetrically in a structured cross-examination:
- **Round 1**: Independent review (already completed in Steps 6.5-6.8)
- **Round 2**: Cross-examination — each model evaluates other models' findings
- **Round 3**: Defense — each model defends its own challenged findings

#### Step 6.10.1: Spawn Debate Arbitrator

```
Read(file_path: "${AGENTS_DIR}/debate-arbitrator.md")

Task(
  subagent_type: "general-purpose",
  team_name: "arena-review-{session_id}",
  name: "debate-arbitrator",
  prompt: "{contents of agents/debate-arbitrator.md}

  --- DEBATE CONTEXT ---
  Session: {session_id}
  Active reviewers: {list of ALL active reviewer teammate names}
  Cross-examination rounds: 3

  ROUND 1 AGGREGATED FINDINGS:
  {aggregated_findings_json}

  ROUND 1 FINDINGS BY MODEL:
  Claude: {round1_claude_findings_json}
  Codex: {round1_codex_findings_json}
  Gemini: {round1_gemini_findings_json}
  --- END CONTEXT ---

  INSTRUCTIONS:
  1. You will receive Round 2 cross-examination results from all 3 model families
  2. You will receive Round 3 defense results from all 3 model families
  3. After all 3 rounds, apply the consensus algorithm incorporating all rounds
  4. Include a cross_examination_trail for each finding in your output
  5. Send the final consensus JSON to the team lead after Round 3 completes"
)
```

#### Step 6.10.2: Round 2 — Cross-Examination

All 3 model families cross-examine each other's findings **in parallel**.

**Codex cross-examines Claude + Gemini findings:**
```bash
# Build Round 2 context for Codex
CODEX_R2_INPUT=$(jq -n \
  --argjson claude "$(cat ${SESSION_DIR}/findings/round1-claude.json)" \
  --argjson gemini "$(cat ${SESSION_DIR}/findings/round1-gemini.json)" \
  --argjson code "$(cat ${SESSION_DIR}/code-context.json)" \
  '{round:2, phase:"cross-examine", examiner:"codex", findings_from:{claude:$claude, gemini:$gemini}, code_context:$code}')

echo "$CODEX_R2_INPUT" | \
  "${SCRIPTS_DIR}/codex-cross-examine.sh" "$CONFIG" "cross-examine" \
  > "${SESSION_DIR}/debate/round2-codex.json" 2>/dev/null &
```

**Gemini cross-examines Claude + Codex findings:**
```bash
GEMINI_R2_INPUT=$(jq -n \
  --argjson claude "$(cat ${SESSION_DIR}/findings/round1-claude.json)" \
  --argjson codex "$(cat ${SESSION_DIR}/findings/round1-codex.json)" \
  --argjson code "$(cat ${SESSION_DIR}/code-context.json)" \
  '{round:2, phase:"cross-examine", examiner:"gemini", findings_from:{claude:$claude, codex:$codex}, code_context:$code}')

echo "$GEMINI_R2_INPUT" | \
  "${SCRIPTS_DIR}/gemini-cross-examine.sh" "$CONFIG" "cross-examine" \
  > "${SESSION_DIR}/debate/round2-gemini.json" 2>/dev/null &
```

**Claude reviewers cross-examine Codex + Gemini findings:**

Send to each active Claude reviewer via SendMessage:
```
SendMessage(
  type: "message",
  recipient: "{reviewer_name}",
  content: "CROSS-EXAMINATION — Round 2 of 3

  Evaluate findings from Codex and Gemini from your domain expertise.

  CODEX FINDINGS:
  {round1_codex_findings_json}

  GEMINI FINDINGS:
  {round1_gemini_findings_json}

  For EACH finding relevant to your domain:
  1. AGREE if valid — cite corroborating evidence, confidence_adjustment (+N)
  2. DISAGREE if false positive — cite counter-evidence, confidence_adjustment (-N)
  3. PARTIAL if partially correct — explain what's right/wrong

  You may add NEW OBSERVATIONS both models missed.

  Send each response to debate-arbitrator via SendMessage as JSON:
  {\"finding_id\":\"<file:line:title>\", \"original_model\":\"codex|gemini\", \"action\":\"agree|disagree|partial\", \"confidence_adjustment\":-30 to +30, \"reasoning\":\"...\", \"new_observations\":[]}

  When done: send '{reviewer_name} round 2 complete' to debate-arbitrator.",
  summary: "Round 2: cross-examine Codex+Gemini findings"
)
```

**Wait for all Round 2 results:**
```bash
wait  # Wait for Codex and Gemini background jobs
```

**Forward external Round 2 results to debate-arbitrator:**
```
SendMessage(
  type: "message",
  recipient: "debate-arbitrator",
  content: "ROUND 2 EXTERNAL RESULTS:

  CODEX CROSS-EXAMINATION:
  {contents of round2-codex.json}

  GEMINI CROSS-EXAMINATION:
  {contents of round2-gemini.json}",
  summary: "Round 2 external model cross-examination results"
)
```

Wait for Claude reviewers to complete Round 2 (they message debate-arbitrator directly).

**Signal Round 2 complete:**
```
SendMessage(
  type: "message",
  recipient: "debate-arbitrator",
  content: "ROUND 2 COMPLETE. All cross-examination responses received.",
  summary: "Round 2 cross-examination complete"
)
```

#### Step 6.10.3: Partition Round 2 Challenges by Target

Before Round 3, extract who challenged whom:

```bash
# Challenges against Codex's findings (from Claude reviewers + Gemini)
jq '[.responses[] | select(.original_model == "codex")]' \
  "${SESSION_DIR}/debate/round2-gemini.json" \
  > "${SESSION_DIR}/debate/round2-challenges-against-codex.json"

# Challenges against Gemini's findings (from Claude reviewers + Codex)
jq '[.responses[] | select(.original_model == "gemini")]' \
  "${SESSION_DIR}/debate/round2-codex.json" \
  > "${SESSION_DIR}/debate/round2-challenges-against-gemini.json"

# Challenges against Claude's findings (from Codex + Gemini)
jq '[.responses[] | select(.original_model == "claude")]' \
  "${SESSION_DIR}/debate/round2-codex.json" \
  > "${SESSION_DIR}/debate/round2-codex-vs-claude.json"
jq '[.responses[] | select(.original_model == "claude")]' \
  "${SESSION_DIR}/debate/round2-gemini.json" \
  > "${SESSION_DIR}/debate/round2-gemini-vs-claude.json"
```

Note: Claude reviewer challenges against Codex/Gemini were sent directly to debate-arbitrator via SendMessage. The partitioned JSON files above are for external model challenges only.

#### Step 6.10.4: Round 3 — Defense

All 3 model families defend their own findings **in parallel**.

**Codex defends its findings:**
```bash
CODEX_R3_INPUT=$(jq -n \
  --argjson challenges "$(cat ${SESSION_DIR}/debate/round2-challenges-against-codex.json)" \
  --argjson original "$(cat ${SESSION_DIR}/findings/round1-codex.json)" \
  --argjson code "$(cat ${SESSION_DIR}/code-context.json)" \
  '{round:3, phase:"defend", defender:"codex", challenges_against_codex:$challenges, original_findings:$original, code_context:$code}')

echo "$CODEX_R3_INPUT" | \
  "${SCRIPTS_DIR}/codex-cross-examine.sh" "$CONFIG" "defend" \
  > "${SESSION_DIR}/debate/round3-codex.json" 2>/dev/null &
```

**Gemini defends its findings:**
```bash
GEMINI_R3_INPUT=$(jq -n \
  --argjson challenges "$(cat ${SESSION_DIR}/debate/round2-challenges-against-gemini.json)" \
  --argjson original "$(cat ${SESSION_DIR}/findings/round1-gemini.json)" \
  --argjson code "$(cat ${SESSION_DIR}/code-context.json)" \
  '{round:3, phase:"defend", defender:"gemini", challenges_against_gemini:$challenges, original_findings:$original, code_context:$code}')

echo "$GEMINI_R3_INPUT" | \
  "${SCRIPTS_DIR}/gemini-cross-examine.sh" "$CONFIG" "defend" \
  > "${SESSION_DIR}/debate/round3-gemini.json" 2>/dev/null &
```

**Claude reviewers defend their findings:**

Send to each Claude reviewer whose findings were challenged:
```
SendMessage(
  type: "message",
  recipient: "{reviewer_name}",
  content: "DEFENSE — Round 3 of 3

  Codex and Gemini challenged some of YOUR Round 1 findings.
  For each challenge, decide: DEFEND, CONCEDE, or MODIFY.

  CHALLENGES AGAINST YOUR FINDINGS:
  From Codex: {codex_challenges_against_this_reviewer}
  From Gemini: {gemini_challenges_against_this_reviewer}

  YOUR ORIGINAL FINDINGS:
  {this_reviewer_original_findings}

  For EACH challenged finding:
  1. DEFEND — maintain with additional evidence
  2. CONCEDE — withdraw (shows intellectual honesty)
  3. MODIFY — adjust severity/description

  Send each defense to debate-arbitrator via SendMessage as JSON:
  {\"finding_id\":\"...\", \"action\":\"defend|concede|modify\", \"confidence_adjustment\":-30 to +30, \"reasoning\":\"...\", \"revised_severity\":null, \"revised_description\":null}

  When done: send '{reviewer_name} round 3 complete' to debate-arbitrator.",
  summary: "Round 3: defend your findings against challenges"
)
```

**Wait for all Round 3 results:**
```bash
wait  # External CLIs
```

**Forward external Round 3 results to debate-arbitrator:**
```
SendMessage(
  type: "message",
  recipient: "debate-arbitrator",
  content: "ROUND 3 EXTERNAL RESULTS:

  CODEX DEFENSE:
  {contents of round3-codex.json}

  GEMINI DEFENSE:
  {contents of round3-gemini.json}",
  summary: "Round 3 external model defense results"
)
```

**Signal Round 3 complete:**
```
SendMessage(
  type: "message",
  recipient: "debate-arbitrator",
  content: "ROUND 3 COMPLETE. All defenses received. Synthesize the final consensus from all 3 rounds.",
  summary: "Round 3 defense complete — synthesize consensus"
)
```

#### Step 6.10.5: Web Search Verification & Final Consensus

1. **Web Search Verification**: For critical/high severity security findings:
   - Use WebSearch for CVE entries, OWASP guidelines, security advisories
   - Send verification results to debate-arbitrator

2. **Collect Consensus**: Wait for debate-arbitrator to send the final consensus JSON incorporating all 3 rounds (CONFIRMED / DISMISSED / DISPUTED with full cross_examination_trail).

#### Cross-Examination Error Handling

- **Round 2 external CLI timeout**: Proceed without that model's cross-examination. Note in report.
- **Round 3 external CLI timeout**: Treat as implicit defense (findings maintained at current confidence).
- **Claude reviewer no response**: Proceed with available responses.
- **All Round 2 fails**: Skip Round 3, fall back to Round 1 data only for consensus.
- **All Round 3 fails**: Synthesize based on Round 1 + Round 2 data only.

---

## Phase 6.5: Apply Findings — Auto-Fix Loop (standard/deep/comprehensive intensity)

Apply consensus findings that meet strict auto-fix criteria. This phase automatically fixes low-risk, high-confidence issues and verifies fixes via test suite. **NEVER auto-fix critical or high severity findings — those always require human review.**

### Step 6.5.1: Identify Auto-Fixable Findings

Filter consensus findings by ALL of the following criteria:

| Criterion | Requirement |
|-----------|------------|
| Severity | `medium` or `low` ONLY (NEVER critical/high) |
| Confidence | >= 90% post-debate consensus confidence |
| Agreement | Unanimous or majority (2+ models/reviewers agree) |
| Scope | Affects <= 10 lines of code |
| Category | ONLY auto-fixable categories (see below) |

**Auto-fixable categories:**

| Category | Description | Examples |
|----------|-------------|---------|
| `naming_convention` | Variable/function rename to match project style | camelCase → snake_case, inconsistent naming |
| `import_ordering` | Import sort/cleanup | Alphabetize imports, remove duplicates |
| `unused_code` | Dead code removal | Unused imports, unreachable branches, dead variables |
| `type_annotation` | Missing type additions | Add return types, parameter types, type narrowing |
| `simple_null_check` | Adding null/undefined guards | Missing optional chaining, nullish coalescing |
| `documentation` | Missing JSDoc/docstring | Add function description, parameter docs |

**EXCLUDED from auto-fix (always manual review):**

- Security vulnerabilities (any severity)
- Logic errors or algorithm bugs
- Race conditions or concurrency issues
- Architectural or design issues
- Performance optimizations
- Any finding touching > 10 lines
- Any finding with `disputed` or `conflict-resolved` agreement level

```
AUTO_FIXABLE = []

FOR each finding in consensus.accepted:
  IF finding.severity in ["medium", "low"]
     AND finding.confidence >= 90
     AND finding.agreement_level in ["unanimous", "majority"]
     AND finding.category in AUTO_FIX_CATEGORIES
     AND finding.affected_lines <= 10
     AND finding.category NOT IN ["security", "logic", "race_condition", "architecture", "performance"]:
    ADD to AUTO_FIXABLE
```

Display identified auto-fixable findings to user:
```
AUTO-FIX CANDIDATES ({N} findings)
| # | File:Line | Category | Description | Confidence |
|---|-----------|----------|-------------|------------|
| 1 | src/api.ts:45 | naming_convention | Rename `getUserData` → `get_user_data` | 95% |
| 2 | src/utils.ts:12 | unused_code | Remove unused import `lodash` | 92% |

Proceed with auto-fix? [Yes / Skip auto-fix / Select specific findings]
```

IF user skips or no auto-fixable findings: proceed directly to Phase 7.

### Step 6.5.2: Apply Fixes

For each auto-fixable finding, apply the fix:

```
FOR each finding in AUTO_FIXABLE:
  1. Read the target file with Read tool
  2. Apply the suggestion using Edit tool
  3. Track the change:
     {
       finding_id: "<id>",
       file: "<path>",
       line: <line_number>,
       category: "<category>",
       original_code: "<before>",
       fixed_code: "<after>",
       status: "applied"
     }
```

### Step 6.5.3: Test Verification

After ALL fixes are applied, verify with the project's test suite:

```bash
# Detect and run appropriate test command
if [ -f "package.json" ]; then
  # Check for test script
  TEST_CMD=$(jq -r '.scripts.test // empty' package.json)
  if [ -n "$TEST_CMD" ]; then
    npm test 2>&1 | tail -50
  fi
elif [ -f "pytest.ini" ] || [ -f "setup.py" ] || [ -f "pyproject.toml" ]; then
  python -m pytest --tb=short 2>&1 | tail -50
elif [ -f "go.mod" ]; then
  go test ./... 2>&1 | tail -50
elif [ -f "Cargo.toml" ]; then
  cargo test 2>&1 | tail -50
fi
```

**If tests FAIL:**
```
# Revert ALL auto-fixes
git checkout -- .

# Mark all findings as auto-fix-failed
FOR each applied_fix:
  applied_fix.status = "auto-fix-failed"

# Log which test failed
WARN: "Auto-fix verification failed. All fixes reverted. Manual review required."
WARN: "Failed test: {test_name}"
WARN: "Possible culprit: {most_recent_fix}"
```

**If tests PASS:**
```
FOR each applied_fix:
  applied_fix.status = "auto-fix-applied-verified"
```

**If NO test suite detected:**
```
FOR each applied_fix:
  applied_fix.status = "auto-fix-applied-unverified"

WARN: "No test suite found. Auto-fixes applied but NOT verified. Manual verification recommended."
```

### Step 6.5.4: Display Applied Fixes

Show the user what was changed:

```
AUTO-FIX RESULTS
| # | File:Line | Category | Change | Status |
|---|-----------|----------|--------|--------|
| 1 | src/api.ts:45 | naming_convention | `getUserData` → `get_user_data` | verified |
| 2 | src/utils.ts:12 | unused_code | Removed `import { merge } from 'lodash'` | verified |

Total: {N} fixes applied, {M} verified, {K} failed (reverted)
```

Store results for Phase 7 report:
```bash
echo '${AUTO_FIX_RESULTS_JSON}' > "${SESSION_DIR}/auto-fix-results.json"
```

**Error Handling:**
- If Edit tool fails on a specific file: skip that fix, mark as "edit-failed", continue with remaining fixes.
- If git checkout fails during revert: warn user, list modified files for manual recovery.
- If test command hangs (>120s): kill process, treat as test failure, revert all fixes.

---

## Phase 7: Final Report & Cleanup

### Step 7.1: Generate Report

1. Run the report generation script if available:
   ```bash
   bash "${SCRIPTS_DIR}/generate-report.sh" \
     --session "${SESSION_DIR}" \
     --config "${DEFAULT_CONFIG}" \
     --language "${OUTPUT_LANGUAGE}" \
     --format markdown
   ```

2. Build the enriched report (extends multi-review.md format):

   ```markdown
   # AI Review Arena - Full Lifecycle Report

   **Date:** {timestamp}
   **Scope:** {diff description or PR number}
   **Intensity:** {intensity level} - {preset description}
   **Models:** {list of participating models}
   **Mode:** Agent Teams (full lifecycle with enriched context)

   ---

   ## Stack Profile
   - Platform: {platform}
   - Languages: {languages}
   - Frameworks: {frameworks}
   - Databases: {databases}

   ---

   ## Executive Summary

   {High-level summary: total findings by severity, key risks, overall code health, compliance status, scale readiness}

   ---

   ## Critical & High Severity Findings

   ### [{severity}] {title}
   - **File:** `{file_path}:{line}`
   - **Confidence:** {confidence}% {cross-validated badge if applicable}
   - **Found by:** {model(s)}
   - **Cross-Examination:** {confirmed|challenged|modified|conceded}
   - **Round 2:** Codex: {agree/disagree/partial}, Gemini: {agree/disagree/partial}
   - **Round 3:** {defended/conceded/modified} by {original_model}
   - **Agreement:** {unanimous|majority|single-source-validated}

   **Description:**
   {detailed description}

   **Best Practice Reference:**
   {relevant best practice from research, if applicable}

   **Suggestion:**
   ```{language}
   {code suggestion}
   ```

   ---

   ## Compliance Status

   | Guideline | Platform | Status | Risk | Details |
   |-----------|----------|--------|------|---------|
   | {guideline_name} | {platform} | {COMPLIANT/NON_COMPLIANT/PARTIAL} | {CRITICAL/HIGH/MEDIUM/LOW} | {brief detail} |

   ### Non-Compliant Items (Requires Action)
   {detailed list of non-compliant items with remediation steps}

   ---

   ## Scale Readiness

   | Category | Issues | Critical | High | Medium |
   |----------|--------|----------|------|--------|
   | Concurrency | {count} | {count} | {count} | {count} |
   | Data Volume | {count} | {count} | {count} | {count} |
   | Resource Mgmt | {count} | {count} | {count} | {count} |
   | Observability | {count} | {count} | {count} | {count} |
   | Horizontal | {count} | {count} | {count} | {count} |

   ### Scale Recommendations
   {detailed scale recommendations}

   ---

   ## Success Criteria Verification

   | # | Criterion | Verification Method | Result |
   |---|-----------|-------------------|--------|
   | 1 | {criterion_1} | {verification_check} | PASS / FAIL |
   | 2 | {criterion_2} | {verification_check} | PASS / FAIL |
   | 3 | {criterion_3} | {verification_check} | PASS / FAIL |

   ---

   ## Scope Review (Surgical Changes)

   **Verdict:** {CLEAN or N violations found}

   {If violations exist:}
   | Type | File | Line | Description |
   |------|------|------|-------------|
   | {SCOPE_VIOLATION/DRIVE_BY_REFACTOR/GOLD_PLATING} | {file} | {line} | {description} |

   ---

   ## Best Practice Gaps

   | Practice | Status | Severity | Recommendation |
   |----------|--------|----------|----------------|
   | {practice_name} | {implemented/missing/anti-pattern} | {severity} | {brief recommendation} |

   ---

   ## Medium & Low Severity Findings

   | Severity | File | Line | Title | Confidence | Model | Debate |
   |----------|------|------|-------|------------|-------|--------|

   ---

   ## Auto-Fix Results (Phase 6.5)

   {If auto-fix was executed:}

   | # | File:Line | Category | Change | Status |
   |---|-----------|----------|--------|--------|
   | 1 | {file}:{line} | {category} | {description of change} | {verified/unverified/failed} |

   **Summary:** {N} fixes applied, {M} verified by test suite, {K} failed (reverted)
   {If no test suite: "No test suite detected — fixes applied but unverified"}

   {If auto-fix was skipped:}
   Auto-fix skipped: {reason — no eligible findings / user declined / quick intensity}

   ---

   ## Disputed Findings (Human Review Required)

   {For each disputed finding: all model perspectives, unresolved questions}

   ---

   ## Cross-Examination Summary

   ### Round 2: Cross-Examination Results
   | Finding | Claude Assessment | Codex Assessment | Gemini Assessment |
   |---------|-------------------|-------------------|-------------------|
   | {title} | agree (+10) | disagree (-15) | partial (-5) |

   **New Observations from Round 2**: {N} additional findings discovered

   ### Round 3: Defense Results
   | Finding | Defender | Action | Outcome |
   |---------|----------|--------|---------|
   | {title} | Claude | defend | maintained (conf: 85→90) |
   | {title} | Codex | concede | withdrawn |
   | {title} | Gemini | modify | severity: critical→high |

   **Concessions**: {N} findings withdrawn | **Modifications**: {M} adjusted | **Defended**: {K} maintained

   ---

   ## Model Agreement Matrix

   | Finding | Claude Reviewers | Codex | Gemini | Round 2 | Round 3 | Consensus |
   |---------|-----------------|-------|--------|---------|---------|-----------|

   ---

   ## Model Routing Performance

   | Focus Area | Primary Model | Score | Findings | Secondary Model | Score | Findings |
   |-----------|---------------|-------|----------|-----------------|-------|----------|

   ---

   ## Debate Log (if show_debate_log is true)

   {3-round cross-examination log: Round 1 findings, Round 2 cross-examinations, Round 3 defenses, and final synthesis}

   ---

   ## Cost Summary

   | Component | Teammates/Calls | Est. Tokens | Est. Cost |
   |-----------|----------------|-------------|-----------|
   | **Round 1: Review** | | | |
   | Claude Reviewers | {N} teammates | ~{X}K | ~${A.AA} |
   | Scale Advisor | 1 teammate | ~{X}K | ~${A.AA} |
   | Scope Reviewer | 1 teammate | ~{X}K | ~${A.AA} |
   | Compliance Checker | {0 or 1} teammate | ~{X}K | ~${A.AA} |
   | Research Coordinator | {0 or 1} teammate | ~{X}K | ~${A.AA} |
   | Codex CLI (Round 1) | {N} calls | ~{X}K | ~${B.BB} |
   | Gemini CLI (Round 1) | {N} calls | ~{X}K | ~${C.CC} |
   | **Round 2: Cross-Exam** | | | |
   | Claude Reviewers (R2) | {N} teammates | ~{X}K | ~${D.DD} |
   | Codex CLI (Round 2) | 1 call | ~{X}K | ~${E.EE} |
   | Gemini CLI (Round 2) | 1 call | ~{X}K | ~${F.FF} |
   | **Round 3: Defense** | | | |
   | Claude Reviewers (R3) | {N} teammates | ~{X}K | ~${G.GG} |
   | Codex CLI (Round 3) | 1 call | ~{X}K | ~${H.HH} |
   | Gemini CLI (Round 3) | 1 call | ~{X}K | ~${I.II} |
   | **Arbitration** | | | |
   | Debate Arbitrator | 1 teammate | ~{X}K | ~${J.JJ} |
   | **Total** | | | **~${K.KK}** |
   ```

**Output Steps:**
1. Generate report in configured language (`output.language`)
2. Display the formatted report to the user
3. Save report: write to `${SESSION_DIR}/reports/arena-report.md`
4. If `--pr` was used and `output.post_to_github` is true:
   ```bash
   gh pr comment $PR_NUMBER --body-file "${SESSION_DIR}/reports/arena-report.md"
   ```

### Step 7.2: Shutdown All Teammates

Send shutdown requests to ALL active teammates. Wait for each confirmation before proceeding.

```
SendMessage(type: "shutdown_request", recipient: "security-reviewer", content: "Arena session complete. Thank you.")
SendMessage(type: "shutdown_request", recipient: "bug-detector", content: "Arena session complete. Thank you.")
SendMessage(type: "shutdown_request", recipient: "architecture-reviewer", content: "Arena session complete. Thank you.")
SendMessage(type: "shutdown_request", recipient: "performance-reviewer", content: "Arena session complete. Thank you.")
SendMessage(type: "shutdown_request", recipient: "test-coverage-reviewer", content: "Arena session complete. Thank you.")
SendMessage(type: "shutdown_request", recipient: "scale-advisor", content: "Arena session complete. Thank you.")
SendMessage(type: "shutdown_request", recipient: "scope-reviewer", content: "Arena session complete. Thank you.")
SendMessage(type: "shutdown_request", recipient: "debate-arbitrator", content: "Arena session complete. Thank you.")
```

Conditionally shutdown if spawned:
```
SendMessage(type: "shutdown_request", recipient: "compliance-checker", content: "Arena session complete. Thank you.")
SendMessage(type: "shutdown_request", recipient: "research-coordinator", content: "Arena session complete. Thank you.")
```

Only send shutdown to teammates that were actually spawned in this session.
Wait for all shutdown confirmations before cleanup.

### Step 7.3: Cleanup Team

After ALL teammates have confirmed shutdown:

```
Teammate(operation: "cleanup")
```

**IMPORTANT:** Cleanup will fail if active teammates still exist. Always shutdown all teammates first.

### Step 7.4: Display Session Reference

```
## Session Complete
- Session directory: ${SESSION_DIR}
- Report: ${SESSION_DIR}/reports/arena-report.md
- Findings: ${SESSION_DIR}/findings/
- Research: ${SESSION_DIR}/research/
- Compliance: ${SESSION_DIR}/compliance/
- Benchmarks: ${SESSION_DIR}/benchmarks/

Use `/multi-review-status --last` to view this report again.
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
| 0 | Full Operation | — | All phases, all models, full Agent Teams | None |
| 1 | Benchmark Failure | Phase 4 fails or times out | Use default role assignments from config | "Benchmark: skipped — default routing" |
| 2 | Research/Compliance Failure | Phase 2 or 3 fails | Proceed without enriched context | "Research: unavailable" or "Compliance: unavailable" |
| 3 | Agent Teams Failure | Teammate spawn fails | Fall back to Task subagents (no inter-agent messaging, no debate) | "Mode: subagent (no debate)" |
| 4 | External CLI Failure | All Codex/Gemini calls fail | Claude-only Agent Teams review | "External models: unavailable" |
| 5 | All Failure | Agent Teams AND subagents fail | Claude solo inline analysis | "Mode: solo inline" |

### Per-Phase Fallback Rules

| Phase | On Failure | Fallback Behavior | Level Escalation |
|-------|-----------|-------------------|-----------------|
| Phase 1 (Stack) | Script error or timeout | Use manual stack hints from config or codebase analysis | Stay at current level |
| Phase 2 (Research) | WebSearch fails or timeout | Skip research context, warn reviewers | Escalate to Level 2 if not already |
| Phase 3 (Compliance) | Script error or timeout | Skip compliance rules, note in report | Escalate to Level 2 if not already |
| Phase 4 (Benchmark) | Script error or timeout | Use default model-role mapping from config | Escalate to Level 1 |
| Phase 5 (Figma) | MCP unavailable | Skip Figma analysis entirely | Stay at current level |
| Phase 5.5 (Strategy) | Debate agents fail | Skip strategy debate, proceed directly to review | Stay at current level |
| Phase 6 (Review) | Teammate spawn fails | Try Task subagents; if that fails, solo analysis | Escalate to Level 3 or 5 |
| Phase 6 (External CLI) | Codex/Gemini timeout or error | Retry once (5s delay), then exclude model | Escalate to Level 4 if all external fail |
| Phase 6.10 (Debate) | Arbitrator fails | Manual consensus synthesis from available responses | Stay at current level |

### External CLI Retry Logic

```
FOR each external CLI call:
  attempt = 1
  WHILE attempt <= config.fallback.retry_attempts + 1:
    result = execute_with_timeout(cli_command, config.fallback.external_cli_timeout_seconds)

    IF result.success:
      BREAK
    ELIF attempt <= config.fallback.retry_attempts:
      WAIT config.fallback.retry_delay_seconds
      attempt += 1
      LOG "Retry #{attempt} for {model} {role}"
    ELSE:
      LOG "FAILED: {model} {role} after {attempt} attempts"
      APPEND to FALLBACK_LOG: {phase, model, role, error, attempts}
      BREAK
```

### Teammate Error Recovery

- **Teammate stops unexpectedly**: Check TaskList for incomplete tasks. Spawn replacement if total active < minimum required.
- **Teammate not responding**: Send follow-up message. Wait 60s. If still no response, mark as failed and proceed with other teammates.
- **Debate-arbitrator fails**: Collect available challenge/support messages. Synthesize consensus manually using the same algorithm defined in debate-arbitrator.md.
- **JSON Parse Errors**: Attempt extraction via 4-layer fallback: direct parse → ` ```json ` block → ` ``` ` block → first-`{`-to-last-`}` regex. If all fail, discard and continue.

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
| Models Excluded | {list of failed models with error type} |
| Retries Attempted | {total retry count} |
| Context Available | {list: stack ✓, research ✗, compliance ✓, ...} |

### Fallback Log
{FALLBACK_LOG entries with timestamps}
```

IF FALLBACK_LEVEL >= 3:
  Add prominent warning at top of report:
  "⚠ This review ran at degraded capacity (Level {N}). Results may be less comprehensive than a full review."
