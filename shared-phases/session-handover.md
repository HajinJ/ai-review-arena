# Session Handover Protocol

When a review pipeline approaches context window limits (>60% utilization) or when explicitly requested, use this protocol to preserve review state across sessions.

## When to Trigger

- Context window utilization exceeds 60% during Phase 6 or later
- User explicitly requests session split
- Compaction warning appears ("Compacting conversation...")
- Review has been running for >45 minutes with significant findings

## Proactive Reset Checkpoints

Phase 경계에서 선제적으로 리셋하여 리뷰 품질을 보장합니다. 기존 반응적 핸드오프(>60% utilization)를 보완하여 phase 전환 시 fresh context를 확보합니다.

### 기본 체크포인트
- **Pre-Review Reset**: Phase 5.9 → Phase 6 전환 시 (리뷰 진입 전 fresh context 확보)
- **Pre-Report Reset**: Phase 6.7 → Phase 7 전환 시 (리포트 생성 시 full context 확보)

### 트리거 조건
- `context_reset.proactive_enabled` = true (config)
- 현재 context utilization > `context_reset.proactive_threshold` (default: 40%)
- 또는 Phase 6 진입 시 무조건 (if `context_reset.always_reset_before_review` = true)

### 리셋 프로세스
1. 현재까지의 phase outputs를 SESSION_DIR에 저장 (Step 3의 Save Artifacts와 동일)
2. Resume prompt 생성 (Step 2와 동일)
3. 사용자에게 자동 리셋 알림 (`silent_mode`에서는 알림 없이 진행)
4. 새 세션에서 resume prompt 로드 후 다음 phase부터 실행

### 프로액티브 리셋 vs 리액티브 핸드오버

| 구분 | 프로액티브 리셋 | 리액티브 핸드오버 |
|------|---------------|-----------------|
| 트리거 | Phase 경계 도달 + config 조건 | Context window > 60% |
| 목적 | Fresh context로 리뷰 품질 보장 | Context window 소진 방지 |
| 시점 | Phase 5.9→6, Phase 6.7→7 | 어느 phase에서든 |
| 제어 | config로 비활성화 가능 | 항상 활성 |

---

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
