#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
HOOK_DEST_DIR="${CLAUDE_DIR}/hooks/session-recap"
SNIPPET_FILE="${SCRIPT_DIR}/settings.snippet.json"
OLD_STOP_HOOK_COMMAND="bash ~/.claude/hooks/save-session-memory.sh"

DRY_RUN=false
if [ -n "${1:-}" ]; then
  if [ "$1" = "--dry-run" ]; then
    DRY_RUN=true
  else
    echo "Unknown argument: $1" >&2
    echo "Usage: $0 [--dry-run]" >&2
    exit 1
  fi
fi

CHANGED=false

# Step 1: dependency checks
for dependency in jq python3 claude; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    echo "${dependency} is required but not found on PATH." >&2
    exit 1
  fi
done

# Step 2: hook scripts
mkdir -p "$HOOK_DEST_DIR"
for script in summarize.py recap.py; do
  if [ -f "${HOOK_DEST_DIR}/${script}" ] && cmp -s "${SCRIPT_DIR}/hooks/${script}" "${HOOK_DEST_DIR}/${script}"; then
    : # already up to date
  else
    if $DRY_RUN; then
      echo "Would copy hooks/${script} -> ${HOOK_DEST_DIR}/${script}"
    else
      cp "${SCRIPT_DIR}/hooks/${script}" "${HOOK_DEST_DIR}/${script}"
      chmod +x "${HOOK_DEST_DIR}/${script}"
    fi
    CHANGED=true
  fi
done

# Step 3: settings merge, one event at a time, appending to any existing hooks for that event
if [ ! -f "$SETTINGS_FILE" ]; then
  if $DRY_RUN; then
    echo "Would create ${SETTINGS_FILE} from ${SNIPPET_FILE}"
  else
    mkdir -p "$CLAUDE_DIR"
    cp "$SNIPPET_FILE" "$SETTINGS_FILE"
  fi
  CHANGED=true
else
  if ! jq -e . "$SETTINGS_FILE" >/dev/null 2>&1; then
    echo "Your ~/.claude/settings.json isn't valid JSON; fix it or merge by hand (see README)." >&2
    exit 1
  fi
  MERGED="$(jq --slurpfile snippet "$SNIPPET_FILE" '
    reduce ($snippet[0].hooks | to_entries[]) as $event (.;
      ($event.value[0].hooks[0].command) as $command
      | if ([(.hooks[$event.key] // [])[] | (.hooks // [])[] | select(.command == $command)] | length) > 0
        then .
        else .hooks[$event.key] = ((.hooks[$event.key] // []) + $event.value)
        end)' "$SETTINGS_FILE")"
  if [ "$MERGED" = "$(jq . "$SETTINGS_FILE")" ]; then
    : # all three hooks already present
  else
    BACKUP_FILE="${SETTINGS_FILE}.bak.$(date -u +%Y-%m-%dT%H-%M-%SZ)"
    if $DRY_RUN; then
      echo "Would back up ${SETTINGS_FILE} -> ${BACKUP_FILE}, then add the SessionEnd, PreCompact and SessionStart hooks"
    else
      cp "$SETTINGS_FILE" "$BACKUP_FILE"
      printf '%s\n' "$MERGED" > "$SETTINGS_FILE"
    fi
    CHANGED=true
  fi
fi

# Step 4: offer to remove the per-turn Stop hook from the older auto-memory-stop-hook spell
if [ -f "$SETTINGS_FILE" ]; then
  HAS_OLD_HOOK="$(jq --arg command "$OLD_STOP_HOOK_COMMAND" \
    '[(.hooks.Stop // [])[] | (.hooks // [])[] | select(.command == $command)] | length > 0' "$SETTINGS_FILE")"
  if [ "$HAS_OLD_HOOK" = "true" ]; then
    if $DRY_RUN; then
      echo "Would offer to remove the old auto-memory-stop-hook Stop hook"
    else
      REPLY=""
      read -r -p "Found the per-turn Stop hook from auto-memory-stop-hook. session-recap replaces it. Remove it? [y/N] " REPLY || true
      if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        jq --arg command "$OLD_STOP_HOOK_COMMAND" '
          .hooks.Stop |= map(.hooks |= map(select(.command != $command)) | select(.hooks | length > 0))
          | if (.hooks.Stop | length) == 0 then del(.hooks.Stop) else . end' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"
        mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
        CHANGED=true
      fi
    fi
  fi
fi

# Step 5: closing summary
if $DRY_RUN; then
  exit 0
fi
if $CHANGED; then
  echo "Installed/updated. Restart Claude Code to pick up the new hooks."
else
  echo "Already installed. No changes made."
fi
