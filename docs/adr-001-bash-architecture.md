# ADR-001: Bash Script Architecture

## Status

Accepted

## Context

AI Review Arena orchestrates multi-AI code and business reviews through a pipeline of 25+ scripts. The key decision was whether to implement these scripts in bash, Python, Node.js, or another language.

## Decision

We chose bash as the primary scripting language for the pipeline.

## Rationale

### Why bash

1. **Zero runtime dependencies.** Claude Code runs on macOS and Linux where bash is always available. No `pip install`, no `npm install`, no virtual environments needed for the core pipeline.

2. **Native CLI orchestration.** Arena's core job is calling external CLIs (Codex, Gemini) and piping JSON between them. Bash excels at this — `echo "$CODE" | codex-review.sh | jq` is natural. Python would need `subprocess.run()` wrappers around every CLI call.

3. **Transparent to users.** When something goes wrong, users can read the scripts directly. Bash scripts are inspectable without understanding a framework or build system.

4. **Plugin distribution simplicity.** The plugin is a directory of files copied into `~/.claude/plugins/`. No build step, no package manager, no compiled artifacts.

### Trade-offs accepted

1. **macOS ships bash 3.2.** Associative arrays (`declare -A`) require bash 4+. We work around this using prefixed variables with indirect expansion (`${!var}`). This adds complexity but avoids requiring users to install a newer bash.

2. **No type safety.** Everything is a string. JSON handling relies on `jq` for parsing and validation. Malformed output from CLIs can cause subtle failures.

3. **Error handling is verbose.** Every external call needs explicit `|| true` or `2>"$errfile"` patterns. Python's try/except would be more concise.

4. **Testing is harder.** No built-in test framework. We wrote a custom test runner (`tests/run-tests.sh`) with colored output and pass/fail tracking.

5. **Windows requires WSL.** Bash scripts don't run natively on Windows. Users need WSL or Git Bash (partial support).

## Alternatives Considered

### Python

Would provide type hints, better error handling, and native JSON support. Rejected because it adds a runtime dependency (specific Python version + packages) and complicates plugin distribution.

### Node.js

Would be natural since Claude Code is a Node.js tool. Rejected because it requires `node_modules/` in the plugin directory, adding complexity and size.

### Mixed (bash + Python)

Currently used for the WebSocket debate client (`openai-ws-debate.py`) which requires the `openai` Python package. This is optional — the pipeline falls back to bash HTTP calls when Python is unavailable.

## Consequences

- Scripts must be POSIX-compatible with bash extensions where needed
- `jq` is a soft dependency (recommended, not required — scripts fall back to regex parsing)
- All new scripts must source `utils.sh` for shared logging, config, and error handling
- Platform support table in README documents the bash limitation honestly
