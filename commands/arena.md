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
├── Phase 0.5: Codebase Analysis (conventions, reusable code, structure)
├── Phase 1: Stack Detection (detect-stack.sh)
├── Phase 2: Pre-Implementation Research (search-best-practices.sh + WebSearch)
├── Phase 3: Compliance Detection (search-guidelines.sh + WebSearch)
├── Phase 4: Model Benchmarking (benchmark-models.sh + Task subagents)
├── Phase 5: Figma Analysis (Figma MCP tools, optional)
├── Phase 6: Agent Team Review (follows multi-review.md pattern)
│   ├── Create team (Teammate tool)
│   ├── Spawn reviewer teammates (Task tool with team_name)
│   ├── Spawn scale-advisor teammate (always included)
│   ├── Spawn compliance-checker teammate (if compliance detected)
│   ├── Spawn research-coordinator teammate (deep intensity only)
│   ├── Run external CLIs (Codex, Gemini via Bash)
│   ├── Coordinate debate phase
│   └── Aggregate findings & generate report
├── Phase 7: Final Report & Cleanup
│   ├── Generate enriched report with compliance + scale sections
│   ├── Shutdown all teammates
│   └── Cleanup team
└── Error handling & graceful degradation

Claude Reviewer Teammates (independent Claude Code instances)
├── security-reviewer    ─┐
├── bug-detector         ─┤── SendMessage <-> each other (debate)
├── architecture-reviewer─┤── SendMessage -> debate-arbitrator
├── performance-reviewer ─┤── SendMessage -> team lead (findings)
├── test-reviewer        ─┤
├── scale-advisor        ─┤── NEW: scale/concurrency analysis
├── compliance-checker   ─┘── NEW: guideline compliance (conditional)
│
├── research-coordinator ─── NEW: deep intensity only
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
   - `all` (default): Run phases 0.5, 1-7 in sequence
   - `codebase`: Run Phase 0.5 only (codebase analysis)
   - `codebase,review`: Run Phase 0.5 + Phase 6 + Phase 7 (refactoring mode)
   - `stack`: Run Phase 0.5 + Phase 1 only
   - `research`: Run Phase 0.5 + Phase 1 + Phase 2
   - `compliance`: Run Phase 0.5 + Phase 1 + Phase 3
   - `benchmark`: Run Phase 4 only
   - `review`: Run Phase 0.5 + Phase 1 (for context) + Phase 6 + Phase 7

   **Quick Intensity Mode** (`--intensity quick`):
   - Run Phase 0 + Phase 0.5 only
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

For each standard role (security-reviewer, bug-detector, architecture-reviewer, performance-reviewer, test-coverage-reviewer):

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
   5. Stay active - you will participate in the debate phase next"
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

6. Save aggregated findings to session.

7. If `--interactive`: ask to proceed to debate phase.

### Step 6.10: Adversarial Debate (Agent Teams)

Skip if `--no-debate` is set or `debate.enabled` is false.

This phase follows the exact same pattern as multi-review.md Phase 6:

1. **Spawn Debate Arbitrator**:
   ```
   Read(file_path: "${AGENTS_DIR}/debate-arbitrator.md")

   Task(
     subagent_type: "general-purpose",
     team_name: "arena-review-{session_id}",
     name: "debate-arbitrator",
     prompt: "{contents of agents/debate-arbitrator.md}

     --- DEBATE CONTEXT ---
     Session: {session_id}
     Active reviewers: {list of ALL active reviewer teammate names, including scale-advisor, compliance-checker, research-coordinator}
     Debate rounds: {debate.max_rounds}

     AGGREGATED FINDINGS:
     {aggregated_findings_json}
     --- END CONTEXT ---

     INSTRUCTIONS:
     1. You will receive challenge/support messages from reviewer teammates
     2. Apply the consensus algorithm as defined in your agent instructions
     3. After all debate rounds complete, send the final consensus JSON to the team lead
     4. Wait for the team lead to signal when each debate round ends"
   )
   ```

2. **Initiate Cross-Challenges**: Send each reviewer teammate instructions to challenge findings from OTHER reviewers using SendMessage (not broadcast):
   ```
   SendMessage(
     type: "message",
     recipient: "{reviewer_name}",
     content: "DEBATE PHASE - Round {N}/{max_rounds}

     Review the following findings from OTHER reviewers and respond to debate-arbitrator with your challenges or support.

     FINDINGS TO EVALUATE:
     {findings_NOT_from_this_reviewer_json}

     For EACH finding:
     1. CHALLENGE if you disagree - explain why it's a false positive or overrated
     2. SUPPORT if you agree - add evidence or corroborate
     3. Send each response to debate-arbitrator via SendMessage

     When done evaluating all findings, send a message to debate-arbitrator saying '{reviewer_name} debate complete'.",
     summary: "Debate round {N}: evaluate other reviewers' findings"
   )
   ```

   Repeat for each active reviewer teammate.

3. **External Model Challenges**: For findings needing cross-model validation:
   ```bash
   echo '{"finding": {...}, "challenge_prompt": "..."}' | \
     "${SCRIPTS_DIR}/codex-review.sh" "$FILE" "$CONFIG" "debate" \
     > "${SESSION_DIR}/debate/codex-challenge-${finding_id}.json" 2>/dev/null
   ```

   Send external responses to debate-arbitrator:
   ```
   SendMessage(
     type: "message",
     recipient: "debate-arbitrator",
     content: "EXTERNAL MODEL RESPONSE ({model}):
     Finding: {finding_title}
     {challenge_result_json}",
     summary: "{model} challenge response for: {finding_title}"
   )
   ```

4. **Web Search Verification**: For critical/high severity security findings:
   - Use WebSearch for CVE entries, OWASP guidelines, security advisories
   - Send verification results to debate-arbitrator

5. **Repeat** for additional rounds if `debate.max_rounds` > 1.

6. **Collect Consensus**: Wait for debate-arbitrator to send final consensus (CONFIRMED / DISMISSED / DISPUTED).

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
   - **Debate status:** {confirmed|adjusted|disputed}
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

   ## Best Practice Gaps

   | Practice | Status | Severity | Recommendation |
   |----------|--------|----------|----------------|
   | {practice_name} | {implemented/missing/anti-pattern} | {severity} | {brief recommendation} |

   ---

   ## Medium & Low Severity Findings

   | Severity | File | Line | Title | Confidence | Model | Debate |
   |----------|------|------|-------|------------|-------|--------|

   ---

   ## Disputed Findings (Human Review Required)

   {For each disputed finding: all model perspectives, unresolved questions}

   ---

   ## Model Agreement Matrix

   | Finding | Claude Reviewers | Codex | Gemini | Consensus |
   |---------|-----------------|-------|--------|-----------|

   ---

   ## Model Routing Performance

   | Focus Area | Primary Model | Score | Findings | Secondary Model | Score | Findings |
   |-----------|---------------|-------|----------|-----------------|-------|----------|

   ---

   ## Debate Log (if show_debate_log is true)

   {Inter-agent message summary, challenges, supports, and resolutions}

   ---

   ## Cost Summary

   | Component | Teammates/Calls | Est. Tokens | Est. Cost |
   |-----------|----------------|-------------|-----------|
   | Claude Reviewers | {N} teammates | ~{X}K | ~${A.AA} |
   | Scale Advisor | 1 teammate | ~{X}K | ~${A.AA} |
   | Compliance Checker | {0 or 1} teammate | ~{X}K | ~${A.AA} |
   | Research Coordinator | {0 or 1} teammate | ~{X}K | ~${A.AA} |
   | Debate Arbitrator | 1 teammate | ~{X}K | ~${A.AA} |
   | Codex CLI | {N} calls | ~{X}K | ~${B.BB} |
   | Gemini CLI | {N} calls | ~{X}K | ~${C.CC} |
   | **Total** | | | **~${D.DD}** |
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

## Error Handling & Fallback Strategy

### Level 0 - Full Operation
All phases complete, all models available, full Agent Teams with enriched context.

### Level 1 - Benchmark Failure
Skip benchmarking, use default role assignments from config.
- Warn: "Benchmarking failed - using default model routing from config"
- Continue with all other phases

### Level 2 - Compliance/Research Failure
Skip compliance or research, proceed with review only.
- Warn: "Compliance detection failed - proceeding without compliance context"
- Warn: "Research phase failed - proceeding without best practice context"
- Reviewers receive code without enriched context for failed phases

### Level 3 - Agent Teams Failure
If spawning teammates fails or resources are insufficient:
- Warn: "Agent Teams unavailable - falling back to subagent mode"
- Use Task tool subagents instead of teammates (no inter-agent messaging)
- Skip debate phase
- Include research/compliance context in subagent prompts

### Level 4 - All External Failures
Claude-only single analysis with whatever context is available.
- Warn: "External CLIs unavailable, Agent Teams failed - running Claude-only analysis"
- Read files directly and provide inline analysis
- Include whatever enriched context was successfully gathered

### Teammate Errors
- **Teammate stops unexpectedly**: Check TaskList for incomplete tasks. Spawn replacement teammate if needed.
- **Teammate not responding**: Send a follow-up message. If still no response after 60 seconds, proceed without their input.
- **Debate-arbitrator fails**: Collect whatever challenge/support messages were received. Synthesize consensus manually using the same algorithm.

### Timeout Handling
- If a teammate times out, use whatever partial results they sent
- If an external CLI times out, log and continue with other models
- Include timeout notes in the final report

### JSON Parse Errors
- If a model returns invalid JSON, attempt extraction with regex
- If extraction fails, log error and continue

### Cleanup on Error
If an error occurs mid-process, always attempt cleanup:
1. Send shutdown requests to all spawned teammates
2. Wait briefly for confirmations
3. Run Teammate cleanup
4. Report the error with partial results if available
5. Save whatever session data exists for debugging
