---
description: "Show AI Review Arena session status - model availability, last review results, history"
argument-hint: "[--history] [--last]"
allowed-tools: [Bash, Read]
---

# AI Review Arena Status

You display the current status of the AI Review Arena system, including model availability, recent review results, and session history.

## Constants

```
PLUGIN_DIR="~/.claude/plugins/ai-review-arena"
DEFAULT_CONFIG="${PLUGIN_DIR}/config/default-config.json"
SESSION_BASE="/tmp/ai-review-arena"
```

## Argument Parsing

Parse `$ARGUMENTS` for flags:
- No flags: Show general status dashboard
- `--last`: Show the last review results in detail
- `--history`: Show review history summary

---

## Default Status Dashboard (no flags)

Display a comprehensive status overview.

**Steps:**

1. Check model CLI availability:
   ```bash
   echo "=== CLI Status ==="

   # Claude
   echo "claude: always available (built-in Task tool)"

   # Codex
   if command -v codex &>/dev/null; then
     echo "codex: installed ($(codex --version 2>/dev/null | head -1 || echo 'version unknown'))"
   else
     echo "codex: NOT INSTALLED (install: npm install -g @openai/codex)"
   fi

   # Gemini
   if command -v gemini &>/dev/null; then
     echo "gemini: installed ($(gemini --version 2>/dev/null | head -1 || echo 'version unknown'))"
   else
     echo "gemini: NOT INSTALLED (install: npm install -g @google/gemini-cli)"
   fi

   # Supporting tools
   if command -v jq &>/dev/null; then
     echo "jq: installed"
   else
     echo "jq: NOT INSTALLED (required - install: brew install jq)"
   fi

   if command -v gh &>/dev/null; then
     echo "gh: installed (needed for --pr mode)"
   else
     echo "gh: not installed (optional - needed for --pr mode)"
   fi
   ```

2. Read current configuration:
   ```bash
   cat "${PLUGIN_DIR}/config/default-config.json"
   ```
   Also check for project/global overrides:
   ```bash
   test -f .ai-review-arena.json && echo "project_config: exists" || echo "project_config: none"
   test -f ~/.claude/.ai-review-arena.json && echo "global_config: exists" || echo "global_config: none"
   ```

3. Check pending changes in current repo:
   ```bash
   # Staged changes
   STAGED_COUNT=$(git diff --staged --name-only 2>/dev/null | wc -l | tr -d ' ')
   echo "staged_files: ${STAGED_COUNT}"

   # Unstaged changes
   UNSTAGED_COUNT=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
   echo "unstaged_files: ${UNSTAGED_COUNT}"

   # Untracked files
   UNTRACKED_COUNT=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
   echo "untracked_files: ${UNTRACKED_COUNT}"
   ```

4. Check for recent sessions:
   ```bash
   # List recent session directories
   if [ -d "${SESSION_BASE}" ]; then
     ls -1td "${SESSION_BASE}"/*/ 2>/dev/null | head -5
     TOTAL_SESSIONS=$(ls -1d "${SESSION_BASE}"/*/ 2>/dev/null | wc -l | tr -d ' ')
     echo "total_sessions: ${TOTAL_SESSIONS}"
   else
     echo "no_sessions: true"
   fi
   ```

5. Determine output language from config and display formatted status.

   **Korean output:**

   ```
   # AI Review Arena 상태

   ## 모델 가용성
   | 모델 | CLI 상태 | 설정 활성화 | 사용 가능 |
   |------|----------|------------|----------|
   | Claude | 항상 사용 가능 | {enabled} | {available} |
   | Codex | {installed/미설치} | {enabled} | {available} |
   | Gemini | {installed/미설치} | {enabled} | {available} |

   ## 현재 설정
   - 강도: {intensity} ({preset description_ko})
   - 포커스 영역: {focus_areas}
   - 토론: {enabled/비활성화}, 최대 {max_rounds}라운드
   - 설정 소스: {config sources}

   ## 현재 저장소
   - 스테이지된 파일: {staged_count}
   - 변경된 파일: {unstaged_count}
   - 추적되지 않는 파일: {untracked_count}
   - 리뷰 가능한 변경: {total reviewable}

   ## 최근 세션
   - 마지막 리뷰: {last session timestamp or "없음"}
   - 전체 세션: {total sessions}
   ```

   **English output:**

   ```
   # AI Review Arena Status

   ## Model Availability
   | Model | CLI Status | Config Enabled | Available |
   |-------|------------|----------------|-----------|
   | Claude | Always available | {enabled} | {available} |
   | Codex | {installed/not installed} | {enabled} | {available} |
   | Gemini | {installed/not installed} | {enabled} | {available} |

   ## Current Configuration
   - Intensity: {intensity} ({preset description_en})
   - Focus areas: {focus_areas}
   - Debate: {enabled/disabled}, max {max_rounds} rounds
   - Config source: {config sources}

   ## Current Repository
   - Staged files: {staged_count}
   - Modified files: {unstaged_count}
   - Untracked files: {untracked_count}
   - Reviewable changes: {total reviewable}

   ## Recent Sessions
   - Last review: {last session timestamp or "none"}
   - Total sessions: {total sessions}
   ```

---

## `--last` Flag: Last Review Results

Display the detailed results from the most recent review session.

**Steps:**

1. Find the latest session directory:
   ```bash
   LATEST_SESSION=$(ls -1td "${SESSION_BASE}"/*/ 2>/dev/null | head -1)
   if [ -z "$LATEST_SESSION" ]; then
     echo "no_sessions"
   else
     echo "latest: ${LATEST_SESSION}"
   fi
   ```

2. If no sessions found:
   - Korean: "이전 리뷰 세션이 없습니다. `/multi-review`를 실행하여 첫 리뷰를 시작하세요."
   - English: "No previous review sessions found. Run `/multi-review` to start your first review."

3. If session found, read the report:
   ```bash
   # Check for report file
   REPORT_FILE="${LATEST_SESSION}/reports/review-report.md"
   if [ -f "$REPORT_FILE" ]; then
     cat "$REPORT_FILE"
   else
     echo "report_not_found"
   fi
   ```

4. If report file exists, display it in full.

5. If report file doesn't exist but findings do, reconstruct a summary:
   ```bash
   # List all findings files
   ls "${LATEST_SESSION}/findings/"*.json 2>/dev/null
   ```

   Read each findings file and display a summary:
   - Total findings count by severity
   - Findings by model
   - Top 5 highest-confidence findings with titles

6. Check for debate log:
   ```bash
   DEBATE_FILE="${LATEST_SESSION}/debate/debate-log.json"
   if [ -f "$DEBATE_FILE" ]; then
     cat "$DEBATE_FILE"
   fi
   ```

7. Display session metadata:
   ```bash
   # Session timestamp from directory name
   SESSION_NAME=$(basename "$LATEST_SESSION")
   echo "session: ${SESSION_NAME}"

   # Count files in session
   FINDINGS_COUNT=$(ls "${LATEST_SESSION}/findings/"*.json 2>/dev/null | wc -l | tr -d ' ')
   echo "findings_files: ${FINDINGS_COUNT}"
   ```

---

## `--history` Flag: Review History Summary

Display a summary of all past review sessions.

**Steps:**

1. List all session directories:
   ```bash
   if [ -d "${SESSION_BASE}" ]; then
     for session_dir in $(ls -1td "${SESSION_BASE}"/*/); do
       SESSION_NAME=$(basename "$session_dir")

       # Count findings files
       FINDINGS_FILES=$(ls "$session_dir/findings/"*.json 2>/dev/null | wc -l | tr -d ' ')

       # Check if report exists
       HAS_REPORT="no"
       [ -f "$session_dir/reports/review-report.md" ] && HAS_REPORT="yes"

       # Check if debate happened
       HAS_DEBATE="no"
       [ -f "$session_dir/debate/debate-log.json" ] && HAS_DEBATE="yes"

       echo "${SESSION_NAME}|${FINDINGS_FILES}|${HAS_REPORT}|${HAS_DEBATE}"
     done
   else
     echo "no_sessions"
   fi
   ```

2. If no sessions found:
   - Korean: "리뷰 이력이 없습니다."
   - English: "No review history found."

3. Display history table.

   **Korean output:**

   ```
   # AI Review Arena 리뷰 이력

   | 세션 | 날짜/시간 | 발견 항목 | 리포트 | 토론 |
   |------|----------|----------|--------|------|
   | {session_name} | {formatted date} | {findings_count} | {yes/no} | {yes/no} |
   ```

   **English output:**

   ```
   # AI Review Arena Review History

   | Session | Date/Time | Findings | Report | Debate |
   |---------|-----------|----------|--------|--------|
   | {session_name} | {formatted date} | {findings_count} | {yes/no} | {yes/no} |
   ```

4. Show summary statistics:
   ```
   - Total sessions: {count}
   - Total findings across all sessions: {count}
   - Sessions with debate: {count}
   - Date range: {earliest} to {latest}
   ```

5. Optionally, for the last 3 sessions, show a brief breakdown:
   - Read the aggregated findings file if it exists
   - Show severity distribution for each session

---

## Error Handling

- Not in a git repository: Show model availability and config only, skip repo-specific info
  ```bash
  git rev-parse --is-inside-work-tree 2>/dev/null || echo "not_a_git_repo"
  ```
- Session directory doesn't exist: Report no sessions, suggest running `/multi-review`
- Corrupted session data: Skip corrupted entries with warning
- Missing jq: Fall back to basic file listing without JSON parsing
