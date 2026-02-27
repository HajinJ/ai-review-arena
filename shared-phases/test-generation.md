# Shared Phase: Test Generation (Code Pipeline)

**Applies to**: standard, deep, comprehensive intensity. Skip for quick.

**Purpose**: Generate regression test stubs for confirmed critical and high-severity findings. Ensures identified issues don't recur.

## Variables (set by calling pipeline)

- `ACCEPTED_FINDINGS`: Confirmed findings from Phase 6 debate (JSON)
- `FILES_CHANGED`: List of files in the review scope
- `DETECTED_STACK`: Stack detection results from Phase 1
- `PROJECT_ROOT`: Project root directory

## Steps

1. **Filter Eligible Findings**:
   ```
   eligible_findings = ACCEPTED_FINDINGS.filter(f =>
     f.severity in ["critical", "high"] AND
     f.confidence >= 70 AND
     f.suggestion != null
   )
   ```

   If no eligible findings, skip this phase with: "No critical/high findings eligible for test generation."

2. **Detect Test Framework**:
   From DETECTED_STACK, identify the project's test framework:
   - JavaScript/TypeScript: jest, vitest, mocha
   - Python: pytest, unittest
   - Go: testing (built-in)
   - Java: JUnit, TestNG
   - Ruby: RSpec, minitest
   - Rust: #[test] (built-in)
   - Default: language-appropriate standard library

3. **Detect Test Directory**:
   Look for existing test directories:
   ```
   test_dirs = Glob("**/test*/**", "**/spec*/**", "**/__tests__/**")
   ```
   Use the most relevant existing test directory, or `tests/` as default.

4. **Generate Test Stubs**:
   For each eligible finding (up to `max_tests_per_finding` per finding):

   ```
   FOR each finding in eligible_findings:
     test_name = "test_regression_{finding.title_slug}"
     test_file = "{test_dir}/regression/test_{finding.file_basename}.{ext}"

     Generate a test stub that:
     a. Documents the finding (title, severity, original line)
     b. Tests the FIXED behavior (not the vulnerability)
     c. Includes setup for the specific scenario
     d. Uses the project's existing test framework and patterns
     e. Marks as regression test with clear comment

     Example structure:
     // Regression test for: {finding.title}
     // Severity: {finding.severity} | Finding from: AI Review Arena
     // Original location: {finding.file}:{finding.line}
     //
     // This test verifies the fix for the identified issue.
     // TODO: Implement actual test logic based on the fix applied.

     test("{description}", () => {
       // Arrange: setup the scenario that triggered the finding
       // Act: execute the code path
       // Assert: verify the fix prevents the issue
       // TODO: Fill in with actual test implementation
     })
   ```

5. **Write Test Files**:
   - Group tests by file (one test file per reviewed source file)
   - Use Write tool to create test stubs
   - Do NOT overwrite existing test files -- append or create new regression files

6. **Display Results**:
   ```
   ## Test Generation
   - Findings eligible: {N}
   - Test stubs generated: {M}
   - Test files created: {list}
   - Framework: {detected_framework}
   - NOTE: Generated tests are stubs -- fill in implementation after reviewing fixes.
   ```

## Configuration

Settings from `config.test_generation`:
- `enabled`: Whether test generation is active (default: true)
- `min_intensity`: Minimum intensity to run (default: standard)
- `max_tests_per_finding`: Maximum tests per finding (default: 2)
- `frameworks`: Test framework override (default: auto)
- `severity_filter`: Which severities to generate for (default: [critical, high])

## Error Handling

- Cannot detect test framework: Use generic test pseudo-code with TODO comments
- Cannot find test directory: Create `tests/regression/` directory
- Write fails: Log warning and continue with remaining tests
- No eligible findings: Skip phase entirely (not an error)
