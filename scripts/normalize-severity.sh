#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Severity Normalizer
#
# Normalizes severity values from external CLIs (Codex/Gemini) to the
# standard 4-level scale: critical, high, medium, low.
#
# Usage: echo '{"severity": "error", ...}' | normalize-severity.sh
#   or:  echo '[{...}, {...}]' | normalize-severity.sh
#
# Input:  JSON on stdin — single object or array of objects with .severity field
# Output: Normalized JSON on stdout with .severity mapped to standard values
#
# Mapping:
#   "error", "critical", "blocker", "fatal"       → "critical"
#   "warning", "major", "high", "important"        → "high"
#   "info", "minor", "medium", "moderate", "note"  → "medium"
#   "hint", "trivial", "low", "suggestion", "style" → "low"
#   (anything else)                                 → "medium" (safe default)
# =============================================================================

set -uo pipefail

# --- Dependencies ---
if ! command -v jq &>/dev/null; then
  # Pass through unchanged if jq not available
  cat
  exit 0
fi

# --- Read input ---
INPUT=$(cat)

if [ -z "$INPUT" ]; then
  echo "$INPUT"
  exit 0
fi

# --- Normalize ---
echo "$INPUT" | jq '
  def normalize_severity:
    (. // "medium") | ascii_downcase |
    if . == "error" or . == "critical" or . == "blocker" or . == "fatal" then "critical"
    elif . == "warning" or . == "major" or . == "high" or . == "important" then "high"
    elif . == "info" or . == "minor" or . == "medium" or . == "moderate" or . == "note" then "medium"
    elif . == "hint" or . == "trivial" or . == "low" or . == "suggestion" or . == "style" then "low"
    else "medium"
    end;

  if type == "array" then
    map(if .severity then .severity |= normalize_severity else . end)
  elif type == "object" then
    if .severity then .severity |= normalize_severity else . end
  else .
  end
'
