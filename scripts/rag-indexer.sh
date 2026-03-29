#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: RAG Indexer
#
# Builds and incrementally updates a vector index of the codebase.
# Uses tree-sitter for AST-based chunking and OpenAI embeddings.
#
# Usage: rag-indexer.sh <project-root> [--force] [--config <config-file>]
# Exit: 0 on success, 1 on error
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# --- Arguments ---
PROJECT_ROOT="${1:?Usage: rag-indexer.sh <project-root> [--force] [--config <config-file>]}"
shift 1

FORCE_REINDEX=false
CONFIG_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE_REINDEX=true; shift ;;
    --config) CONFIG_FILE="${2:?--config requires a value}"; shift 2 ;;
    *) shift ;;
  esac
done

# --- Load config ---
if [ -z "$CONFIG_FILE" ]; then
  if command -v load_config &>/dev/null; then
    CONFIG_FILE=$(load_config "$PROJECT_ROOT" 2>/dev/null) || CONFIG_FILE=""
  fi
fi

# RAG config defaults
RAG_ENABLED=true
EMBEDDING_MODEL="text-embedding-3-small"
CHUNK_SIZE=500
CHUNK_OVERLAP=50
INDEX_EXTENSIONS=".java .kt .py .ts .tsx .js .jsx .go .rs .rb .php .c .cpp .cs .swift"
EXCLUDE_PATHS="node_modules .git build dist vendor __pycache__ .venv target"

if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ] && command -v jq &>/dev/null; then
  RAG_ENABLED=$(jq -r '.rag.enabled // true' "$CONFIG_FILE")
  EMBEDDING_MODEL=$(jq -r '.rag.embedding_model // "text-embedding-3-small"' "$CONFIG_FILE")
  CHUNK_SIZE=$(jq -r '.rag.chunk_size // 500' "$CONFIG_FILE")
  CHUNK_OVERLAP=$(jq -r '.rag.chunk_overlap // 50' "$CONFIG_FILE")

  # Read extensions array and convert to space-separated with dots
  _ext_arr=$(jq -r '.rag.index_extensions[]? // empty' "$CONFIG_FILE")
  if [ -n "$_ext_arr" ]; then
    INDEX_EXTENSIONS=""
    while IFS= read -r ext; do
      [ -z "$ext" ] && continue
      case "$ext" in
        .*) INDEX_EXTENSIONS="$INDEX_EXTENSIONS $ext" ;;
        *)  INDEX_EXTENSIONS="$INDEX_EXTENSIONS .$ext" ;;
      esac
    done <<< "$_ext_arr"
  fi

  _excl_arr=$(jq -r '.rag.exclude_paths[]? // empty' "$CONFIG_FILE")
  if [ -n "$_excl_arr" ]; then
    EXCLUDE_PATHS=$(echo "$_excl_arr" | tr '\n' ' ')
  fi
fi

if [ "$RAG_ENABLED" != "true" ]; then
  log_info "RAG indexing disabled in config."
  exit 0
fi

# --- Check Python dependencies ---
if ! command -v python3 &>/dev/null; then
  log_warn "python3 not found. RAG indexing requires Python 3."
  exit 0
fi

# Check required Python packages
_missing_deps=false
for pkg in chromadb openai; do
  if ! python3 -c "import $pkg" 2>/dev/null; then
    _missing_deps=true
    log_warn "Python package '$pkg' not found."
  fi
done

if [ "$_missing_deps" = "true" ]; then
  log_warn "Install missing dependencies: pip install chromadb openai"
  log_warn "RAG indexing skipped."
  exit 0
fi

# --- Determine index directory ---
_project_hash=$(project_hash "$PROJECT_ROOT")
INDEX_DIR="${UTILS_PLUGIN_DIR}/cache/${_project_hash}/rag-index"
mkdir -p "$INDEX_DIR"

# --- Collect code files ---
FILE_LIST="${INDEX_DIR}/file-list.txt"
HASH_FILE="${INDEX_DIR}/file-hashes.json"

# Build find expression for extensions
FIND_ARGS=()
first=true
for ext in $INDEX_EXTENSIONS; do
  if [ "$first" = "true" ]; then
    FIND_ARGS+=(-name "*${ext}")
    first=false
  else
    FIND_ARGS+=(-o -name "*${ext}")
  fi
done

# Build exclude expressions
PRUNE_ARGS=()
for excl in $EXCLUDE_PATHS; do
  PRUNE_ARGS+=(-path "*/${excl}" -prune -o)
done

# Find files
find "$PROJECT_ROOT" \
  "${PRUNE_ARGS[@]}" \
  -type f \( "${FIND_ARGS[@]}" \) \
  -print \
  > "$FILE_LIST" 2>/dev/null

FILE_COUNT=$(wc -l < "$FILE_LIST" | tr -d ' ')
if [ "$FILE_COUNT" -eq 0 ]; then
  log_info "No files found for RAG indexing."
  exit 0
fi

log_info "RAG indexer: found $FILE_COUNT files in $PROJECT_ROOT"

# --- Run Python indexer (handles incremental logic internally) ---
export RAG_PROJECT_ROOT="$PROJECT_ROOT"
export RAG_INDEX_DIR="$INDEX_DIR"
export RAG_FILE_LIST="$FILE_LIST"
export RAG_HASH_FILE="$HASH_FILE"
export RAG_EMBEDDING_MODEL="$EMBEDDING_MODEL"
export RAG_CHUNK_SIZE="$CHUNK_SIZE"
export RAG_CHUNK_OVERLAP="$CHUNK_OVERLAP"
export RAG_FORCE_REINDEX="$FORCE_REINDEX"

python3 "$SCRIPT_DIR/rag-engine.py" index 2>&1 | while IFS= read -r line; do
  log_info "RAG: $line"
done

exit_code=${PIPESTATUS[0]}
if [ "$exit_code" -ne 0 ]; then
  log_warn "RAG indexing failed with exit code $exit_code"
  exit 0  # Non-blocking
fi

log_info "RAG index updated at $INDEX_DIR"
exit 0
