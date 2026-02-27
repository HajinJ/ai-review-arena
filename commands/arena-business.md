---
description: "Business content lifecycle orchestrator - market research, accuracy audit, content strategy, and multi-agent business review"
argument-hint: "[task] [--type content|strategy|communication] [--audience investor|customer|partner|internal|general] [--tone formal|casual|persuasive|analytical] [--intensity quick|standard|deep|comprehensive] [--interactive] [--skip-cache]"
allowed-tools: [Bash, Glob, Grep, Read, Task, WebSearch, WebFetch, Teammate, SendMessage, TaskCreate, TaskUpdate, TaskList, TaskGet]
---

# AI Review Arena - Business Content Lifecycle Orchestrator (Agent Teams)

You are the **team lead** for the AI Review Arena business content lifecycle orchestrator. This command orchestrates the entire business content review lifecycle: business context extraction, market/industry research, content best practices research, accuracy & consistency auditing, business model benchmarking, content strategy debate, and multi-agent adversarial business review with Agent Teams and optional external CLI models (Codex, Gemini).

## Architecture

```
Team Lead (You - this session)
+-- Phase B0: Context & Configuration (+ MCP Dependency Detection)
+-- Phase B0.1: Intensity Decision (Agent Teams debate - MANDATORY)
|   +-- intensity-advocate     -> argues for higher intensity
|   +-- efficiency-advocate    -> argues for lower intensity
|   +-- risk-assessor          -> evaluates audience/brand/accuracy risk
|   +-- intensity-arbitrator   -> synthesizes consensus, decides intensity
+-- Phase B0.2: Cost & Time Estimation (user approval before proceeding)
+-- Phase B0.5: Business Context Analysis (docs, README, specs, plans)
+-- Phase B1: Market/Industry Context (WebSearch)
+-- Phase B2: Content Best Practices Research (deep+ only, with debate)
|   +-- Research Direction Debate
|       +-- researcher-industry   -> industry communication standards
|       +-- researcher-audience   -> audience-specific writing guidelines
|       +-- researcher-format     -> content format best practices
|       +-- research-arbitrator   -> prioritizes research agenda
+-- Phase B3: Accuracy & Consistency Audit (deep+ only, with debate)
|   +-- Accuracy Scope Debate
|       +-- accuracy-advocate     -> argues for broader verification
|       +-- scope-challenger      -> argues against over-verification
|       +-- accuracy-arbitrator   -> decides verification scope
+-- Phase B4: Business Model Benchmarking (comprehensive only)
|   +-- Run benchmark-business-models.sh against planted-error test cases
|   +-- Score each model (Claude, Codex, Gemini) per category (avg F1)
|   +-- Determine model role assignments for Phase B6
+-- Phase B5.5: Content Strategy Debate (standard+)
|   +-- messaging-advocate       -> proposes messaging strategy
|   +-- audience-challenger      -> challenges audience fit
|   +-- accuracy-challenger      -> challenges factual claims
|   +-- strategy-arbitrator      -> synthesizes content strategy
+-- Phase B6: Multi-Agent Business Review (5 reviewers + arbitrator + external CLIs, 3-round debate)
|   +-- Step B6.1.5: Determine external model participation (benchmark-driven at comprehensive)
|   +-- Create team (Teammate tool)
|   +-- Spawn business reviewer teammates (Task tool with team_name)
|   +-- Run external CLI Round 1 if assigned as primary (parallel with Claude teammates)
|   +-- Coordinate 3-round debate phase (independent review, cross-review, defense)
|   +-- Run external CLI Round 2 cross-review (parallel with Claude Round 2)
|   +-- Aggregate findings & generate consensus
+-- Phase B6.5: Apply Findings (review→fix loop for critical/high findings)
|   +-- Auto-revise content based on consensus findings
|   +-- Verify fixes address the issues
+-- Phase B7: Final Report & Cleanup
|   +-- Generate enriched business review report
|   +-- Shutdown all teammates
|   +-- Cleanup team
+-- Fallback Framework (structured 5-level graceful degradation)

Business Reviewer Teammates (dynamic, from config business_intensity_presets.{INTENSITY}.reviewer_roles)
+-- {role-1}                    --+
+-- {role-2}                    --+-- SendMessage <-> each other (debate)
+-- {role-3}                    --+-- SendMessage -> business-debate-arbitrator
+-- {role-N}                    --+-- SendMessage -> team lead (findings)
+-- business-debate-arbitrator  ------ Receives challenges/supports -> synthesizes consensus

External CLI Models (intensity-dependent roles)
+-- Codex CLI (codex-business-review.sh)  --+-- Round 1 primary (if benchmark-assigned at comprehensive)
+-- Gemini CLI (gemini-business-review.sh) --+-- Round 2 cross-reviewer (default at standard/deep)
                                              +-- Round 1 primary OR Round 2 cross (comprehensive, benchmark-driven)
```

## Constants

```
PLUGIN_DIR="~/.claude/plugins/ai-review-arena"
SCRIPTS_DIR="${PLUGIN_DIR}/scripts"
CONFIG_DIR="${PLUGIN_DIR}/config"
CACHE_DIR="${PLUGIN_DIR}/cache"
AGENTS_DIR="${PLUGIN_DIR}/agents"
DEFAULT_CONFIG="${CONFIG_DIR}/default-config.json"
SESSION_DIR="$(mktemp -d /tmp/ai-review-arena-biz.XXXXXXXXXX)"
```

## Phase B0: Context & Configuration

Establish business context, load configuration, and prepare the session environment.

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
   - Extract `--type` value (default: "content"). Valid values: `content`, `strategy`, `communication`
   - Extract `--audience` value (default: "general"). Valid values: `investor`, `customer`, `partner`, `internal`, `general`
   - Extract `--tone` value (default: "formal"). Valid values: `formal`, `casual`, `persuasive`, `analytical`
   - Extract `--skip-cache` flag (default: false)
   - Extract `--interactive` flag (default: from config `arena.interactive_by_default`)
   - Extract `--intensity` value (default: from config `review.intensity`)
   - Remaining arguments are treated as the business task description (the content to create, review, or refine)

4. Check that `arena.enabled` is true in config. If false:
   - Display: "AI Review Arena is disabled in configuration. Enable it with: `/arena-config set arena.enabled true`"
   - Exit early.

5. Create session directory:
   ```bash
   mkdir -p "${SESSION_DIR}/findings" "${SESSION_DIR}/research" "${SESSION_DIR}/reports"
   echo "session: ${SESSION_DIR}"
   ```

6. Determine business type focus areas based on `--type`:
   - `content` (default): accuracy + audience fit + messaging emphasis
     - Phase B0.5: Full context extraction
     - Phase B1: Market positioning context
     - Phase B2 (deep+): Content writing best practices
     - Phase B3 (deep+): Full accuracy audit
     - Phase B5.5: Messaging-first strategy debate
     - Phase B6: All reviewers with emphasis scoring on accuracy-evidence-reviewer and audience-fit-reviewer
   - `strategy`: market research + data evidence + competitive positioning emphasis
     - Phase B0.5: Full context extraction with emphasis on competitive data
     - Phase B1: Deep market research (extended search queries)
     - Phase B2 (deep+): Strategy framework best practices
     - Phase B3 (deep+): Data and evidence audit
     - Phase B5.5: Positioning-first strategy debate
     - Phase B6: All reviewers with emphasis scoring on competitive-positioning-reviewer and market-fit-reviewer
   - `communication`: tone + clarity + audience fit emphasis
     - Phase B0.5: Full context extraction with brand voice emphasis
     - Phase B1: Industry communication norms
     - Phase B2 (deep+): Communication style best practices
     - Phase B3 (deep+): Tone consistency audit
     - Phase B5.5: Audience-first strategy debate
     - Phase B6: All reviewers with emphasis scoring on communication-narrative-reviewer and audience-fit-reviewer

7. Determine which phases to execute based on intensity:

   **Intensity determines Phase scope** (decided by Phase B0.1 debate or `--intensity` flag):
   - `quick`: Phase B0 -> B0.1 -> B0.5 only (Claude solo, no Agent Team)
   - `standard`: Phase B0 -> B0.1 -> B0.5 -> B1 -> B5.5 -> B6 -> B7
   - `deep`: Phase B0 -> B0.1 -> B0.5 -> B1 -> B2(+debate) -> B3(+debate) -> B5.5 -> B6 -> B7
   - `comprehensive`: Phase B0 -> B0.1 -> B0.5 -> B1 -> B2(+debate) -> B3(+debate) -> B5.5 -> B6 -> B7 (all phases with all debates, maximum reviewer depth)

   **Quick Intensity Mode** (`--intensity quick` or decided by Phase B0.1):
   - Run Phase B0 + Phase B0.1 + Phase B0.5 only
   - Skip all other phases (B1-B7)
   - Claude executes the task solo using business context analysis results
   - After task completion, perform simplified self-review (no Agent Team)
   - No team spawning

8. If `--interactive` is set, display the execution plan:
   ```
   ## Arena Business Execution Plan
   - Content Type: {type}
   - Target Audience: {audience}
   - Tone: {tone}
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
         - **Cancel**: Abort arena-business execution

    b. **Google Sheets/Docs MCP Detection**:
       - Check if request contains: "spreadsheet", "Google Sheet", "Google Doc", "financial model"
       - If detected:
         ```
         ToolSearch(query: "google sheets")
         ```
       - If not found: Inform user and suggest installation, continue without it

    c. **Figma MCP Detection** (for brand asset/design reference):
       - Check if request contains: figma.com URL, "brand guidelines", "design system"
       - If detected:
         ```
         ToolSearch(query: "figma")
         ```
       - If not found: Inform user and suggest installation, continue without it

    d. Record MCP availability status for session:
       ```json
       {
         "notion_mcp": "available|installed|unavailable",
         "google_mcp": "available|installed|unavailable",
         "figma_mcp": "available|installed|unavailable"
       }
       ```

---

## Phase B0.1: Intensity Decision (Agent Teams Debate)

> **Shared Phase**: Full definition at `${PLUGIN_DIR}/shared-phases/intensity-decision.md`
> Set variables: `PIPELINE_TYPE=business`, `TEAM_PREFIX=biz-intensity-decision`

**MANDATORY for all requests.** Determine the appropriate intensity level through adversarial debate among Claude agents. Skip only if user explicitly specified `--intensity`.

**Purpose**: Prevent both under-processing (missing accuracy issues in investor materials) and over-processing (running full pipeline for an internal note). No single Claude instance can reliably judge business content complexity alone.

**Steps:**

1. **Create Decision Team**:
   ```
   Teammate(
     operation: "spawnTeam",
     team_name: "biz-intensity-decision-{YYYYMMDD-HHMMSS}",
     description: "Business content intensity level determination debate"
   )
   ```

2. **Create Debate Tasks**:
   ```
   TaskCreate(
     subject: "Advocate for higher business content intensity",
     description: "Argue for the highest reasonable intensity level for this business content request. Consider: audience exposure, strategic impact, accuracy sensitivity, brand risk, regulatory implications. Provide specific business reasoning.",
     activeForm: "Advocating for higher intensity"
   )

   TaskCreate(
     subject: "Advocate for lower business content intensity",
     description: "Argue for the lowest reasonable intensity level for this business content request. Consider: internal vs external audience, existing template availability, time sensitivity, content reusability, low-stakes context. Provide specific business reasoning.",
     activeForm: "Advocating for lower intensity"
   )

   TaskCreate(
     subject: "Assess business content risk and impact",
     description: "Evaluate the audience exposure, strategic impact, accuracy sensitivity, and brand risk of this business content request. Consider: who will see this? What decisions will be made based on it? What happens if there is an error? Provide risk assessment with severity rating.",
     activeForm: "Assessing business content risk and impact"
   )

   TaskCreate(
     subject: "Arbitrate business content intensity decision",
     description: "Wait for all three advocates to present their arguments. Weigh the business merits of each position. Decide the final intensity level (quick/standard/deep/comprehensive) with clear justification. Send the decision to the team lead.",
     activeForm: "Arbitrating intensity decision"
   )
   ```

3. **Spawn Debate Agents** (all in parallel):
   ```
   Task(
     subagent_type: "general-purpose",
     team_name: "biz-intensity-decision-{session}",
     name: "intensity-advocate",
     prompt: "You are the Intensity Advocate for business content review. Your role is to argue for the HIGHEST reasonable intensity level.

     USER REQUEST: {user_request}
     CONTENT TYPE: {type}
     TARGET AUDIENCE: {audience}
     TONE: {tone}
     PROJECT CONTEXT: {discovered_context_from_step1}

     Analyze this request and argue why it needs a higher intensity level. Consider:
     - Audience Exposure: Internal draft has low risk. Customer-facing content is medium. Investor materials, media releases, or regulatory filings are high-risk and need comprehensive review.
     - Strategic Impact: Is this a minor text update, a core positioning document, or a market entry strategy? Higher strategic impact demands deeper review.
     - Accuracy Sensitivity: General claims have moderate sensitivity. Specific numbers or percentages need verification. Regulatory statements or financial projections demand the highest scrutiny.
     - Brand Risk: Internal docs are low risk. Customer docs are medium. PR/media content, investor decks, and regulatory filings carry the highest brand risk.
     - Regulatory Implications: Content with compliance claims, legal positioning, or regulatory statements needs deep accuracy auditing.
     - Cross-Document Impact: Does this content set precedents that other documents will reference?

     Present your argument to intensity-arbitrator via SendMessage.
     Then engage with efficiency-advocate's counter-arguments.
     Continue debating until intensity-arbitrator makes a decision."
   )

   Task(
     subagent_type: "general-purpose",
     team_name: "biz-intensity-decision-{session}",
     name: "efficiency-advocate",
     prompt: "You are the Efficiency Advocate for business content review. Your role is to argue for the LOWEST reasonable intensity level.

     USER REQUEST: {user_request}
     CONTENT TYPE: {type}
     TARGET AUDIENCE: {audience}
     TONE: {tone}
     PROJECT CONTEXT: {discovered_context_from_step1}

     Analyze this request and argue why a lower intensity is sufficient. Consider:
     - Is this content internal-only? Internal notes and drafts rarely need multi-agent review.
     - Are there existing templates or patterns that can be followed? Template-based content is lower risk.
     - Is the content time-sensitive? Speed may be more important than exhaustive review.
     - Is this a minor revision to existing reviewed content? Incremental changes need less scrutiny.
     - Is the content reusable boilerplate? Standard proposals and emails follow established patterns.
     - Will the content go through additional human review anyway?
     - Would higher intensity waste resources without proportional improvement in quality?

     Present your argument to intensity-arbitrator via SendMessage.
     Then engage with intensity-advocate's counter-arguments.
     Continue debating until intensity-arbitrator makes a decision."
   )

   Task(
     subagent_type: "general-purpose",
     team_name: "biz-intensity-decision-{session}",
     name: "risk-assessor",
     prompt: "You are the Risk Assessor for business content review. Your role is to provide an objective risk evaluation.

     USER REQUEST: {user_request}
     CONTENT TYPE: {type}
     TARGET AUDIENCE: {audience}
     TONE: {tone}
     PROJECT CONTEXT: {discovered_context_from_step1}

     Evaluate along these dimensions:

     1. Audience Exposure:
        - Internal draft -> LOW
        - Internal presentation -> LOW-MEDIUM
        - Customer document -> MEDIUM
        - Partner/vendor document -> MEDIUM-HIGH
        - Investor materials -> HIGH
        - Media/PR content -> HIGH
        - Regulatory filing -> CRITICAL

     2. Strategic Impact:
        - Minor text edit -> LOW
        - Individual document -> MEDIUM
        - Core positioning document -> HIGH
        - Market entry strategy -> HIGH
        - Full business plan -> CRITICAL

     3. Accuracy Sensitivity:
        - General qualitative claims -> LOW
        - Specific feature claims -> MEDIUM
        - Quantitative claims (numbers, percentages) -> HIGH
        - Financial projections -> HIGH
        - Regulatory/compliance statements -> CRITICAL

     4. Brand Risk:
        - Internal docs -> LOW
        - Customer docs -> MEDIUM
        - Public-facing content -> HIGH
        - PR/media releases -> HIGH
        - Investor/regulatory -> CRITICAL

     Rate overall risk as: LOW / MEDIUM / HIGH / CRITICAL
     Send your assessment to intensity-arbitrator via SendMessage."
   )

   Task(
     subagent_type: "general-purpose",
     team_name: "biz-intensity-decision-{session}",
     name: "intensity-arbitrator",
     prompt: "You are the Intensity Arbitrator for business content review. Your role is to make the FINAL intensity decision.

     Wait for arguments from:
     1. intensity-advocate (argues for higher intensity)
     2. efficiency-advocate (argues for lower intensity)
     3. risk-assessor (provides risk evaluation)

     After receiving all arguments:
     1. Weigh the business merits of each position
     2. Consider the risk assessment dimensions
     3. Decide: quick, standard, deep, or comprehensive
     4. Provide clear justification for your decision

     Intensity guidelines for business content:
     - quick: 내부 메모, 단순 텍스트 수정만
     - standard: 블로그 포스트, 단일 문서 작성, 내부 프레젠테이션
     - deep: 외부 노출 문서, 투자자 대면 자료, 제품 소개서, 마케팅 카피
     - comprehensive: 비즈니스 플랜, 펀드레이징 자료, 규제 제출물, 전략 문서, 경쟁 분석

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
   ## Intensity Decision (Phase B0.1)
   - Decision: {intensity_level}
   - Risk Level: {risk_level}
   - Key Factors: {key_factors}
   - Justification: {justification}
   ```

**Error Handling:**
- If Agent Teams are unavailable: fall back to Claude solo judgment with explicit reasoning logged.
- If debate times out (>60 seconds): use the last available position from the arbitrator, or default to `standard`.
- If no consensus reached: default to `deep` (err on the side of caution for business content).

---

## Phase B0.2: Cost & Time Estimation

> **Shared Phase**: Full definition at `${PLUGIN_DIR}/shared-phases/cost-estimation.md`
> Uses `cost-estimator.sh --intensity ${INTENSITY} --pipeline business`

Based on the decided intensity, estimate costs and time before proceeding. This phase runs immediately after intensity decision for ALL intensity levels.

**Purpose**: Give the user visibility into expected resource usage before committing to execution.

### Estimation Formula

Sum the applicable components based on decided intensity:

| Component | Applies At | Token Estimate | Est. Cost |
|-----------|-----------|---------------|-----------|
| Phase B0.5 Context Analysis | all | ~10K | ~$0.50 |
| Phase B1 Market Research | standard+ | ~15K | ~$0.75 |
| Phase B2 Best Practices Research | deep+ | ~20K | ~$1.00 |
| Phase B3 Accuracy Audit | deep+ | ~18K | ~$0.90 |
| Phase B4 Benchmarking | comprehensive | ~40K | ~$2.00 |
| Phase B5.5 Strategy Debate | standard+ | ~25K | ~$1.25 |
| Phase B6 Review (5 agents) | standard+ | ~60K | ~$3.00 |
| Phase B6 External CLI (if enabled) | standard+ | ~16K | ~$0.26 |
| Phase B6 Debate Rounds 2+3 | standard+ | ~50K | ~$2.50 |
| Phase B6.5 Auto-Fix | standard+ | ~15K | ~$0.75 |
| Phase B7 Report | all | ~8K | ~$0.40 |

### Calculation

```
total_tokens = SUM(applicable_components)
total_cost = SUM(component_tokens * config.cost_estimation.token_cost_per_1k)
est_time_minutes = CEIL(total_tokens / 15000)  # ~15K tokens per minute throughput
```

### Display to User

```
## Cost & Time Estimate (Phase B0.2)

Intensity: {intensity}
Content Type: {type}
Audience: {audience}
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
- IF user selects "Adjust intensity": Prompt for new intensity level, skip back to Phase B0.1 with `--intensity` override
- IF user selects "Proceed": Continue to Phase B0.5

---

## Phase B0.5: Business Context Analysis

Analyze the existing project documentation to extract business context, brand voice, product capabilities, and competitive positioning. This phase runs for ALL intensity levels including `quick`. Results are passed as context to all subsequent phases and to Claude's own task execution.

**Purpose**: Ensure that all business content is grounded in actual product capabilities, consistent with existing brand voice, and aligned with documented business strategy. Prevents disconnection between content claims and product reality.

**Steps:**

1. **Project Documentation Scan** (Glob):
   ```
   Glob(pattern: "docs/**/*.md", path: "${PROJECT_ROOT}")
   Glob(pattern: "*.md", path: "${PROJECT_ROOT}")
   Glob(pattern: "docs/**/*.txt", path: "${PROJECT_ROOT}")
   Glob(pattern: "**/*.md", path: "${PROJECT_ROOT}/design-system")
   ```
   - Map all documentation files
   - Identify key business documents by name pattern:
     - README.md (project overview)
     - *business*plan* (business strategy)
     - *development*spec* (product specification)
     - *handoff* (operational handoff)
     - *implementation*tracker* (feature status)
     - *direction* or *roadmap* (future plans)
     - *judging* or *readiness* (evaluation criteria)
     - *deploy* or *runbook* (operational documents)
     - *alerting* or *policy* (operational policies)

2. **Read Key Business Documents** (Read):
   Use the glob results from step 1 to dynamically find and read key business documents.
   Do NOT hardcode filenames — match against the patterns defined above:
   ```
   # Always read README if it exists
   Read(file_path: "${PROJECT_ROOT}/README.md")

   # Dynamically find business documents using glob results from step 1
   # Match files against patterns: *business*plan*, *development*spec*, *handoff*,
   # *implementation*tracker*, *direction*, *roadmap*, *judging*, *readiness*,
   # *deploy*, *runbook*, *alerting*, *policy*
   #
   # For each pattern, read the FIRST matching file (most recent by modification time):
   Glob(pattern: "docs/*business*plan*", path: "${PROJECT_ROOT}")  -> Read first match
   Glob(pattern: "docs/*development*spec*", path: "${PROJECT_ROOT}")  -> Read first match
   Glob(pattern: "docs/*handoff*", path: "${PROJECT_ROOT}")  -> Read first match
   Glob(pattern: "docs/*implementation*tracker*", path: "${PROJECT_ROOT}")  -> Read first match
   Glob(pattern: "docs/*direction*", path: "${PROJECT_ROOT}")  -> Read first match
   Glob(pattern: "docs/*judging*", path: "${PROJECT_ROOT}")  -> Read first match
   Glob(pattern: "docs/*roadmap*", path: "${PROJECT_ROOT}")  -> Read first match
   ```
   Read up to 7 key documents. If no files match a pattern, skip without error.

3. **Extract Business Context**:
   From the documents read, extract and compile the following categories:

   a. **Product Description**:
      - Product name and tagline
      - Core functionality and features
      - Technology stack summary
      - Current development status (MVP, beta, production, etc.)
      - Feature implementation status (complete, in-progress, planned)

   b. **Value Propositions**:
      - Primary value proposition
      - Secondary value propositions
      - Key differentiators from competitors
      - Unique selling points

   c. **Target Markets**:
      - Primary target market
      - Secondary target markets
      - Geographic focus
      - Industry/vertical focus

   d. **Customer Segments**:
      - Primary customer personas
      - Customer pain points addressed
      - Customer journey stages targeted
      - Decision-maker profiles

   e. **Existing Brand Voice/Tone**:
      - Detected writing style patterns from existing docs
      - Formality level
      - Technical depth level
      - Personality traits (authoritative, friendly, innovative, etc.)
      - Consistent terminology and phrasing

   f. **Key KPIs and Metrics**:
      - Business KPIs mentioned in documents
      - Target values for each KPI
      - Measurement methodology references
      - Industry benchmarks cited

   g. **Competitive Positioning**:
      - Named competitors
      - Competitive differentiation claims
      - Market category / positioning statement
      - Defensibility claims (moats, barriers)

   h. **Pricing Model**:
      - Pricing structure (freemium, subscription, usage-based, etc.)
      - Price points if stated
      - Revenue model description
      - Unit economics references

4. **Compile Business Context Brief**:
   Structure the extracted information into a single reference document:
   ```
   === BUSINESS CONTEXT BRIEF ===

   Product: {product_name}
   Status: {development_status}
   Primary Market: {primary_market}

   VALUE PROPOSITION:
   {primary_value_proposition}

   KEY DIFFERENTIATORS:
   - {differentiator_1}
   - {differentiator_2}
   - {differentiator_3}

   TARGET AUDIENCE:
   Primary: {primary_audience}
   Secondary: {secondary_audiences}

   BRAND VOICE:
   Tone: {detected_tone}
   Formality: {formality_level}
   Style Notes: {style_observations}

   KEY METRICS:
   - {kpi_1}: {target_or_current_value}
   - {kpi_2}: {target_or_current_value}

   COMPETITIVE LANDSCAPE:
   Category: {market_category}
   Competitors: {named_competitors}
   Positioning: {positioning_statement}

   PRICING:
   Model: {pricing_model}
   Details: {pricing_details}

   FEATURE STATUS:
   Complete: {complete_features_list}
   In Progress: {in_progress_features_list}
   Planned: {planned_features_list}

   === END BUSINESS CONTEXT BRIEF ===
   ```

5. **Save Context to Session**:
   Store the Business Context Brief so it is available to all subsequent phases:
   ```bash
   echo '${BUSINESS_CONTEXT_BRIEF}' > "${SESSION_DIR}/research/business-context-brief.md"
   ```

6. **Mandatory Instructions for Subsequent Phases**:
   Append to all phase contexts and agent prompts:
   ```
   BUSINESS CONTEXT (MUST FOLLOW):
   {business_context_brief}

   Rules:
   1. ALL product claims MUST align with documented feature status (complete, in-progress, planned)
   2. Do NOT present planned or in-progress features as if they are currently available
   3. Follow the detected brand voice and tone consistently
   4. Use the same terminology as existing documentation
   5. All quantitative claims MUST be sourced or flagged as estimates
   6. Competitive positioning MUST be consistent with documented strategy
   7. Pricing and revenue model references MUST match documented pricing
   ```

7. **Quick Mode Execution** (if `--intensity quick`):
   After business context analysis, execute the user's task directly:
   - Apply discovered brand voice and tone
   - Use identified product capabilities accurately
   - Ensure consistency with existing documents
   - Perform simplified self-review:
     ```
     Self-Review Checklist:
     - Consistent with project documentation
     - Matches existing brand voice/tone
     - Claims align with actual product capabilities
     - Target audience appropriate
     - No factual errors detected
     ```
   - Display completion summary and exit (skip remaining phases)

**Error Handling:**
- If Glob returns no documentation files: warn "No project documentation found. Business context will be limited." Proceed with whatever README.md is available.
- If key documents do not exist at expected paths: skip those documents, proceed with what is available.
- If no business context can be extracted: warn user and proceed with generic context. Note this limitation in all subsequent phase prompts.

---

## Phase B1: Market/Industry Context

Gather current market data, competitive intelligence, and industry trends relevant to the business content being created or reviewed.

**Purpose**: Provide up-to-date market context so that business content reflects current competitive landscape, market trends, and industry standards. Prevents content from being outdated or disconnected from market reality.

**Steps:**

1. Check cache first (unless `--skip-cache`):
   ```bash
   bash "${SCRIPTS_DIR}/cache-manager.sh" check "${PROJECT_ROOT}" market-research industry-context --ttl 1
   ```

2. If cache is fresh and not `--skip-cache`:
   - Read cached market research data
   - Parse and load into session context

3. If cache is stale or `--skip-cache`:

   a. **Industry Overview Search**:
      Using the product domain and market category from Business Context Brief:
      ```
      WebSearch(query: "{product_domain} industry overview market size {current_year}")
      WebSearch(query: "{market_category} market trends {current_year}")
      ```

   b. **Competitive Landscape Search**:
      Using named competitors from Business Context Brief:
      ```
      WebSearch(query: "{competitor_1} vs {competitor_2} comparison {product_domain} {current_year}")
      WebSearch(query: "{market_category} competitive landscape key players {current_year}")
      ```

   c. **Market Size Data (TAM/SAM/SOM)**:
      ```
      WebSearch(query: "{market_category} total addressable market TAM {current_year}")
      WebSearch(query: "{product_domain} market size forecast growth rate {current_year}")
      ```

   d. **Industry News and Regulatory Changes**:
      ```
      WebSearch(query: "{product_domain} regulatory changes compliance updates {current_year}")
      WebSearch(query: "{market_category} industry news developments {current_year}")
      ```

   e. **Content Type-Specific Research** (based on `--type`):
      - If `strategy`:
        ```
        WebSearch(query: "{product_domain} go-to-market strategy best practices {current_year}")
        WebSearch(query: "{market_category} pricing strategies SaaS {current_year}")
        ```
      - If `communication`:
        ```
        WebSearch(query: "{product_domain} industry communication standards {current_year}")
        WebSearch(query: "{audience} communication preferences B2B {current_year}")
        ```
      - If `content`:
        ```
        WebSearch(query: "{product_domain} content marketing trends {current_year}")
        WebSearch(query: "{audience} content expectations {market_category} {current_year}")
        ```

4. **Compile Market Context Summary**:
   ```
   === MARKET CONTEXT SUMMARY ===

   INDUSTRY OVERVIEW:
   - Market Category: {category}
   - Market Size: {TAM/SAM/SOM if found}
   - Growth Rate: {projected growth}
   - Key Trends: {trend_1}, {trend_2}, {trend_3}

   COMPETITIVE LANDSCAPE:
   - Major Players: {competitor_list}
   - Market Positioning: {how competitors position}
   - Differentiation Gaps: {opportunities}

   RECENT DEVELOPMENTS:
   - {news_item_1}
   - {news_item_2}

   REGULATORY ENVIRONMENT:
   - {regulation_1}: {status}
   - {regulation_2}: {status}

   DATA FRESHNESS: {search_date}
   SOURCES: {list of sources used}

   === END MARKET CONTEXT SUMMARY ===
   ```

5. **Cache Results**:
   ```bash
   echo '${MARKET_CONTEXT}' | bash "${SCRIPTS_DIR}/cache-manager.sh" write "${PROJECT_ROOT}" market-research industry-context --ttl 1
   ```

6. **Save to Session**:
   ```bash
   echo '${MARKET_CONTEXT_SUMMARY}' > "${SESSION_DIR}/research/market-context.md"
   ```

7. **Display Market Context Summary**:
   ```
   ## Market/Industry Context (Phase B1)

   ### Industry Overview
   - Market: {market_category}
   - Size: {market_size_data}
   - Growth: {growth_rate}
   - Key Trends: {trends}

   ### Competitive Landscape
   - Players: {competitors}
   - Positioning: {competitive_positioning}

   ### Recent Developments
   - {developments}

   ### Regulatory Environment
   - {regulatory_items}
   ```

8. If `--interactive`: ask user to confirm or supplement market context.
   ```
   Market research complete. Add additional context or proceed? (Enter to proceed, or type additions)
   ```

**Error Handling:**
- If cache-manager.sh fails: proceed without caching, run WebSearch directly.
- If WebSearch returns no results for a query: note the gap and continue with other queries.
- If all market research fails: warn "Market research unavailable - proceeding without market context." Set `market_context_available = false` for downstream phases.

---

## Phase B2: Content Best Practices Research (deep/comprehensive intensity only)

Gather content creation best practices specific to the content type, audience, and industry. Requires deep or comprehensive intensity.

**Pre-Step: Research Direction Debate** (deep/comprehensive intensity only):

Before executing searches, debate what to research:

1. **Create Research Direction Team**:
   ```
   Teammate(
     operation: "spawnTeam",
     team_name: "biz-research-direction-{YYYYMMDD-HHMMSS}",
     description: "Business content research direction debate"
   )
   ```

2. **Create Research Tasks**:
   ```
   TaskCreate(
     subject: "Research industry communication standards",
     description: "Propose research directions for industry-specific communication standards, norms, and conventions relevant to this content. Consider regulatory requirements, industry jargon usage, compliance language standards.",
     activeForm: "Proposing industry communication research"
   )

   TaskCreate(
     subject: "Research audience-specific writing guidelines",
     description: "Propose research directions for audience-specific writing guidelines. Consider how this audience (investor/customer/partner/internal) expects to receive information, their reading patterns, decision-making frameworks.",
     activeForm: "Proposing audience writing research"
   )

   TaskCreate(
     subject: "Research content format best practices",
     description: "Propose research directions for best practices specific to this content format and type. Consider structure templates, length guidelines, visual element usage, data presentation norms.",
     activeForm: "Proposing content format research"
   )

   TaskCreate(
     subject: "Arbitrate research direction priorities",
     description: "Wait for all three researcher proposals. Evaluate and prioritize the research agenda. Select top 3-5 research topics that will most improve the content quality. Send the prioritized agenda to the team lead.",
     activeForm: "Arbitrating research direction"
   )
   ```

3. **Spawn Research Direction Agents** (all in parallel):
   ```
   Task(
     subagent_type: "general-purpose",
     team_name: "biz-research-direction-{session}",
     name: "researcher-industry",
     prompt: "You are the Industry Communication Researcher. Propose research directions for industry-specific communication standards.

     USER REQUEST: {user_request}
     CONTENT TYPE: {type}
     AUDIENCE: {audience}
     BUSINESS CONTEXT: {business_context_brief}

     Propose 3-5 research topics related to:
     - Industry-specific communication standards and norms
     - Regulatory language requirements for this domain
     - Industry jargon usage guidelines and glossary standards
     - Professional communication conventions in {market_category}
     - Compliance language requirements if applicable

     For each topic, provide:
     - Topic title
     - Why it matters for this specific content
     - Suggested search queries
     - Expected impact on content quality

     Send your proposals to research-arbitrator via SendMessage.
     Engage with other researchers' proposals — challenge or support their priorities."
   )

   Task(
     subagent_type: "general-purpose",
     team_name: "biz-research-direction-{session}",
     name: "researcher-audience",
     prompt: "You are the Audience Writing Researcher. Propose research directions for audience-specific writing guidelines.

     USER REQUEST: {user_request}
     CONTENT TYPE: {type}
     AUDIENCE: {audience}
     BUSINESS CONTEXT: {business_context_brief}

     Propose 3-5 research topics related to:
     - How {audience} stakeholders prefer to receive information
     - Reading patterns and attention spans for this audience
     - Decision-making frameworks used by {audience}
     - Persuasion techniques effective for {audience}
     - Information hierarchy preferences for {audience} documents

     For each topic, provide:
     - Topic title
     - Why it matters for this specific content
     - Suggested search queries
     - Expected impact on content quality

     Send your proposals to research-arbitrator via SendMessage.
     Engage with other researchers' proposals — challenge or support their priorities."
   )

   Task(
     subagent_type: "general-purpose",
     team_name: "biz-research-direction-{session}",
     name: "researcher-format",
     prompt: "You are the Content Format Researcher. Propose research directions for content format best practices.

     USER REQUEST: {user_request}
     CONTENT TYPE: {type}
     AUDIENCE: {audience}
     BUSINESS CONTEXT: {business_context_brief}

     Propose 3-5 research topics related to:
     - Best practices for this specific content format (pitch deck, business plan, proposal, etc.)
     - Structure and organization templates that work for this content type
     - Data visualization and presentation norms
     - Length and density guidelines for the format
     - Successful examples and anti-patterns

     For each topic, provide:
     - Topic title
     - Why it matters for this specific content
     - Suggested search queries
     - Expected impact on content quality

     Send your proposals to research-arbitrator via SendMessage.
     Engage with other researchers' proposals — challenge or support their priorities."
   )

   Task(
     subagent_type: "general-purpose",
     team_name: "biz-research-direction-{session}",
     name: "research-arbitrator",
     prompt: "You are the Research Arbitrator. Prioritize the research agenda for business content best practices.

     Wait for proposals from:
     1. researcher-industry (industry communication standards)
     2. researcher-audience (audience-specific writing guidelines)
     3. researcher-format (content format best practices)

     After receiving all proposals:
     1. Evaluate each proposed topic for relevance and impact
     2. Identify overlaps and dependencies between proposals
     3. Prioritize the top 3-5 research topics
     4. Consider the content type ({type}) and audience ({audience}) when prioritizing

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
   TaskUpdate(taskId: "{industry_task}", owner: "researcher-industry")
   TaskUpdate(taskId: "{audience_task}", owner: "researcher-audience")
   TaskUpdate(taskId: "{format_task}", owner: "researcher-format")
   TaskUpdate(taskId: "{arbitrator_task}", owner: "research-arbitrator")
   ```

5. **Wait for Research Agenda**: Wait for research-arbitrator to send the prioritized agenda via SendMessage.

6. **Shutdown Research Direction Team**:
   ```
   SendMessage(type: "shutdown_request", recipient: "researcher-industry", content: "Research direction decided.")
   SendMessage(type: "shutdown_request", recipient: "researcher-audience", content: "Research direction decided.")
   SendMessage(type: "shutdown_request", recipient: "researcher-format", content: "Research direction decided.")
   SendMessage(type: "shutdown_request", recipient: "research-arbitrator", content: "Research direction decided.")
   Teammate(operation: "cleanup")
   ```

7. **Display Research Direction Decision**:
   ```
   ## Research Direction (Phase B2 Debate Result)
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

9. **Compile Best Practices Brief**:
   ```
   === CONTENT BEST PRACTICES BRIEF ===

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

   === END CONTENT BEST PRACTICES BRIEF ===
   ```

10. **Cache Results**:
    ```bash
    echo '${BEST_PRACTICES_BRIEF}' | bash "${SCRIPTS_DIR}/cache-manager.sh" write "${PROJECT_ROOT}" market-research content-best-practices --ttl 3
    ```

11. **Save to Session**:
    ```bash
    echo '${BEST_PRACTICES_BRIEF}' > "${SESSION_DIR}/research/best-practices-brief.md"
    ```

12. **Display Best Practices Summary**:
    ```
    ## Content Best Practices Research (Phase B2)

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
    Best practices research complete. Proceed to accuracy audit? (y/n)
    ```

**Error Handling:**
- If research direction debate fails: use default research topics based on content type and audience.
- If WebSearch returns no results for a topic: note the gap and continue with other topics.
- If all research fails: warn "Best practices research unavailable - proceeding without best practice context." Set `best_practices_available = false` for downstream phases.

---

## Phase B2.9: Intensity Checkpoint (Bidirectional)

**Applies to**: deep and comprehensive intensity (skip for quick and standard).

**Purpose**: After market research and best practices research complete, re-evaluate whether the decided intensity is still appropriate.

**Evaluation:**

```
COLLECT research_findings FROM Phase B1 + B2

downgrade_score = 0
upgrade_score = 0

# Evidence for DOWNGRADE:
IF research found straightforward content format:             downgrade_score += 3
IF target audience is well-understood and standard:           downgrade_score += 2
IF no complex compliance requirements:                        downgrade_score += 2
IF content is short-form (< 2000 words):                      downgrade_score += 1

# Evidence for UPGRADE:
IF content involves regulated industry claims (financial, medical, legal): upgrade_score += 3
IF multiple competing products with aggressive positioning to fact-check:  upgrade_score += 3
IF content targets high-stakes audience (board, investors, regulators):    upgrade_score += 2
IF discovered brand consistency issues across multiple documents:          upgrade_score += 2
IF content makes quantitative claims needing verification (>5 data points): upgrade_score += 1

# Decision:
IF downgrade_score >= 5 AND downgrade_score > upgrade_score + 2:
  recommendation = "DOWNGRADE"
ELIF upgrade_score >= 5 AND upgrade_score > downgrade_score + 2:
  recommendation = "UPGRADE"
ELSE:
  recommendation = "NO CHANGE"
```

**If DOWNGRADE recommended:**
```
Display to user:
"Research suggests this content is simpler than initially assessed.
 Current intensity: {current}
 Recommended: {lower_intensity}
 Estimated savings: ~${savings} and ~{minutes} min
 Reason: {top_downgrade_evidence}
 [Downgrade / Keep current]"
```

**If UPGRADE recommended:**
```
Display to user:
"Research reveals higher complexity than initially assessed.
 Current intensity: {current}
 Recommended: {higher_intensity}
 Additional estimated cost: ~${delta_cost}
 Reason: {top_upgrade_evidence}
 [Upgrade / Keep current]"
```

**Non-interactive mode:** Auto-adjust only if score >= 7 (strong evidence).

---

## Phase B3: Accuracy & Consistency Audit (deep/comprehensive intensity only)

Cross-reference all claims in the business content against project documentation and external data. Requires deep or comprehensive intensity.

**Pre-Step: Accuracy Scope Debate** (deep/comprehensive intensity only):

Before executing the audit, debate what needs verification:

1. **Create Accuracy Scope Team**:
   ```
   Teammate(
     operation: "spawnTeam",
     team_name: "biz-accuracy-scope-{YYYYMMDD-HHMMSS}",
     description: "Business content accuracy scope debate"
   )
   ```

2. **Create Scope Tasks**:
   ```
   TaskCreate(
     subject: "Advocate for broader verification scope",
     description: "Argue for a comprehensive verification scope. Consider all quantitative claims, all product capability claims, all competitive positioning claims, all market data references, and all regulatory/compliance statements. Identify which claim categories carry the most risk if inaccurate.",
     activeForm: "Advocating for broader verification"
   )

   TaskCreate(
     subject: "Challenge over-verification",
     description: "Argue against over-verification. Consider which claims are well-established and do not need re-verification, which are subjective opinions that cannot be verified, and which are clearly marked as estimates or projections. Identify the minimum verification scope that adequately protects against material errors.",
     activeForm: "Challenging over-verification"
   )

   TaskCreate(
     subject: "Arbitrate accuracy scope",
     description: "Wait for arguments from accuracy-advocate and scope-challenger. Decide the final verification scope: which categories of claims must be verified, which can be spot-checked, and which can be skipped. Send the decision to the team lead.",
     activeForm: "Arbitrating accuracy scope"
   )
   ```

3. **Spawn Scope Agents** (all in parallel):
   ```
   Task(
     subagent_type: "general-purpose",
     team_name: "biz-accuracy-scope-{session}",
     name: "accuracy-advocate",
     prompt: "You are the Accuracy Advocate. Argue for a comprehensive verification scope for this business content.

     USER REQUEST: {user_request}
     CONTENT TYPE: {type}
     AUDIENCE: {audience}
     BUSINESS CONTEXT: {business_context_brief}

     Argue for verifying:
     - ALL quantitative claims (numbers, percentages, growth rates)
     - ALL product capability claims against actual implementation status
     - ALL competitive positioning claims against current competitor data
     - ALL market size and opportunity claims against published data
     - ALL regulatory and compliance statements against current regulations
     - ALL timeline and milestone claims against project documentation
     - ALL financial projections for methodology soundness

     For each category, explain the risk of NOT verifying.
     Consider: audience trust damage, legal liability, investor relations risk, competitive vulnerability.

     Send your argument to accuracy-arbitrator via SendMessage.
     Engage with scope-challenger's counter-arguments."
   )

   Task(
     subagent_type: "general-purpose",
     team_name: "biz-accuracy-scope-{session}",
     name: "scope-challenger",
     prompt: "You are the Scope Challenger. Argue against over-verification of business content.

     USER REQUEST: {user_request}
     CONTENT TYPE: {type}
     AUDIENCE: {audience}
     BUSINESS CONTEXT: {business_context_brief}

     Argue for a focused verification scope. Consider:
     - Qualitative opinions and subjective assessments do not need verification
     - Claims clearly marked as estimates, projections, or forward-looking statements have lower verification burden
     - Internal documents face less scrutiny than external-facing ones
     - Well-established industry facts do not need re-verification
     - Product capabilities documented in implementation trackers are already tracked
     - Over-verification wastes resources and delays content delivery

     Propose a minimum verification scope that protects against material errors without excessive overhead.

     Send your argument to accuracy-arbitrator via SendMessage.
     Engage with accuracy-advocate's counter-arguments."
   )

   Task(
     subagent_type: "general-purpose",
     team_name: "biz-accuracy-scope-{session}",
     name: "accuracy-arbitrator",
     prompt: "You are the Accuracy Arbitrator. Decide the final verification scope.

     Wait for arguments from:
     1. accuracy-advocate (argues for broader verification)
     2. scope-challenger (argues against over-verification)

     After receiving both arguments:
     1. Weigh the risk of each claim category against verification cost
     2. Consider the audience ({audience}) and content type ({type})
     3. Decide for each claim category: VERIFY, SPOT-CHECK, or SKIP

     Send your decision to the team lead via SendMessage:
     ACCURACY_SCOPE:
     VERIFY (full check):
     - {claim_category}: {reason}
     SPOT-CHECK (sample):
     - {claim_category}: {reason}
     SKIP (not needed):
     - {claim_category}: {reason}"
   )
   ```

4. **Assign Tasks**:
   ```
   TaskUpdate(taskId: "{accuracy_advocate_task}", owner: "accuracy-advocate")
   TaskUpdate(taskId: "{scope_challenger_task}", owner: "scope-challenger")
   TaskUpdate(taskId: "{accuracy_arbitrator_task}", owner: "accuracy-arbitrator")
   ```

5. **Wait for Scope Decision**: Wait for accuracy-arbitrator to send the decision via SendMessage.

6. **Shutdown Accuracy Scope Team**:
   ```
   SendMessage(type: "shutdown_request", recipient: "accuracy-advocate", content: "Scope decided.")
   SendMessage(type: "shutdown_request", recipient: "scope-challenger", content: "Scope decided.")
   SendMessage(type: "shutdown_request", recipient: "accuracy-arbitrator", content: "Scope decided.")
   Teammate(operation: "cleanup")
   ```

7. **Display Accuracy Scope Decision**:
   ```
   ## Accuracy Scope (Phase B3 Debate Result)
   Verify: {list}
   Spot-Check: {list}
   Skip: {list with reasons}
   ```

---

Now execute the main accuracy audit using the debate-determined scope:

8. **Cross-Reference Product Claims Against Documentation**:
   For each product capability claim in the draft content:
   - Check against Implementation Tracker feature status
   - Check against Development Spec feature descriptions
   - Check against README current capabilities
   - Flag: claims about in-progress features presented as complete
   - Flag: claims about planned features presented as available
   - Flag: claims that overstate capability scope

9. **Verify Quantitative Claims Against External Data**:
   For each quantitative claim marked for VERIFY or SPOT-CHECK:
   ```
   WebSearch(query: "{specific_claim} {data_source} {current_year}")
   ```
   Cross-reference the result against the claim. Record:
   - Claim text
   - Claimed value
   - Verified value (if found)
   - Source of verification
   - Match status: CONFIRMED, CONTRADICTED, UNVERIFIED, OUTDATED

10. **Check Consistency With All Existing Business Documents**:
    For each claim, check for contradictions across all documents read in Phase B0.5:
    - Product name and description consistency
    - Pricing model consistency
    - Target market description consistency
    - Competitive positioning consistency
    - KPI target consistency
    - Timeline and milestone consistency
    - Terminology consistency

11. **Compile Audit Findings**:
    ```
    === ACCURACY AUDIT RESULTS ===

    PRODUCT CAPABILITY CLAIMS:
    - {claim_1}: {CONFIRMED|OVERCLAIMED|INACCURATE} - {evidence}
    - {claim_2}: {CONFIRMED|OVERCLAIMED|INACCURATE} - {evidence}

    QUANTITATIVE CLAIMS:
    - {claim_1}: {CONFIRMED|CONTRADICTED|UNVERIFIED|OUTDATED} - Source: {source}
    - {claim_2}: {CONFIRMED|CONTRADICTED|UNVERIFIED|OUTDATED} - Source: {source}

    CONSISTENCY ISSUES:
    - {inconsistency_1}: {document_A} says X, {document_B} says Y
    - {inconsistency_2}: {document_A} says X, current content says Y

    FLAGGED ITEMS:
    - Unverifiable claims: {list}
    - Potentially misleading statements: {list}
    - Outdated references: {list}

    === END ACCURACY AUDIT RESULTS ===
    ```

12. **Save Audit Results to Session**:
    ```bash
    echo '${ACCURACY_AUDIT}' > "${SESSION_DIR}/research/accuracy-audit.md"
    ```

13. **Display Audit Summary**:
    ```
    ## Accuracy & Consistency Audit (Phase B3)

    ### Product Capability Claims
    - Checked: {N}
    - Confirmed: {N}
    - Overclaimed: {N}
    - Inaccurate: {N}

    ### Quantitative Claims
    - Checked: {N}
    - Confirmed: {N}
    - Contradicted: {N}
    - Unverified: {N}

    ### Consistency Issues
    - {N} cross-document inconsistencies found

    ### Flagged Items
    - {N} unverifiable claims
    - {N} potentially misleading statements
    ```

14. If `--interactive`: ask user to review flagged items before proceeding.
    ```
    Accuracy audit complete. {N} items flagged. Review flagged items before proceeding? (y/n)
    ```

**Error Handling:**
- If accuracy scope debate fails: default to VERIFY for quantitative claims and product capabilities, SPOT-CHECK for everything else.
- If WebSearch verification fails for a claim: mark as UNVERIFIED and continue.
- If project documentation is insufficient for cross-reference: note as "insufficient documentation" and flag the claim for manual review.
- If all accuracy checks fail: warn "Accuracy audit could not be completed - proceeding with available data." Set `accuracy_audit_available = false` for downstream phases.

---

## Phase B4: Business Model Benchmarking (comprehensive intensity only)

**Applies to**: comprehensive intensity only. Skip for quick, standard, deep. Can be forced with `--force-benchmark`.

**Purpose**: Benchmark Claude, Codex, and Gemini on planted-error business documents to determine which model is best at catching each category of business content issues. Results drive model role assignments in Phase B6 — the highest-scoring model for each category becomes the Round 1 primary reviewer for that category.

**Steps:**

1. **Check benchmark cache**:
   ```bash
   BENCHMARK_CACHE=$("${SCRIPTS_DIR}/cache-manager.sh" read "${PROJECT_ROOT}" "benchmarks" "business-model-scores" 2>/dev/null)
   ```
   Cache TTL: 14 days (from `config.cache.ttl_overrides.benchmarks`).

2. **Run benchmarks if cache miss or stale**:
   ```bash
   BENCHMARK_RESULTS=$(bash "${SCRIPTS_DIR}/benchmark-business-models.sh" \
     --category all \
     --models "codex,gemini,claude" \
     --config "${DEFAULT_CONFIG}")
   ```

3. **Handle Claude benchmarks** (Claude cannot be called via CLI):

   The script outputs `claude_benchmark_needed: true` with test cases. For each test case:
   ```
   Task(
     subagent_type: "general-purpose",
     prompt: "You are a business content reviewer specializing in {category}.
     Review this content and return findings JSON.

     CONTENT:
     {test_case_content}

     Return JSON: {model: 'claude', role: '{category}', findings: [{severity, confidence, section, title, category, description, suggestion}]}"
   )
   ```

   Score Claude findings against ground_truth using the same matching algorithm as the script (section match + keyword majority). Compute F1 per test case, average per category.

4. **Parse results and determine model role assignments**:

   ```
   FOR each review category (accuracy, audience, positioning, clarity, evidence):
     scores = {
       claude: benchmark_results.scores.claude[category],
       codex: benchmark_results.scores.codex[category],
       gemini: benchmark_results.scores.gemini[category]
     }

     best_model = model with highest score
     min_score = config.business_benchmarks.min_score_for_role (default: 60)

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
     "audience": { "primary": "claude|codex|gemini", "cross_reviewers": ["codex", "gemini"] },
     "positioning": { "primary": "claude|codex|gemini", "cross_reviewers": ["codex", "gemini"] },
     "clarity": { "primary": "claude|codex|gemini", "cross_reviewers": ["codex", "gemini"] },
     "evidence": { "primary": "claude|codex|gemini", "cross_reviewers": ["codex", "gemini"] }
   }
   ```

6. **Display benchmark results**:
   ```
   BUSINESS MODEL BENCHMARK RESULTS
   | Category     | Claude | Codex | Gemini | Primary Reviewer |
   |-------------|--------|-------|--------|-----------------|
   | accuracy     | {f1}   | {f1}  | {f1}   | {best_model}    |
   | audience     | {f1}   | {f1}  | {f1}   | {best_model}    |
   | positioning  | {f1}   | {f1}  | {f1}   | {best_model}    |
   | clarity      | {f1}   | {f1}  | {f1}   | {best_model}    |
   | evidence     | {f1}   | {f1}  | {f1}   | {best_model}    |
   ```

7. **Cache results**:
   ```bash
   echo '${BENCHMARK_RESULTS}' | "${SCRIPTS_DIR}/cache-manager.sh" write "${PROJECT_ROOT}" "benchmarks" "business-model-scores" 2>/dev/null
   ```

**Error Handling:**
- If benchmark script fails: use default assignments (Claude primary for all, externals as cross-reviewers). Set `FALLBACK_LEVEL = max(FALLBACK_LEVEL, 1)`.
- If one external model fails benchmarking: exclude that model, use remaining models.
- If Claude benchmark Task fails: use score of 70 (assumed baseline) for Claude in that category.

---

## Phase B5.5: Content Strategy Debate (standard/deep/comprehensive intensity)

**Applies to**: standard, deep, comprehensive intensity. Skip for quick.

**Purpose**: Before creating or finalizing content, debate the best content strategy. Prevents costly rewrites by catching messaging issues, audience mismatches, and unsupported claims before the content is finalized.

**Steps:**

1. **Create Strategy Team**:
   ```
   Teammate(
     operation: "spawnTeam",
     team_name: "biz-strategy-decision-{YYYYMMDD-HHMMSS}",
     description: "Business content strategy debate"
   )
   ```

2. **Prepare Context**: Compile all information gathered so far:
   - User's original request and task description
   - Business Context Brief (Phase B0.5)
   - Market/Industry Context (Phase B1)
   - Content Best Practices (Phase B2, if executed)
   - Accuracy Audit Results (Phase B3, if executed)
   - Content type, target audience, and tone settings

3. **Create Strategy Tasks**:
   ```
   TaskCreate(
     subject: "Propose messaging strategy",
     description: "Propose the best messaging strategy for this business content. Include key themes, value proposition framing, content structure, and tone guidelines. Use all available context from business analysis, market research, and best practices.",
     activeForm: "Proposing messaging strategy"
   )

   TaskCreate(
     subject: "Challenge audience fit of messaging",
     description: "Challenge whether the proposed messaging fits the target audience. Evaluate tone appropriateness, complexity level, information hierarchy, and persuasion approach for this specific audience.",
     activeForm: "Challenging audience fit"
   )

   TaskCreate(
     subject: "Challenge factual accuracy of messaging",
     description: "Challenge the factual claims, unsupported assertions, and potential overclaims in the proposed messaging strategy. Cross-reference against business context and accuracy audit results.",
     activeForm: "Challenging factual accuracy"
   )

   TaskCreate(
     subject: "Arbitrate content strategy",
     description: "Wait for the messaging proposal and both challenges. Synthesize the best content strategy incorporating all perspectives. Output the final strategy with key messages, tone guidelines, structure, and success criteria. Send to team lead.",
     activeForm: "Arbitrating content strategy"
   )
   ```

4. **Spawn Strategy Agents** (all in parallel):
   ```
   Task(
     subagent_type: "general-purpose",
     team_name: "biz-strategy-decision-{session}",
     name: "messaging-advocate",
     prompt: "You are the Messaging Advocate. Propose the best content strategy for this business content.

     REQUEST: {user_request}
     CONTENT TYPE: {type}
     AUDIENCE: {audience}
     TONE: {tone}
     BUSINESS CONTEXT: {business_context_brief}
     MARKET CONTEXT: {market_context_summary}
     BEST PRACTICES: {best_practices_brief_if_available}
     ACCURACY AUDIT: {accuracy_audit_if_available}

     Propose:
     1. Key Messages: The 3-5 core messages this content should convey
     2. Value Proposition Framing: How to frame the value proposition for this audience
     3. Content Structure: Recommended outline and section ordering
     4. Tone & Voice: Specific tone guidelines aligned with brand voice and audience expectations
     5. Evidence Strategy: Which data points, case studies, or references to include
     6. Call to Action: What the audience should do after reading

     Consider:
     - What does the audience care about most?
     - What objections will they have?
     - What competing messages are they hearing from competitors?
     - What is the strongest evidence available to support key claims?

     Send your proposal to strategy-arbitrator via SendMessage.
     Engage with challenges from other agents."
   )

   Task(
     subagent_type: "general-purpose",
     team_name: "biz-strategy-decision-{session}",
     name: "audience-challenger",
     prompt: "You are the Audience Challenger. Challenge the proposed messaging for audience fit.

     REQUEST: {user_request}
     CONTENT TYPE: {type}
     AUDIENCE: {audience}
     TONE: {tone}
     BUSINESS CONTEXT: {business_context_brief}

     Wait for messaging-advocate's proposal, then:
     1. Challenge tone mismatches: Is the proposed tone appropriate for {audience}?
     2. Challenge complexity: Is the jargon level right? Are concepts explained at the right depth?
     3. Challenge information hierarchy: Is the most important info for this audience first?
     4. Challenge relevance: Does the messaging address what {audience} actually cares about?
     5. Challenge persuasion approach: Is the persuasion technique right for {audience}?
     6. Suggest audience-specific improvements

     Send challenges to strategy-arbitrator via SendMessage.
     Engage in debate with messaging-advocate."
   )

   Task(
     subagent_type: "general-purpose",
     team_name: "biz-strategy-decision-{session}",
     name: "accuracy-challenger",
     prompt: "You are the Accuracy Challenger. Challenge the proposed messaging for factual accuracy.

     REQUEST: {user_request}
     CONTENT TYPE: {type}
     BUSINESS CONTEXT: {business_context_brief}
     ACCURACY AUDIT: {accuracy_audit_if_available}

     Wait for messaging-advocate's proposal, then:
     1. Challenge unsupported claims: Which proposed messages make claims without evidence?
     2. Challenge overclaims: Does the messaging overstate product capabilities?
     3. Challenge competitive claims: Are comparisons fair and defensible?
     4. Challenge quantitative assertions: Are numbers accurate and sourced?
     5. Challenge forward-looking statements: Are projections clearly marked as such?
     6. Flag claims that require evidence before they can be included

     Send challenges to strategy-arbitrator via SendMessage.
     Engage in debate with messaging-advocate."
   )

   Task(
     subagent_type: "general-purpose",
     team_name: "biz-strategy-decision-{session}",
     name: "strategy-arbitrator",
     prompt: "You are the Strategy Arbitrator. Synthesize the best content strategy.

     Wait for:
     1. messaging-advocate's proposal (messaging strategy)
     2. audience-challenger's challenges (audience fit)
     3. accuracy-challenger's challenges (factual accuracy)

     Then:
     1. Weigh each position on its merits
     2. Resolve conflicts between messaging impact and factual accuracy
     3. Ensure the final strategy fits the target audience ({audience})
     4. Ensure the tone matches the requested tone ({tone}) and brand voice
     5. Produce a concrete content strategy

     Send your decision to the team lead via SendMessage in this EXACT format:
     CONTENT_STRATEGY:
     Key Messages:
     1. {core_message_1}
     2. {core_message_2}
     3. {core_message_3}
     Tone & Voice: {specific_guidelines}
     Structure: {recommended_outline}
     Claims Requiring Evidence:
     - {claim_1}: {evidence_needed}
     - {claim_2}: {evidence_needed}
     Success Criteria:
     1. {criterion_1} -> verify: {how_to_check}
     2. {criterion_2} -> verify: {how_to_check}
     3. {criterion_3} -> verify: {how_to_check}
     4. {criterion_4} -> verify: {how_to_check}
     5. {criterion_5} -> verify: {how_to_check}

     IMPORTANT: Success Criteria must be concrete and verifiable.
     Good: 'All market size claims cite a published source -> verify: each TAM/SAM figure has a citation'
     Bad: 'Content is well-written and persuasive' (not verifiable)"
   )
   ```

5. **Assign Tasks**:
   ```
   TaskUpdate(taskId: "{messaging_task}", owner: "messaging-advocate")
   TaskUpdate(taskId: "{audience_task}", owner: "audience-challenger")
   TaskUpdate(taskId: "{accuracy_task}", owner: "accuracy-challenger")
   TaskUpdate(taskId: "{arbitrator_task}", owner: "strategy-arbitrator")
   ```

6. **Wait for Strategy Decision**: Wait for strategy-arbitrator to send the final strategy via SendMessage.

7. **Shutdown Strategy Team**:
   ```
   SendMessage(type: "shutdown_request", recipient: "messaging-advocate", content: "Strategy decided.")
   SendMessage(type: "shutdown_request", recipient: "audience-challenger", content: "Strategy decided.")
   SendMessage(type: "shutdown_request", recipient: "accuracy-challenger", content: "Strategy decided.")
   SendMessage(type: "shutdown_request", recipient: "strategy-arbitrator", content: "Strategy decided.")
   Teammate(operation: "cleanup")
   ```

8. **Apply Strategy**: Use the arbitrator's decision as the content creation/revision plan. Pass it as context to Phase B6 reviewers so they can verify the content follows the agreed strategy. **Pass Success Criteria to Phase B7 for post-content verification.**

9. **Implement**: Execute the content creation or revision following the decided strategy. Apply brand voice from Phase B0.5. Use market context from Phase B1. Incorporate best practices from Phase B2 (if available). Respect accuracy audit findings from Phase B3 (if available). **Only include claims listed in the strategy. If additional claims are needed, document the deviation.**

10. **Display Strategy Decision**:
    ```
    ## Content Strategy (Phase B5.5 Debate Result)
    - Key Messages: {messages}
    - Tone & Voice: {guidelines}
    - Structure: {outline}
    - Claims Requiring Evidence: {list}
    - Success Criteria:
      1. {criterion_1} -> verify: {check}
      2. {criterion_2} -> verify: {check}
      3. {criterion_3} -> verify: {check}
    ```

**Error Handling:**
- If Agent Teams are unavailable: fall back to Claude solo strategy with explicit reasoning.
- If debate times out: use messaging-advocate's initial proposal with accuracy-challenger's concerns noted.
- If no consensus: err on the side of accuracy (accuracy-challenger's position takes precedence on factual matters).

---

## Phase B6: Multi-Agent Business Review (standard/deep/comprehensive intensity)

> **Feedback Routing**: If `feedback.use_for_routing` is true, read `${PLUGIN_DIR}/shared-phases/feedback-routing.md` and apply feedback-based model-category role assignments before spawning reviewers.

This phase deploys 5 specialized business reviewer teammates plus a debate arbitrator, with optional external CLI models (Codex, Gemini), to perform a comprehensive multi-perspective review of the business content. Each reviewer examines the content from their domain expertise, then they cross-review each other's findings in a structured 3-round debate. External models participate as either Round 1 primary reviewers (if benchmark-assigned at comprehensive intensity) or Round 2 cross-reviewers (default at standard/deep).

### Step B6.1: Create Agent Team

Create a new Agent Team for this business review session:

```
Teammate(
  operation: "spawnTeam",
  team_name: "biz-review-{YYYYMMDD-HHMMSS}",
  description: "AI Review Arena - Business content review session"
)
```

### Step B6.1.5: Determine External Model Participation

Determine which external models (Codex, Gemini) will participate and in what role, based on intensity and benchmark results.

**Role Assignment Logic:**

```
IF intensity == "comprehensive" AND Phase B4 benchmark results exist:
  Load role assignments from "${SESSION_DIR}/benchmark-role-assignments.json"

  FOR each review category (accuracy, audience, positioning, clarity, evidence):
    IF role_assignments[category].primary is an external model:
      Mark that external model as Round 1 PRIMARY for this category
      The corresponding Claude reviewer still participates but with CROSS-REVIEWER role
    ELSE:
      External models participate as Round 2 cross-reviewers only (default)

ELIF intensity in ["standard", "deep"]:
  # No benchmarking data available — all external models are Round 2 cross-reviewers only
  FOR each available external model (codex, gemini):
    IF config.models[model].enabled AND CLI is available:
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
    "primary_categories": ["accuracy", ...] or [],  // only at comprehensive with benchmark
    "cross_review_categories": ["audience", ...] or ["all"]
  },
  "gemini": {
    "available": true|false,
    "role": "round1_primary|round2_cross|none",
    "primary_categories": [...] or [],
    "cross_review_categories": [...] or ["all"]
  }
}
```

### Step B6.2: Create Review Tasks

Create tasks in the shared task list for each of the 5 business reviewers:

```
TaskCreate(
  subject: "Domain accuracy review of business content",
  description: "Review the business content for domain accuracy. Validate all product claims, market data, quantitative assertions, regulatory statements, and cross-document consistency. Send findings to team lead via SendMessage when complete.",
  activeForm: "Reviewing domain accuracy"
)

TaskCreate(
  subject: "Audience fit review of business content",
  description: "Review the business content for audience fit. Evaluate tone, complexity, relevance, information hierarchy, and cultural appropriateness for the target audience. Send findings to team lead via SendMessage when complete.",
  activeForm: "Reviewing audience fit"
)

TaskCreate(
  subject: "Competitive positioning review of business content",
  description: "Review the business content for competitive positioning. Evaluate differentiation claims, market positioning accuracy, competitor awareness, defensibility assertions, and value proposition clarity. Send findings to team lead via SendMessage when complete.",
  activeForm: "Reviewing competitive positioning"
)

TaskCreate(
  subject: "Communication clarity review of business content",
  description: "Review the business content for communication clarity. Evaluate structure, flow, clarity, persuasiveness, consistency, and writing quality. Send findings to team lead via SendMessage when complete.",
  activeForm: "Reviewing communication clarity"
)

TaskCreate(
  subject: "Data and evidence review of business content",
  description: "Review the business content for data and evidence quality. Validate statistical claims, source quality, projection methodology, KPI relevance, and data presentation accuracy. Send findings to team lead via SendMessage when complete.",
  activeForm: "Reviewing data and evidence"
)
```

### Step B6.3: Spawn Business Reviewer Teammates + External CLI Round 1

For each reviewer in REVIEWER_ROLES, read the agent definition file and spawn a teammate with ENRICHED business context. **Spawn ALL reviewers + arbitrator in parallel** by making multiple Task tool calls in a single message.

**External CLI Round 1 (if assigned as primary):**

If any external model was assigned as Round 1 primary for a category in Step B6.1.5, run the corresponding CLI script **in parallel** with Claude teammate spawning:

```bash
# For each external model assigned as Round 1 primary:
IF EXTERNAL_PARTICIPATION.codex.role == "round1_primary":
  FOR category IN EXTERNAL_PARTICIPATION.codex.primary_categories:
    echo "$BUSINESS_CONTENT_WITH_CONTEXT" | \
      "${SCRIPTS_DIR}/codex-business-review.sh" "${DEFAULT_CONFIG}" --mode round1 --category "$category" \
      > "${SESSION_DIR}/findings/round1-codex-${category}.json" 2>/dev/null &

IF EXTERNAL_PARTICIPATION.gemini.role == "round1_primary":
  FOR category IN EXTERNAL_PARTICIPATION.gemini.primary_categories:
    echo "$BUSINESS_CONTENT_WITH_CONTEXT" | \
      "${SCRIPTS_DIR}/gemini-business-review.sh" "${DEFAULT_CONFIG}" --mode round1 --category "$category" \
      > "${SESSION_DIR}/findings/round1-gemini-${category}.json" 2>/dev/null &
```

Where `$BUSINESS_CONTENT_WITH_CONTEXT` includes the business content plus enriched context (market data, best practices, accuracy audit if available). Wait for external CLIs to complete alongside Claude teammates.

**Merging external Round 1 results**: After external CLI Round 1 completes, parse the JSON output and merge into the findings aggregation alongside Claude reviewer results. Each external finding follows the same schema: `{model, role, mode, findings: [{severity, confidence, section, title, category, description, suggestion}]}`.

**NOTE**: When an external model is Round 1 primary for a category, the corresponding Claude reviewer for that category still runs independently. Both sets of findings are included in Round 2 cross-review and debate. This provides redundancy — if the external CLI fails, the Claude reviewer's findings are still available.

Read REVIEWER_ROLES from config business_intensity_presets.{INTENSITY}.reviewer_roles.
Fallback if missing: ["accuracy-evidence-reviewer", "audience-fit-reviewer", "communication-narrative-reviewer", "competitive-positioning-reviewer", "market-fit-reviewer"]

For each role in REVIEWER_ROLES:

1. Read the agent definition:
   ```
   Read(file_path: "${AGENTS_DIR}/{role}.md")
   ```

2. Spawn as teammate with ENRICHED context:
   ```
   Task(
     subagent_type: "general-purpose",
     team_name: "biz-review-{session_id}",
     name: "{role}",
     prompt: "{contents of agents/{role}.md}

     --- REVIEW TASK ---
     Task ID: {task_id}
     Content Type: {type}
     Target Audience: {audience}
     Tone: {tone}

     === ENRICHED CONTEXT (from Arena Business Lifecycle) ===

     BUSINESS CONTEXT BRIEF:
     {business_context_brief_from_phase_b0_5}

     MARKET CONTEXT:
     {market_context_summary_from_phase_b1}

     BEST PRACTICES:
     {best_practices_brief_from_phase_b2_if_available}

     ACCURACY AUDIT:
     {accuracy_audit_results_from_phase_b3_if_available}

     CONTENT STRATEGY:
     {content_strategy_from_phase_b5_5}

     === END ENRICHED CONTEXT ===

     CONTENT TO REVIEW:
     {the_business_content_being_reviewed}
     --- END CONTENT ---

     INSTRUCTIONS:
     1. Review the content above following your agent instructions
     2. USE the enriched context to inform your review
     3. Send your findings JSON to the team lead using SendMessage
     4. Mark your task as completed using TaskUpdate
     5. Stay active for the 3-round debate:
        Round 2: You will receive other reviewers' findings and provide challenge/support responses
        Round 3: You will defend your challenged findings or withdraw/revise them"
   )
   ```

**CRITICAL: Launch ALL reviewers simultaneously.** Use multiple Task tool calls in a single message to maximize parallelism. Do NOT wait for one teammate to finish before spawning the next.

**Spawn business-debate-arbitrator:**
```
Read(file_path: "${AGENTS_DIR}/business-debate-arbitrator.md")

Task(
  subagent_type: "general-purpose",
  team_name: "biz-review-{session_id}",
  name: "business-debate-arbitrator",
  prompt: "{contents of agents/business-debate-arbitrator.md}

  --- DEBATE CONTEXT ---
  Session: {session_id}
  Content Type: {type}
  Target Audience: {audience}
  Active reviewers: {REVIEWER_ROLES list — the roles spawned for this session}
  Cross-review rounds: 3

  CONTENT STRATEGY (from Phase B5.5):
  {content_strategy_from_phase_b5_5}

  You will receive:
  1. Round 1 findings from all reviewers (forwarded by team lead)
  2. Round 2 cross-review responses from all 5 reviewers (sent directly to you)
  3. A 'ROUND 2 COMPLETE' signal from the team lead
  4. Round 3 defense responses from reviewers whose findings were challenged
  5. A 'ROUND 3 COMPLETE' signal from the team lead

  After Round 3 completes, apply the consensus algorithm (including defense data) and send the final consensus JSON to the team lead.
  --- END CONTEXT ---"
)
```

**CRITICAL: Launch ALL 5 reviewers + arbitrator simultaneously.** Use multiple Task tool calls in a single message to maximize parallelism. Do NOT wait for one teammate to finish before spawning the next.

### Step B6.4: Assign Tasks to Teammates

After spawning, assign each task to its corresponding teammate:

```
TaskUpdate(taskId: "{accuracy_task_id}", owner: "accuracy-evidence-reviewer")
TaskUpdate(taskId: "{audience_task_id}", owner: "audience-fit-reviewer")
TaskUpdate(taskId: "{positioning_task_id}", owner: "competitive-positioning-reviewer")
TaskUpdate(taskId: "{narrative_task_id}", owner: "communication-narrative-reviewer")
TaskUpdate(taskId: "{market_fit_task_id}", owner: "market-fit-reviewer")
```

### Step B6.5: Collect Round 1 Results

Wait for all 5 reviewers to send their findings via SendMessage. Messages are delivered to you (the team lead) as they complete. Wait for all active reviewer teammates to report.

For each reviewer, expect:
- accuracy-evidence-reviewer: findings JSON with accuracy issues
- audience-fit-reviewer: findings JSON with audience fit issues + audience_scorecard
- competitive-positioning-reviewer: findings JSON with positioning issues + positioning_scorecard
- communication-narrative-reviewer: findings JSON with clarity issues + narrative_scorecard
- market-fit-reviewer: findings JSON with evidence issues + market_fit_scorecard

Parse and validate all findings. Skip invalid JSON with a warning.

### Step B6.6: Findings Aggregation

Merge and deduplicate findings from all 5 reviewers:

1. **Combine all findings**: Collect findings from all 5 reviewer SendMessage responses.

2. **Deduplicate**:
   - Group by section + category (within same section AND similar issue category)
   - Cross-validated findings (same section flagged by 2+ reviewers): average confidence + 10% boost
   - Keep most detailed description, note which reviewers agreed
   - Merge suggestions: take the most specific and actionable remediation

3. **Filter by confidence threshold**: Use `review.confidence_threshold` from config (default: 40 for business content).

4. **Sort**: severity (critical > high > medium > low) > confidence > section

5. **Display intermediate results**:
   ```
   ## Findings Summary (Pre-Debate)
   - Total findings: {N}
   - By severity: {X} critical, {Y} high, {Z} medium, {W} low
   - By category: Accuracy: {A}, Audience: {B}, Positioning: {C}, Narrative: {D}, Market Fit: {E}
   - Cross-validated: {M} findings confirmed by 2+ reviewers
   ```

6. **Forward aggregated findings to business-debate-arbitrator**:
   ```
   SendMessage(
     type: "message",
     recipient: "business-debate-arbitrator",
     content: "ROUND 1 AGGREGATED FINDINGS:
     {aggregated_findings_json}

     ROUND 1 FINDINGS BY REVIEWER:
     accuracy-evidence-reviewer: {accuracy_findings_json}
     audience-fit-reviewer: {audience_findings_json}
     competitive-positioning-reviewer: {positioning_findings_json}
     communication-narrative-reviewer: {narrative_findings_json}
     market-fit-reviewer: {market_fit_findings_json}",
     summary: "Round 1 complete - {N} total findings from 5 reviewers"
   )
   ```

### Step B6.7: 3-Round Debate

**Round 1**: Independent review (already completed in Steps B6.3-B6.5).

**Round 2**: Cross-review -- each reviewer evaluates other reviewers' findings.

Send each reviewer the OTHER four reviewers' findings:

**Send to accuracy-evidence-reviewer:**
```
SendMessage(
  type: "message",
  recipient: "accuracy-evidence-reviewer",
  content: "CROSS-REVIEW -- Round 2 of 3

  Evaluate findings from the other 4 business reviewers from your ACCURACY expertise perspective.

  AUDIENCE-FIT-REVIEWER FINDINGS:
  {audience_findings_json}

  COMPETITIVE-POSITIONING-REVIEWER FINDINGS:
  {positioning_findings_json}

  COMMUNICATION-CLARITY-REVIEWER FINDINGS:
  {narrative_findings_json}

  DATA-EVIDENCE-REVIEWER FINDINGS:
  {market_fit_findings_json}

  For EACH finding relevant to your domain:
  1. SUPPORT if the finding is valid from an accuracy perspective -- cite corroborating evidence, confidence_adjustment (+N)
  2. CHALLENGE if the finding is incorrect or misrepresents the product -- cite counter-evidence, confidence_adjustment (-N)

  You may add NEW OBSERVATIONS that other reviewers missed from your accuracy perspective.

  Send each response to business-debate-arbitrator via SendMessage as JSON:
  {\"finding_id\":\"<section:title>\", \"action\":\"challenge|support\", \"confidence_adjustment\":-20 to +20, \"reasoning\":\"<detailed reasoning>\", \"evidence\":\"<evidence>\"}

  When done: send 'accuracy-evidence-reviewer debate evaluation complete' to business-debate-arbitrator.",
  summary: "Round 2: cross-review other reviewers' findings"
)
```

**Send to audience-fit-reviewer:**
```
SendMessage(
  type: "message",
  recipient: "audience-fit-reviewer",
  content: "CROSS-REVIEW -- Round 2 of 3

  Evaluate findings from the other 4 business reviewers from your AUDIENCE FIT expertise perspective.

  DOMAIN-ACCURACY-REVIEWER FINDINGS:
  {accuracy_findings_json}

  COMPETITIVE-POSITIONING-REVIEWER FINDINGS:
  {positioning_findings_json}

  COMMUNICATION-CLARITY-REVIEWER FINDINGS:
  {narrative_findings_json}

  DATA-EVIDENCE-REVIEWER FINDINGS:
  {market_fit_findings_json}

  For EACH finding relevant to your domain:
  1. SUPPORT if the finding matters for audience reception -- cite audience impact, confidence_adjustment (+N)
  2. CHALLENGE if the finding would not affect this audience -- cite audience context, confidence_adjustment (-N)

  You may add NEW OBSERVATIONS that other reviewers missed from your audience expertise.

  Send each response to business-debate-arbitrator via SendMessage as JSON:
  {\"finding_id\":\"<section:title>\", \"action\":\"challenge|support\", \"confidence_adjustment\":-20 to +20, \"reasoning\":\"<detailed reasoning>\", \"evidence\":\"<evidence>\"}

  When done: send 'audience-fit-reviewer debate evaluation complete' to business-debate-arbitrator.",
  summary: "Round 2: cross-review other reviewers' findings"
)
```

**Send to competitive-positioning-reviewer:**
```
SendMessage(
  type: "message",
  recipient: "competitive-positioning-reviewer",
  content: "CROSS-REVIEW -- Round 2 of 3

  Evaluate findings from the other 4 business reviewers from your COMPETITIVE POSITIONING expertise perspective.

  DOMAIN-ACCURACY-REVIEWER FINDINGS:
  {accuracy_findings_json}

  AUDIENCE-FIT-REVIEWER FINDINGS:
  {audience_findings_json}

  COMMUNICATION-CLARITY-REVIEWER FINDINGS:
  {narrative_findings_json}

  DATA-EVIDENCE-REVIEWER FINDINGS:
  {market_fit_findings_json}

  For EACH finding relevant to your domain:
  1. SUPPORT if the finding has competitive implications -- cite market context, confidence_adjustment (+N)
  2. CHALLENGE if the finding misreads the competitive landscape -- cite competitor data, confidence_adjustment (-N)

  You SHOULD use WebSearch to verify competitive claims raised by other reviewers.
  You may add NEW OBSERVATIONS that other reviewers missed from your competitive expertise.

  Send each response to business-debate-arbitrator via SendMessage as JSON:
  {\"finding_id\":\"<section:title>\", \"action\":\"challenge|support\", \"confidence_adjustment\":-20 to +20, \"reasoning\":\"<detailed reasoning>\", \"evidence\":\"<evidence>\"}

  When done: send 'competitive-positioning-reviewer debate evaluation complete' to business-debate-arbitrator.",
  summary: "Round 2: cross-review other reviewers' findings"
)
```

**Send to communication-narrative-reviewer:**
```
SendMessage(
  type: "message",
  recipient: "communication-narrative-reviewer",
  content: "CROSS-REVIEW -- Round 2 of 3

  Evaluate findings from the other 4 business reviewers from your COMMUNICATION & NARRATIVE expertise perspective.

  DOMAIN-ACCURACY-REVIEWER FINDINGS:
  {accuracy_findings_json}

  AUDIENCE-FIT-REVIEWER FINDINGS:
  {audience_findings_json}

  COMPETITIVE-POSITIONING-REVIEWER FINDINGS:
  {positioning_findings_json}

  DATA-EVIDENCE-REVIEWER FINDINGS:
  {market_fit_findings_json}

  For EACH finding relevant to your domain:
  1. SUPPORT if the finding involves a communication or narrative issue -- cite writing standard, confidence_adjustment (+N)
  2. CHALLENGE if the finding conflates content accuracy with narrative quality -- cite distinction, confidence_adjustment (-N)

  You may add NEW OBSERVATIONS that other reviewers missed from your communication and narrative expertise.

  Send each response to business-debate-arbitrator via SendMessage as JSON:
  {\"finding_id\":\"<section:title>\", \"action\":\"challenge|support\", \"confidence_adjustment\":-20 to +20, \"reasoning\":\"<detailed reasoning>\", \"evidence\":\"<evidence>\"}

  When done: send 'communication-narrative-reviewer debate evaluation complete' to business-debate-arbitrator.",
  summary: "Round 2: cross-review other reviewers' findings"
)
```

**Send to market-fit-reviewer:**
```
SendMessage(
  type: "message",
  recipient: "market-fit-reviewer",
  content: "CROSS-REVIEW -- Round 2 of 3

  Evaluate findings from the other 4 business reviewers from your PRODUCT-MARKET FIT expertise perspective.

  DOMAIN-ACCURACY-REVIEWER FINDINGS:
  {accuracy_findings_json}

  AUDIENCE-FIT-REVIEWER FINDINGS:
  {audience_findings_json}

  COMPETITIVE-POSITIONING-REVIEWER FINDINGS:
  {positioning_findings_json}

  COMMUNICATION-CLARITY-REVIEWER FINDINGS:
  {narrative_findings_json}

  For EACH finding relevant to your domain:
  1. SUPPORT if the finding involves a product-market fit issue -- cite verification result, confidence_adjustment (+N)
  2. CHALLENGE if the finding misreads market fit signals or applies wrong methodology -- cite correct interpretation, confidence_adjustment (-N)

  You SHOULD use WebSearch to verify data claims raised by other reviewers.
  You may add NEW OBSERVATIONS that other reviewers missed from your market fit expertise.

  Send each response to business-debate-arbitrator via SendMessage as JSON:
  {\"finding_id\":\"<section:title>\", \"action\":\"challenge|support\", \"confidence_adjustment\":-20 to +20, \"reasoning\":\"<detailed reasoning>\", \"evidence\":\"<evidence>\"}

  When done: send 'market-fit-reviewer debate evaluation complete' to business-debate-arbitrator.",
  summary: "Round 2: cross-review other reviewers' findings"
)
```

**Wait for all Claude Round 2 responses**: All 5 Claude reviewers send their challenge/support responses directly to business-debate-arbitrator via SendMessage. Wait for each reviewer to send their completion message.

**Step B6.7.2: External CLI Cross-Review (Round 2)**

Run external CLI cross-review **in parallel** with Claude Round 2 responses. External models that are NOT assigned as Round 1 primary participate as Round 2 cross-reviewers:

```bash
# Prepare aggregated Round 1 findings for external CLI input
ALL_ROUND1_FINDINGS=$(jq -s '.' "${SESSION_DIR}"/findings/round1-*.json 2>/dev/null)

# Codex Round 2 cross-review (if available and configured as cross-reviewer for any category)
IF config.models.codex.enabled AND codex_available AND codex has cross_review_categories:
  echo "$ALL_ROUND1_FINDINGS" | \
    "${SCRIPTS_DIR}/codex-business-review.sh" "${DEFAULT_CONFIG}" --mode round2 \
    > "${SESSION_DIR}/debate/round2-codex-biz.json" 2>/dev/null &

# Gemini Round 2 cross-review
IF config.models.gemini.enabled AND gemini_available AND gemini has cross_review_categories:
  echo "$ALL_ROUND1_FINDINGS" | \
    "${SCRIPTS_DIR}/gemini-business-review.sh" "${DEFAULT_CONFIG}" --mode round2 \
    > "${SESSION_DIR}/debate/round2-gemini-biz.json" 2>/dev/null &

wait  # Wait for external CLIs (parallel with Claude Round 2)
```

**Merge external Round 2 responses**: Parse external CLI cross-review JSON and forward to business-debate-arbitrator alongside Claude Round 2 data:

```
FOR each external_model_round2_file IN "${SESSION_DIR}/debate/round2-*-biz.json":
  Parse JSON responses
  IF valid AND has responses array:
    Forward to business-debate-arbitrator via SendMessage:
    SendMessage(
      type: "message",
      recipient: "business-debate-arbitrator",
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
  recipient: "business-debate-arbitrator",
  content: "ROUND 2 COMPLETE. All cross-review responses received from all 5 Claude reviewers + {N} external model(s). Hold for Round 3 defense responses.",
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

  Send each response to business-debate-arbitrator via SendMessage as JSON:
  {\"finding_id\":\"<section:title>\", \"action\":\"defend|withdraw|revise\", \"original_severity\":\"<original>\", \"revised_severity\":\"<same or adjusted>\", \"revised_confidence\":0-100, \"defense_reasoning\":\"<why finding should stand, or why revising/withdrawing>\", \"additional_evidence\":\"<new evidence if any>\"}

  When done: send '{reviewer-name} defense round complete' to business-debate-arbitrator.",
  summary: "Round 3: defend your challenged findings"
)
```

**NOTE**: Only send defense requests to Claude reviewers who had at least one finding challenged. Reviewers with zero challenges skip Round 3.

**External model Round 3 defense**: If an external model participated as Round 1 primary and its findings were challenged, the external model **cannot** defend (no interactive CLI capability). In this case:
- The finding receives `defense_status = "implicit_defend"` in the arbitrator
- The finding stands at its post-Round 2 confidence (no recovery)
- The arbitrator should note "external model — no interactive defense capability"

**Wait for all Round 3 responses**: All challenged Claude reviewers send their defend/withdraw/revise responses directly to business-debate-arbitrator via SendMessage. External model findings with challenges use implicit defense.

**Signal Round 3 complete to arbitrator:**
```
SendMessage(
  type: "message",
  recipient: "business-debate-arbitrator",
  content: "ROUND 3 COMPLETE. All defense responses received. Synthesize the final consensus from all 3 rounds.",
  summary: "Round 3 defense complete -- synthesize final consensus"
)
```

### Step B6.8: Collect Consensus

Wait for business-debate-arbitrator to send the final consensus JSON via SendMessage. The consensus includes:

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
- If business-debate-arbitrator fails: collect whatever challenge/support/defense messages were received. Synthesize consensus manually using the aggregated Round 1 findings with Round 2 and Round 3 adjustments.
- If no cross-review responses at all: skip debate rounds 2 and 3, use Round 1 aggregated findings as final results.

---

## Phase B6.5: Apply Findings (Review → Fix Loop)

After the debate consensus is reached, automatically apply fixes for critical and high severity findings.

**Trigger condition**: At least 1 accepted finding with severity `critical` or `high` in the consensus.

**If no critical/high findings**: Skip Phase B6.5, proceed directly to Phase B7.

### Step B6.5.1: Identify Actionable Findings

From the consensus results, extract all accepted findings with severity `critical` or `high`:

```
actionable_findings = consensus.accepted.filter(f =>
  f.severity == "critical" OR f.severity == "high"
)
```

Sort by severity (critical first), then by confidence (descending).

### Step B6.5.2: Auto-Revise Content

For each actionable finding, apply the suggested fix to the content:

```
FOR each finding IN actionable_findings:
  1. Locate the section referenced by finding.section
  2. Apply the finding.suggestion as a content revision
  3. Track the change: {finding_id, original_text, revised_text, applied_suggestion}

  Revision rules:
  - ACCURACY findings: correct factual claims, add caveats, remove unverifiable assertions
  - AUDIENCE-FIT findings: adjust tone, vocabulary, framing for target audience
  - POSITIONING findings: refine competitive claims, strengthen differentiators, remove unsupported comparisons
  - CLARITY findings: restructure sentences, fix ambiguous phrasing, improve logical flow
  - EVIDENCE findings: add citations, qualify unsupported claims, remove or flag unverifiable data
```

### Step B6.5.3: Verify Fixes

After applying all revisions, do a quick self-verification:

```
FOR each applied revision:
  1. Does the revised text address the original finding?
  2. Does the revision maintain consistency with surrounding content?
  3. Does the revision preserve the intended message and tone?
  4. Does the revision not introduce NEW issues?

  IF verification fails for any revision:
    Revert that specific revision and flag it for manual review
```

### Step B6.5.4: Display Applied Changes

```markdown
## Applied Fixes (Phase B6.5)

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

## Phase B7: Final Report & Cleanup

### Step B7.1: Generate Business Review Report

Build the complete business content review report:

```markdown
# AI Review Arena - Business Content Review Report

**Date:** {timestamp}
**Content Type:** {type}
**Target Audience:** {audience}
**Tone:** {tone}
**Intensity:** {intensity_level}
**Mode:** Agent Teams (business content lifecycle with enriched context)

---

## Business Context Summary

{from Phase B0.5 - abbreviated business context brief}

---

## Executive Summary

{key findings from consensus, overall content quality assessment, top 3 priorities for improvement, compliance and accuracy status}

---

## Quality Scorecard

| Category | Score | Key Issues |
|----------|-------|------------|
| Domain Accuracy | {score}% | {brief_summary} |
| Audience Fit | {score}% | {brief_summary} |
| Competitive Positioning | {score}% | {brief_summary} |
| Communication Clarity | {score}% | {brief_summary} |
| Data & Evidence | {score}% | {brief_summary} |
| **Overall** | **{score}%** | |

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
| 1 | {criterion_from_phase_b5_5} | {verification_method} | PASS/FAIL |
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
- By reviewer: Accuracy: {A}, Audience: {B}, Positioning: {C}, Narrative: {D}, Market Fit: {E}

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

## Applied Fixes (Phase B6.5)
- Critical/high findings auto-revised: {N}
- Successfully applied: {N}
- Reverted (manual review needed): {N}

---

## Market Context Reference

{abbreviated market context from Phase B1, for reader reference}

---

## Cost Summary

| Component | Teammates | Est. Tokens | Est. Cost |
|-----------|-----------|-------------|-----------|
| **Phase B0.1: Intensity Decision** | | | |
| Intensity Debate Agents | 4 teammates | ~{X}K | ~${A.AA} |
| **Phase B2: Best Practices Research** | | | |
| Research Direction Debate | {0 or 4} teammates | ~{X}K | ~${B.BB} |
| **Phase B3: Accuracy Audit** | | | |
| Accuracy Scope Debate | {0 or 3} teammates | ~{X}K | ~${C.CC} |
| **Phase B5.5: Content Strategy** | | | |
| Strategy Debate Agents | 4 teammates | ~{X}K | ~${D.DD} |
| **Phase B6: Business Review** | | | |
| accuracy-evidence-reviewer | 1 teammate | ~{X}K | ~${E.EE} |
| audience-fit-reviewer | 1 teammate | ~{X}K | ~${F.FF} |
| competitive-positioning-reviewer | 1 teammate | ~{X}K | ~${G.GG} |
| communication-narrative-reviewer | 1 teammate | ~{X}K | ~${H.HH} |
| market-fit-reviewer | 1 teammate | ~{X}K | ~${I.II} |
| business-debate-arbitrator | 1 teammate | ~{X}K | ~${J.JJ} |
| **Total** | | | **~${K.KK}** |
```

**Output Steps:**
1. Generate report in configured language (`output.language`)
2. Display the formatted report to the user
3. Save report: write to `${SESSION_DIR}/reports/business-review-report.md`
4. If output path was specified in config:
   ```bash
   cp "${SESSION_DIR}/reports/business-review-report.md" "${OUTPUT_PATH}"
   ```

### Step B7.2: Shutdown All Teammates

Send shutdown requests to ALL active teammates. Wait for each confirmation before proceeding.

```
For each role in REVIEWER_ROLES (the roles that were spawned in Phase B6):
  SendMessage(type: "shutdown_request", recipient: "{role}", content: "Business review session complete. Thank you.")
SendMessage(type: "shutdown_request", recipient: "business-debate-arbitrator", content: "Business review session complete. Thank you.")
```

Only send shutdown to teammates that were actually spawned in this session.
Wait for all shutdown confirmations before cleanup.

### Step B7.3: Cleanup Team & Sessions

After ALL teammates have confirmed shutdown:

```
Teammate(operation: "cleanup")
```

Clean up stale session directories from previous runs:
```bash
bash "${SCRIPTS_DIR}/cache-manager.sh" cleanup-sessions --max-age 24
```

**IMPORTANT:** Team cleanup will fail if active teammates still exist. Always shutdown all teammates first.

### Step B7.4: Display Session Reference

```
## Session Complete
- Session directory: ${SESSION_DIR}
- Report: ${SESSION_DIR}/reports/business-review-report.md
- Market Research: ${SESSION_DIR}/research/market-context.md
- Business Context: ${SESSION_DIR}/research/business-context-brief.md
- Best Practices: ${SESSION_DIR}/research/best-practices-brief.md
- Accuracy Audit: ${SESSION_DIR}/research/accuracy-audit.md
- Consensus: ${SESSION_DIR}/findings/consensus.json
```

### Step B7.5: Feedback Collection (Optional)

**Applies when**: `config.feedback.enabled == true` AND `--interactive` mode.

After displaying the report, prompt the user for feedback on the top findings:

```
BUSINESS REVIEW QUALITY FEEDBACK (optional — helps improve future reviews)

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
| 0 | Full Operation | — | All phases, all Agent Teams, full 5-reviewer debate | None |
| 1 | Research Failure | Phase B1 or B2 fails | Proceed without market/research context | "Market context: unavailable" or "Research: unavailable" |
| 1.5 | Benchmark Failure | Phase B4 fails | Use default role assignments (Claude primary for all, externals as cross-reviewers) | "Benchmarks: defaults used" |
| 2 | Accuracy Audit Failure | Phase B3 fails | Skip pre-verification, reviewers work without pre-audited claims | "Accuracy: not pre-audited" |
| 2.5 | External CLI Failure | Codex/Gemini CLI fails | Proceed with Claude reviewers only | "External models: unavailable" |
| 3 | Agent Teams Failure | Teammate spawn fails | Fall back to Task subagents (no debate, sequential) | "Mode: subagent (no debate)" |
| 4 | All Failure | Agent Teams AND subagents fail | Claude solo inline analysis with self-review checklist | "Mode: solo inline" |

### Per-Phase Fallback Rules

| Phase | On Failure | Fallback Behavior | Level Escalation |
|-------|-----------|-------------------|-----------------|
| Phase B0.5 (Context) | Glob/Read fails | Use minimal context from user request only | Stay at current level |
| Phase B1 (Market) | WebSearch fails or timeout | Skip market context, warn reviewers | Escalate to Level 1 |
| Phase B2 (Research) | Debate or WebSearch fails | Skip best practices, note in report | Escalate to Level 1 if not already |
| Phase B3 (Accuracy) | Audit debate fails | Skip pre-verification | Escalate to Level 2 |
| Phase B4 (Benchmark) | Script or Claude scoring fails | Use default role assignments | Escalate to Level 1.5 |
| Phase B5.5 (Strategy) | Strategy debate agents fail | Skip strategy, proceed to review | Stay at current level |
| Phase B6 (External CLI) | Codex/Gemini CLI fails | Proceed with Claude reviewers only | Escalate to Level 2.5 |
| Phase B6 (Review) | Teammate spawn fails | Try Task subagents; if that fails, solo | Escalate to Level 3 or 4 |
| Phase B6 (Debate) | Arbitrator fails | Manual consensus from available responses | Stay at current level |
| Phase B6.5 (Auto-Fix) | Fix verification fails | Revert all fixes, flag for manual review | Stay at current level |

### Teammate Error Recovery

- **Teammate stops unexpectedly**: Check TaskList for incomplete tasks. Spawn replacement if total active < minimum required (3 reviewers minimum for valid debate).
- **Teammate not responding**: Send follow-up message. Wait 60s. If still no response, mark as failed and proceed with other teammates.
- **business-debate-arbitrator fails**: Collect available challenge/support messages. Synthesize consensus manually: group by section+category, apply confidence adjustments, sort by severity then confidence.
- **JSON Parse Errors**: Attempt extraction via regex (first-`{`-to-last-`}`). If fails, discard and continue.

### Self-Review Checklist (Level 4 Fallback)

When all review infrastructure fails, apply this self-review checklist:
```
Self-Review Checklist (Fallback Mode):
- Consistent with project documentation
- Matches existing brand voice/tone
- Claims align with actual product capabilities
- Target audience appropriate
- No factual errors detected
- Competitive positioning reasonable
- Data claims appear supported
- Communication is clear and well-structured
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
| Context Available | {list: business_context ✓, market ✗, research ✓, accuracy ✗, ...} |

### Fallback Log
{FALLBACK_LOG entries with timestamps}
```

IF FALLBACK_LEVEL >= 3:
  Add prominent warning at top of report:
  "This review ran at degraded capacity (Level {N}). Results may be less comprehensive than a full review."
