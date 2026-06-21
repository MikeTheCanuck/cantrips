#!/bin/bash
# Fires on Stop. On first Stop, wakes Claude to save memory. On second Stop (after save), exits cleanly.
INPUT=$(cat)
SESSION_ID=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id','unknown'))" <<< "$INPUT" 2>/dev/null || echo "unknown")
SENTINEL="/tmp/claude-memory-wakeup-${SESSION_ID}"

if [ -f "$SENTINEL" ]; then
    rm -f "$SENTINEL"
    exit 0
fi

touch "$SENTINEL"
echo '{"systemMessage": "MEMORY CHECKPOINT: This session is ending. Review the conversation and save any important context — decisions, user preferences, project goals, key facts — to the memory system using the Write tool. Memory files live in ~/.claude/projects/<project>/memory/. If nothing new is worth saving, you can skip."}'
exit 2
