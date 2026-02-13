---
description: "Configure AI Review Arena settings - toggle models, set intensity, manage debate settings"
argument-hint: "[show|set|reset] [key] [value]"
allowed-tools: [Bash, Read]
---

# AI Review Arena Configuration Manager

You manage the configuration for the AI Review Arena multi-AI code review system. You can display, modify, and reset settings.

## Constants

```
PLUGIN_DIR="~/.claude/plugins/ai-review-arena"
DEFAULT_CONFIG="${PLUGIN_DIR}/config/default-config.json"
GLOBAL_CONFIG="~/.claude/.ai-review-arena.json"
PROJECT_CONFIG="./.ai-review-arena.json"
```

## Operations

Parse the first argument from `$ARGUMENTS` to determine the operation:
- `show` (or no arguments): Display current configuration
- `set <key> <value>`: Update a configuration value
- `reset`: Reset to default configuration

---

## Operation: `show`

Display the current effective configuration in a formatted, readable table.

**Steps:**

1. Read the default config:
   ```bash
   cat "${PLUGIN_DIR}/config/default-config.json"
   ```

2. Check for override configs:
   ```bash
   # Check global config
   test -f ~/.claude/.ai-review-arena.json && cat ~/.claude/.ai-review-arena.json || echo "{}"

   # Check project config
   test -f .ai-review-arena.json && cat .ai-review-arena.json || echo "{}"
   ```

3. Check model CLI availability:
   ```bash
   echo "--- CLI Availability ---"
   command -v codex &>/dev/null && echo "codex: installed ($(codex --version 2>/dev/null | head -1 || echo 'version unknown'))" || echo "codex: NOT INSTALLED"
   command -v gemini &>/dev/null && echo "gemini: installed ($(gemini --version 2>/dev/null | head -1 || echo 'version unknown'))" || echo "gemini: NOT INSTALLED"
   command -v gh &>/dev/null && echo "gh: installed" || echo "gh: NOT INSTALLED (needed for --pr mode)"
   command -v jq &>/dev/null && echo "jq: installed" || echo "jq: NOT INSTALLED (required)"
   ```

4. Determine the output language from config `output.language` (default: "ko").

5. Display the configuration using the following format:

   **Korean output (output.language == "ko"):**

   ```
   # AI Review Arena 설정

   ## 모델 설정
   | 모델 | 활성화 | CLI 상태 | 역할 |
   |------|--------|----------|------|
   | Claude | {enabled} | 항상 사용 가능 | {roles} |
   | Codex | {enabled} | {installed/미설치} | {roles} |
   | Gemini | {enabled} | {installed/미설치} | {roles} |

   ## 리뷰 설정
   - 강도: {intensity} ({preset description_ko})
   - 포커스 영역: {focus_areas}
   - 신뢰도 임계값: {confidence_threshold}%
   - 최대 파일 라인: {max_file_lines}

   ## 토론 설정
   - 활성화: {enabled}
   - 최대 라운드: {max_rounds}
   - 도전 임계값: {challenge_threshold}%
   - 합의 임계값: {consensus_threshold}%
   - 다수결 필요: {require_majority}
   - 웹 검색: {web_search_enabled}

   ## 출력 설정
   - 언어: {language}
   - 형식: {format}
   - 비용 추정 표시: {show_cost_estimate}
   - 모델 표시: {show_model_attribution}
   - 신뢰도 표시: {show_confidence_scores}
   - 토론 로그 표시: {show_debate_log}
   - GitHub PR 게시: {post_to_github}

   ## Hook 모드
   - 활성화: {enabled}
   - 배치 크기: {batch_size}
   - 최소 변경 라인: {min_lines_changed}

   ## 설정 소스
   - 기본: {DEFAULT_CONFIG}
   - 글로벌: {exists? path : "없음"}
   - 프로젝트: {exists? path : "없음"}
   ```

   **English output (output.language == "en"):**

   ```
   # AI Review Arena Configuration

   ## Model Settings
   | Model | Enabled | CLI Status | Roles |
   |-------|---------|------------|-------|
   | Claude | {enabled} | Always available | {roles} |
   | Codex | {enabled} | {installed/not installed} | {roles} |
   | Gemini | {enabled} | {installed/not installed} | {roles} |

   ## Review Settings
   - Intensity: {intensity} ({preset description_en})
   - Focus areas: {focus_areas}
   - Confidence threshold: {confidence_threshold}%
   - Max file lines: {max_file_lines}

   ## Debate Settings
   - Enabled: {enabled}
   - Max rounds: {max_rounds}
   - Challenge threshold: {challenge_threshold}%
   - Consensus threshold: {consensus_threshold}%
   - Require majority: {require_majority}
   - Web search: {web_search_enabled}

   ## Output Settings
   - Language: {language}
   - Format: {format}
   - Show cost estimate: {show_cost_estimate}
   - Show model attribution: {show_model_attribution}
   - Show confidence scores: {show_confidence_scores}
   - Show debate log: {show_debate_log}
   - Post to GitHub PR: {post_to_github}

   ## Hook Mode
   - Enabled: {enabled}
   - Batch size: {batch_size}
   - Min lines changed: {min_lines_changed}

   ## Config Sources
   - Default: {DEFAULT_CONFIG}
   - Global: {exists? path : "none"}
   - Project: {exists? path : "none"}
   ```

---

## Operation: `set <key> <value>`

Update a configuration value in the project-level config file.

**Supported Keys** (dot-notation):

| Key | Type | Valid Values | Description |
|-----|------|-------------|-------------|
| `models.claude.enabled` | boolean | true, false | Toggle Claude model |
| `models.codex.enabled` | boolean | true, false | Toggle Codex model |
| `models.gemini.enabled` | boolean | true, false | Toggle Gemini model |
| `models.claude.roles` | array | security,bugs,architecture,performance,testing | Claude review roles |
| `models.codex.roles` | array | security,bugs,architecture,performance,testing | Codex review roles |
| `models.gemini.roles` | array | security,bugs,architecture,performance,testing | Gemini review roles |
| `models.gemini.model_variant` | string | gemini-2.5-pro, gemini-2.5-flash | Gemini model variant |
| `models.codex.timeout_seconds` | number | 30-600 | Codex timeout in seconds |
| `models.gemini.timeout_seconds` | number | 30-600 | Gemini timeout in seconds |
| `review.intensity` | string | quick, standard, deep, comprehensive | Review intensity preset |
| `review.focus_areas` | array | security,bugs,architecture,performance,testing | Focus areas |
| `review.confidence_threshold` | number | 0-100 | Minimum confidence to report |
| `review.max_file_lines` | number | 50-5000 | Max lines per file |
| `debate.enabled` | boolean | true, false | Toggle debate phase |
| `debate.max_rounds` | number | 0-5 | Maximum debate rounds |
| `debate.challenge_threshold` | number | 0-100 | Confidence below which findings are debated |
| `debate.consensus_threshold` | number | 0-100 | Confidence for auto-consensus |
| `debate.web_search_enabled` | boolean | true, false | Web search during debate |
| `output.language` | string | ko, en | Output language |
| `output.show_cost_estimate` | boolean | true, false | Show cost estimates |
| `output.show_model_attribution` | boolean | true, false | Show which model found what |
| `output.show_confidence_scores` | boolean | true, false | Show confidence percentages |
| `output.show_debate_log` | boolean | true, false | Include debate log in report |
| `output.post_to_github` | boolean | true, false | Auto-post to PR comments |
| `hook_mode.enabled` | boolean | true, false | Toggle hook mode |
| `hook_mode.batch_size` | number | 1-20 | Files per hook batch |
| `hook_mode.min_lines_changed` | number | 1-100 | Min lines to trigger review |

**Steps:**

1. Parse the key and value from arguments.

2. Validate the key exists in the supported keys table.

3. Validate the value type and range:
   - Boolean: must be "true" or "false"
   - Number: must be within the valid range
   - String: must be one of the valid values
   - Array: parse comma-separated values, validate each

4. Read or create the project config file:
   ```bash
   # Read existing or start with empty object
   if [ -f .ai-review-arena.json ]; then
     cat .ai-review-arena.json
   else
     echo "{}"
   fi
   ```

5. Update the value using jq:
   ```bash
   # Example for boolean:
   jq '.models.codex.enabled = false' .ai-review-arena.json > .ai-review-arena.json.tmp && \
     mv .ai-review-arena.json.tmp .ai-review-arena.json

   # Example for array:
   jq '.review.focus_areas = ["security","bugs"]' .ai-review-arena.json > .ai-review-arena.json.tmp && \
     mv .ai-review-arena.json.tmp .ai-review-arena.json

   # Example for number:
   jq '.review.confidence_threshold = 80' .ai-review-arena.json > .ai-review-arena.json.tmp && \
     mv .ai-review-arena.json.tmp .ai-review-arena.json
   ```

6. Confirm the change:
   - Korean: "설정 변경 완료: {key} = {value}"
   - English: "Configuration updated: {key} = {value}"

7. If the key is `review.intensity`, also show the preset description:
   - Korean: "강도 프리셋: {description_ko}"
   - English: "Intensity preset: {description_en}"

8. If the key is a model toggle and the value is `true`, check CLI availability:
   - If CLI not installed, warn:
     - Korean: "주의: {model} CLI가 설치되어 있지 않습니다. 리뷰 시 자동으로 비활성화됩니다."
     - English: "Warning: {model} CLI is not installed. It will be auto-disabled during review."

---

## Operation: `reset`

Reset configuration to defaults by removing the project-level config file.

**Steps:**

1. Check if project config exists:
   ```bash
   test -f .ai-review-arena.json && echo "exists" || echo "not found"
   ```

2. If it exists, remove it:
   ```bash
   rm .ai-review-arena.json
   ```

3. Confirm the reset:
   - Korean: "프로젝트 설정이 기본값으로 초기화되었습니다. 기본 설정 파일: {DEFAULT_CONFIG}"
   - English: "Project configuration reset to defaults. Default config: {DEFAULT_CONFIG}"

4. Check if global config also exists and mention it:
   ```bash
   test -f ~/.claude/.ai-review-arena.json && echo "global config exists"
   ```
   - If global config exists, note:
     - Korean: "참고: 글로벌 설정 파일이 여전히 존재합니다: ~/.claude/.ai-review-arena.json"
     - English: "Note: Global config file still exists: ~/.claude/.ai-review-arena.json"

## Error Handling

- Invalid operation: Show usage help with available operations
- Invalid key: Show list of supported keys
- Invalid value: Show valid values/ranges for the specified key
- Missing jq: Warn that jq is required for set operations
- File permission errors: Report and suggest checking directory permissions
