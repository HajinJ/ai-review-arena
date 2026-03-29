#!/usr/bin/env python3
"""
ai-review-arena: RAG Engine

Core Python engine for RAG indexing and retrieval.
All external input is received via environment variables (no shell injection risk).

Commands:
  index    - Build/update vector index from codebase
  retrieve - Query the index for relevant code chunks

Environment variables:
  RAG_INDEX_DIR       - Path to the index directory
  RAG_FILE_LIST       - Path to file list (index only)
  RAG_HASH_FILE       - Path to file hash cache (index only)
  RAG_EMBEDDING_MODEL - OpenAI embedding model name
  RAG_CHUNK_SIZE      - Target chunk size in tokens
  RAG_CHUNK_OVERLAP   - Overlap between chunks in tokens
  RAG_FORCE_REINDEX   - Force full reindex (true/false)
  RAG_PROJECT_ROOT    - Project root path
  RAG_QUERY           - Search query (retrieve only)
  RAG_ROLE_KEYWORDS   - Role-specific augmentation keywords (retrieve only)
  RAG_TOP_K           - Number of results to return (retrieve only)
  RAG_RERANK          - Enable reranking (true/false)
"""

import hashlib
import json
import os
import re
import sys
from pathlib import Path
from typing import Optional


# =============================================================================
# Tree-sitter Chunking (AST-based)
# =============================================================================

def _try_tree_sitter_chunk(content: str, file_path: str, chunk_size: int) -> Optional[list]:
    """Attempt tree-sitter AST-based chunking. Returns None if tree-sitter unavailable."""
    try:
        from tree_sitter_languages import get_parser
    except ImportError:
        return None

    # Map file extensions to tree-sitter language names
    ext = Path(file_path).suffix.lower()
    lang_map = {
        '.py': 'python', '.js': 'javascript', '.jsx': 'javascript',
        '.ts': 'typescript', '.tsx': 'tsx',
        '.java': 'java', '.kt': 'kotlin',
        '.go': 'go', '.rs': 'rust', '.rb': 'ruby',
        '.php': 'php', '.c': 'c', '.cpp': 'cpp', '.cs': 'c_sharp',
        '.swift': 'swift',
    }

    lang = lang_map.get(ext)
    if not lang:
        return None

    try:
        parser = get_parser(lang)
    except Exception:
        return None

    try:
        tree = parser.parse(content.encode('utf-8'))
    except Exception:
        return None

    # Extract top-level function/class/method nodes
    chunks = []
    root = tree.root_node

    # Node types that represent meaningful code units
    meaningful_types = {
        'function_definition', 'function_declaration', 'method_definition',
        'method_declaration', 'class_definition', 'class_declaration',
        'interface_declaration', 'enum_declaration', 'struct_item',
        'impl_item', 'trait_item', 'module_declaration',
        'arrow_function', 'function_expression',
        # Go
        'function_declaration', 'method_declaration', 'type_declaration',
        # Kotlin
        'function_declaration', 'class_declaration', 'object_declaration',
    }

    def extract_nodes(node, depth=0):
        """Recursively extract meaningful code units."""
        if node.type in meaningful_types:
            text = content[node.start_byte:node.end_byte]
            # If the chunk is too large, split it further
            char_limit = chunk_size * 4  # ~4 chars per token
            if len(text) > char_limit and depth < 2:
                # Try to split children
                for child in node.children:
                    extract_nodes(child, depth + 1)
            else:
                if text.strip():
                    chunks.append({
                        'file': file_path,
                        'content': text.strip(),
                        'type': node.type,
                        'start_line': node.start_point[0] + 1,
                        'end_line': node.end_point[0] + 1,
                    })
            return

        # Recurse into children for non-meaningful nodes
        for child in node.children:
            extract_nodes(child, depth)

    extract_nodes(root)

    # If tree-sitter found nothing (e.g., a script with no functions), fall back
    if not chunks:
        return None

    return chunks


# =============================================================================
# Regex Fallback Chunking
# =============================================================================

def _regex_chunk(content: str, file_path: str, chunk_size: int, overlap: int) -> list:
    """Fallback: regex-based chunking by function/class signatures."""
    chunks = []
    ext = Path(file_path).suffix.lower()
    char_limit = chunk_size * 4

    # Language-specific patterns
    if ext in ('.java', '.kt', '.cs', '.swift'):
        pattern = r'(?:^|\n)((?:public|private|protected|internal|open|override|static|abstract|final|suspend)?\s*(?:fun|void|int|long|String|Boolean|class|interface|enum|object|struct|data class)\s+\w+)'
    elif ext in ('.py',):
        pattern = r'(?:^|\n)((?:async\s+)?(?:def|class)\s+\w+)'
    elif ext in ('.go',):
        pattern = r'(?:^|\n)((?:func)\s+(?:\([^)]*\)\s+)?\w+)'
    elif ext in ('.rs',):
        pattern = r'(?:^|\n)((?:pub\s+)?(?:fn|struct|enum|impl|trait|mod)\s+\w+)'
    elif ext in ('.rb',):
        pattern = r'(?:^|\n)((?:def|class|module)\s+\w+)'
    elif ext in ('.js', '.jsx', '.ts', '.tsx'):
        pattern = r'(?:^|\n)((?:export\s+)?(?:async\s+)?(?:function|class|const|let|var)\s+\w+)'
    else:
        # Generic: split by blank lines or every N lines
        lines = content.split('\n')
        step = max(1, chunk_size * 4 // 80)  # ~80 chars per line
        overlap_lines = max(1, overlap * 4 // 80)
        i = 0
        while i < len(lines):
            end = min(i + step, len(lines))
            chunk_text = '\n'.join(lines[i:end])
            if chunk_text.strip():
                chunks.append({
                    'file': file_path,
                    'content': chunk_text.strip(),
                    'type': 'block',
                    'start_line': i + 1,
                    'end_line': end,
                })
            i += step - overlap_lines
        return chunks

    # Split by pattern
    parts = re.split(pattern, content)
    current_chunk = ""
    current_start = 1

    for part in parts:
        if len(current_chunk) + len(part) > char_limit:
            if current_chunk.strip():
                line_count = current_chunk[:current_chunk.find(current_chunk.strip())].count('\n')
                chunks.append({
                    'file': file_path,
                    'content': current_chunk.strip(),
                    'type': 'code',
                    'start_line': current_start,
                    'end_line': current_start + current_chunk.count('\n'),
                })
            current_start = current_start + current_chunk.count('\n') + 1
            current_chunk = part
        else:
            current_chunk += part

    if current_chunk.strip():
        chunks.append({
            'file': file_path,
            'content': current_chunk.strip(),
            'type': 'code',
            'start_line': current_start,
            'end_line': current_start + current_chunk.count('\n'),
        })

    return chunks


# =============================================================================
# Chunking Dispatcher
# =============================================================================

def chunk_file(content: str, file_path: str, chunk_size: int = 500, overlap: int = 50) -> list:
    """Chunk a file using tree-sitter (preferred) or regex fallback."""
    # Try tree-sitter first
    ts_chunks = _try_tree_sitter_chunk(content, file_path, chunk_size)
    if ts_chunks is not None:
        return ts_chunks

    # Fallback to regex
    return _regex_chunk(content, file_path, chunk_size, overlap)


# =============================================================================
# File Hashing (Incremental Indexing)
# =============================================================================

def compute_file_hash(filepath: str) -> str:
    """SHA256 hash of file content for change detection."""
    h = hashlib.sha256()
    try:
        with open(filepath, 'rb') as f:
            for block in iter(lambda: f.read(8192), b''):
                h.update(block)
    except (OSError, IOError):
        return ""
    return h.hexdigest()


def load_hash_cache(hash_file: str) -> dict:
    """Load previous file hashes."""
    if not os.path.exists(hash_file):
        return {}
    try:
        with open(hash_file, 'r') as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return {}


def save_hash_cache(hash_file: str, hashes: dict):
    """Save file hashes atomically."""
    tmp = hash_file + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(hashes, f)
    os.replace(tmp, hash_file)


# =============================================================================
# Index Command
# =============================================================================

def cmd_index():
    """Build or incrementally update the vector index."""
    index_dir = os.environ.get('RAG_INDEX_DIR', '')
    file_list_path = os.environ.get('RAG_FILE_LIST', '')
    hash_file = os.environ.get('RAG_HASH_FILE', '')
    embedding_model = os.environ.get('RAG_EMBEDDING_MODEL', 'text-embedding-3-small')
    chunk_size = int(os.environ.get('RAG_CHUNK_SIZE', '500'))
    chunk_overlap = int(os.environ.get('RAG_CHUNK_OVERLAP', '50'))
    force_reindex = os.environ.get('RAG_FORCE_REINDEX', 'false').lower() == 'true'

    if not index_dir or not file_list_path:
        print("Error: RAG_INDEX_DIR and RAG_FILE_LIST required", file=sys.stderr)
        sys.exit(1)

    # Load file list
    with open(file_list_path, 'r') as f:
        files = [line.strip() for line in f if line.strip()]

    if not files:
        print("No files to index", file=sys.stderr)
        return

    # Load hash cache for incremental indexing
    prev_hashes = {} if force_reindex else load_hash_cache(hash_file)
    new_hashes = {}

    # Determine which files changed
    changed_files = []
    unchanged_files = []
    for filepath in files:
        file_hash = compute_file_hash(filepath)
        new_hashes[filepath] = file_hash
        if file_hash and file_hash != prev_hashes.get(filepath, ''):
            changed_files.append(filepath)
        else:
            unchanged_files.append(filepath)

    # Detect deleted files
    deleted_files = set(prev_hashes.keys()) - set(new_hashes.keys())

    if not changed_files and not deleted_files:
        print(f"No changes detected. Index up-to-date ({len(files)} files).")
        return

    print(f"Indexing: {len(changed_files)} changed, {len(deleted_files)} deleted, {len(unchanged_files)} unchanged")

    # Initialize ChromaDB
    import chromadb
    db_path = os.path.join(index_dir, 'chroma.db')
    chroma = chromadb.PersistentClient(path=db_path)
    collection = chroma.get_or_create_collection(
        name="codebase",
        metadata={"hnsw:space": "cosine"}
    )

    # Delete chunks from deleted/changed files
    files_to_remove = list(deleted_files) + changed_files
    if files_to_remove:
        # ChromaDB where filter for file metadata
        for filepath in files_to_remove:
            try:
                existing = collection.get(where={"file": filepath})
                if existing and existing['ids']:
                    collection.delete(ids=existing['ids'])
            except Exception:
                pass

    # Chunk changed files
    all_chunks = []
    for filepath in changed_files:
        try:
            with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            if not content.strip():
                continue
            chunks = chunk_file(content, filepath, chunk_size, chunk_overlap)
            all_chunks.extend(chunks)
        except Exception as e:
            print(f"Warning: {filepath}: {e}", file=sys.stderr)

    if not all_chunks:
        print("No chunks generated from changed files.")
        save_hash_cache(hash_file, new_hashes)
        return

    print(f"Created {len(all_chunks)} chunks from {len(changed_files)} files")

    # Batch embed and store
    from openai import OpenAI
    client = OpenAI()

    BATCH_SIZE = 100
    total_embedded = 0
    chunk_id_base = int(hashlib.sha256(str(len(all_chunks)).encode()).hexdigest()[:8], 16)

    for i in range(0, len(all_chunks), BATCH_SIZE):
        batch = all_chunks[i:i + BATCH_SIZE]
        texts = [c['content'] for c in batch]

        try:
            response = client.embeddings.create(
                model=embedding_model,
                input=texts
            )
        except Exception as e:
            print(f"Embedding API error: {e}", file=sys.stderr)
            continue

        embeddings = [e.embedding for e in response.data]
        ids = [f"chunk_{chunk_id_base + i + j}" for j in range(len(batch))]
        metadatas = [{
            'file': c['file'],
            'type': c.get('type', 'code'),
            'start_line': c.get('start_line', 0),
            'end_line': c.get('end_line', 0),
        } for c in batch]

        collection.add(
            ids=ids,
            embeddings=embeddings,
            documents=texts,
            metadatas=metadatas
        )
        total_embedded += len(batch)

    print(f"Indexed {total_embedded} chunks to {db_path}")

    # Save updated hashes
    save_hash_cache(hash_file, new_hashes)


# =============================================================================
# Retrieve Command
# =============================================================================

def cmd_retrieve():
    """Query the vector index for relevant code chunks."""
    index_dir = os.environ.get('RAG_INDEX_DIR', '')
    query = os.environ.get('RAG_QUERY', '')
    role_keywords = os.environ.get('RAG_ROLE_KEYWORDS', '')
    top_k = int(os.environ.get('RAG_TOP_K', '5'))
    rerank = os.environ.get('RAG_RERANK', 'false').lower() == 'true'
    embedding_model = os.environ.get('RAG_EMBEDDING_MODEL', 'text-embedding-3-small')

    if not index_dir or not query:
        return

    db_path = os.path.join(index_dir, 'chroma.db')
    if not os.path.exists(db_path):
        return

    # Augment query with role keywords
    augmented_query = f"{query} {role_keywords}".strip()

    # Initialize ChromaDB
    import chromadb
    chroma = chromadb.PersistentClient(path=db_path)

    try:
        collection = chroma.get_collection('codebase')
    except Exception:
        return

    # Get query embedding
    from openai import OpenAI
    client = OpenAI()

    try:
        resp = client.embeddings.create(model=embedding_model, input=[augmented_query])
        query_embedding = resp.data[0].embedding
    except Exception as e:
        print(f"Embedding API error: {e}", file=sys.stderr)
        return

    # Retrieve more candidates if reranking
    fetch_k = top_k * 3 if rerank else top_k

    try:
        results = collection.query(
            query_embeddings=[query_embedding],
            n_results=min(fetch_k, collection.count())
        )
    except Exception:
        return

    if not results or not results['documents'] or not results['documents'][0]:
        return

    docs = results['documents'][0]
    metas = results['metadatas'][0]
    distances = results['distances'][0] if results.get('distances') else [0.0] * len(docs)

    # Optional reranking
    if rerank and len(docs) > top_k:
        # Simple keyword-based reranking: boost chunks that contain query terms
        query_terms = set(augmented_query.lower().split())
        scored = []
        for j, (doc, meta, dist) in enumerate(zip(docs, metas, distances)):
            doc_lower = doc.lower()
            keyword_hits = sum(1 for term in query_terms if term in doc_lower)
            # Combined score: lower distance is better, more keyword hits is better
            combined_score = (1.0 - dist) + (keyword_hits * 0.1)
            scored.append((combined_score, doc, meta, dist))

        scored.sort(key=lambda x: -x[0])
        docs = [s[1] for s in scored[:top_k]]
        metas = [s[2] for s in scored[:top_k]]
        distances = [s[3] for s in scored[:top_k]]

    # Output as JSONL
    for doc, meta, dist in zip(docs[:top_k], metas[:top_k], distances[:top_k]):
        result = {
            'file': meta.get('file', ''),
            'content': doc,
            'start_line': meta.get('start_line', 0),
            'end_line': meta.get('end_line', 0),
            'type': meta.get('type', 'code'),
            'score': round(1.0 - dist, 4),  # Convert distance to similarity
        }
        print(json.dumps(result, ensure_ascii=False))


# =============================================================================
# Main
# =============================================================================

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: rag-engine.py <index|retrieve>", file=sys.stderr)
        sys.exit(1)

    command = sys.argv[1]
    if command == 'index':
        cmd_index()
    elif command == 'retrieve':
        cmd_retrieve()
    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)
