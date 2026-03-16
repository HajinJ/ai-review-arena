# Shared Phase: Spec Verification Gate (Code Pipeline)

**Applies to**: standard, deep, comprehensive intensity. Skip for quick.

**Purpose**: Transform LLM-generated Success Criteria into user-approved, deterministic verification tests. Replaces subjective LLM self-evaluation with concrete test execution for pass/fail determination.

## Variables (set by calling pipeline)

- `APPROVED_SPEC_CRITERIA`: User-approved acceptance criteria (JSON, set after Step 2)
- `DETECTED_STACK`: Stack detection results from Phase 1
- `PROJECT_ROOT`: Project root directory
- `TEST_DIR`: Detected test directory from project structure

## Steps

### Phase 5.5.5: Spec Approval Gate

1. **Parse Success Criteria**:
   Extract Success Criteria from Phase 5.5 strategy-arbitrator output and structure as JSON:
   ```json
   [
     {"id": 1, "criterion": "API returns 200 for valid input", "verification": "curl test with sample payload", "test_type": "automated_test"},
     {"id": 2, "criterion": "Error message is user-friendly", "verification": "manual check", "test_type": "manual_check"},
     {"id": 3, "criterion": "Config file created at /etc/app.conf", "verification": "file existence check", "test_type": "static_assertion"}
   ]
   ```

2. **Auto-classify test_type** (if `spec_verification.auto_classify_test_type` is true):
   Based on the `verification` field content:
   - `automated_test`: Contains "curl", "test", "assert", "expect", "should", "verify response", "call API", "invoke", "run"
   - `static_assertion`: Contains "file exist", "grep", "contains", "check file", "directory exist", "env var", "config value"
   - `manual_check`: All others (visual checks, subjective evaluations, user experience)

3. **User Approval Gate** (if `spec_verification.require_user_approval` is true):
   Display criteria to user via AskUserQuestion:
   ```
   ## Acceptance Criteria (Phase 5.5.5)

   | # | Criterion | Verification | Type |
   |---|-----------|-------------|------|
   | 1 | API returns 200 for valid input | curl test with sample payload | automated |
   | 2 | Error message is user-friendly | manual check | manual |
   | 3 | Config file created at /etc/app.conf | file existence check | static |

   [Approve / Edit / Add criteria / Skip]
   ```

   - **Approve**: Accept criteria as-is, save to `APPROVED_SPEC_CRITERIA`
   - **Edit**: User modifies criteria text or types, re-display for confirmation
   - **Add criteria**: User adds new criteria, re-display for confirmation
   - **Skip**: Skip spec verification entirely, proceed without `APPROVED_SPEC_CRITERIA`

4. **Save Approved Criteria**:
   Store `APPROVED_SPEC_CRITERIA` as session variable for Phase 6.6 and Phase 7.

### Phase 6.6 Extension: Spec Test Generation

After existing findings-based test generation, additionally generate tests from `APPROVED_SPEC_CRITERIA`:

1. **Filter criteria by test_type**:
   ```
   automated_criteria = APPROVED_SPEC_CRITERIA.filter(c => c.test_type == "automated_test")
   static_criteria = APPROVED_SPEC_CRITERIA.filter(c => c.test_type == "static_assertion")
   manual_criteria = APPROVED_SPEC_CRITERIA.filter(c => c.test_type == "manual_check")
   ```

2. **Generate BDD tests for automated_criteria**:
   For each automated criterion, generate a test in the project's test framework:
   ```
   FOR each criterion in automated_criteria:
     test_file = "{TEST_DIR}/spec/{test_file_prefix}{scope_slug}.{ext}"

     Generate BDD-style test:
     // Acceptance Criteria #{criterion.id}: {criterion.criterion}
     // Verification: {criterion.verification}
     // Source: AI Review Arena Phase 5.5.5 (user-approved)

     describe("Acceptance Criteria", () => {
       it("{criterion.criterion}", () => {
         // Given: {setup from verification context}
         // When: {action from criterion}
         // Then: {expected result}
         // TODO: Implement based on verification method: {criterion.verification}
       })
     })
   ```

3. **Generate static assertions for static_criteria**:
   For each static criterion, generate a bash one-liner assertion:
   ```
   FOR each criterion in static_criteria:
     Generate assertion:
     # Acceptance Criteria #{criterion.id}: {criterion.criterion}
     # Verification: {criterion.verification}
     test -f "/etc/app.conf" && echo "PASS: #{criterion.id}" || echo "FAIL: #{criterion.id}"
   ```

4. **Record manual_check criteria** for Phase 7 report display only.

5. **Write test files**:
   - BDD tests: `{TEST_DIR}/spec/{test_file_prefix}{scope_slug}.{ext}`
   - Static assertions: `{SESSION_DIR}/spec-assertions.sh`
   - Do NOT overwrite existing files

### Phase 7 Extension: Deterministic Verification

In the Phase 7 report, replace LLM-judged Success Criteria with deterministic results:

1. **Run automated tests**:
   ```bash
   # Run spec test file if it exists
   if [ -f "{test_file}" ]; then
     {test_runner} "{test_file}" 2>&1
   fi
   ```

2. **Run static assertions**:
   ```bash
   if [ -f "${SESSION_DIR}/spec-assertions.sh" ]; then
     bash "${SESSION_DIR}/spec-assertions.sh" 2>&1
   fi
   ```

3. **Generate verification table**:
   ```
   ## Success Criteria Verification

   | # | Criterion | Type | Result | Details |
   |---|-----------|------|--------|---------|
   | 1 | API returns 200 | automated | PASS | Test passed in 0.3s |
   | 2 | Error message is user-friendly | manual | MANUAL_VERIFY | Check error page UX |
   | 3 | Config file exists | static | PASS | /etc/app.conf found |

   Pass Rate: 2/3 (67%) — 1 manual verification pending
   ```

4. **Determine overall status**:
   - All automated/static PASS + no FAIL → `PASS`
   - Any FAIL → `FAIL`
   - Only MANUAL_VERIFY remaining → `PASS_PENDING_MANUAL`
   - Test execution error → `EXECUTION_ERROR` (warn, don't fail)

## Configuration

Settings from `config.spec_verification`:
- `enabled`: Whether spec verification is active (default: true)
- `min_intensity`: Minimum intensity to run (default: standard)
- `require_user_approval`: Show approval gate (default: true)
- `auto_classify_test_type`: Auto-classify verification types (default: true)
- `max_criteria`: Maximum number of criteria (default: 10)
- `test_file_prefix`: Prefix for generated test files (default: test_acceptance_)
- `run_after_implementation`: Run tests after implementation (default: true)
- `fail_action`: What to do on test failure — "warn" or "block" (default: warn)

## Error Handling

- Test framework not detected: Generate language-agnostic pseudo-test with TODO comments
- Test execution fails: Mark as `EXECUTION_ERROR`, log warning, continue report generation
- No Success Criteria from Phase 5.5: Skip entire phase (not an error)
- User skips approval: Proceed without spec verification, note in Phase 7 report
- Static assertion file permission error: Log warning, mark as `EXECUTION_ERROR`
