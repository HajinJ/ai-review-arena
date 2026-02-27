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

print_summary
