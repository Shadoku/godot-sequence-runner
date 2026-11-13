#!/bin/bash
# SessionStart hook for Claude Code on the web: make the pinned Godot available so
# `python3 tools/check.py` works. Does nothing outside the remote environment.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
BIN="$(bash "$ROOT/tools/install_godot.sh" | tail -n 1)"

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export GODOT=\"$BIN\"" >> "$CLAUDE_ENV_FILE"
  echo "export PATH=\"$(dirname "$BIN"):\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi

# Warm the test project's import cache so the first check of the session is fast.
(cd "$ROOT" && GODOT="$BIN" python3 tools/check.py --only import >/dev/null 2>&1) || true
echo "Godot ready: $BIN"
