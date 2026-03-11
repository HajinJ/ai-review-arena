#!/usr/bin/env bash
# =============================================================================
# Tests for scripts/context-filter.sh
# =============================================================================

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$TESTS_DIR/test-helpers.sh"

SCRIPT="$REPO_DIR/scripts/context-filter.sh"

echo "=== test-context-filter.sh ==="

setup_temp_dir

# Use the real default config for role filter patterns
CONFIG="$REPO_DIR/config/default-config.json"

# =========================================================================
# Test: role_to_filter_key mapping for "security" role
# =========================================================================

# We test this indirectly by feeding security-relevant files
# Create test source files
mkdir -p "$TEMP_DIR/src"

cat > "$TEMP_DIR/src/auth.ts" <<'EOF'
import { hash } from 'crypto';

export function login(username: string, password: string) {
  const token = hash(password + 'salt');
  if (!sanitize(username)) {
    throw new Error('Invalid input');
  }
  return createSession(token);
}

function sanitize(input: string): string {
  return input.replace(/[<>]/g, '');
}
EOF

cat > "$TEMP_DIR/src/utils.ts" <<'EOF'
export function add(a: number, b: number) {
  return a + b;
}

export function subtract(a: number, b: number) {
  return a - b;
}
EOF

# =========================================================================
# Test: security role filters security-related content
# =========================================================================

result=$(echo "$TEMP_DIR/src/auth.ts" | bash "$SCRIPT" security-reviewer "$CONFIG" --budget 8000 2>/dev/null)
assert_contains "$result" "auth.ts" "security role: includes auth.ts"
assert_contains "$result" "login" "security role: includes login function"

# =========================================================================
# Test: file filtering by include_file_patterns
# =========================================================================

# The security role has include_file_patterns: ["*auth*", "*security*", "*middleware*", "*session*", "*crypto*"]
# auth.ts should match, utils.ts should not match (when file patterns are active)
result=$(printf "%s\n%s\n" "$TEMP_DIR/src/auth.ts" "$TEMP_DIR/src/utils.ts" | \
  bash "$SCRIPT" security-reviewer "$CONFIG" --budget 8000 2>/dev/null)

assert_contains "$result" "auth.ts" "file filter: auth.ts included for security"

# =========================================================================
# Test: token budget limiting
# =========================================================================

# Create a large file to test budget
for i in $(seq 1 500); do
  echo "line $i: some code with auth and password and token handling"
done > "$TEMP_DIR/src/big-auth.ts"

# Very small budget
result=$(echo "$TEMP_DIR/src/big-auth.ts" | bash "$SCRIPT" security-reviewer "$CONFIG" --budget 100 2>/dev/null)

# With budget of 100 tokens (~25 lines at 4 tokens/line), output should be limited
line_count=$(echo "$result" | wc -l | tr -d ' ')
assert_gt 200 "$line_count" "budget limit: output limited (fewer than 200 lines for 100-token budget)"

# =========================================================================
# Test: unknown role passes all content
# =========================================================================

result=$(echo "$TEMP_DIR/src/utils.ts" | bash "$SCRIPT" "unknown-role" "$CONFIG" --budget 8000 2>/dev/null)
assert_contains "$result" "utils.ts" "unknown role: passes content through"

# =========================================================================
# Test: disabled filtering passes through
# =========================================================================

cat > "$TEMP_DIR/config-disabled.json" <<'EOF'
{
  "context_density": {
    "enabled": false,
    "agent_context_budget_tokens": 8000
  }
}
EOF

result=$(echo "$TEMP_DIR/src/auth.ts" | bash "$SCRIPT" security-reviewer "$TEMP_DIR/config-disabled.json" --budget 8000 2>/dev/null)
assert_contains "$result" "auth.ts" "disabled filter: passes content through"
assert_contains "$result" "full" "disabled filter: full content passed"

# =========================================================================
# Test: empty stdin produces no output (graceful)
# =========================================================================

result=$(echo "" | bash "$SCRIPT" security-reviewer "$CONFIG" --budget 8000 2>/dev/null)
rc=$?
assert_exit_code 0 "$rc" "empty stdin: exits 0 gracefully"

# =========================================================================
# Test: performance role filters for performance patterns
# =========================================================================

cat > "$TEMP_DIR/src/service.ts" <<'EOF'
import { cache } from './cache';

export class UserService {
  async findAll() {
    const result = await this.db.query('SELECT * FROM users');
    return result.map(u => u.toJSON());
  }

  async findCached(id: string) {
    return cache.memo(id, () => this.db.query('SELECT * FROM users WHERE id = ?', [id]));
  }
}
EOF

result=$(echo "$TEMP_DIR/src/service.ts" | bash "$SCRIPT" performance-reviewer "$CONFIG" --budget 8000 2>/dev/null)
assert_contains "$result" "service.ts" "performance role: includes service file"

# =========================================================================
# Test: project context file present → injected before code
# =========================================================================

# Create a project context file in the temp dir
cat > "$TEMP_DIR/.ai-review-arena-context.md" <<'EOF'
# Project Context
This project uses JWT authentication with RSA-256 signing.
Always validate tokens before processing requests.
EOF

# Config that points to the context file name
cat > "$TEMP_DIR/config-with-context.json" <<'CEOF'
{
  "project_context": {
    "enabled": true,
    "filename": ".ai-review-arena-context.md",
    "max_tokens": 1500,
    "inject_before_code": true
  },
  "context_density": {
    "enabled": true,
    "agent_context_budget_tokens": 8000,
    "role_filters": {},
    "fallback_on_small_files": true,
    "small_file_threshold_lines": 200
  }
}
CEOF

# Run from temp dir so the context file is found
result=$(cd "$TEMP_DIR" && echo "$TEMP_DIR/src/auth.ts" | bash "$SCRIPT" security-reviewer "$TEMP_DIR/config-with-context.json" --budget 8000 2>/dev/null)
assert_contains "$result" "PROJECT CONTEXT" "project context: header present when file exists"
assert_contains "$result" "JWT authentication" "project context: content injected"
assert_contains "$result" "auth.ts" "project context: code still present after context"

# =========================================================================
# Test: project context file absent → no injection
# =========================================================================

# Config with a filename that doesn't exist
cat > "$TEMP_DIR/config-no-context.json" <<'CEOF'
{
  "project_context": {
    "enabled": true,
    "filename": ".nonexistent-context.md",
    "max_tokens": 1500,
    "inject_before_code": true
  },
  "context_density": {
    "enabled": true,
    "agent_context_budget_tokens": 8000,
    "role_filters": {},
    "fallback_on_small_files": true,
    "small_file_threshold_lines": 200
  }
}
CEOF

result=$(cd "$TEMP_DIR" && echo "$TEMP_DIR/src/auth.ts" | bash "$SCRIPT" security-reviewer "$TEMP_DIR/config-no-context.json" --budget 8000 2>/dev/null)
assert_not_contains "$result" "PROJECT CONTEXT" "project context absent: no header when file missing"

# =========================================================================
# Test: project context disabled in config → no injection
# =========================================================================

cat > "$TEMP_DIR/config-context-disabled.json" <<'CEOF'
{
  "project_context": {
    "enabled": false,
    "filename": ".ai-review-arena-context.md",
    "max_tokens": 1500,
    "inject_before_code": true
  },
  "context_density": {
    "enabled": true,
    "agent_context_budget_tokens": 8000,
    "role_filters": {},
    "fallback_on_small_files": true,
    "small_file_threshold_lines": 200
  }
}
CEOF

result=$(cd "$TEMP_DIR" && echo "$TEMP_DIR/src/auth.ts" | bash "$SCRIPT" security-reviewer "$TEMP_DIR/config-context-disabled.json" --budget 8000 2>/dev/null)
assert_not_contains "$result" "PROJECT CONTEXT" "project context disabled: no injection"

# =========================================================================
# Test: large context file truncated to max_tokens budget
# =========================================================================

# Create a large context file (500 lines)
for i in $(seq 1 500); do
  echo "Line $i of project context documentation with important details"
done > "$TEMP_DIR/.ai-review-arena-context.md"

# Config with small max_tokens (200 tokens = 50 lines at 4 tokens/line)
cat > "$TEMP_DIR/config-small-context.json" <<'CEOF'
{
  "project_context": {
    "enabled": true,
    "filename": ".ai-review-arena-context.md",
    "max_tokens": 200,
    "inject_before_code": true
  },
  "context_density": {
    "enabled": true,
    "agent_context_budget_tokens": 8000,
    "role_filters": {},
    "fallback_on_small_files": true,
    "small_file_threshold_lines": 200
  }
}
CEOF

result=$(cd "$TEMP_DIR" && echo "$TEMP_DIR/src/auth.ts" | bash "$SCRIPT" security-reviewer "$TEMP_DIR/config-small-context.json" --budget 8000 2>/dev/null)
assert_contains "$result" "PROJECT CONTEXT" "large context: header present"
# Should NOT contain line 100 (truncated at ~50 lines)
assert_not_contains "$result" "Line 100" "large context: truncated past max_tokens"

# =========================================================================
# Test: budget deduction from project context
# =========================================================================

# Small total budget (400 tokens = 100 lines) with 200-token context = only 50 lines for code
cat > "$TEMP_DIR/config-budget-deduct.json" <<'CEOF'
{
  "project_context": {
    "enabled": true,
    "filename": ".ai-review-arena-context.md",
    "max_tokens": 200,
    "inject_before_code": true
  },
  "context_density": {
    "enabled": true,
    "agent_context_budget_tokens": 400,
    "role_filters": {},
    "fallback_on_small_files": true,
    "small_file_threshold_lines": 200
  }
}
CEOF

# Create a moderate context file
echo "This is project context." > "$TEMP_DIR/.ai-review-arena-context.md"

stderr_out=$(cd "$TEMP_DIR" && echo "$TEMP_DIR/src/big-auth.ts" | bash "$SCRIPT" security-reviewer "$TEMP_DIR/config-budget-deduct.json" --budget 400 2>&1 >/dev/null)
# Should log project context loading
assert_contains "$stderr_out" "Project context loaded" "budget deduction: context logged"

print_summary
