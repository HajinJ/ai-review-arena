#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: RAG Retriever
#
# Retrieves relevant code context from the vector index for a given reviewer role.
# Returns JSONL with file paths and code snippets.
#
# Usage: rag-retrieve.sh <project-root> <role> <query> [--top-k N] [--config <file>]
# Stdout: JSONL of {file, content, score} objects
# Exit: 0 always (non-blocking)
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# --- Arguments ---
PROJECT_ROOT="${1:?Usage: rag-retrieve.sh <project-root> <role> <query> [--top-k N]}"
ROLE="${2:?Usage: rag-retrieve.sh <project-root> <role> <query>}"
QUERY="${3:?Usage: rag-retrieve.sh <project-root> <role> <query>}"
shift 3

TOP_K=5
CONFIG_FILE=""
RERANK=false

while [ $# -gt 0 ]; do
  case "$1" in
    --top-k) TOP_K="${2:-5}"; shift 2 ;;
    --config) CONFIG_FILE="${2:-}"; shift 2 ;;
    --rerank) RERANK=true; shift ;;
    *) shift ;;
  esac
done

# --- Load config ---
if [ -z "$CONFIG_FILE" ]; then
  if command -v load_config &>/dev/null; then
    CONFIG_FILE=$(load_config "$PROJECT_ROOT" 2>/dev/null) || CONFIG_FILE=""
  fi
fi

if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ] && command -v jq &>/dev/null; then
  _rag_enabled=$(jq -r '.rag.enabled // true' "$CONFIG_FILE")
  if [ "$_rag_enabled" != "true" ]; then
    exit 0
  fi
  _top_k=$(jq -r '.rag.top_k // 5' "$CONFIG_FILE")
  TOP_K="${TOP_K:-$_top_k}"
  _rerank=$(jq -r '.rag.rerank // false' "$CONFIG_FILE")
  if [ "$_rerank" = "true" ]; then
    RERANK=true
  fi
fi

# --- Check index exists ---
_project_hash=$(project_hash "$PROJECT_ROOT")
INDEX_DIR="${UTILS_PLUGIN_DIR}/cache/${_project_hash}/rag-index"

if [ ! -d "$INDEX_DIR" ]; then
  log_info "RAG index not found for project. Run rag-indexer.sh first."
  exit 0
fi

# --- Check Python deps ---
if ! command -v python3 &>/dev/null; then
  exit 0
fi

# --- Role-based query augmentation ---
# Augment the query with role-specific keywords to improve retrieval relevance.
# Passed via env var to avoid shell injection.
ROLE_KEYWORDS=""
case "$ROLE" in
  security-reviewer|security)
    ROLE_KEYWORDS="authentication authorization input validation SQL injection XSS CSRF encryption session token secret credential" ;;
  bug-detector|bugs)
    ROLE_KEYWORDS="error handling null undefined race condition async await promise exception try catch finally concurrency thread lock" ;;
  performance-reviewer|performance)
    ROLE_KEYWORDS="database query cache latency connection pool N+1 algorithm complexity memory allocation buffer stream batch optimization" ;;
  architecture-reviewer|architecture)
    ROLE_KEYWORDS="design pattern module dependency coupling cohesion interface abstract factory singleton import export service layer" ;;
  test-coverage-reviewer|testing)
    ROLE_KEYWORDS="test describe it expect assert mock stub spy coverage unit integration e2e fixture setup teardown" ;;
  dependency-reviewer)
    ROLE_KEYWORDS="import require package version dependency upgrade vulnerable license" ;;
  api-contract-reviewer)
    ROLE_KEYWORDS="endpoint route handler controller request response schema validate middleware versioning breaking change" ;;
  observability-reviewer)
    ROLE_KEYWORDS="log logger trace span metric monitor alert health probe correlation" ;;
  data-integrity-reviewer)
    ROLE_KEYWORDS="schema validate migration transaction rollback constraint foreign key integrity model entity" ;;
  *)
    ROLE_KEYWORDS="" ;;
esac

# --- Execute Python retriever (all user input via env vars) ---
export RAG_INDEX_DIR="$INDEX_DIR"
export RAG_QUERY="$QUERY"
export RAG_ROLE_KEYWORDS="$ROLE_KEYWORDS"
export RAG_TOP_K="$TOP_K"
export RAG_RERANK="$RERANK"
export RAG_EMBEDDING_MODEL="${RAG_EMBEDDING_MODEL:-text-embedding-3-small}"

python3 "$SCRIPT_DIR/rag-engine.py" retrieve 2>/dev/null

exit 0
