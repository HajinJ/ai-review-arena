# Contributing to AI Review Arena

## Project Structure

```
agents/       - 27 Claude agent role definitions (12 code + 10 business + 5 utility)
commands/     - 7 pipeline command files (.md)
scripts/      - 25 shell/Python scripts
config/       - Configuration, prompts, schemas, benchmarks
shared-phases/ - Common phase definitions shared by code and business pipelines
hooks/        - PostToolUse hook (Claude) and AfterTool hook (Gemini)
docs/         - Documentation
```

## Adding a New Agent

1. Create `agents/<role-name>.md` with these required sections:
   - `## Role` - one-line description
   - `## Reporting Threshold` - 3 AND-criteria for reportable findings (use **positive framing**)
   - `## Recognized Patterns` - patterns that confirm mitigation (not prohibitions)
   - `## Error Recovery Protocol` - retry, partial submit, team lead notification
   - `## Rules` - detailed instructions

2. Use positive framing per [arxiv 2602.11988](https://arxiv.org/abs/2602.11988): "Report ONLY when..." instead of "Do NOT report..."

3. Add the agent to the appropriate intensity preset in `config/default-config.json` under `intensity_presets` or `business_intensity_presets`.

4. If the agent needs context filtering, add a role entry to `config.context_density.role_filters`.

5. If the agent has a responsibility matrix, add it to `config.agent_responsibility_matrix`.

## Script Writing Rules

- Start with `#!/usr/bin/env bash` and `set -uo pipefail`
- Source utils.sh: `source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"`
- Use `log_info`, `log_warn`, `log_error` for logging (all go to stderr)
- Output JSON results to stdout, human-readable messages to stderr
- Handle missing CLI tools gracefully (check before use, fall back)
- Use `ensure_jq` before any jq operations
- Use `load_config()` for config loading (deep merges default > global > project)
- Silent exit on non-critical errors (`exit 0`)
- Do NOT use `declare -A` (requires bash 4+; macOS ships 3.2). Use prefixed variables with `${!var}` indirect expansion instead.
- Do NOT use `sed` for JSON content manipulation. Use `${var//pattern/replacement}` to avoid injection.

## Running Tests

```bash
# Validate config
./scripts/validate-config.sh config/default-config.json

# Run pipeline evaluation
./scripts/evaluate-pipeline.sh

# Test stack detection
./scripts/detect-stack.sh

# Test cache operations
./scripts/cache-manager.sh write test-key "test-value"
./scripts/cache-manager.sh read test-key
```

## PR Guidelines

1. Keep changes focused on a single concern.
2. Run `./scripts/validate-config.sh config/default-config.json` if you modified config.
3. Test with intentionally buggy code to verify detection for review agents.
4. Test model fallback by disabling CLIs if touching external integrations.
5. Update both `README.md` and `README.ko.md` for user-facing changes.
6. Follow the commit message style: `<type>: <description>` (feat, fix, docs, chore, refactor).

## Configuration

- Project config: `.ai-review-arena.json` in project root
- Global config: `~/.claude/.ai-review-arena.json`
- Default config: `config/default-config.json`
- Config merge order: default > global > project (project wins)
- Environment variables with `MULTI_REVIEW_` or `ARENA_` prefix override config

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
