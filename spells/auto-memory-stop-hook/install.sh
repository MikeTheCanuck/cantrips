#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
HOOK_DEST="${CLAUDE_DIR}/hooks/save-session-memory.sh"
HOOK_SRC="${SCRIPT_DIR}/hooks/save-session-memory.sh"
SNIPPET_FILE="${SCRIPT_DIR}/settings.snippet.json"
CLAUDE_MD_FILE="${HOME}/.claude/CLAUDE.md"
CLAUDE_MD_SNIPPET="${SCRIPT_DIR}/claude-md-snippet.md"
HOOK_COMMAND="bash ~/.claude/hooks/save-session-memory.sh"

DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=true
fi

CHANGED=false

# Step 1: jq dependency check
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required but not found." >&2
  echo "Install it with: brew install jq   (macOS)   or   apt install jq   (Linux)" >&2
  exit 1
fi

# Step 2: hook install
mkdir -p "${CLAUDE_DIR}/hooks"
if [ -f "$HOOK_DEST" ] && cmp -s "$HOOK_SRC" "$HOOK_DEST"; then
  : # hook already up to date, no-op
else
  if $DRY_RUN; then
    echo "Would copy ${HOOK_SRC} -> ${HOOK_DEST}"
  else
    cp "$HOOK_SRC" "$HOOK_DEST"
    chmod +x "$HOOK_DEST"
  fi
  CHANGED=true
fi
