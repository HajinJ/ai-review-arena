# Session Handover Protocol

When a review pipeline approaches context window limits (>60% utilization) or when explicitly requested, use this protocol to preserve review state across sessions.

## When to Trigger

- Context window utilization exceeds 60% during Phase 6 or later
- User explicitly requests session split
- Compaction warning appears ("Compacting conversation...")
- Review has been running for >45 minutes with significant findings

## Handover Process

### Step 1: Freeze Write Operations

Before handover, prevent any file modifications:
- Complete or revert any in-progress auto-fixes (Phase 6.5)
- Ensure all git operations are committed or stashed
- Save current pipeline state

### Step 2: Generate Resume Prompt

Create a resume-prompt file at the project root:

```bash
# Save to: .ai-review-arena-resume.md
RESUME_FILE="${PROJECT_ROOT}/.ai-review-arena-resume.md"
```

The resume prompt MUST include:

```markdown
# AI Review Arena - Session Resume

## Pipeline State
- **Current Phase**: [phase number and name]
- **Intensity**: [quick|standard|deep|comprehensive]
- **Intensity Rationale**: [why this intensity was chosen]
- **Target Files**: [list of files in scope]
- **Config**: [path to merged config file]

## Completed Phases
[List each completed phase with key outputs]

## Pending Phases
[List remaining phases to execute]

## Findings So Far
- Accepted: [count] ([critical/high/medium/low breakdown])
- Rejected: [count]
- Disputed: [count]

## Key Decisions Made
[List critical decisions from debates, with rationale]

## Active Signals
[Recent cross-agent signals that inform remaining phases]

## Files Modified
[List of files changed by auto-fix, with git diff summary]

## Resume Instructions
Continue the review pipeline from Phase [N]. Load the following:
1. Consensus findings: [path to consensus JSON]
2. Signal log: [path to JSONL signal log]
3. Spec criteria: [path to approved spec, if applicable]

Execute remaining phases in order. Do NOT re-run completed phases.
```

### Step 3: Save Artifacts

```bash
SESSION_DIR="${PROJECT_ROOT}/.ai-review-arena-session"
mkdir -p "$SESSION_DIR"

# Save consensus findings accumulated so far
cp "$CONSENSUS_FILE" "$SESSION_DIR/consensus-partial.json"

# Save signal log
cp "$SIGNAL_LOG" "$SESSION_DIR/signal-log.jsonl"

# Save phase outputs
cp "$PHASE_OUTPUTS" "$SESSION_DIR/phase-outputs.json"
```

### Step 4: Notify User

Use AskUserQuestion to inform the user:
- Session handover is ready
- Resume file location
- Instruction to start new session with: "Resume review from .ai-review-arena-resume.md"

## Resume Process

When a new session starts and finds `.ai-review-arena-resume.md`:

1. **Read resume prompt** — Load the full resume file
2. **Validate state** — Check that referenced files still exist
3. **Verify git state** — Ensure no code changes since handover (use git hash comparison)
4. **Load artifacts** — Read consensus JSON, signal log, phase outputs
5. **Continue pipeline** — Execute remaining phases from where the previous session stopped
6. **Merge results** — Combine new findings with previous findings in final report

## Gap Analysis

After resuming, run a sub-agent to verify no context was lost:

1. Compare resume prompt against signal log entries
2. Identify any findings referenced in debates but missing from consensus
3. Flag any phase outputs that reference files not in the resume's file list
4. Report gaps to the user before continuing

## Cleanup

After the review pipeline completes successfully:
- Remove `.ai-review-arena-resume.md`
- Remove `.ai-review-arena-session/` directory
- Log session handover metrics to short-term memory tier
