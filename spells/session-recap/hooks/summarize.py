#!/usr/bin/env python3
"""SessionEnd / PreCompact hook: write a "where we left off" note for this project.

Hook mode returns immediately and hands the work to a detached worker, so it never
blocks exit or compaction and never shows anything in the session. The worker runs a
headless `claude -p` over the transcript and writes <bucket>/memory/last_session.md,
which recap.py shows at the next session start.

Optional: put extra instructions in extra-prompt.md next to this script to ask the
summarizer for more "KEY: value" lines. recap.py shows any extra line that isn't "none".
"""
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

CHILD_ENVIRONMENT_FLAG = "CLAUDE_RECAP_CHILD"
HOOK_DIRECTORY = Path(__file__).resolve().parent
LOG_PATH = HOOK_DIRECTORY / "recap.log"
EXTRA_PROMPT_PATH = HOOK_DIRECTORY / "extra-prompt.md"
NOTE_FILENAME = "last_session.md"
PENDING_FILENAME = "last_session.pending"
MINIMUM_USER_PROMPTS = 2
EXCERPT_CHARACTER_LIMIT = 40_000
SUMMARIZER_MODEL = "haiku"
SUMMARIZER_TIMEOUT_SECONDS = 240

SUMMARIZER_PROMPT = """You are writing a short "where we left off" note so that the user, who \
may be juggling several projects, can instantly re-orient at the start of their next Claude \
Code session in this project. You will be given the transcript of the session that just ended.

Focus on the MOST RECENT thread of work, not the whole session history. Write exactly this \
format and nothing else, plain text, no markdown headers or bold:

HEADLINE: <at most 12 words: what we were working on>
STATE: <1-2 sentences: where it stands right now, concretely>
NEXT: <1 sentence: the most likely next step>
OPEN QUESTION: <the unanswered question or pending decision for the user, or "none">
{extra_lines}
You are only a summarizer. Never continue, answer, or take part in the conversation."""


def build_summarizer_prompt():
    extra_lines = ""
    if EXTRA_PROMPT_PATH.is_file():
        extra_lines = (
            "\nThen add these extra lines, same KEY: value format:\n"
            f"{EXTRA_PROMPT_PATH.read_text().strip()}\n"
        )
    return SUMMARIZER_PROMPT.format(extra_lines=extra_lines)


def log(message):
    timestamp = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    with open(LOG_PATH, "a") as log_file:
        log_file.write(f"{timestamp} {message}\n")


def strip_system_noise(text):
    text = re.sub(r"<system-reminder>.*?</system-reminder>", "", text, flags=re.DOTALL)
    return text.strip()


def extract_conversation(transcript_path):
    """Return (list of "User:/Claude:" lines, count of real user prompts)."""
    lines = []
    user_prompt_count = 0
    with open(transcript_path) as transcript_file:
        for raw_line in transcript_file:
            try:
                entry = json.loads(raw_line)
            except json.JSONDecodeError:
                continue
            entry_type = entry.get("type")
            if entry_type not in ("user", "assistant") or entry.get("isMeta"):
                continue
            content = entry.get("message", {}).get("content")
            if isinstance(content, str):
                texts = [content]
            elif isinstance(content, list):
                texts = [block.get("text", "") for block in content if block.get("type") == "text"]
            else:
                continue
            text = strip_system_noise("\n".join(texts))
            if not text or text.startswith("<"):
                continue
            speaker = "User" if entry_type == "user" else "Claude"
            if speaker == "User":
                user_prompt_count += 1
            lines.append(f"{speaker}: {text}")
    return lines, user_prompt_count


def run_hook():
    if os.environ.get(CHILD_ENVIRONMENT_FLAG):
        return
    payload = json.load(sys.stdin)
    claude_binary = shutil.which("claude")
    if not claude_binary:
        log("claude binary not found on PATH; skipping")
        return
    payload["claude_binary"] = claude_binary
    memory_directory = Path(payload.get("transcript_path", "")).parent / "memory"
    if memory_directory.parent.is_dir():
        memory_directory.mkdir(exist_ok=True)
        (memory_directory / PENDING_FILENAME).write_text(payload.get("hook_event_name", "?"))
    handle, payload_path = tempfile.mkstemp(prefix="recap-", suffix=".json")
    with os.fdopen(handle, "w") as payload_file:
        json.dump(payload, payload_file)
    subprocess.Popen(
        [sys.executable, __file__, "--worker", payload_path],
        start_new_session=True,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env={**os.environ, CHILD_ENVIRONMENT_FLAG: "1"},
    )


def run_worker(payload_path):
    with open(payload_path) as payload_file:
        payload = json.load(payload_file)
    os.unlink(payload_path)
    pending_path = Path(payload.get("transcript_path", "")).parent / "memory" / PENDING_FILENAME
    try:
        summarize_session(payload)
    finally:
        pending_path.unlink(missing_ok=True)


def summarize_session(payload):
    transcript_path = Path(payload.get("transcript_path", ""))
    event = payload.get("hook_event_name", "?")
    if not transcript_path.is_file():
        log(f"{event}: no transcript at {transcript_path}")
        return
    lines, user_prompt_count = extract_conversation(transcript_path)
    if user_prompt_count < MINIMUM_USER_PROMPTS:
        log(f"{event}: {transcript_path.name} too short ({user_prompt_count} prompts); keeping previous note")
        return
    excerpt = "\n\n".join(lines)[-EXCERPT_CHARACTER_LIMIT:]
    result = subprocess.run(
        [payload["claude_binary"], "-p", "--model", SUMMARIZER_MODEL,
         "--no-session-persistence", "--tools", "", "--setting-sources", "project",
         "--system-prompt", build_summarizer_prompt()],
        input=f"<transcript>\n{excerpt}\n</transcript>\n\nWrite the four-line note for this transcript now.",
        capture_output=True,
        text=True,
        timeout=SUMMARIZER_TIMEOUT_SECONDS,
        cwd=tempfile.gettempdir(),
    )
    summary = result.stdout.strip()
    if result.returncode != 0 or "HEADLINE:" not in summary:
        log(f"{event}: summarizer failed rc={result.returncode} stderr={result.stderr.strip()[:300]!r} stdout={summary[:400]!r}")
        return
    memory_directory = transcript_path.parent / "memory"
    memory_directory.mkdir(exist_ok=True)
    written_at = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    note = (
        f"<!-- written {written_at} by session-recap ({event}), "
        f"session {payload.get('session_id')}, cwd {payload.get('cwd')} -->\n{summary}\n"
    )
    note_path = memory_directory / NOTE_FILENAME
    temporary_note_path = note_path.with_suffix(".tmp")
    temporary_note_path.write_text(note)
    temporary_note_path.replace(note_path)
    log(f"{event}: wrote {note_path}")


if __name__ == "__main__":
    try:
        if len(sys.argv) == 3 and sys.argv[1] == "--worker":
            run_worker(sys.argv[2])
        else:
            run_hook()
    except Exception as error:  # never let a hook failure surface in the session
        log(f"error: {error!r}")
