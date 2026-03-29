#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Context Density Filter
#
# Role-based code filtering + token budgeting for reviewer agents.
# Reduces context sent to each agent by extracting only role-relevant code.
#
# Usage: context-filter.sh <role> <config_file> [--budget N] [--context-lines N]
# Stdin:  newline-separated file paths
# Stdout: filtered code (file headers + relevant excerpts)
# Stderr: logging
# Exit:   always 0 (non-blocking)
#
# Example:
#   ls scripts/*.sh | bash scripts/context-filter.sh security-reviewer config/default-config.json
#   echo "src/auth.ts" | bash scripts/context-filter.sh security-reviewer config.json --budget 4000
# =============================================================================

set -o pipefail

# --- Source utils ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh" || true

# =============================================================================
# Constants & Defaults
# =============================================================================

DEFAULT_BUDGET=8000
DEFAULT_CONTEXT_LINES=3
SMALL_FILE_THRESHOLD=200
TOKENS_PER_LINE=4

# =============================================================================
# Role → Filter Key Mapping
# =============================================================================

role_to_filter_key() {
  local role="$1"
  case "$role" in
    security-reviewer)   echo "security" ;;
    bug-detector)        echo "bugs" ;;
    performance-reviewer) echo "performance" ;;
    architecture-reviewer) echo "architecture" ;;
    test-coverage-reviewer) echo "testing" ;;
    dependency-reviewer) echo "dependency" ;;
    scope-reviewer)      echo "scope" ;;
    api-contract-reviewer) echo "api_contract" ;;
    observability-reviewer) echo "observability" ;;
    data-integrity-reviewer) echo "data_integrity" ;;
    accessibility-reviewer) echo "accessibility" ;;
    configuration-reviewer) echo "configuration" ;;
    compliance-checker)  echo "security" ;;
    research-coordinator) echo "architecture" ;;
    *)                   echo "" ;;
  esac
}

# =============================================================================
# Argument Parsing
# =============================================================================

ROLE="${1:?Usage: context-filter.sh <role> <config_file> [--budget N] [--context-lines N]}"
CONFIG_FILE="${2:?Usage: context-filter.sh <role> <config_file> [--budget N] [--context-lines N]}"
shift 2

BUDGET="$DEFAULT_BUDGET"
CONTEXT_LINES="$DEFAULT_CONTEXT_LINES"

while [ $# -gt 0 ]; do
  case "$1" in
    --budget)
      BUDGET="${2:-$DEFAULT_BUDGET}"
      if ! [[ "$BUDGET" =~ ^[0-9]+$ ]] || [ "$BUDGET" -le 0 ]; then
        log_warn "Invalid --budget value '$BUDGET', using default $DEFAULT_BUDGET"
        BUDGET="$DEFAULT_BUDGET"
      fi
      shift 2
      ;;
    --context-lines)
      CONTEXT_LINES="${2:-$DEFAULT_CONTEXT_LINES}"
      if ! [[ "$CONTEXT_LINES" =~ ^[0-9]+$ ]]; then
        log_warn "Invalid --context-lines value '$CONTEXT_LINES', using default $DEFAULT_CONTEXT_LINES"
        CONTEXT_LINES="$DEFAULT_CONTEXT_LINES"
      fi
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

# =============================================================================
# Load Config
# =============================================================================

FILTER_KEY=$(role_to_filter_key "$ROLE")

if [ -z "$FILTER_KEY" ]; then
  log_warn "Unknown role '$ROLE', no filter key mapped. Passing all content."
  FILTER_KEY=""
fi

# Read config values
ENABLED="true"
INCLUDE_PATTERNS=""
INCLUDE_FILE_PATTERNS=""
FALLBACK_SMALL="true"

# Project context injection settings
PROJECT_CONTEXT_ENABLED="true"
PROJECT_CONTEXT_FILENAME=".ai-review-arena-context.md"
PROJECT_CONTEXT_MAX_TOKENS=1500
PROJECT_CONTEXT_INJECT_BEFORE="true"

if [ -f "$CONFIG_FILE" ] && command -v jq &>/dev/null; then
  jq empty "$CONFIG_FILE" 2>/dev/null || log_warn "Malformed JSON in config: $CONFIG_FILE. Using defaults."
  ENABLED=$(jq -r '.context_density.enabled // true' "$CONFIG_FILE")
  BUDGET_CFG=$(jq -r '.context_density.agent_context_budget_tokens // empty' "$CONFIG_FILE")
  SMALL_FILE_THRESHOLD_CFG=$(jq -r '.context_density.small_file_threshold_lines // empty' "$CONFIG_FILE")
  FALLBACK_SMALL=$(jq -r '.context_density.fallback_on_small_files // true' "$CONFIG_FILE")

  # Load project context settings
  PROJECT_CONTEXT_ENABLED=$(jq -r 'if .project_context.enabled == false then "false" else "true" end' "$CONFIG_FILE")
  PROJECT_CONTEXT_FILENAME=$(jq -r '.project_context.filename // ".ai-review-arena-context.md"' "$CONFIG_FILE")
  PROJECT_CONTEXT_MAX_TOKENS=$(jq -r '.project_context.max_tokens // 1500' "$CONFIG_FILE")
  PROJECT_CONTEXT_INJECT_BEFORE=$(jq -r 'if .project_context.inject_before_code == false then "false" else "true" end' "$CONFIG_FILE")

  # Override budget from config if not set via CLI
  if [ "$BUDGET" = "$DEFAULT_BUDGET" ] && [ -n "$BUDGET_CFG" ]; then
    BUDGET="$BUDGET_CFG"
  fi
  if [ -n "$SMALL_FILE_THRESHOLD_CFG" ]; then
    SMALL_FILE_THRESHOLD="$SMALL_FILE_THRESHOLD_CFG"
  fi

  if [ -n "$FILTER_KEY" ]; then
    INCLUDE_PATTERNS=$(jq -r --arg key "$FILTER_KEY" '.context_density.role_filters[$key].include_patterns // [] | join("|")' "$CONFIG_FILE")
    INCLUDE_FILE_PATTERNS=$(jq -r --arg key "$FILTER_KEY" '.context_density.role_filters[$key].include_file_patterns // [] | .[]' "$CONFIG_FILE")
  fi
fi

# =============================================================================
# Project Context: detect and load shared context document
# =============================================================================

PROJECT_CONTEXT_CONTENT=""
PROJECT_CONTEXT_LINES=0

if [ "$PROJECT_CONTEXT_ENABLED" = "true" ]; then
  # Search for context file: current dir, then git root
  PROJECT_CONTEXT_FILE=""
  if [ -f "$PROJECT_CONTEXT_FILENAME" ]; then
    PROJECT_CONTEXT_FILE="$PROJECT_CONTEXT_FILENAME"
  else
    GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
    if [ -n "$GIT_ROOT" ] && [ -f "${GIT_ROOT}/${PROJECT_CONTEXT_FILENAME}" ]; then
      PROJECT_CONTEXT_FILE="${GIT_ROOT}/${PROJECT_CONTEXT_FILENAME}"
    fi
  fi

  if [ -n "$PROJECT_CONTEXT_FILE" ]; then
    PROJECT_CONTEXT_MAX_LINES=$((PROJECT_CONTEXT_MAX_TOKENS / TOKENS_PER_LINE))
    PROJECT_CONTEXT_CONTENT=$(head -n "$PROJECT_CONTEXT_MAX_LINES" "$PROJECT_CONTEXT_FILE")
    PROJECT_CONTEXT_LINES=$(echo "$PROJECT_CONTEXT_CONTENT" | wc -l | tr -d ' ')
    PROJECT_CONTEXT_TOKENS=$((PROJECT_CONTEXT_LINES * TOKENS_PER_LINE))

    # Deduct project context tokens from the available budget
    BUDGET=$((BUDGET - PROJECT_CONTEXT_TOKENS))
    if [ "$BUDGET" -le 0 ]; then
      BUDGET=100
      log_warn "Project context consumed most of the budget. Minimal code budget remaining."
    fi

    log_info "Project context loaded: ${PROJECT_CONTEXT_FILE} (${PROJECT_CONTEXT_LINES} lines, ~${PROJECT_CONTEXT_TOKENS} tokens)"
  fi
fi

# If filtering disabled, pass through with truncation
if [ "$ENABLED" != "true" ]; then
  log_info "Context density filtering disabled. Passing through with line limit."
  MAX_LINES=$((BUDGET / TOKENS_PER_LINE))
  TOTAL=0
  while IFS= read -r filepath; do
    [ -f "$filepath" ] || continue
    LINES=$(wc -l < "$filepath" 2>/dev/null | tr -d ' ')
    REMAINING=$((MAX_LINES - TOTAL))
    [ "$REMAINING" -le 0 ] && break
    echo "=== FILE: ${filepath} (full, unfiltered) ==="
    head -n "$REMAINING" "$filepath" | nl -ba
    echo "=== END FILE ==="
    echo ""
    TOTAL=$((TOTAL + LINES))
  done
  exit 0
fi

# =============================================================================
# File-Level Filter: match against include_file_patterns
# =============================================================================

file_matches_role() {
  local filepath="$1"
  local basename
  basename=$(basename "$filepath")

  # No file patterns or wildcard = match everything
  if [ -z "$INCLUDE_FILE_PATTERNS" ]; then
    return 0
  fi

  local pattern
  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    # Wildcard matches all
    if [ "$pattern" = "*" ]; then
      return 0
    fi
    # Bash glob match against basename
    # shellcheck disable=SC2254
    case "$basename" in
      $pattern) return 0 ;;
    esac
    # Also check full path
    # shellcheck disable=SC2254
    case "$filepath" in
      $pattern) return 0 ;;
    esac
  done <<< "$INCLUDE_FILE_PATTERNS"

  return 1
}

# =============================================================================
# Line-Level Filter: grep include_patterns with context
# =============================================================================

filter_file_lines() {
  local filepath="$1"
  local total_lines="$2"

  # Small files: include in full
  if [ "$FALLBACK_SMALL" = "true" ] && [ "$total_lines" -le "$SMALL_FILE_THRESHOLD" ]; then
    nl -ba "$filepath"
    return
  fi

  # No patterns to grep = include full file
  if [ -z "$INCLUDE_PATTERNS" ]; then
    nl -ba "$filepath"
    return
  fi

  # Grep with context lines, using extended regex for the OR-joined patterns
  local result
  result=$(grep -n -C "$CONTEXT_LINES" -E "$INCLUDE_PATTERNS" "$filepath" 2>/dev/null | head -n 500)
  if [ -n "$result" ]; then
    echo "$result"
  else
    # If grep found nothing but file matched at file-level, include first N lines as fallback
    head -n "$SMALL_FILE_THRESHOLD" "$filepath" | nl -ba
  fi
}

# =============================================================================
# Main: Read file paths from stdin, filter, budget
# =============================================================================

# Collect file paths
FILES=()
while IFS= read -r filepath; do
  filepath=$(echo "$filepath" | tr -d '\r')
  filepath="${filepath#"${filepath%%[![:space:]]*}"}"
  filepath="${filepath%"${filepath##*[![:space:]]}"}"
  [ -z "$filepath" ] && continue
  [ -f "$filepath" ] || continue
  FILES+=("$filepath")
done

if [ ${#FILES[@]} -eq 0 ]; then
  log_warn "No valid files received on stdin."
  exit 0
fi

log_info "Context filter: role=${ROLE} filter_key=${FILTER_KEY} budget=${BUDGET} files=${#FILES[@]}"

# =============================================================================
# Pass 1: File-level filter + line counting
# =============================================================================

declare -a MATCHED_FILES=()
declare -a MATCHED_LINES=()
declare -a MATCH_DENSITIES=()
TOTAL_INPUT_FILES=${#FILES[@]}
TOTAL_MATCHED_FILES=0

for filepath in "${FILES[@]}"; do
  if ! file_matches_role "$filepath"; then
    continue
  fi

  total_lines=$(wc -l < "$filepath" 2>/dev/null | tr -d ' ')
  [[ "$total_lines" =~ ^[0-9]+$ ]] || continue
  [ "$total_lines" -eq 0 ] && continue

  # Count pattern matches once (reused for both filtered_lines and density)
  match_count=0
  if [ -n "$INCLUDE_PATTERNS" ]; then
    match_count=$(grep -c -E "$INCLUDE_PATTERNS" "$filepath" || true)
    match_count=$(echo "$match_count" | tr -dc '0-9')
    match_count=${match_count:-0}
  fi

  # Estimate filtered line count
  if [ "$FALLBACK_SMALL" = "true" ] && [ "$total_lines" -le "$SMALL_FILE_THRESHOLD" ]; then
    filtered_lines="$total_lines"
  elif [ -n "$INCLUDE_PATTERNS" ]; then
    # Each match contributes ~(1 + 2*context_lines) lines
    filtered_lines=$((match_count * (1 + 2 * CONTEXT_LINES)))
    [ "$filtered_lines" -gt "$total_lines" ] && filtered_lines="$total_lines"
    if [ "$filtered_lines" -eq 0 ]; then
      # No matches: fallback to min(total_lines, SMALL_FILE_THRESHOLD)
      filtered_lines=$(( total_lines < SMALL_FILE_THRESHOLD ? total_lines : SMALL_FILE_THRESHOLD ))
    fi
  else
    filtered_lines="$total_lines"
  fi

  # Density = match_count / total_lines (as integer percentage)
  if [ -n "$INCLUDE_PATTERNS" ] && [ "$total_lines" -gt 0 ]; then
    density=$((match_count * 100 / total_lines))
  else
    density=50
  fi

  MATCHED_FILES+=("$filepath")
  MATCHED_LINES+=("$filtered_lines")
  MATCH_DENSITIES+=("$density")
  TOTAL_MATCHED_FILES=$((TOTAL_MATCHED_FILES + 1))
done

if [ "$TOTAL_MATCHED_FILES" -eq 0 ]; then
  log_warn "No files matched role filter for '${ROLE}'."
  exit 0
fi

# =============================================================================
# Pass 2: Token budgeting — prioritize by match density
# =============================================================================

BUDGET_LINES=$((BUDGET / TOKENS_PER_LINE))
TOTAL_FILTERED_LINES=0
for lines in "${MATCHED_LINES[@]}"; do
  TOTAL_FILTERED_LINES=$((TOTAL_FILTERED_LINES + lines))
done

TOTAL_FILTERED_TOKENS=$((TOTAL_FILTERED_LINES * TOKENS_PER_LINE))

# Check if chunking is needed
if [ "$TOTAL_FILTERED_TOKENS" -gt $((BUDGET * 2)) ]; then
  echo "CHUNKING_NEEDED" >&2
  log_warn "Filtered content (${TOTAL_FILTERED_TOKENS} tokens) exceeds 2x budget (${BUDGET}). Chunking recommended."
fi

# Sort files by density (descending) — POSIX-compatible insertion sort
SORTED_INDICES=()
for i in $(seq 0 $((TOTAL_MATCHED_FILES - 1))); do
  SORTED_INDICES+=("$i")
done

for i in $(seq 1 $((TOTAL_MATCHED_FILES - 1))); do
  j=$i
  while [ "$j" -gt 0 ] && [ "${MATCH_DENSITIES[${SORTED_INDICES[$j]}]}" -gt "${MATCH_DENSITIES[${SORTED_INDICES[$((j-1))]}]}" ]; do
    tmp="${SORTED_INDICES[$j]}"
    SORTED_INDICES[$j]="${SORTED_INDICES[$((j-1))]}"
    SORTED_INDICES[$((j-1))]="$tmp"
    j=$((j - 1))
  done
done

# =============================================================================
# Pass 3: Emit filtered output within budget
# =============================================================================

EMITTED_LINES=0
EMITTED_FILES=0
TOTAL_SOURCE_LINES=0

# Emit project context before code if enabled and available
if [ -n "$PROJECT_CONTEXT_CONTENT" ] && [ "$PROJECT_CONTEXT_INJECT_BEFORE" = "true" ]; then
  echo "=== PROJECT CONTEXT ==="
  echo "$PROJECT_CONTEXT_CONTENT"
  echo "=== END PROJECT CONTEXT ==="
  echo ""
fi

for idx in "${SORTED_INDICES[@]}"; do
  filepath="${MATCHED_FILES[$idx]}"
  est_lines="${MATCHED_LINES[$idx]}"

  # Budget check
  if [ "$EMITTED_LINES" -ge "$BUDGET_LINES" ]; then
    log_info "Budget reached (${EMITTED_LINES}/${BUDGET_LINES} lines). Remaining files skipped."
    break
  fi

  REMAINING=$((BUDGET_LINES - EMITTED_LINES))
  total_lines=$(wc -l < "$filepath" 2>/dev/null | tr -d ' ')
  TOTAL_SOURCE_LINES=$((TOTAL_SOURCE_LINES + total_lines))

  # Header
  if [ "$FALLBACK_SMALL" = "true" ] && [ "$total_lines" -le "$SMALL_FILE_THRESHOLD" ]; then
    echo "=== FILE: ${filepath} (${total_lines}/${total_lines} lines, full — small file) ==="
  else
    echo "=== FILE: ${filepath} (${est_lines}/${total_lines} lines, filtered for ${FILTER_KEY}) ==="
  fi

  # Emit filtered content, capped at remaining budget (single execution)
  FILTERED_OUTPUT=$(filter_file_lines "$filepath" "$total_lines" | head -n "$REMAINING")
  echo "$FILTERED_OUTPUT"
  LINES_EMITTED_THIS_FILE=$(echo "$FILTERED_OUTPUT" | wc -l | tr -d ' ')

  echo "=== END FILE ==="
  echo ""

  EMITTED_LINES=$((EMITTED_LINES + LINES_EMITTED_THIS_FILE))
  EMITTED_FILES=$((EMITTED_FILES + 1))
done

# =============================================================================
# Summary (stderr)
# =============================================================================

EMITTED_TOKENS=$((EMITTED_LINES * TOKENS_PER_LINE))

log_info "Filter summary: role=${ROLE} files_in=${TOTAL_INPUT_FILES} matched=${TOTAL_MATCHED_FILES} emitted=${EMITTED_FILES} lines=${EMITTED_LINES}/${TOTAL_SOURCE_LINES} tokens=~${EMITTED_TOKENS}/${BUDGET}"

# =============================================================================
# RAG Context Augmentation (optional)
# =============================================================================
# If RAG is enabled and index exists, retrieve related code to augment context.
# This runs AFTER rule-based filtering to add semantically relevant snippets.

RAG_ENABLED_CFG="false"
if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ] && command -v jq &>/dev/null; then
  RAG_ENABLED_CFG=$(jq -r '.rag.enabled // false' "$CONFIG_FILE")
fi

if [ "$RAG_ENABLED_CFG" = "true" ] && [ -f "$SCRIPT_DIR/rag-retrieve.sh" ]; then
  # Build a summary of emitted content as RAG query
  # Use the filter key + first few file names as query context
  _rag_query="${FILTER_KEY:-general} review"
  for _emitted_idx in "${SORTED_INDICES[@]}"; do
    _rag_query="$_rag_query $(basename "${MATCHED_FILES[$_emitted_idx]}")"
    # Limit query length
    if [ ${#_rag_query} -gt 200 ]; then
      break
    fi
  done

  _project_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  _rag_top_k=3  # Fewer results to stay within budget
  _rag_budget_lines=20  # Max lines from RAG

  RAG_RESULT=$("$SCRIPT_DIR/rag-retrieve.sh" "$_project_root" "$ROLE" "$_rag_query" --top-k "$_rag_top_k" 2>/dev/null) || RAG_RESULT=""

  if [ -n "$RAG_RESULT" ]; then
    _rag_lines=0
    _rag_output=""
    while IFS= read -r _rag_line; do
      [ -z "$_rag_line" ] && continue
      _rag_file=$(echo "$_rag_line" | python3 -c "import sys,json; print(json.load(sys.stdin).get('file',''))" 2>/dev/null) || continue
      _rag_content=$(echo "$_rag_line" | python3 -c "import sys,json; print(json.load(sys.stdin).get('content',''))" 2>/dev/null) || continue
      _rag_score=$(echo "$_rag_line" | python3 -c "import sys,json; print(json.load(sys.stdin).get('score',0))" 2>/dev/null) || _rag_score="0"

      [ -z "$_rag_content" ] && continue

      _content_lines=$(echo "$_rag_content" | wc -l | tr -d ' ')
      _rag_lines=$((_rag_lines + _content_lines + 2))

      if [ "$_rag_lines" -gt "$_rag_budget_lines" ]; then
        break
      fi

      _rag_output="${_rag_output}--- ${_rag_file} (relevance: ${_rag_score}) ---
${_rag_content}

"
    done <<< "$RAG_RESULT"

    if [ -n "$_rag_output" ]; then
      echo ""
      echo "=== RELATED CODE (RAG) ==="
      echo "$_rag_output"
      echo "=== END RELATED CODE ==="
      EMITTED_LINES=$((EMITTED_LINES + _rag_lines))
      log_info "RAG augmentation: added ~${_rag_lines} lines of related code for ${ROLE}"
    fi
  fi
fi

exit 0
