#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Escalation Trigger Scanner
#
# Usage: escalation-scan.sh <config_file> [file_list_file]
#
# Scans files against escalation trigger patterns from config.
# File list can be provided via a file path argument or via stdin (one path per line).
#
# Output (stdout): JSON object with:
#   - triggers_matched: array of matched trigger patterns
#   - escalated_intensity: highest min_intensity from matched triggers
#   - requires_approval: true if any matched trigger requires human approval
#   - auto_fix_blocked_files: files that should be excluded from auto-fix
#
# If no triggers matched or escalation_triggers is disabled, outputs empty result.
# =============================================================================

set -uo pipefail

# --- Arguments ---
CONFIG_FILE="${1:?Usage: escalation-scan.sh <config_file> [file_list_file]}"
FILE_LIST_FILE="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# --- Dependencies ---
ensure_jq

# --- Check if escalation triggers are enabled ---
ENABLED=$(jq -r '.escalation_triggers.enabled // false' "$CONFIG_FILE" 2>/dev/null)
if [ "$ENABLED" != "true" ]; then
  echo '{"triggers_matched":[],"escalated_intensity":"","requires_approval":false,"auto_fix_blocked_files":[]}'
  exit 0
fi

# --- Read file list ---
FILES=()
if [ -n "$FILE_LIST_FILE" ] && [ -f "$FILE_LIST_FILE" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && FILES+=("$line")
  done < "$FILE_LIST_FILE"
elif [ ! -t 0 ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && FILES+=("$line")
  done
fi

if [ ${#FILES[@]} -eq 0 ]; then
  echo '{"triggers_matched":[],"escalated_intensity":"","requires_approval":false,"auto_fix_blocked_files":[]}'
  exit 0
fi

# --- Intensity ranking ---
intensity_rank() {
  case "$1" in
    quick)         echo 1 ;;
    standard)      echo 2 ;;
    deep)          echo 3 ;;
    comprehensive) echo 4 ;;
    *)             echo 0 ;;
  esac
}

rank_to_intensity() {
  case "$1" in
    1) echo "quick" ;;
    2) echo "standard" ;;
    3) echo "deep" ;;
    4) echo "comprehensive" ;;
    *) echo "" ;;
  esac
}

# --- Extract trigger patterns from config ---
PATTERNS_JSON=$(jq -r '.escalation_triggers.patterns // {}' "$CONFIG_FILE" 2>/dev/null)
PATTERN_NAMES=$(echo "$PATTERNS_JSON" | jq -r 'keys[]' 2>/dev/null)

if [ -z "$PATTERN_NAMES" ]; then
  echo '{"triggers_matched":[],"escalated_intensity":"","requires_approval":false,"auto_fix_blocked_files":[]}'
  exit 0
fi

# --- Scan each pattern ---
TRIGGERS_MATCHED="[]"
MAX_INTENSITY_RANK=0
REQUIRES_APPROVAL=false
AUTO_FIX_BLOCKED="[]"

for pattern_name in $PATTERN_NAMES; do
  # Extract pattern config
  FILE_PATTERNS=$(echo "$PATTERNS_JSON" | jq -r --arg p "$pattern_name" '.[$p].file_patterns // [] | .[]' 2>/dev/null)
  CONTENT_PATTERNS=$(echo "$PATTERNS_JSON" | jq -r --arg p "$pattern_name" '.[$p].content_patterns // [] | .[]' 2>/dev/null)
  MIN_INTENSITY=$(echo "$PATTERNS_JSON" | jq -r --arg p "$pattern_name" '.[$p].min_intensity // "standard"' 2>/dev/null)
  REQUIRE_APPROVAL=$(echo "$PATTERNS_JSON" | jq -r --arg p "$pattern_name" '.[$p].require_human_approval // false' 2>/dev/null)
  BLOCK_AUTO_FIX=$(echo "$PATTERNS_JSON" | jq -r --arg p "$pattern_name" '.[$p].block_auto_fix // false' 2>/dev/null)

  MATCHED_FILES=()

  for file_path in "${FILES[@]}"; do
    file_matched=false

    # Check file_patterns (glob matching on filename/path)
    for fp in $FILE_PATTERNS; do
      # Use bash pattern matching (case for glob)
      basename_file=$(basename "$file_path")
      # shellcheck disable=SC2254
      case "$basename_file" in
        $fp) file_matched=true; break ;;
      esac
      # Also try matching against full path
      if [ "$file_matched" = "false" ]; then
        # shellcheck disable=SC2254
        case "$file_path" in
          $fp) file_matched=true; break ;;
        esac
      fi
    done

    # If file pattern matched but there are content patterns, also check content
    if [ "$file_matched" = "true" ] && [ -n "$CONTENT_PATTERNS" ]; then
      # File pattern matched; content patterns are optional enrichment
      # If content_patterns is non-empty, the file is still matched by filename alone
      MATCHED_FILES+=("$file_path")
    elif [ "$file_matched" = "true" ]; then
      MATCHED_FILES+=("$file_path")
    fi

    # If file not matched by name, check content patterns in the file
    if [ "$file_matched" = "false" ] && [ -n "$CONTENT_PATTERNS" ] && [ -f "$file_path" ]; then
      for cp in $CONTENT_PATTERNS; do
        if grep -q -E "$cp" "$file_path" 2>/dev/null; then
          MATCHED_FILES+=("$file_path")
          break
        fi
      done
    fi
  done

  # If any files matched this pattern, add to triggers
  if [ ${#MATCHED_FILES[@]} -gt 0 ]; then
    # Build matched files JSON array
    FILES_JSON="[]"
    for mf in "${MATCHED_FILES[@]}"; do
      FILES_JSON=$(echo "$FILES_JSON" | jq --arg f "$mf" '. + [$f]')
    done

    # Build trigger entry
    TRIGGER_ENTRY=$(jq -n \
      --arg pattern "$pattern_name" \
      --argjson files "$FILES_JSON" \
      --arg min_int "$MIN_INTENSITY" \
      --argjson req_approval "$REQUIRE_APPROVAL" \
      --argjson block_fix "$BLOCK_AUTO_FIX" \
      '{pattern: $pattern, files: $files, min_intensity: $min_int, require_approval: $req_approval, block_auto_fix: $block_fix}')

    TRIGGERS_MATCHED=$(echo "$TRIGGERS_MATCHED" | jq --argjson entry "$TRIGGER_ENTRY" '. + [$entry]')

    # Track max intensity
    rank=$(intensity_rank "$MIN_INTENSITY")
    if [ "$rank" -gt "$MAX_INTENSITY_RANK" ]; then
      MAX_INTENSITY_RANK=$rank
    fi

    # Track approval requirement
    if [ "$REQUIRE_APPROVAL" = "true" ]; then
      REQUIRES_APPROVAL=true
    fi

    # Track auto-fix blocked files
    if [ "$BLOCK_AUTO_FIX" = "true" ]; then
      AUTO_FIX_BLOCKED=$(echo "$AUTO_FIX_BLOCKED" | jq --argjson new "$FILES_JSON" '. + $new | unique')
    fi
  fi
done

# --- Build output ---
ESCALATED_INTENSITY=""
if [ "$MAX_INTENSITY_RANK" -gt 0 ]; then
  ESCALATED_INTENSITY=$(rank_to_intensity "$MAX_INTENSITY_RANK")
fi

jq -n \
  --argjson triggers "$TRIGGERS_MATCHED" \
  --arg escalated "$ESCALATED_INTENSITY" \
  --argjson approval "$REQUIRES_APPROVAL" \
  --argjson blocked "$AUTO_FIX_BLOCKED" \
  '{triggers_matched: $triggers, escalated_intensity: $escalated, requires_approval: $approval, auto_fix_blocked_files: $blocked}'
