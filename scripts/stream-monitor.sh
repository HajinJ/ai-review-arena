#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
export ARENA_PLUGIN_DIR="$PLUGIN_DIR"
exec python3 "$SCRIPT_DIR/arena-runtime.py" stream-monitor "$@"
