#!/usr/bin/env python3
"""SessionStart hook: show the "where we left off" note written by summarize.py.

Shows a short recap on screen (systemMessage) and gives Claude the full note
(additionalContext) so it can offer to pick up where the last session ended.
"""
import datetime
import json
import os
import re
import sys
from pathlib import Path

CHILD_ENVIRONMENT_FLAG = "CLAUDE_RECAP_CHILD"
NOTE_FILENAME = "last_session.md"
SHOWN_SOURCES = ("startup", "clear")


def describe_age(written_at):
    minutes = int((datetime.datetime.now().astimezone() - written_at).total_seconds() // 60)
    if minutes < 60:
        return f"{minutes}m ago"
    if minutes < 48 * 60:
        return f"{minutes // 60}h ago"
    return f"{minutes // (24 * 60)} days ago"


def parse_fields(note):
    """Return the note's KEY: value lines as an ordered dict."""
    return {
        match.group(1): match.group(2).strip()
        for match in re.finditer(r"^([A-Z][A-Z ]*):\s*(.+)$", note, flags=re.MULTILINE)
    }


def build_display(fields, age):
    """Headline first, then every other non-empty field except STATE (context only)."""
    lines = [f"Last time here ({age}): {fields.get('HEADLINE', '')}"]
    labels = {"NEXT": "Next", "OPEN QUESTION": "Open"}
    for key, value in fields.items():
        if key in ("HEADLINE", "STATE") or not value or value.lower().rstrip(".") == "none":
            continue
        lines.append(f"{labels.get(key, key.capitalize())}: {value}")
    return "\n".join(lines)


def main():
    if os.environ.get(CHILD_ENVIRONMENT_FLAG):
        return
    payload = json.load(sys.stdin)
    if payload.get("source") not in SHOWN_SOURCES:
        return
    note_path = Path(payload.get("transcript_path", "")).parent / "memory" / NOTE_FILENAME
    if not note_path.is_file():
        return
    note = note_path.read_text()
    written_match = re.search(r"written (\S+)", note)
    age = describe_age(datetime.datetime.fromisoformat(written_match.group(1))) if written_match else "recently"

    context = (
        f"Where the previous session in this project left off ({age}):\n{note}\n"
        "The user has already seen this recap on screen (every line except STATE). If their first "
        "message is a greeting, vague, or asks what's next, offer in one sentence to pick this up, "
        "or to choose something else from memory or the project backlog. If their first message "
        "is about something else, just do that and don't mention this note."
    )
    print(json.dumps({
        "systemMessage": build_display(parse_fields(note), age),
        "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": context},
    }))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
