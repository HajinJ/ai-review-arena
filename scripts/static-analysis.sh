#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNTIME="$SCRIPT_DIR/arena-runtime.py"
export ARENA_PLUGIN_DIR="$PLUGIN_DIR"
exec python3 "$RUNTIME" static-analysis "$@"
