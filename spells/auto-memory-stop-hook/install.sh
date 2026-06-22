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

# Step 3: settings merge
if [ ! -f "$SETTINGS_FILE" ]; then
  if $DRY_RUN; then
    echo "Would create ${SETTINGS_FILE} from ${SNIPPET_FILE}"
  else
    mkdir -p "$CLAUDE_DIR"
    cp "$SNIPPET_FILE" "$SETTINGS_FILE"
  fi
  CHANGED=true
else
  ALREADY_PRESENT="$(jq --arg cmd "$HOOK_COMMAND" \
    '[(.hooks.Stop // [])[] | (.hooks // [])[] | select(.command == $cmd)] | length > 0' \
    "$SETTINGS_FILE")"
  if [ "$ALREADY_PRESENT" = "true" ]; then
    : # already installed, no-op
  else
    TIMESTAMP="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
    BACKUP_FILE="${SETTINGS_FILE}.bak.${TIMESTAMP}"
    HAS_STOP="$(jq 'has("hooks") and (.hooks | has("Stop"))' "$SETTINGS_FILE")"
    if $DRY_RUN; then
      if [ "$HAS_STOP" = "true" ]; then
        echo "Would back up ${SETTINGS_FILE} -> ${BACKUP_FILE}, then append this hook to its existing hooks.Stop array"
      else
        echo "Would back up ${SETTINGS_FILE} -> ${BACKUP_FILE}, then add hooks.Stop"
      fi
    else
      cp "$SETTINGS_FILE" "$BACKUP_FILE"
      if [ "$HAS_STOP" = "true" ]; then
        SNIPPET_STOP_ENTRY="$(jq '.hooks.Stop[0]' "$SNIPPET_FILE")"
        jq --argjson entry "$SNIPPET_STOP_ENTRY" '.hooks.Stop += [$entry]' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"
      else
        SNIPPET_STOP="$(jq '.hooks.Stop' "$SNIPPET_FILE")"
        jq --argjson stop "$SNIPPET_STOP" '.hooks.Stop = $stop' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"
      fi
      mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    fi
    CHANGED=true
  fi
fi

# Step 4: CLAUDE.md snippet prompt
if [ -f "$CLAUDE_MD_FILE" ] && grep -q "## Memory Management" "$CLAUDE_MD_FILE"; then
  : # already present, no-op, never prompt
else
  if $DRY_RUN; then
    echo "Would prompt to append ${CLAUDE_MD_SNIPPET} to ${CLAUDE_MD_FILE} (no existing ## Memory Management section found)"
  else
    REPLY=""
    read -r -p "Also append a CLAUDE.md snippet that tells Claude to save memory proactively during a session (not just when this hook checkpoints it) and to write memory to the correct per-project bucket when working across multiple projects? [y/N] " REPLY || true
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
      mkdir -p "$CLAUDE_DIR"
      printf '\n%s\n' "$(cat "$CLAUDE_MD_SNIPPET")" >> "$CLAUDE_MD_FILE"
      CHANGED=true
    fi
  fi
fi

# Step 5: closing summary
if $DRY_RUN; then
  exit 0
fi
if $CHANGED; then
  echo "Installed/updated. Restart Claude Code to pick up the new hook."
else
  echo "Already installed. No changes made."
fi
