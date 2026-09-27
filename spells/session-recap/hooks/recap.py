#!/usr/bin/env python3
"""SessionStart hook: show the "where we left off" note written by summarize.py.

Shows a short recap on screen (systemMessage) and gives Claude the full note
(additionalContext) so it can offer to pick up where the last session ended.

While summarize.py is still writing a fresh note (last_session.pending exists), a fresh
start shows the previous note marked as updating, and /clear shows a one-line pointer
instead of a recap of the conversation that was just cleared.

`recap.py --wait <cwd>` (used by the /recap skill) waits for a pending note to finish,
then prints the recap as plain text.
"""
import datetime
import json
import os
import re
import sys
import time
from pathlib import Path

CHILD_ENVIRONMENT_FLAG = "CLAUDE_RECAP_CHILD"
NOTE_FILENAME = "last_session.md"
PENDING_FILENAME = "last_session.pending"
PROJECTS_DIRECTORY = Path.home() / ".claude" / "projects"
PENDING_STALE_AFTER_SECONDS = 5 * 60
WAIT_LIMIT_SECONDS = 110
WAIT_POLL_SECONDS = 2
UPDATING_HINT = "(updating in the background - /recap shows the fresh one when it's done)"


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


def is_pending(memory_directory):
    pending_path = memory_directory / PENDING_FILENAME
    if not pending_path.is_file():
        return False
    return time.time() - pending_path.stat().st_mtime < PENDING_STALE_AFTER_SECONDS


def read_note(memory_directory):
    """Return (note text, age description), or (None, None) if there is no note."""
    note_path = memory_directory / NOTE_FILENAME
    if not note_path.is_file():
        return None, None
    note = note_path.read_text()
    written_match = re.search(r"written (\S+)", note)
    age = describe_age(datetime.datetime.fromisoformat(written_match.group(1))) if written_match else "recently"
    return note, age


def bucket_for_working_directory(working_directory):
    """Claude Code names a project's bucket after its path, with every non-alphanumeric as '-'."""
    return PROJECTS_DIRECTORY / re.sub(r"[^A-Za-z0-9]", "-", working_directory)


def run_session_start_hook():
    payload = json.load(sys.stdin)
    source = payload.get("source")
    if source not in ("startup", "clear"):
        return
    memory_directory = Path(payload.get("transcript_path", "")).parent / "memory"
    pending = is_pending(memory_directory)
    if source == "clear":
        if pending:
            print(json.dumps({"systemMessage": "Recap of what you just cleared is being written. /recap shows it when it's ready."}))
        return
    note, age = read_note(memory_directory)
    if note is None:
        return
    display = build_display(parse_fields(note), age)
    if pending:
        display += f"\n{UPDATING_HINT}"
    context = (
        f"Where the previous session in this project left off ({age}):\n{note}\n"
        "The user has already seen this recap on screen (every line except STATE). If their first "
        "message is a greeting, vague, or asks what's next, offer in one sentence to pick this up, "
        "or to choose something else from memory or the project backlog. If their first message "
        "is about something else, just do that and don't mention this note."
    )
    print(json.dumps({
        "systemMessage": display,
        "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": context},
    }))


def run_wait(working_directory):
    memory_directory = bucket_for_working_directory(working_directory) / "memory"
    deadline = time.time() + WAIT_LIMIT_SECONDS
    while is_pending(memory_directory) and time.time() < deadline:
        time.sleep(WAIT_POLL_SECONDS)
    note, age = read_note(memory_directory)
    if note is None:
        print("No recap yet for this project.")
        return
    print(build_display(parse_fields(note), age))
    if is_pending(memory_directory):
        print("(still updating - try /recap again in a minute)")


if __name__ == "__main__":
    if os.environ.get(CHILD_ENVIRONMENT_FLAG):
        sys.exit(0)
    if len(sys.argv) == 3 and sys.argv[1] == "--wait":
        run_wait(sys.argv[2])
        sys.exit(0)
    try:
        run_session_start_hook()
    except Exception:
        pass
