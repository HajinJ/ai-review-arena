#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Batch Worktree Review
#
# Leverages Claude Code native git worktree parallelism for fleet/swarm mode.
# Each review target gets its own isolated worktree, preventing cross-contamination
# and enabling true parallel execution without subprocess management overhead.
#
# Modes:
#   fleet  - Same review role applied across multiple files/repos
#   swarm  - Different review roles applied to same target in parallel
#
# Usage:
#   ./batch-worktree-review.sh --mode fleet --role security [file1 file2 ...]
#   ./batch-worktree-review.sh --mode swarm --roles security,bugs,performance <file>
#   echo "file1\nfile2" | ./batch-worktree-review.sh --mode fleet --role security --stdin
#
# Falls back to codex-batch-review.sh subprocess model when:
#   - Git worktree is unavailable
#   - batch_worktree.enabled is false
#   - batch_worktree.fallback_to_subprocess is true and worktree creation fails
#
# Exit codes:
#   0 - Always (review tool)
# =============================================================================

set -uo pipefail

# --- Constants ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/utils.sh"

ensure_jq

# =============================================================================
# Argument Parsing
# =============================================================================

MODE=""
ROLE=""
ROLES=""
CONFIG_FILE=""
USE_STDIN="false"
FILES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)     MODE="${2:-}"; shift 2 ;;
    --role)     ROLE="${2:-}"; shift 2 ;;
    --roles)    ROLES="${2:-}"; shift 2 ;;
    --config)   CONFIG_FILE="${2:-}"; shift 2 ;;
    --stdin)    USE_STDIN="true"; shift ;;
    -*)         shift ;;
    *)          FILES+=("$1"); shift ;;
  esac
done

# Read from stdin if requested
if [ "$USE_STDIN" = "true" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && FILES+=("$line")
  done
fi

# Validate mode
case "${MODE:-fleet}" in
  fleet|swarm) ;;
  *) MODE="fleet" ;;
esac

# =============================================================================
# Config Loading
# =============================================================================

if [ -z "$CONFIG_FILE" ]; then
  CONFIG_FILE=$(load_config "$(find_project_root)") || CONFIG_FILE=""
fi
if [ -z "$CONFIG_FILE" ] || [ ! -f "$CONFIG_FILE" ]; then
  CONFIG_FILE="${PLUGIN_DIR}/config/default-config.json"
fi

# Read batch_worktree config
_BW_VALUES=$(jq -r '[
  (.fleet_swarm.batch_worktree.enabled // true),
  (.fleet_swarm.batch_worktree.prefer_native // true),
  (.fleet_swarm.batch_worktree.max_worktrees // 10),
  (.fleet_swarm.batch_worktree.cleanup_on_complete // true),
  (.fleet_swarm.batch_worktree.worktree_base // ".claude/worktrees"),
  (.fleet_swarm.batch_worktree.fallback_to_subprocess // true)
] | @tsv' "$CONFIG_FILE") || _BW_VALUES=""

IFS=$'\t' read -r bw_enabled bw_prefer_native bw_max_worktrees bw_cleanup bw_base bw_fallback <<< "$_BW_VALUES"

# Read convergence strategy for swarm mode
CONVERGENCE_STRATEGY=$(jq -r '.fleet_swarm.swarm.convergence_strategy // "debate_arbitrator"' "$CONFIG_FILE")
SIGNAL_SHARING=$(jq -r '.fleet_swarm.swarm.signal_sharing // true' "$CONFIG_FILE")

# =============================================================================
# Worktree Availability Check
# =============================================================================

WORKTREE_AVAILABLE="false"
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

if [ -n "$PROJECT_ROOT" ] && git worktree list &>/dev/null; then
  WORKTREE_AVAILABLE="true"
fi

# =============================================================================
# Fallback Decision
# =============================================================================

USE_WORKTREE="false"
if [ "$bw_enabled" = "true" ] && [ "$bw_prefer_native" = "true" ] && [ "$WORKTREE_AVAILABLE" = "true" ]; then
  USE_WORKTREE="true"
fi

if [ "$USE_WORKTREE" != "true" ] && [ "$bw_fallback" = "true" ]; then
  # Fallback to subprocess-based batch review
  log_info "batch-worktree: Falling back to subprocess-based review"

  if [ "$MODE" = "fleet" ] && [ -n "$ROLE" ]; then
    exec "$SCRIPT_DIR/codex-batch-review.sh" "$ROLE" "$CONFIG_FILE" "${FILES[@]}"
  elif [ "$MODE" = "swarm" ] && [ -n "$ROLES" ]; then
    # For swarm: run each role as a separate batch
    RESULTS="[]"
    IFS=',' read -ra ROLE_ARRAY <<< "$ROLES"
    for role in "${ROLE_ARRAY[@]}"; do
      ROLE_RESULT=$("$SCRIPT_DIR/codex-batch-review.sh" "$role" "$CONFIG_FILE" "${FILES[@]}" 2>/dev/null || echo "[]")
      RESULTS=$(echo "$RESULTS" | jq --argjson r "$ROLE_RESULT" '. + $r')
    done
    echo "$RESULTS"
    exit 0
  fi
  exit 0
fi

if [ "$USE_WORKTREE" != "true" ]; then
  echo '{"error": "Worktree not available and fallback disabled", "results": []}'
  exit 0
fi

# =============================================================================
# Worktree-Based Parallel Execution
# =============================================================================

WORKTREE_DIR="${PROJECT_ROOT}/${bw_base}/arena-batch-$$"
RESULTS_DIR=$(mktemp -d)
WORKTREE_PIDS=()
CREATED_WORKTREES=()

cleanup_worktrees() {
  # Kill remaining processes
  for pid in "${WORKTREE_PIDS[@]+${WORKTREE_PIDS[@]}}"; do
    kill "$pid" 2>/dev/null || true
  done

  # Clean up worktrees
  if [ "$bw_cleanup" = "true" ]; then
    for wt in "${CREATED_WORKTREES[@]+${CREATED_WORKTREES[@]}}"; do
      git worktree remove "$wt" --force 2>/dev/null || true
    done
    rmdir "$WORKTREE_DIR" 2>/dev/null || true
  fi

  rm -rf "$RESULTS_DIR" 2>/dev/null || true
}
trap cleanup_worktrees EXIT INT TERM

mkdir -p "$WORKTREE_DIR" 2>/dev/null || true

# --- Determine current branch ---
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
CURRENT_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")

# --- Throttle helper ---
ACTIVE_WORKTREES=0

_throttle_worktrees() {
  while [ "$ACTIVE_WORKTREES" -ge "$bw_max_worktrees" ]; do
    local new_pids=()
    for pid in "${WORKTREE_PIDS[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        new_pids+=("$pid")
      else
        ACTIVE_WORKTREES=$((ACTIVE_WORKTREES - 1))
      fi
    done
    WORKTREE_PIDS=("${new_pids[@]+${new_pids[@]}}")
    if [ "$ACTIVE_WORKTREES" -ge "$bw_max_worktrees" ]; then
      sleep 0.5
    fi
  done
}

# =============================================================================
# Execute: Fleet Mode
# =============================================================================

_run_review_in_worktree() {
  local worktree_path="$1"
  local file="$2"
  local role="$3"
  local result_file="$4"

  # Determine which review script to use
  local review_script=""
  if command -v codex &>/dev/null; then
    review_script="$SCRIPT_DIR/codex-review.sh"
  elif command -v gemini &>/dev/null; then
    review_script="$SCRIPT_DIR/gemini-review.sh"
  fi

  if [ -z "$review_script" ]; then
    echo '{"error": "No review CLI available", "findings": []}' > "$result_file"
    return
  fi

  # Run review in worktree context
  local wt_file="${worktree_path}/${file}"
  if [ -f "$wt_file" ]; then
    cat "$wt_file" | "$review_script" "$file" "$CONFIG_FILE" "$role" > "$result_file" 2>/dev/null || \
      echo "{\"error\": \"Review failed\", \"file\": \"$file\", \"role\": \"$role\", \"findings\": []}" > "$result_file"
  else
    echo "{\"error\": \"File not found in worktree\", \"file\": \"$file\", \"role\": \"$role\", \"findings\": []}" > "$result_file"
  fi
}

if [ "$MODE" = "fleet" ]; then
  # Fleet: same role across multiple files, each in its own worktree
  [ -z "$ROLE" ] && ROLE="security"

  TASK_INDEX=0
  for file in "${FILES[@]}"; do
    _throttle_worktrees

    WT_NAME="fleet-${TASK_INDEX}"
    WT_PATH="${WORKTREE_DIR}/${WT_NAME}"
    BRANCH_NAME="arena/fleet-${WT_NAME}-$$"
    RESULT_FILE="${RESULTS_DIR}/result_${TASK_INDEX}.json"

    # Create worktree
    if git worktree add "$WT_PATH" -b "$BRANCH_NAME" "$CURRENT_SHA" --quiet 2>/dev/null; then
      CREATED_WORKTREES+=("$WT_PATH")

      (
        _run_review_in_worktree "$WT_PATH" "$file" "$ROLE" "$RESULT_FILE"
      ) &
      WORKTREE_PIDS+=($!)
      ACTIVE_WORKTREES=$((ACTIVE_WORKTREES + 1))
    else
      # Worktree creation failed — run directly
      log_warn "batch-worktree: Failed to create worktree for $file, running in-process"
      if [ -f "$file" ]; then
        cat "$file" | "$SCRIPT_DIR/codex-review.sh" "$file" "$CONFIG_FILE" "$ROLE" > "$RESULT_FILE" 2>/dev/null || \
          echo "{\"error\": \"Direct review failed\", \"file\": \"$file\", \"findings\": []}" > "$RESULT_FILE"
      fi
    fi

    TASK_INDEX=$((TASK_INDEX + 1))
  done
fi

# =============================================================================
# Execute: Swarm Mode
# =============================================================================

if [ "$MODE" = "swarm" ]; then
  # Swarm: multiple roles on same file(s), each role in its own worktree
  [ -z "$ROLES" ] && ROLES="security,bugs,performance"
  IFS=',' read -ra ROLE_ARRAY <<< "$ROLES"

  TARGET_FILE="${FILES[0]:-}"
  if [ -z "$TARGET_FILE" ]; then
    echo '{"error": "No target file specified for swarm mode", "results": []}'
    exit 0
  fi

  TASK_INDEX=0
  for role in "${ROLE_ARRAY[@]}"; do
    _throttle_worktrees

    WT_NAME="swarm-${role}-${TASK_INDEX}"
    WT_PATH="${WORKTREE_DIR}/${WT_NAME}"
    BRANCH_NAME="arena/swarm-${WT_NAME}-$$"
    RESULT_FILE="${RESULTS_DIR}/result_${TASK_INDEX}.json"

    if git worktree add "$WT_PATH" -b "$BRANCH_NAME" "$CURRENT_SHA" --quiet 2>/dev/null; then
      CREATED_WORKTREES+=("$WT_PATH")

      (
        # If signal sharing is enabled, write signals for other agents
        if [ "$SIGNAL_SHARING" = "true" ]; then
          SIGNAL_FILE="${RESULTS_DIR}/signal_${role}.json"
          _run_review_in_worktree "$WT_PATH" "$TARGET_FILE" "$role" "$RESULT_FILE"
          # Extract key signals for convergence
          if [ -f "$RESULT_FILE" ] && jq . "$RESULT_FILE" &>/dev/null; then
            jq --arg role "$role" '{role: $role, signals: [.findings[]? | {severity, category, line}]}' \
              "$RESULT_FILE" > "$SIGNAL_FILE" 2>/dev/null || true
          fi
        else
          _run_review_in_worktree "$WT_PATH" "$TARGET_FILE" "$role" "$RESULT_FILE"
        fi
      ) &
      WORKTREE_PIDS+=($!)
      ACTIVE_WORKTREES=$((ACTIVE_WORKTREES + 1))
    else
      # Fallback: run directly
      if [ -f "$TARGET_FILE" ]; then
        local_review_script="$SCRIPT_DIR/codex-review.sh"
        command -v codex &>/dev/null || local_review_script="$SCRIPT_DIR/gemini-review.sh"
        cat "$TARGET_FILE" | "$local_review_script" "$TARGET_FILE" "$CONFIG_FILE" "$role" > "$RESULT_FILE" 2>/dev/null || \
          echo "{\"error\": \"Review failed\", \"role\": \"$role\", \"findings\": []}" > "$RESULT_FILE"
      fi
    fi

    TASK_INDEX=$((TASK_INDEX + 1))
  done
fi

# =============================================================================
# Wait & Aggregate
# =============================================================================

for pid in "${WORKTREE_PIDS[@]+${WORKTREE_PIDS[@]}}"; do
  wait "$pid" 2>/dev/null || true
done

# --- Clean up worktree branches ---
for wt in "${CREATED_WORKTREES[@]+${CREATED_WORKTREES[@]}}"; do
  git worktree remove "$wt" --force 2>/dev/null || true
done
CREATED_WORKTREES=()

# Remove temporary branches
git branch --list "arena/fleet-*-$$" "arena/swarm-*-$$" 2>/dev/null | while read -r branch; do
  git branch -D "$branch" 2>/dev/null || true
done

# --- Aggregate results ---
echo "["
FIRST=true
for result_file in "$RESULTS_DIR"/result_*.json; do
  [ ! -f "$result_file" ] && continue
  if jq . "$result_file" &>/dev/null; then
    [ "$FIRST" = "true" ] && FIRST=false || echo ","
    cat "$result_file"
  fi
done
echo "]"

# --- Swarm convergence: output signal summary ---
if [ "$MODE" = "swarm" ] && [ "$SIGNAL_SHARING" = "true" ]; then
  SIGNAL_FILES=("$RESULTS_DIR"/signal_*.json)
  if [ ${#SIGNAL_FILES[@]} -gt 0 ]; then
    log_info "batch-worktree: Swarm signal convergence (${#SIGNAL_FILES[@]} agents)"
    # Signals are available in RESULTS_DIR for debate-arbitrator consumption
  fi
fi

exit 0
