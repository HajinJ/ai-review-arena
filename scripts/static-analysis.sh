#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Static Analysis Integration
#
# Usage: static-analysis.sh [project-root] [--stack <json>] [--max-findings 50] [--confidence-floor 60] [--output-dir <dir>]
#
# Runs external static analysis scanners based on detected stack,
# normalizes output into standard finding format.
#
# Output: JSON array of normalized findings to stdout
#
# Exit codes:
#   0 - Always (informational tool, graceful degradation)
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

ensure_jq

# --- Constants ---
DEFAULT_MAX_FINDINGS=50
DEFAULT_CONFIDENCE_FLOOR=60

# --- Arguments ---
PROJECT_ROOT=""
STACK_JSON=""
MAX_FINDINGS="$DEFAULT_MAX_FINDINGS"
CONFIDENCE_FLOOR="$DEFAULT_CONFIDENCE_FLOOR"
OUTPUT_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --stack) STACK_JSON="${2:-}"; shift 2 ;;
    --max-findings) MAX_FINDINGS="${2:-$DEFAULT_MAX_FINDINGS}"; shift 2 ;;
    --confidence-floor) CONFIDENCE_FLOOR="${2:-$DEFAULT_CONFIDENCE_FLOOR}"; shift 2 ;;
    --output-dir) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -*) shift ;;
    *)
      if [ -z "$PROJECT_ROOT" ]; then
        PROJECT_ROOT="$1"
      fi
      shift
      ;;
  esac
done

if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT=$(find_project_root)
fi

if [ -n "$OUTPUT_DIR" ]; then
  mkdir -p "$OUTPUT_DIR"
fi

# --- Scanner Selection ---
# Map detected languages/frameworks to scanner commands
select_scanners() {
  local stack_json="$1"
  local scanners=()

  # Extract languages from stack JSON
  local languages
  languages=$(echo "$stack_json" | jq -r '.languages[]? // empty' 2>/dev/null)

  for lang in $languages; do
    case "$lang" in
      python|Python)
        command -v bandit &>/dev/null && scanners+=("bandit")
        command -v semgrep &>/dev/null && scanners+=("semgrep-python")
        ;;
      javascript|typescript|JavaScript|TypeScript)
        command -v eslint &>/dev/null && scanners+=("eslint")
        command -v semgrep &>/dev/null && scanners+=("semgrep-js")
        ;;
      go|Go)
        command -v gosec &>/dev/null && scanners+=("gosec")
        command -v semgrep &>/dev/null && scanners+=("semgrep-go")
        ;;
      java|Java|kotlin|Kotlin)
        command -v semgrep &>/dev/null && scanners+=("semgrep-java")
        ;;
      ruby|Ruby)
        command -v brakeman &>/dev/null && scanners+=("brakeman")
        command -v semgrep &>/dev/null && scanners+=("semgrep-ruby")
        ;;
      rust|Rust)
        command -v cargo &>/dev/null && scanners+=("cargo-audit")
        ;;
      *)
        command -v semgrep &>/dev/null && scanners+=("semgrep-generic")
        ;;
    esac
  done

  # Fallback: if no language-specific scanners, try semgrep generic
  if [ ${#scanners[@]} -eq 0 ]; then
    command -v semgrep &>/dev/null && scanners+=("semgrep-generic")
  fi

  # Deduplicate
  if [ ${#scanners[@]} -gt 0 ]; then
    printf '%s\n' "${scanners[@]}" | sort -u
  fi
}

# --- Scanner Execution ---
run_scanner() {
  local scanner="$1"
  local project="$2"
  local output_file="$3"
  local timeout_sec=120

  case "$scanner" in
    bandit)
      arena_timeout "$timeout_sec" bandit -r "$project" -f json --quiet 2>/dev/null > "$output_file" || true
      ;;
    eslint)
      arena_timeout "$timeout_sec" eslint "$project" -f json --no-error-on-unmatched-pattern 2>/dev/null > "$output_file" || true
      ;;
    gosec)
      arena_timeout "$timeout_sec" gosec -fmt=json -quiet "$project/..." 2>/dev/null > "$output_file" || true
      ;;
    brakeman)
      arena_timeout "$timeout_sec" brakeman -q -f json "$project" 2>/dev/null > "$output_file" || true
      ;;
    cargo-audit)
      (cd "$project" && arena_timeout "$timeout_sec" cargo audit --json 2>/dev/null > "$output_file") || true
      ;;
    semgrep-python)
      arena_timeout "$timeout_sec" semgrep --config=auto --lang=python --json --quiet "$project" 2>/dev/null > "$output_file" || true
      ;;
    semgrep-js)
      arena_timeout "$timeout_sec" semgrep --config=auto --lang=javascript --lang=typescript --json --quiet "$project" 2>/dev/null > "$output_file" || true
      ;;
    semgrep-go)
      arena_timeout "$timeout_sec" semgrep --config=auto --lang=go --json --quiet "$project" 2>/dev/null > "$output_file" || true
      ;;
    semgrep-java)
      arena_timeout "$timeout_sec" semgrep --config=auto --lang=java --json --quiet "$project" 2>/dev/null > "$output_file" || true
      ;;
    semgrep-ruby)
      arena_timeout "$timeout_sec" semgrep --config=auto --lang=ruby --json --quiet "$project" 2>/dev/null > "$output_file" || true
      ;;
    semgrep-generic)
      arena_timeout "$timeout_sec" semgrep --config=auto --json --quiet "$project" 2>/dev/null > "$output_file" || true
      ;;
    *)
      echo '[]' > "$output_file"
      ;;
  esac
}

# --- Main ---

# Get or detect stack
if [ -z "$STACK_JSON" ]; then
  STACK_JSON=$(bash "$SCRIPT_DIR/detect-stack.sh" "$PROJECT_ROOT" --output json 2>/dev/null || echo '{"languages":[]}')
fi

# Select scanners
SCANNERS=$(select_scanners "$STACK_JSON")

if [ -z "$SCANNERS" ]; then
  log_info "No static analysis scanners available. Install semgrep, eslint, bandit, or gosec for enhanced analysis."
  echo '{"scanners_run":[],"findings":[],"summary":"No scanners available"}'
  exit 0
fi

# Create temp directory for scanner outputs
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Run scanners in parallel
PIDS=()
SCANNER_LIST=()
while IFS= read -r scanner; do
  [ -z "$scanner" ] && continue
  SCANNER_LIST+=("$scanner")
  run_scanner "$scanner" "$PROJECT_ROOT" "$TEMP_DIR/${scanner}.json" &
  PIDS+=($!)
done <<< "$SCANNERS"

# Wait for all scanners
for pid in "${PIDS[@]}"; do
  wait "$pid" 2>/dev/null || true
done

# Normalize and merge all outputs
ALL_FINDINGS="[]"
for scanner in "${SCANNER_LIST[@]}"; do
  output_file="$TEMP_DIR/${scanner}.json"
  if [ -f "$output_file" ] && [ -s "$output_file" ]; then
    normalized=$(bash "$SCRIPT_DIR/normalize-scanner-output.sh" \
      --scanner "$scanner" \
      --input "$output_file" \
      --confidence-floor "$CONFIDENCE_FLOOR" 2>/dev/null || echo '[]')
    if echo "$normalized" | jq . &>/dev/null; then
      ALL_FINDINGS=$(echo "$ALL_FINDINGS" | jq --argjson new "$normalized" '. + $new')
    fi
  fi
done

# Sort by severity and confidence, limit findings
RESULT=$(echo "$ALL_FINDINGS" | jq --argjson max "$MAX_FINDINGS" '
  sort_by(
    (if .severity == "critical" then 0
     elif .severity == "high" then 1
     elif .severity == "medium" then 2
     else 3 end),
    (-.confidence)
  ) | .[:$max]
')

TOTAL=$(echo "$ALL_FINDINGS" | jq 'length')
KEPT=$(echo "$RESULT" | jq 'length')

# Save to output dir if specified
if [ -n "$OUTPUT_DIR" ]; then
  echo "$RESULT" > "$OUTPUT_DIR/static-analysis-findings.json"
fi

# Output final result
jq -n \
  --argjson findings "$RESULT" \
  --argjson scanners "$(printf '%s\n' "${SCANNER_LIST[@]}" | jq -R . | jq -s .)" \
  --arg total "$TOTAL" \
  --arg kept "$KEPT" \
  '{
    scanners_run: $scanners,
    total_findings: ($total | tonumber),
    findings_returned: ($kept | tonumber),
    findings: $findings,
    summary: "Static analysis complete: \($scanners | length) scanners, \($total) findings (\($kept) returned after filtering)"
  }'

exit 0
