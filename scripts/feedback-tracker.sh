#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNTIME="$SCRIPT_DIR/arena-runtime.py"
if [ ! -f "$RUNTIME" ]; then
  SEARCH_DIR="$PWD"
  while [ "$SEARCH_DIR" != "/" ]; do
    if [ -f "$SEARCH_DIR/scripts/arena-runtime.py" ] && [ -d "$SEARCH_DIR/arena_runtime" ]; then
      RUNTIME="$SEARCH_DIR/scripts/arena-runtime.py"
      break
    fi
    SEARCH_DIR="$(dirname "$SEARCH_DIR")"
  done
fi
export ARENA_PLUGIN_DIR="$PLUGIN_DIR"
exec python3 "$RUNTIME" feedback-tracker "$@"
