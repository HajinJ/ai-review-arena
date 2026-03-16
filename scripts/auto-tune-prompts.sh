#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Auto-Tune Prompt Optimization Loop
#
# Karpathy autoresearch-inspired F1 optimization loop for review prompts.
# Iteratively mutates prompts via Claude CLI, benchmarks them, and keeps
# improvements.
#
# Usage: auto-tune-prompts.sh [--category security|bugs|...|all]
#                              [--max-iterations N]
#                              [--budget N]
#                              [--convergence-threshold N]
#                              [--config <config>]
#                              [--dry-run]
#                              [--json]
#
# Dependencies:
#   - scripts/benchmark-models.sh (F1 measurement)
#   - scripts/benchmark-utils.sh (compute_metrics, compute_weighted_f1)
#   - scripts/cache-manager.sh (memory-write/read for history)
#   - scripts/cost-estimator.sh (daily cost tracking)
#   - scripts/utils.sh (load_config, get_config_value, extract_json)
#   - claude CLI (for prompt mutation generation)
#
# Exit codes:
#   0 - Always (informational tool)
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/utils.sh"
source "$SCRIPT_DIR/benchmark-utils.sh"

ensure_jq

# =============================================================================
# Constants
# =============================================================================

LOCKFILE="${PLUGIN_DIR}/cache/.auto-tune.lock"
PROMPTS_DIR="${PLUGIN_DIR}/config/review-prompts"
# Defaults are loaded from config in init_auto_tune() with jq fallbacks.
# See config/default-config.json section "auto_tune" for default values.

# =============================================================================
# Argument Parsing
# =============================================================================

CATEGORY="all"
MAX_ITERATIONS=""
DAILY_BUDGET=""
CONVERGENCE_THRESHOLD=""
CONFIG_FILE=""
DRY_RUN="false"
OUTPUT_JSON="false"

while [ $# -gt 0 ]; do
  case "$1" in
    --category)          CATEGORY="${2:-all}"; shift 2 ;;
    --max-iterations)    MAX_ITERATIONS="${2:-}"; shift 2 ;;
    --budget)            DAILY_BUDGET="${2:-}"; shift 2 ;;
    --convergence-threshold) CONVERGENCE_THRESHOLD="${2:-}"; shift 2 ;;
    --config)            CONFIG_FILE="${2:-}"; shift 2 ;;
    --dry-run)           DRY_RUN="true"; shift ;;
    --json)              OUTPUT_JSON="true"; shift ;;
    *)                   shift ;;
  esac
done

# =============================================================================
# Config Loading
# =============================================================================

init_auto_tune() {
  # Resolve config
  if [ -z "$CONFIG_FILE" ]; then
    CONFIG_FILE=$(load_config "$(find_project_root)") || CONFIG_FILE=""
  fi

  if [ -z "$CONFIG_FILE" ] || [ ! -f "$CONFIG_FILE" ]; then
    CONFIG_FILE="${PLUGIN_DIR}/config/default-config.json"
  fi

  # Load auto_tune config values
  local cfg="$CONFIG_FILE"

  MAX_ITERATIONS="${MAX_ITERATIONS:-$(jq -r '.auto_tune.max_iterations_per_category // 10' "$cfg")}"
  MAX_TOTAL_ITERATIONS=$(jq -r '.auto_tune.max_iterations_total // 30' "$cfg")
  CONVERGENCE_THRESHOLD="${CONVERGENCE_THRESHOLD:-$(jq -r '.auto_tune.convergence_threshold_pct // 0.5' "$cfg")}"
  CONVERGENCE_WINDOW=$(jq -r '.auto_tune.convergence_window // 3' "$cfg")
  DAILY_BUDGET="${DAILY_BUDGET:-$(jq -r '.auto_tune.daily_budget_dollars // 10.0' "$cfg")}"
  BENCHMARK_MODELS=$(jq -r '.auto_tune.benchmark_models // ["codex","gemini"] | join(",")' "$cfg")
  HISTORY_TIER=$(jq -r '.auto_tune.history_memory_tier // "long-term"' "$cfg")
  BACKUP_DIR=$(jq -r '.auto_tune.backup_dir // "cache/auto-tune-backups"' "$cfg")
  LOCK_TIMEOUT=$(jq -r '.auto_tune.lock_timeout_seconds // 300' "$cfg")

  # Resolve relative backup dir
  case "$BACKUP_DIR" in
    /*) ;; # absolute
    *)  BACKUP_DIR="${PLUGIN_DIR}/${BACKUP_DIR}" ;;
  esac

  # Determine target categories
  if [ "$CATEGORY" = "all" ]; then
    TARGET_CATEGORIES=$(jq -r '.auto_tune.target_categories // ["security","bugs","performance","architecture","testing"] | .[]' "$cfg")
  else
    TARGET_CATEGORIES="$CATEGORY"
  fi

  # Verify dependencies
  if ! command -v claude &>/dev/null; then
    log_warn "Claude CLI not found. Prompt mutation requires 'claude' command."
    log_warn "Install: npm install -g @anthropic-ai/claude-code"
    CLAUDE_CLI_AVAILABLE="false"
  else
    CLAUDE_CLI_AVAILABLE="true"
  fi

  if [ ! -d "$PROMPTS_DIR" ]; then
    log_error "Review prompts directory not found: $PROMPTS_DIR"
    exit 0
  fi

  mkdir -p "$BACKUP_DIR" 2>/dev/null || true
}

# =============================================================================
# Lockfile Management
# =============================================================================

acquire_lock() {
  if [ -f "$LOCKFILE" ]; then
    local lock_pid
    lock_pid=$(cat "$LOCKFILE" 2>/dev/null || echo "")
    local lock_age=0

    if [ -f "$LOCKFILE" ]; then
      local now lock_mtime
      now=$(date +%s)
      lock_mtime=$(stat -f %m "$LOCKFILE" 2>/dev/null || stat -c %Y "$LOCKFILE" 2>/dev/null || echo "$now")
      lock_age=$((now - lock_mtime))
    fi

    # Check if lock is stale (older than LOCK_TIMEOUT)
    if [ "$lock_age" -ge "$LOCK_TIMEOUT" ]; then
      log_warn "Stale lock detected (age: ${lock_age}s). Removing."
      rm -f "$LOCKFILE"
    elif [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
      log_error "Another auto-tune process is running (PID: $lock_pid). Exiting."
      exit 0
    else
      log_warn "Orphaned lock detected. Removing."
      rm -f "$LOCKFILE"
    fi
  fi

  mkdir -p "$(dirname "$LOCKFILE")" 2>/dev/null || true
  echo "$$" > "$LOCKFILE"
}

release_lock() {
  rm -f "$LOCKFILE"
}

# =============================================================================
# Budget Guard
# =============================================================================

check_daily_budget() {
  local cache_base_dir
  cache_base_dir=$(jq -r '.cache.base_dir // "'"$HOME"'/.claude/plugins/ai-review-arena/cache"' "$CONFIG_FILE" || echo "$HOME/.claude/plugins/ai-review-arena/cache")
  cache_base_dir="${cache_base_dir/#\~/$HOME}"

  local cost_dir="${cache_base_dir}/cost-tracking"
  local today
  today=$(date +%Y-%m-%d)
  local daily_file="${cost_dir}/${today}.json"

  local daily_total="0.0"
  if [ -f "$daily_file" ]; then
    daily_total=$(jq -r '.total_cost // 0' "$daily_file" || echo "0.0")
  fi

  local exceeds
  exceeds=$(awk -v total="$daily_total" -v budget="$DAILY_BUDGET" 'BEGIN { print (total >= budget) ? "1" : "0" }')

  if [ "$exceeds" = "1" ]; then
    log_warn "Daily budget exhausted: \$${daily_total} >= \$${DAILY_BUDGET}. Stopping."
    return 1
  fi

  return 0
}

# =============================================================================
# Benchmark Execution
# =============================================================================

run_benchmark_for_category() {
  local category="$1"

  local result
  result=$(bash "$SCRIPT_DIR/benchmark-models.sh" \
    --category "$category" \
    --models "$BENCHMARK_MODELS" \
    --config "$CONFIG_FILE" 2>/dev/null)

  echo "$result"
}

# =============================================================================
# F1 Computation
# =============================================================================

compute_category_f1() {
  local benchmark_result="$1"
  local category="$2"

  # Extract F1 scores from each model for this category, compute weighted average
  local total_f1=0
  local model_count=0

  local models
  models=$(echo "$benchmark_result" | jq -r '.scores | keys[]' 2>/dev/null || echo "")

  for model in $models; do
    local f1
    # Try exact category match first, then prefix match
    f1=$(echo "$benchmark_result" | jq -r --arg m "$model" --arg c "$category" \
      '.scores[$m] | map(select(.category == $c or (.category | startswith($c)))) | .[0].f1 // 0' 2>/dev/null || echo "0")

    if [ "$f1" != "0" ] && [ "$f1" != "null" ]; then
      total_f1=$((total_f1 + f1))
      model_count=$((model_count + 1))
    fi
  done

  if [ "$model_count" -gt 0 ]; then
    echo $((total_f1 / model_count))
  else
    echo "0"
  fi
}

# =============================================================================
# Prompt Mutation
# =============================================================================

generate_prompt_mutation() {
  local category="$1"
  local current_f1="$2"
  local prompt_file="$3"
  local iteration="$4"

  if [ "$CLAUDE_CLI_AVAILABLE" != "true" ]; then
    log_warn "Claude CLI unavailable. Cannot generate prompt mutation."
    return 1
  fi

  local current_prompt
  current_prompt=$(cat "$prompt_file")

  local mutation_prompt="You are optimizing a code review prompt for the '${category}' category.

Current F1 score: ${current_f1}%
Iteration: ${iteration}

CURRENT PROMPT:
---
${current_prompt}
---

TASK:
Improve this prompt to achieve a higher F1 score on code review benchmarks.
Focus on:
- Making detection patterns more specific to reduce false positives
- Adding coverage for common vulnerability/bug patterns to reduce false negatives
- Improving the clarity of instructions for the AI reviewer

OUTPUT RULES:
- Output ONLY the improved prompt text
- Do NOT include any explanation, preamble, or markdown formatting
- Preserve the general structure and format of the original prompt
- Make targeted, incremental improvements (not a complete rewrite)"

  local mutated
  mutated=$(echo "$mutation_prompt" | claude -p 2>/dev/null)

  if [ -z "$mutated" ]; then
    log_warn "Claude CLI returned empty mutation for ${category}."
    return 1
  fi

  echo "$mutated"
}

# =============================================================================
# Backup & Restore
# =============================================================================

backup_prompt() {
  local prompt_file="$1"
  local iteration="$2"
  local category="$3"

  local backup_path="${BACKUP_DIR}/${category}.bak.${iteration}"
  cp "$prompt_file" "$backup_path"
  echo "$backup_path"
}

restore_prompt() {
  local prompt_file="$1"
  local backup_path="$2"

  if [ -f "$backup_path" ]; then
    cp "$backup_path" "$prompt_file"
    return 0
  fi
  return 1
}

# =============================================================================
# History Management
# =============================================================================

save_iteration_history() {
  local category="$1"
  local iteration="$2"
  local old_f1="$3"
  local new_f1="$4"
  local kept="$5"

  local project_root
  project_root=$(find_project_root)

  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  local entry
  entry=$(jq -n \
    --arg cat "$category" \
    --argjson iter "$iteration" \
    --argjson old_f1 "$old_f1" \
    --argjson new_f1 "$new_f1" \
    --arg kept "$kept" \
    --arg ts "$timestamp" \
    '{
      category: $cat,
      iteration: $iter,
      old_f1: $old_f1,
      new_f1: $new_f1,
      kept: ($kept == "true"),
      timestamp: $ts
    }')

  local history_key="auto-tune-${category}"

  # Read existing history, append, and write back
  local existing
  existing=$(bash "$SCRIPT_DIR/cache-manager.sh" memory-read "$project_root" "$HISTORY_TIER" "$history_key" 2>/dev/null || echo "[]")

  if ! echo "$existing" | jq empty 2>/dev/null; then
    existing="[]"
  fi

  local updated
  updated=$(echo "$existing" | jq --argjson entry "$entry" '. + [$entry]')

  echo "$updated" | bash "$SCRIPT_DIR/cache-manager.sh" memory-write "$project_root" "$HISTORY_TIER" "$history_key" 2>/dev/null || true
}

# =============================================================================
# Convergence Detection
# =============================================================================

check_convergence() {
  local recent_deltas="$1"
  # recent_deltas is a space-separated list of F1 deltas

  local count=0
  local all_below="true"

  for delta in $recent_deltas; do
    count=$((count + 1))
    # Check if abs(delta) > threshold
    local above
    above=$(awk -v d="$delta" -v t="$CONVERGENCE_THRESHOLD" 'BEGIN { print (d > t || d < -t) ? "1" : "0" }')
    if [ "$above" = "1" ]; then
      all_below="false"
    fi
  done

  if [ "$count" -ge "$CONVERGENCE_WINDOW" ] && [ "$all_below" = "true" ]; then
    return 0  # converged
  fi
  return 1  # not converged
}

# =============================================================================
# Cleanup Trap
# =============================================================================

cleanup_on_exit() {
  release_lock
  log_info "Auto-tune cleanup complete."
}

trap cleanup_on_exit EXIT SIGTERM SIGINT

# =============================================================================
# Main Loop
# =============================================================================

run_auto_tune_loop() {
  local total_iterations=0
  local results_json="[]"

  for category in $TARGET_CATEGORIES; do
    local prompt_file="${PROMPTS_DIR}/${category}.txt"

    if [ ! -f "$prompt_file" ]; then
      log_warn "Prompt file not found for category '${category}': ${prompt_file}"
      continue
    fi

    log_info "=== Auto-tuning category: ${category} ==="

    # 1. Baseline: measure current F1
    local baseline_f1=0
    if [ "$DRY_RUN" = "true" ]; then
      log_info "[DRY-RUN] Skipping baseline benchmark for ${category}. Using F1=0."
    else
      log_info "Measuring baseline F1 for ${category}..."
      local baseline_result
      baseline_result=$(run_benchmark_for_category "$category")
      baseline_f1=$(compute_category_f1 "$baseline_result" "$category")
    fi

    log_info "Baseline F1 for ${category}: ${baseline_f1}%"

    local current_f1="$baseline_f1"
    local iteration=0
    local recent_deltas=""
    local improvements=0

    while [ "$iteration" -lt "$MAX_ITERATIONS" ] && [ "$total_iterations" -lt "$MAX_TOTAL_ITERATIONS" ]; do
      iteration=$((iteration + 1))
      total_iterations=$((total_iterations + 1))

      # Budget check
      if ! check_daily_budget; then
        log_info "Budget exceeded. Stopping auto-tune."
        break 2
      fi

      log_info "--- Iteration ${iteration}/${MAX_ITERATIONS} for ${category} (total: ${total_iterations}/${MAX_TOTAL_ITERATIONS}) ---"

      if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would mutate ${prompt_file}"
        log_info "[DRY-RUN] Would benchmark category ${category}"
        log_info "[DRY-RUN] Would compare F1 and keep/revert"

        # Simulate a small improvement for dry-run output
        local sim_delta=1
        recent_deltas="${recent_deltas} ${sim_delta}"
        save_iteration_history "$category" "$iteration" "$current_f1" "$((current_f1 + sim_delta))" "true" 2>/dev/null || true
        continue
      fi

      # 2. Backup current prompt
      local backup_path
      backup_path=$(backup_prompt "$prompt_file" "$iteration" "$category")

      # 3. Generate mutation via Claude CLI
      log_info "Generating prompt mutation via Claude CLI..."
      local mutated
      mutated=$(generate_prompt_mutation "$category" "$current_f1" "$prompt_file" "$iteration")

      if [ -z "$mutated" ]; then
        log_warn "Mutation generation failed. Skipping iteration."
        restore_prompt "$prompt_file" "$backup_path"
        recent_deltas="${recent_deltas} 0"
        continue
      fi

      # Write mutated prompt
      echo "$mutated" > "$prompt_file"

      # 4. Re-benchmark
      log_info "Benchmarking mutated prompt..."
      local new_result
      new_result=$(run_benchmark_for_category "$category")
      local new_f1
      new_f1=$(compute_category_f1 "$new_result" "$category")

      local delta=$((new_f1 - current_f1))
      log_info "F1: ${current_f1}% → ${new_f1}% (Δ${delta}%)"

      # 5. Keep or revert
      if [ "$new_f1" -gt "$current_f1" ]; then
        log_info "IMPROVED: Keeping mutated prompt."
        current_f1="$new_f1"
        improvements=$((improvements + 1))
        save_iteration_history "$category" "$iteration" "$((current_f1 - delta))" "$current_f1" "true"
      else
        log_info "NO IMPROVEMENT: Reverting to backup."
        restore_prompt "$prompt_file" "$backup_path"
        save_iteration_history "$category" "$iteration" "$current_f1" "$new_f1" "false"
      fi

      # Track delta for convergence
      local abs_delta
      abs_delta=$(awk -v d="$delta" 'BEGIN { print (d < 0) ? -d : d }')
      recent_deltas="${recent_deltas} ${abs_delta}"

      # Keep only last CONVERGENCE_WINDOW deltas
      local delta_count
      delta_count=$(echo "$recent_deltas" | wc -w | tr -d ' ')
      if [ "$delta_count" -gt "$CONVERGENCE_WINDOW" ]; then
        recent_deltas=$(echo "$recent_deltas" | tr ' ' '\n' | tail -n "$CONVERGENCE_WINDOW" | tr '\n' ' ')
      fi

      # 6. Convergence check
      if check_convergence "$recent_deltas"; then
        log_info "Converged: ΔF1 < ${CONVERGENCE_THRESHOLD}% for ${CONVERGENCE_WINDOW} consecutive iterations."
        break
      fi
    done

    local category_result
    category_result=$(jq -n \
      --arg cat "$category" \
      --argjson baseline "$baseline_f1" \
      --argjson final "$current_f1" \
      --argjson iterations "$iteration" \
      --argjson improvements "$improvements" \
      '{
        category: $cat,
        baseline_f1: $baseline,
        final_f1: $final,
        iterations: $iterations,
        improvements: $improvements,
        delta: ($final - $baseline)
      }')

    results_json=$(echo "$results_json" | jq --argjson r "$category_result" '. + [$r]')

    log_info "Category ${category}: F1 ${baseline_f1}% → ${current_f1}% (${improvements} improvements in ${iteration} iterations)"
  done

  echo "$results_json"
}

# =============================================================================
# Entry Point
# =============================================================================

init_auto_tune

# Acquire lock
acquire_lock

log_info "Auto-tune started: categories=[${TARGET_CATEGORIES}] max_iter=${MAX_ITERATIONS} budget=\$${DAILY_BUDGET}"

if [ "$DRY_RUN" = "true" ]; then
  log_info "=== DRY-RUN MODE: No actual prompt modifications ==="
fi

RESULTS=$(run_auto_tune_loop)

# Output
if [ "$OUTPUT_JSON" = "true" ]; then
  echo "$RESULTS"
else
  # Human-readable summary
  echo ""
  echo "=== Auto-Tune Results ==="
  echo "$RESULTS" | jq -r '.[] | "  \(.category): F1 \(.baseline_f1)% → \(.final_f1)% (Δ\(.delta)%, \(.improvements) improvements in \(.iterations) iterations)"'
  echo ""
fi

exit 0
