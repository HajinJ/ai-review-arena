# Shared Phase: Static Analysis Integration

**Applies to**: standard, deep, comprehensive intensity. Skip for quick.

**Purpose**: Run external static analysis scanners before agent review. Scanner findings provide tool-verified issues as additional context for Phase 6 reviewer agents.

## Variables (set by calling pipeline before including this phase)

- `INTENSITY`: Current intensity level (must be standard, deep, or comprehensive)
- `PROJECT_ROOT`: Project root directory
- `DETECTED_STACK`: Stack detection results from Phase 1 (JSON)
- `SESSION_DIR`: Current session directory

## Steps

1. **Check configuration**: Load `static_analysis` settings from config. If `static_analysis.enabled` is false, skip this phase.

2. **Run static analysis script**:
   ```bash
   bash "${SCRIPTS_DIR}/static-analysis.sh" "${PROJECT_ROOT}" \
     --stack "${DETECTED_STACK_JSON}" \
     --max-findings "${config.static_analysis.max_findings:-50}" \
     --confidence-floor "${config.static_analysis.confidence_floor:-60}" \
     --output-dir "${SESSION_DIR}/static-analysis"
   ```

   The script will:
   - Detect available scanners based on the project stack
   - Run selected scanners in parallel (semgrep, eslint, bandit, gosec, brakeman, cargo-audit)
   - Normalize all outputs into standard format via `normalize-scanner-output.sh`
   - Filter by confidence floor and limit to max findings
   - Output sorted JSON (critical first, then by confidence descending)

3. **Parse results**: Read the JSON output and store as `STATIC_ANALYSIS_FINDINGS`.

4. **Display summary**:
   ```
   ## Static Analysis Results
   - Scanners: {list of scanners run}
   - Findings: {total} ({critical} critical, {high} high, {medium} medium, {low} low)
   - Top Issues:
     1. [{severity}] {title} — {file}:{line}
     2. ...
   ```

5. **Forward to Phase 6**: Include `STATIC_ANALYSIS_FINDINGS` as additional context for reviewer agents. Each reviewer receives findings relevant to their domain:
   - security-reviewer → all scanner findings
   - bug-detector → findings with patterns matching error handling, null, concurrency
   - performance-reviewer → findings related to resource usage, complexity
   - Other reviewers → summary of scanner findings for awareness

## Configuration

Settings from `config.static_analysis`:
- `enabled`: Whether static analysis is active (default: true)
- `min_intensity`: Minimum intensity to run (default: standard)
- `scanners`: Per-scanner settings (enabled, timeout)
- `max_findings`: Maximum findings to return (default: 50)
- `confidence_floor`: Minimum confidence to include (default: 60)

## Scanner Selection

| Language | Scanner | What it detects |
|----------|---------|----------------|
| Python | bandit | Security issues (injection, crypto, etc.) |
| JavaScript/TypeScript | eslint | Code quality and security rules |
| Go | gosec | Security vulnerabilities |
| Ruby | brakeman | Web application vulnerabilities |
| Rust | cargo-audit | Known vulnerable dependencies |
| Any | semgrep | Pattern-based security and code quality |

## Error Handling

- No scanners available: Log info message, skip phase. This is NOT an error — many projects won't have scanners installed.
- Scanner timeout: Use partial results from completed scanners.
- Script error: Skip phase, log warning: "Static analysis unavailable — proceeding without scanner results."
- Invalid scanner output: Skip that scanner's results, continue with others.
