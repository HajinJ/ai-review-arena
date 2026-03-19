#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Documentation Inventory Scanner
#
# Usage: doc-inventory.sh [--root <project_root>] [--config <config_file>] [--format json|text]
#
# Scans the project for documentation files, classifies them by type,
# and generates an inventory with metadata (last modified, size, doc type).
#
# Output: JSON inventory to stdout, human-readable summary to stderr.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

ensure_jq

# --- Arguments ---
PROJECT_ROOT=""
CONFIG_FILE=""
OUTPUT_FORMAT="json"

while [ $# -gt 0 ]; do
  case "$1" in
    --root) PROJECT_ROOT="${2:-}"; shift 2 ;;
    --config) CONFIG_FILE="${2:-}"; shift 2 ;;
    --format) OUTPUT_FORMAT="${2:-json}"; shift 2 ;;
    *) shift ;;
  esac
done

if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi

# --- Load config ---
DOC_EXTENSIONS=("md" "mdx" "rst" "txt" "adoc" "asciidoc" "html" "htm")
EXCLUDE_PATTERNS=("node_modules" "vendor" "dist" ".git" "*.min.*")

if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
  cfg_extensions=$(jq -r '.docs.doc_extensions // empty' "$CONFIG_FILE" 2>/dev/null || true)
  if [ -n "$cfg_extensions" ]; then
    DOC_EXTENSIONS=()
    while IFS= read -r ext; do
      [ -n "$ext" ] && DOC_EXTENSIONS+=("$ext")
    done < <(echo "$cfg_extensions" | jq -r '.[]')
  fi
fi

# --- Build find command ---
FIND_ARGS=("$PROJECT_ROOT" -type f)

# Add exclude patterns
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
  FIND_ARGS+=(-not -path "*/${pattern}" -not -path "*/${pattern}/*")
done

# Add extension filter
EXT_FILTER=""
for i in "${!DOC_EXTENSIONS[@]}"; do
  if [ "$i" -eq 0 ]; then
    EXT_FILTER="-name '*.${DOC_EXTENSIONS[$i]}'"
  else
    EXT_FILTER="$EXT_FILTER -o -name '*.${DOC_EXTENSIONS[$i]}'"
  fi
done

# --- Detect doc type ---
detect_doc_type() {
  local filepath="$1"
  local filename
  filename=$(basename "$filepath" | tr '[:upper:]' '[:lower:]')
  local dirpath
  dirpath=$(dirname "$filepath" | tr '[:upper:]' '[:lower:]')

  case "$filename" in
    readme*) echo "readme" ;;
    changelog*|changes*|history*|release*) echo "changelog" ;;
    contributing*) echo "contributing" ;;
    license*) echo "license" ;;
    *)
      case "$dirpath" in
        *adr*|*architecture-decision*) echo "adr" ;;
        *api*|*reference*) echo "api_reference" ;;
        *tutorial*|*guide*|*getting-started*|*quickstart*) echo "tutorial" ;;
        *runbook*|*playbook*|*ops*) echo "runbook" ;;
        *) echo "general" ;;
      esac
      ;;
  esac
}

# --- Scan and build inventory ---
DOC_COUNT=0
TOTAL_LINES=0
INVENTORY_JSON="[]"

while IFS= read -r file; do
  [ -z "$file" ] && continue

  rel_path="${file#"$PROJECT_ROOT"/}"
  doc_type=$(detect_doc_type "$file")
  file_size=$(wc -c < "$file" 2>/dev/null | tr -d ' ')
  line_count=$(wc -l < "$file" 2>/dev/null | tr -d ' ')
  last_modified=""

  if command -v git &>/dev/null && git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree &>/dev/null; then
    last_modified=$(git -C "$PROJECT_ROOT" log -1 --format="%aI" -- "$rel_path" 2>/dev/null || echo "unknown")
  else
    last_modified=$(stat -f "%Sm" -t "%Y-%m-%dT%H:%M:%S" "$file" 2>/dev/null \
      || stat --format="%y" "$file" 2>/dev/null | cut -d. -f1 \
      || echo "unknown")
  fi

  ext="${file##*.}"

  entry=$(jq -n \
    --arg path "$rel_path" \
    --arg doc_type "$doc_type" \
    --arg ext "$ext" \
    --argjson size "${file_size:-0}" \
    --argjson lines "${line_count:-0}" \
    --arg last_modified "$last_modified" \
    '{path: $path, doc_type: $doc_type, extension: $ext, size_bytes: $size, line_count: $lines, last_modified: $last_modified}')

  INVENTORY_JSON=$(echo "$INVENTORY_JSON" | jq --argjson entry "$entry" '. + [$entry]')
  DOC_COUNT=$((DOC_COUNT + 1))
  TOTAL_LINES=$((TOTAL_LINES + ${line_count:-0}))
done < <(eval "find ${FIND_ARGS[*]} \\( $EXT_FILTER \\)" 2>/dev/null | sort)

# --- Build summary ---
TYPE_SUMMARY=$(echo "$INVENTORY_JSON" | jq '[group_by(.doc_type)[] | {type: .[0].doc_type, count: length}]')
EXT_SUMMARY=$(echo "$INVENTORY_JSON" | jq '[group_by(.extension)[] | {extension: .[0].extension, count: length}]')

RESULT=$(jq -n \
  --argjson files "$INVENTORY_JSON" \
  --argjson by_type "$TYPE_SUMMARY" \
  --argjson by_extension "$EXT_SUMMARY" \
  --argjson total_files "$DOC_COUNT" \
  --argjson total_lines "$TOTAL_LINES" \
  --arg project_root "$PROJECT_ROOT" \
  '{
    project_root: $project_root,
    total_files: $total_files,
    total_lines: $total_lines,
    by_type: $by_type,
    by_extension: $by_extension,
    files: $files
  }')

# --- Output ---
if [ "$OUTPUT_FORMAT" = "text" ]; then
  echo "=== Documentation Inventory ===" >&2
  echo "Project: $PROJECT_ROOT" >&2
  echo "Total docs: $DOC_COUNT files, $TOTAL_LINES lines" >&2
  echo "" >&2
  echo "By Type:" >&2
  echo "$TYPE_SUMMARY" | jq -r '.[] | "  \(.type): \(.count)"' >&2
  echo "" >&2
  echo "By Extension:" >&2
  echo "$EXT_SUMMARY" | jq -r '.[] | "  .\(.extension): \(.count)"' >&2
fi

echo "$RESULT"
exit 0
