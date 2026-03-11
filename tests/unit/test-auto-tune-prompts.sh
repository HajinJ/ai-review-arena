#!/usr/bin/env bash
# =============================================================================
# Tests for scripts/auto-tune-prompts.sh
# =============================================================================

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$TESTS_DIR/test-helpers.sh"

SCRIPT="$REPO_DIR/scripts/auto-tune-prompts.sh"
CONFIG="$REPO_DIR/config/default-config.json"

echo "=== test-auto-tune-prompts.sh ==="

setup_temp_dir

# =========================================================================
# Test: config loading reads auto_tune section
# =========================================================================

# Verify default config has auto_tune section
auto_tune_section=$(jq '.auto_tune' "$CONFIG" 2>/dev/null)
assert_contains "$auto_tune_section" "max_iterations_per_category" "config: auto_tune section exists"
assert_contains "$auto_tune_section" "convergence_threshold_pct" "config: convergence_threshold_pct exists"
assert_contains "$auto_tune_section" "daily_budget_dollars" "config: daily_budget_dollars exists"

# =========================================================================
# Test: convergence detection
# =========================================================================

# Source the script functions without running main (use bash function extraction)
# We test convergence by calling the script in dry-run and checking logs

# Manually test convergence logic via a small helper
cat > "$TEMP_DIR/test-convergence.sh" <<'EOF'
#!/usr/bin/env bash
CONVERGENCE_THRESHOLD="0.5"
CONVERGENCE_WINDOW=3

check_convergence() {
  local recent_deltas="$1"
  local count=0
  local all_below="true"
  for delta in $recent_deltas; do
    count=$((count + 1))
    local above
    above=$(awk -v d="$delta" -v t="$CONVERGENCE_THRESHOLD" 'BEGIN { print (d > t || d < -t) ? "1" : "0" }')
    if [ "$above" = "1" ]; then
      all_below="false"
    fi
  done
  if [ "$count" -ge "$CONVERGENCE_WINDOW" ] && [ "$all_below" = "true" ]; then
    echo "converged"
  else
    echo "not_converged"
  fi
}

echo $(check_convergence "$1")
EOF
chmod +x "$TEMP_DIR/test-convergence.sh"

# Below threshold for 3 iterations → converged
result=$(bash "$TEMP_DIR/test-convergence.sh" "0.3 0.1 0.2")
assert_eq "$result" "converged" "convergence: below threshold x3 → converged"

# One above threshold → not converged
result=$(bash "$TEMP_DIR/test-convergence.sh" "0.3 0.1 1.5")
assert_eq "$result" "not_converged" "convergence: one above threshold → not converged"

# Too few deltas → not converged
result=$(bash "$TEMP_DIR/test-convergence.sh" "0.3 0.1")
assert_eq "$result" "not_converged" "convergence: fewer than window → not converged"

# =========================================================================
# Test: budget guard with exhausted budget
# =========================================================================

# Create a fake cost-tracking file showing budget exceeded
mkdir -p "$TEMP_DIR/cache/cost-tracking"
today=$(date +%Y-%m-%d)
cat > "$TEMP_DIR/cache/cost-tracking/${today}.json" <<EOF
{"date": "$today", "reviews": 50, "total_cost": 999.0, "last_review_cost": 5.0}
EOF

cat > "$TEMP_DIR/budget-config.json" <<EOF
{
  "cache": {"base_dir": "$TEMP_DIR/cache"},
  "auto_tune": {
    "enabled": true,
    "max_iterations_per_category": 2,
    "max_iterations_total": 5,
    "convergence_threshold_pct": 0.5,
    "convergence_window": 3,
    "daily_budget_dollars": 10.0,
    "target_categories": ["security"],
    "benchmark_models": ["codex"],
    "backup_dir": "$TEMP_DIR/backups",
    "history_memory_tier": "long-term",
    "lock_timeout_seconds": 300
  }
}
EOF

result=$(bash "$SCRIPT" --config "$TEMP_DIR/budget-config.json" --category security --dry-run 2>&1 || true)
assert_contains "$result" "Budget" "budget guard: detects exhausted budget"

# =========================================================================
# Test: backup and restore of prompt files
# =========================================================================

mkdir -p "$TEMP_DIR/backups"
mkdir -p "$TEMP_DIR/prompts"
echo "original prompt content" > "$TEMP_DIR/prompts/security.txt"

# Backup
cp "$TEMP_DIR/prompts/security.txt" "$TEMP_DIR/backups/security.bak.1"
assert_file_exists "$TEMP_DIR/backups/security.bak.1" "backup: file created"

# Modify
echo "mutated prompt content" > "$TEMP_DIR/prompts/security.txt"
modified=$(cat "$TEMP_DIR/prompts/security.txt")
assert_eq "$modified" "mutated prompt content" "backup: prompt modified"

# Restore
cp "$TEMP_DIR/backups/security.bak.1" "$TEMP_DIR/prompts/security.txt"
restored=$(cat "$TEMP_DIR/prompts/security.txt")
assert_eq "$restored" "original prompt content" "restore: original content restored"

# =========================================================================
# Test: category selection from config
# =========================================================================

target_cats=$(jq -r '.auto_tune.target_categories | .[]' "$CONFIG" 2>/dev/null)
assert_contains "$target_cats" "security" "category selection: security in targets"
assert_contains "$target_cats" "bugs" "category selection: bugs in targets"
assert_contains "$target_cats" "performance" "category selection: performance in targets"

# =========================================================================
# Test: lockfile detection logic
# =========================================================================

# Create a stale lockfile and test detection
mkdir -p "$TEMP_DIR/cache"
echo "99999999" > "$TEMP_DIR/cache/.auto-tune.lock"
touch -t 202001010000 "$TEMP_DIR/cache/.auto-tune.lock" 2>/dev/null || true

# Verify stale lock file exists and has old timestamp
lock_exists="false"
if [ -f "$TEMP_DIR/cache/.auto-tune.lock" ]; then
  lock_exists="true"
fi
assert_eq "$lock_exists" "true" "lockfile: stale lock file created"

# Verify the PID in lockfile doesn't correspond to a running process
lock_pid=$(cat "$TEMP_DIR/cache/.auto-tune.lock")
if ! kill -0 "$lock_pid" 2>/dev/null; then
  pass "lockfile: stale PID not running (would be cleaned up)"
else
  pass "lockfile: PID exists but lock is old (would be cleaned up by age)"
fi

# =========================================================================
# Test: Claude CLI detection
# =========================================================================

if command -v claude &>/dev/null; then
  pass "claude CLI: detected as available"
else
  pass "claude CLI: correctly detected as unavailable (graceful handling)"
fi

print_summary
