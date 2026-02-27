---
description: "Multi-AI adversarial code review with Claude Agent Teams, Codex, and Gemini"
argument-hint: "[scope] [--intensity quick|standard|deep|comprehensive] [--focus security,bugs,...] [--models claude,codex,gemini] [--no-debate] [--interactive] [--pr <number>]"
allowed-tools: [Bash, Glob, Grep, Read, Task, WebSearch, WebFetch, Teammate, SendMessage, TaskCreate, TaskUpdate, TaskList, TaskGet]
---

# Multi-AI Adversarial Code Review (Agent Teams)

You are the **team lead** for a multi-AI adversarial code review system using Claude Code Agent Teams. You spawn Claude reviewer teammates as independent Claude Code instances that communicate directly with each other via SendMessage during the adversarial debate phase. Codex and Gemini participate via external CLI tools.

## Architecture

```
Team Lead (You - this session)
├── Create team (Teammate tool)
├── Spawn reviewer teammates (Task tool with team_name)
├── Run external CLIs (Codex, Gemini via Bash)
├── Coordinate debate phase
├── Aggregate findings & generate report
└── Shutdown teammates & cleanup team

Claude Reviewer Teammates (dynamic, from config intensity_presets.{INTENSITY}.reviewer_roles)
├── {role-1}             ─┐
├── {role-2}             ─┤── SendMessage ⇄ each other (debate)
├── {role-3}             ─┤── SendMessage → debate-arbitrator
├── {role-N}             ─┘── SendMessage → team lead (findings)

Debate Arbitrator (teammate)
└── Receives challenges/supports → synthesizes consensus → reports to lead

External CLIs (via Bash, not teammates)
├── Codex CLI → JSON findings
└── Gemini CLI → JSON findings
```

## Constants

```
PLUGIN_DIR="~/.claude/plugins/ai-review-arena"
SCRIPTS_DIR="${PLUGIN_DIR}/scripts"
CONFIG_DIR="${PLUGIN_DIR}/config"
DEFAULT_CONFIG="${CONFIG_DIR}/default-config.json"
AGENTS_DIR="${PLUGIN_DIR}/agents"
SESSION_DIR="/tmp/ai-review-arena/$(date +%Y%m%d-%H%M%S)"
```

## Phase 1: Scope Resolution

Parse the user's arguments to determine what code to review.

**Argument Parsing Rules:**
- No arguments: use `git diff --staged` (if staged changes exist) or `git diff HEAD` (unstaged changes)
- `--pr <number>`: use `gh pr diff <number>` to get the PR diff
- Specific file paths: review those files directly
- Directory path: review all changed files under that directory

**Steps:**
1. Parse all arguments from `$ARGUMENTS`:
   - Extract `--intensity` value (default: from config `review.intensity`)
   - Extract `--focus` comma-separated values (default: from config `review.focus_areas`)
   - Extract `--models` comma-separated values (default: all enabled models)
   - Check for `--no-debate` flag
   - Check for `--interactive` flag
   - Extract `--pr <number>` if present
   - Remaining arguments are treated as file/directory paths

2. Resolve the diff/files to review:
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

   # For specific files:
   # Read each file directly
   ```

3. List all changed files with line counts:
   ```bash
   grep '^diff --git' "${SESSION_DIR}/diff.patch" | sed 's|diff --git a/\(.*\) b/.*|\1|'
   ```

4. Filter files based on config:
   - Only include files matching `review.file_extensions`
   - Exclude files matching `review.exclude_patterns`
   - Skip files exceeding `max_file_lines` (from intensity preset)

5. If no reviewable files found, report and exit early.

6. Create session directory:
   ```bash
   mkdir -p "${SESSION_DIR}/findings" "${SESSION_DIR}/debate" "${SESSION_DIR}/reports"
   ```

Display the scope summary: number of files, total lines, which models will participate.

## Phase 2: Configuration

Load and merge configuration from multiple sources.

**Config Resolution Order (later overrides earlier):**
1. Default config: `${DEFAULT_CONFIG}`
2. Global user config: `~/.claude/.ai-review-arena.json`
3. Project config: `./.ai-review-arena.json` (in current project root)
4. Command-line flags (highest priority)

**Steps:**
1. Read the default config file using the Read tool.

2. Check for and read override configs:
   ```bash
   ls .ai-review-arena.json 2>/dev/null
   ls ~/.claude/.ai-review-arena.json 2>/dev/null
   ```

3. Merge configs (command-line flags override everything):
   - `--intensity` overrides `review.intensity` and applies the matching preset from `intensity_presets`
   - `--focus` overrides `review.focus_areas`
   - `--models` overrides which models are active
   - `--no-debate` sets `debate.enabled` to false

4. Validate external CLI availability:
   ```bash
   command -v codex &>/dev/null && echo "codex:available" || echo "codex:unavailable"
   command -v gemini &>/dev/null && echo "gemini:available" || echo "gemini:unavailable"
   command -v gh &>/dev/null && echo "gh:available" || echo "gh:unavailable"
   ```

5. Auto-disable unavailable models with a warning message.

6. Determine active roles per model based on merged config and `--focus` filter.

7. Display final configuration summary.

## Phase 3: Cost Estimation

Estimate the cost before proceeding.

**Note:** Agent Teams use more tokens than subagents because each teammate is an independent Claude Code instance with its own context window. Factor this into cost estimates.

**Steps:**
1. Calculate estimated token usage:
   - Count total lines across all files to review
   - Estimate input tokens: `total_lines * 4` (rough tokens-per-line)
   - Estimate output tokens per model per role: ~500-2000 tokens
   - Multiply by number of active model-role combinations
   - Add debate overhead if enabled: `findings_count * 300 * debate_rounds` (higher for Agent Teams due to inter-agent messaging)
   - Add teammate coordination overhead: ~1000 tokens per teammate

2. Estimate costs:
   - Claude (sonnet): input $3/MTok, output $15/MTok
   - Codex: estimate based on GPT-4 pricing ($10/MTok input, $30/MTok output)
   - Gemini 2.5 Pro: $1.25/MTok input, $10/MTok output

3. Display cost estimate:
   ```
   ## Cost Estimate
   - Files: N files, M total lines
   - Agent Team: X Claude teammates + debate-arbitrator
   - External CLI calls: Codex: B, Gemini: C
   - Estimated cost: ~$X.XX (higher due to Agent Teams coordination)
   ```

4. If `--interactive` flag is set:
   - Display the cost estimate
   - Ask: "Proceed with review? (Estimated cost: ~$X.XX)"
   - Wait for user confirmation before continuing

## Phase 4: Team Creation & Parallel Review

### Step 4.1: Create Agent Team

Create a new Agent Team for this review session:

```
Teammate(
  operation: "spawnTeam",
  team_name: "review-{YYYYMMDD-HHMMSS}",
  description: "AI Review Arena - Multi-AI code review session"
)
```

### Step 4.2: Create Review Tasks

Create tasks in the shared task list for each active Claude role. These tasks let teammates track their work and let the lead monitor progress.

```
TaskCreate(
  subject: "Security review of {scope_description}",
  description: "Review the code changes for security vulnerabilities. Follow the security-reviewer agent instructions. Send findings to team lead via SendMessage when complete.",
  activeForm: "Reviewing security vulnerabilities"
)

TaskCreate(
  subject: "Bug detection for {scope_description}",
  description: "Review the code changes for bugs and logic errors. Follow the bug-detector agent instructions. Send findings to team lead via SendMessage when complete.",
  activeForm: "Detecting bugs and logic errors"
)

# ... one TaskCreate per active Claude role
```

### Step 4.2.5: Context Density Filtering

Apply role-based context filtering to reduce token usage per agent. Each reviewer receives only code relevant to their domain, staying within the configured token budget.

**Prerequisites**: `context_density.enabled` must be true in config (default: true). If false or if `context-filter.sh` is missing, skip this step and fall back to full content truncated at `file_lines_max` from the intensity preset.

**Steps:**

1. Build the file list from the review scope (all files to be reviewed):
   ```bash
   FILE_LIST="${SESSION_DIR}/review-file-list.txt"
   # Populate from diff or direct file paths collected in Phase 1
   ```

2. For each role in REVIEWER_ROLES, run context-filter.sh:
   ```bash
   for role in $REVIEWER_ROLES; do
     if [ -f "${SCRIPTS_DIR}/context-filter.sh" ]; then
       cat "${FILE_LIST}" | bash "${SCRIPTS_DIR}/context-filter.sh" \
         "${role}" "${CONFIG_FILE}" \
         > "${SESSION_DIR}/filtered-${role}.txt" \
         2>"${SESSION_DIR}/filter-${role}.log"
     else
       # Fallback: truncate full content to intensity preset limit
       for file in $(cat "${FILE_LIST}"); do
         head -n ${FILE_LINES_MAX} "$file"
       done > "${SESSION_DIR}/filtered-${role}.txt"
     fi
   done
   ```

3. Check stderr logs for `CHUNKING_NEEDED`:
   ```bash
   for role in $REVIEWER_ROLES; do
     if grep -q "CHUNKING_NEEDED" "${SESSION_DIR}/filter-${role}.log" 2>/dev/null; then
       CHUNK_BUDGET=$((AGENT_CONTEXT_BUDGET / MAX_CHUNKS_PER_ROLE))
       CHUNK_LINES=$((CHUNK_BUDGET / 4))
       split -l ${CHUNK_LINES} "${SESSION_DIR}/filtered-${role}.txt" \
         "${SESSION_DIR}/filtered-${role}-chunk-"
       echo "${role}" >> "${SESSION_DIR}/chunked-roles.txt"
     fi
   done
   ```

4. Display filtering summary:
   ```
   ## Context Density Filtering (Step 4.2.5)
   | Role | Files In | Matched | Lines Extracted | Est. Tokens | Chunked |
   |------|----------|---------|-----------------|-------------|---------|
   | security-reviewer | 24 | 8 | 450 | ~1,800 | No |
   ...
   ```

### Step 4.3: Spawn Claude Reviewer Teammates

For each active Claude role, read the agent definition file and spawn a teammate. **Spawn ALL teammates in parallel** by making multiple Task tool calls in a single message.

Read reviewer_roles from config intensity_presets.{INTENSITY}.reviewer_roles.
Fallback if missing: ["security-reviewer", "bug-detector", "performance-reviewer", "scope-reviewer", "test-coverage-reviewer"]

For each role in REVIEWER_ROLES:

1. Read the agent definition:
   ```
   Read(file_path: "{AGENTS_DIR}/{role}.md")
   ```

2. Spawn as teammate:
   ```
   Task(
     subagent_type: "general-purpose",
     team_name: "review-{session_id}",
     name: "{role}",
     prompt: "{contents of agents/{role}.md}

   --- REVIEW TASK ---
   Task ID: {task_id}
   Scope: {scope_description}

   CODE TO REVIEW (filtered for {role}, {filtered_lines} lines from {filtered_files} files):
   {contents of SESSION_DIR/filtered-{role}.txt}
   --- END CODE ---

   NOTE: Code filtered for your review domain ({agent_context_budget_tokens} token budget).
   Use Read tool to examine files outside your filtered view if needed.

   INSTRUCTIONS:
   1. Review the code above following your agent instructions
   2. If the filtered view is insufficient, use the Read tool to examine specific files directly
   3. Send your findings JSON to the team lead using SendMessage
   4. Mark your task as completed using TaskUpdate
   5. Stay active - you will participate in the debate phase next"
   )
   ```

**CRITICAL: Launch ALL Claude reviewer teammates simultaneously.** Use multiple Task tool calls in a single message to maximize parallelism. Do NOT wait for one teammate to finish before spawning the next.

**Chunked Roles**: For roles listed in `${SESSION_DIR}/chunked-roles.txt` (from Step 4.2.5), spawn sub-agents instead of a single teammate:

```
For each chunked role:
  For each chunk file (filtered-{role}-chunk-aa, filtered-{role}-chunk-ab, ...):
    Task(
      subagent_type: "general-purpose",
      team_name: "review-{session_id}",
      name: "{role}-chunk-{N}",
      prompt: "{same agent definition as above}

      CODE TO REVIEW (chunk {N}/{total_chunks} for {role}):
      {contents of chunk file}
      --- END CODE ---

      NOTE: This is chunk {N} of {total_chunks}. Review only this portion.
      Send findings to team lead. Mark task as completed."
    )
```

### Step 4.4: Assign Tasks to Teammates

After spawning, assign each task to its corresponding teammate:

```
TaskUpdate(taskId: "{security_task_id}", owner: "security-reviewer")
TaskUpdate(taskId: "{bug_task_id}", owner: "bug-detector")
# ... one per active role
```

### Step 4.5: Launch External CLI Reviews (Parallel)

While Claude teammates work, run Codex and Gemini CLI reviews in parallel via Bash. **Apply per-file budget** from context density filtering to cap external CLI input.

```bash
# Calculate per-file line budget for external CLIs
FILE_COUNT=$(cat "${FILE_LIST}" | wc -l | tr -d ' ')
PER_FILE_BUDGET=$((AGENT_CONTEXT_BUDGET / 4 / (FILE_COUNT > 0 ? FILE_COUNT : 1)))
[ "$PER_FILE_BUDGET" -lt 50 ] && PER_FILE_BUDGET=50

# Launch all external reviews in background
for role in $CODEX_ROLES; do
  for file in $FILES; do
    head -n "$PER_FILE_BUDGET" "$file" | "${SCRIPTS_DIR}/codex-review.sh" "$file" "$CONFIG" "$role" \
      > "${SESSION_DIR}/findings/codex-${role}-$(basename $file).json" 2>/dev/null &
  done
done

for role in $GEMINI_ROLES; do
  for file in $FILES; do
    head -n "$PER_FILE_BUDGET" "$file" | "${SCRIPTS_DIR}/gemini-review.sh" "$file" "$CONFIG" "$role" \
      > "${SESSION_DIR}/findings/gemini-${role}-$(basename $file).json" 2>/dev/null &
  done
done

# Wait for all background jobs
wait
```

### Step 4.6: Collect All Results

Wait for all results from both sources:

1. **Claude teammates**: They will send findings via SendMessage automatically. Messages are delivered to you (the team lead) as they complete. Wait for all active reviewer teammates to report.

2. **External CLI results**: Read JSON output files from `${SESSION_DIR}/findings/`:
   ```bash
   ls "${SESSION_DIR}/findings/"*.json 2>/dev/null
   ```

3. Parse and validate all findings. Skip invalid JSON with a warning.

### Step 4.5.5: Merge Chunk Findings

For roles that were chunked in Step 4.2.5, merge sub-agent findings before aggregation.

```
For each role in chunked-roles.txt:
  1. Collect findings from all chunk sub-agents: {role}-chunk-1, {role}-chunk-2, ...
  2. Flatten into a single findings array
  3. Deduplicate by file + line proximity (within +/- merge_dedup_line_proximity lines,
     default 3 from context_density.chunking.merge_dedup_line_proximity)
  4. If chunks overlap (overlap_lines > 0), check for duplicate findings at chunk boundaries
  5. Relabel source from "{role}-chunk-N" to "{role}" for consistent downstream processing
  6. Merge into the main findings collection alongside non-chunked role findings
```

Skip this step if no roles were chunked (chunked-roles.txt is empty or missing).

## Phase 5: Findings Aggregation

Merge and deduplicate findings from all sources.

**Steps:**
1. Combine all findings:
   - Teammate findings (received via SendMessage)
   - External CLI findings (from JSON files)

2. Deduplicate:
   - Group by file + line number (within +/- 3 lines tolerance)
   - If multiple models found the same issue:
     - Mark as "cross-validated"
     - Average confidence scores and boost by 10%
     - Keep the most detailed description
     - Note which models agreed

3. Filter by confidence threshold: Remove findings below `review.confidence_threshold`

4. Sort findings:
   - Primary: severity (critical > high > medium > low)
   - Secondary: confidence (highest first)
   - Tertiary: file path, then line number

5. Display intermediate results:
   ```
   ## Findings Summary (Pre-Debate)
   - Total findings: N
   - By severity: X critical, Y high, Z medium, W low
   - By model: Claude: A, Codex: B, Gemini: C
   - Cross-validated: M findings confirmed by 2+ models
   ```

6. Save aggregated findings to session directory.

7. If `--interactive` flag is set: Ask to proceed to debate phase.

## Phase 6: Adversarial Debate (Agent Teams)

Skip if `--no-debate` is set or `debate.enabled` is false.

This phase leverages Agent Teams' inter-agent messaging. Reviewer teammates challenge each other's findings directly, and the debate-arbitrator synthesizes consensus.

### Step 6.1: Spawn Debate Arbitrator

Read the arbitrator agent definition and spawn as a teammate:

```
Read(file_path: "{AGENTS_DIR}/debate-arbitrator.md")

Task(
  subagent_type: "general-purpose",
  team_name: "review-{session_id}",
  name: "debate-arbitrator",
  prompt: "{contents of agents/debate-arbitrator.md}

  --- DEBATE CONTEXT ---
  Session: {session_id}
  Active reviewers: {list of active reviewer teammate names}
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

### Step 6.2: Create Debate Tasks

```
TaskCreate(
  subject: "Debate Round {N}: Cross-validate findings",
  description: "Review teammates challenge each other's findings via direct messaging. Debate-arbitrator collects and synthesizes responses.",
  activeForm: "Running adversarial debate round {N}"
)
```

### Step 6.3: Initiate Cross-Challenges

Send each reviewer teammate instructions to challenge findings from OTHER reviewers. Use individual SendMessage (not broadcast) so each reviewer gets only the findings they should evaluate:

```
SendMessage(
  type: "message",
  recipient: "security-reviewer",
  content: "DEBATE PHASE - Round {N}/{max_rounds}

  Review the following findings from OTHER reviewers and respond to debate-arbitrator with your challenges or support.

  FINDINGS TO EVALUATE:
  {findings_NOT_from_security_reviewer_json}

  For EACH finding:
  1. CHALLENGE if you disagree - explain why it's a false positive or overrated
  2. SUPPORT if you agree - add evidence or corroborate
  3. Send each response to debate-arbitrator via SendMessage

  Use WebSearch to verify security patterns or CVEs if needed.
  When done evaluating all findings, send a message to debate-arbitrator saying 'security-reviewer debate complete'.",
  summary: "Debate round {N}: evaluate other reviewers' findings"
)
```

Repeat for each active reviewer teammate, giving them findings from OTHER roles to evaluate.

### Step 6.4: External Model Challenges

For findings that need cross-model validation with Codex/Gemini:

1. Run challenge prompts through CLI scripts:
   ```bash
   echo '{"finding": {...}, "challenge_prompt": "..."}' | \
     "${SCRIPTS_DIR}/codex-review.sh" "$FILE" "$CONFIG" "debate" \
     > "${SESSION_DIR}/debate/codex-challenge-${finding_id}.json" 2>/dev/null
   ```

2. Send external model responses to debate-arbitrator:
   ```
   SendMessage(
     type: "message",
     recipient: "debate-arbitrator",
     content: "EXTERNAL MODEL RESPONSE (Codex):
     Finding: {finding_title}
     {codex_challenge_result_json}",
     summary: "Codex challenge response for: {finding_title}"
   )
   ```

### Step 6.5: Web Search Verification

For critical/high severity security findings, use WebSearch directly:
- Check latest CVE entries for mentioned libraries/frameworks
- Verify OWASP guidelines for the vulnerability class
- Check security advisories from framework maintainers

Send verification results to debate-arbitrator:
```
SendMessage(
  type: "message",
  recipient: "debate-arbitrator",
  content: "WEB SEARCH VERIFICATION:
  Finding: {finding_title}
  CVE results: {search_results}
  Confidence adjustment: {+/- N}",
  summary: "CVE verification for: {finding_title}"
)
```

### Step 6.6: Repeat for Additional Rounds

If `debate.max_rounds` > 1:
1. Wait for debate-arbitrator to report round results
2. Send remaining disputed findings for the next round
3. In subsequent rounds, focus only on findings still marked "disputed"

### Step 6.7: Collect Consensus

Wait for debate-arbitrator to send the final consensus results via SendMessage. The arbitrator will categorize all findings as:
- **CONFIRMED**: 2+ sources agree (models or web search corroboration)
- **DISMISSED**: Majority challenged with strong evidence
- **DISPUTED**: No consensus reached, requires human review

## Phase 7: Final Report & Team Cleanup

### Step 7.1: Generate Report

Build the report in the configured language (`output.language`):

```markdown
# AI Review Arena Report

**Date:** {timestamp}
**Scope:** {diff description or PR number}
**Intensity:** {intensity level} - {preset description}
**Models:** {list of participating models}
**Mode:** Agent Teams (teammates communicated directly during debate)

---

## Executive Summary

{High-level summary: total findings by severity, key risks, overall code health}

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

**Suggestion:**
```{language}
{code suggestion}
```

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

## Debate Log (if show_debate_log is true)

{Inter-agent message summary, challenges, supports, and resolutions}

---

## Cost Summary

| Model | Teammates | Est. Tokens | Est. Cost |
|-------|-----------|-------------|-----------|
| Claude | N reviewers + arbitrator | ~XK | ~$A.AA |
| Codex | CLI calls | ~XK | ~$B.BB |
| Gemini | CLI calls | ~XK | ~$C.CC |
| **Total** | | | **~$D.DD** |
```

**Output Steps:**
1. Generate report in configured language (ko or en)
2. Display the formatted report to the user
3. Save report: `echo "$REPORT" > "${SESSION_DIR}/reports/review-report.md"`
4. If `--pr` was used and `output.post_to_github` is true: `gh pr comment $PR_NUMBER --body "$REPORT"`

### Step 7.2: Shutdown All Teammates

Send shutdown requests to ALL active teammates. Wait for each confirmation before proceeding.

```
For each role in REVIEWER_ROLES (the roles that were spawned in Phase 4):
  SendMessage(type: "shutdown_request", recipient: "{role}", content: "Review session complete. Thank you.")
SendMessage(type: "shutdown_request", recipient: "debate-arbitrator", content: "Review session complete. Thank you.")
```

Only send shutdown to teammates that were actually spawned in this session.
Wait for all shutdown confirmations before cleanup.

### Step 7.3: Cleanup Team

After ALL teammates have confirmed shutdown:

```
Teammate(operation: "cleanup")
```

**IMPORTANT:** Cleanup will fail if active teammates still exist. Always shutdown all teammates first.

## Error Handling & Fallback Strategy

### Level 0 - Full Operation
All three models available. Full Agent Teams debate with inter-agent messaging.

### Level 1 - Partial Models
One external CLI missing. Continue with available models.
- Warn: "{model} CLI not found - continuing with {remaining models}"
- Claude teammates still debate each other
- External CLI challenges skipped for missing model

### Level 2 - Claude Only
Both external CLIs missing. Run Claude-only review with Agent Teams.
- Warn: "External AI CLIs not available - running Claude-only Agent Teams review"
- Spawn multiple Claude reviewer teammates for different roles
- Teammates still debate each other (Claude vs Claude across roles)
- Debate is still valuable: different role perspectives catch different things

### Level 3 - Minimal (No Agent Teams)
If spawning teammates fails or resources are insufficient:
- Warn: "Agent Teams unavailable - falling back to subagent mode"
- Use Task tool subagents instead of teammates (no inter-agent messaging)
- Skip debate phase
- Read files directly and provide analysis inline

### Teammate Errors
- **Teammate stops unexpectedly**: Check TaskList for incomplete tasks. Spawn replacement teammate if needed.
- **Teammate not responding**: Send a follow-up message. If still no response after 60 seconds, proceed without their input.
- **Debate-arbitrator fails**: Collect whatever challenge/support messages were received. Synthesize consensus manually using the same algorithm.

### Timeout Handling
- If a teammate times out, use whatever partial results they sent
- If an external CLI times out, log and continue with other models
- Include timeout notes in the final report

### JSON Parse Errors
- If a model returns invalid JSON, attempt extraction
- If extraction fails, log error and continue

### Cleanup on Error
If an error occurs mid-process, always attempt cleanup:
1. Send shutdown requests to all spawned teammates
2. Wait briefly for confirmations
3. Run Teammate cleanup
4. Report the error with partial results if available
