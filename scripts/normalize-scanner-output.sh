#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Scanner Output Normalizer
#
# Usage: normalize-scanner-output.sh --scanner <name> --input <file> [--confidence-floor 60]
#
# Converts output from various static analysis tools into the standard
# finding format: {severity, confidence, line, file, title, description, suggestion}
#
# Output: JSON array of normalized findings to stdout
#
# Exit codes:
#   0 - Always (graceful degradation)
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

ensure_jq

# --- Arguments ---
SCANNER=""
INPUT_FILE=""
CONFIDENCE_FLOOR=60

while [ $# -gt 0 ]; do
  case "$1" in
    --scanner) SCANNER="${2:-}"; shift 2 ;;
    --input) INPUT_FILE="${2:-}"; shift 2 ;;
    --confidence-floor) CONFIDENCE_FLOOR="${2:-60}"; shift 2 ;;
    -*) shift ;;
    *) shift ;;
  esac
done

if [ -z "$SCANNER" ] || [ -z "$INPUT_FILE" ]; then
  echo '[]'
  exit 0
fi

if [ ! -f "$INPUT_FILE" ] || [ ! -s "$INPUT_FILE" ]; then
  echo '[]'
  exit 0
fi

# --- Normalizers ---

normalize_bandit() {
  jq --argjson floor "$CONFIDENCE_FLOOR" '
    [.results[]? | {
      severity: (if .issue_severity == "HIGH" then "high"
                 elif .issue_severity == "MEDIUM" then "medium"
                 elif .issue_severity == "LOW" then "low"
                 else "medium" end),
      confidence: (if .issue_confidence == "HIGH" then 85
                   elif .issue_confidence == "MEDIUM" then 65
                   else 45 end),
      line: .line_number,
      file: .filename,
      title: .issue_text,
      description: "[\(.test_id)] \(.issue_text). More info: \(.more_info // "N/A")",
      suggestion: "Review and fix the security issue identified by Bandit \(.test_id).",
      scanner: "bandit"
    } | select(.confidence >= $floor)]
  ' "$INPUT_FILE" 2>/dev/null || echo '[]'
}

normalize_eslint() {
  jq --argjson floor "$CONFIDENCE_FLOOR" '
    [.[]? | .filePath as $file | .messages[]? | {
      severity: (if .severity == 2 then "high" elif .severity == 1 then "medium" else "low" end),
      confidence: (if .severity == 2 then 80 else 60 end),
      line: .line,
      file: $file,
      title: "\(.ruleId // "unknown"): \(.message)",
      description: .message,
      suggestion: "Fix the \(.ruleId // "unknown") rule violation.",
      scanner: "eslint"
    } | select(.confidence >= $floor)]
  ' "$INPUT_FILE" 2>/dev/null || echo '[]'
}

normalize_gosec() {
  jq --argjson floor "$CONFIDENCE_FLOOR" '
    [.Issues[]? | {
      severity: (if .severity == "HIGH" then "high"
                 elif .severity == "MEDIUM" then "medium"
                 else "low" end),
      confidence: (if .confidence == "HIGH" then 85
                   elif .confidence == "MEDIUM" then 65
                   else 45 end),
      line: (.line | tonumber? // 0),
      file: .file,
      title: "\(.rule_id): \(.details)",
      description: .details,
      suggestion: "Review and fix the security issue identified by gosec \(.rule_id).",
      scanner: "gosec"
    } | select(.confidence >= $floor)]
  ' "$INPUT_FILE" 2>/dev/null || echo '[]'
}

normalize_brakeman() {
  jq --argjson floor "$CONFIDENCE_FLOOR" '
    [.warnings[]? | {
      severity: (if .confidence == "High" then "high"
                 elif .confidence == "Medium" then "medium"
                 else "low" end),
      confidence: (if .confidence == "High" then 85
                   elif .confidence == "Medium" then 65
                   else 45 end),
      line: .line,
      file: .file,
      title: "\(.warning_type): \(.message)",
      description: "\(.warning_type) - \(.message). Code: \(.code // "N/A")",
      suggestion: "Fix the \(.warning_type) vulnerability in \(.file).",
      scanner: "brakeman"
    } | select(.confidence >= $floor)]
  ' "$INPUT_FILE" 2>/dev/null || echo '[]'
}

normalize_semgrep() {
  jq --argjson floor "$CONFIDENCE_FLOOR" '
    [.results[]? | {
      severity: (if .extra.severity == "ERROR" then "high"
                 elif .extra.severity == "WARNING" then "medium"
                 else "low" end),
      confidence: (if .extra.severity == "ERROR" then 80
                   elif .extra.severity == "WARNING" then 65
                   else 50 end),
      line: .start.line,
      file: .path,
      title: (.check_id | split(".")[-1:] | join("")),
      description: (.extra.message // "Semgrep finding"),
      suggestion: (.extra.fix // "Review and fix the identified issue."),
      scanner: "semgrep"
    } | select(.confidence >= $floor)]
  ' "$INPUT_FILE" 2>/dev/null || echo '[]'
}

normalize_cargo_audit() {
  jq --argjson floor "$CONFIDENCE_FLOOR" '
    [.vulnerabilities.list[]? | {
      severity: "high",
      confidence: 90,
      line: 0,
      file: "Cargo.toml",
      title: "\(.advisory.id): \(.advisory.title)",
      description: "\(.advisory.description // .advisory.title). Package: \(.package.name) v\(.package.version)",
      suggestion: "Update \(.package.name) to a patched version. See: \(.advisory.url // "N/A")",
      scanner: "cargo-audit"
    } | select(.confidence >= $floor)]
  ' "$INPUT_FILE" 2>/dev/null || echo '[]'
}

# --- Main ---

case "$SCANNER" in
  bandit)         normalize_bandit ;;
  eslint)         normalize_eslint ;;
  gosec)          normalize_gosec ;;
  brakeman)       normalize_brakeman ;;
  cargo-audit)    normalize_cargo_audit ;;
  semgrep-*)      normalize_semgrep ;;
  *)
    log_warn "Unknown scanner: $SCANNER"
    echo '[]'
    ;;
esac

exit 0
