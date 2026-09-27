"""Tests for the session-recap hook scripts. Run with: python3 -m unittest discover tests"""
import contextlib
import datetime
import io
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

HOOKS_DIRECTORY = Path(__file__).resolve().parent.parent / "hooks"
sys.path.insert(0, str(HOOKS_DIRECTORY))

import recap  # noqa: E402
import summarize  # noqa: E402

SAMPLE_NOTE = """<!-- written {written_at} by session-recap (SessionEnd), session abc, cwd /x -->
HEADLINE: Wiring up the widget exporter
STATE: Exporter writes CSV; JSON path untested.
NEXT: Add a JSON round-trip test.
OPEN QUESTION: none
BRIDGE: New pytest fixture pattern worth sharing
"""


def write_transcript(path, entries):
    with open(path, "w") as transcript_file:
        for entry in entries:
            transcript_file.write(json.dumps(entry) + "\n")


def user_entry(content, **extra):
    return {"type": "user", "message": {"role": "user", "content": content}, **extra}


def assistant_entry(text):
    return {"type": "assistant", "message": {"role": "assistant", "content": [
        {"type": "thinking", "thinking": "hidden"},
        {"type": "text", "text": text},
        {"type": "tool_use", "name": "Bash", "input": {}},
    ]}}


class ExtractConversationTests(unittest.TestCase):
    def test_keeps_real_prompts_and_assistant_text_only(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            transcript_path = Path(temporary_directory) / "session.jsonl"
            write_transcript(transcript_path, [
                {"type": "system", "content": "ignored"},
                user_entry("fix the exporter"),
                user_entry("<command-name>/clear</command-name>"),
                user_entry("meta note", isMeta=True),
                user_entry([{"type": "tool_result", "content": "tool noise"}]),
                assistant_entry("Looking at it.<system-reminder>internal</system-reminder>"),
                user_entry("now add JSON"),
            ])
            lines, user_prompt_count = summarize.extract_conversation(transcript_path)
        self.assertEqual(user_prompt_count, 2)
        self.assertEqual(lines, ["User: fix the exporter", "Claude: Looking at it.", "User: now add JSON"])


class SummarizerPromptTests(unittest.TestCase):
    def test_extra_prompt_file_is_appended_when_present(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            extra_prompt_path = Path(temporary_directory) / "extra-prompt.md"
            original_path = summarize.EXTRA_PROMPT_PATH
            summarize.EXTRA_PROMPT_PATH = extra_prompt_path
            try:
                self.assertNotIn("extra lines", summarize.build_summarizer_prompt())
                extra_prompt_path.write_text("BRIDGE: <anything worth sharing, or none>")
                prompt = summarize.build_summarizer_prompt()
            finally:
                summarize.EXTRA_PROMPT_PATH = original_path
        self.assertIn("BRIDGE: <anything worth sharing, or none>", prompt)
        self.assertIn("HEADLINE:", prompt)


class RecapDisplayTests(unittest.TestCase):
    def test_display_skips_state_and_none_and_shows_extra_fields(self):
        fields = recap.parse_fields(SAMPLE_NOTE.format(written_at="2026-01-01T00:00:00+00:00"))
        display = recap.build_display(fields, "2h ago")
        self.assertEqual(display.splitlines(), [
            "Last time here (2h ago): Wiring up the widget exporter",
            "Next: Add a JSON round-trip test.",
            "Bridge: New pytest fixture pattern worth sharing",
        ])


class RecapHookTests(unittest.TestCase):
    def run_recap(self, payload, environment=None):
        result = subprocess.run(
            [sys.executable, str(HOOKS_DIRECTORY / "recap.py")],
            input=json.dumps(payload), capture_output=True, text=True,
            env={**os.environ, **(environment or {})},
        )
        return result.stdout.strip()

    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        bucket = Path(self.temporary_directory.name) / "bucket"
        (bucket / "memory").mkdir(parents=True)
        written_at = (datetime.datetime.now().astimezone() - datetime.timedelta(hours=3)).isoformat()
        (bucket / "memory" / "last_session.md").write_text(SAMPLE_NOTE.format(written_at=written_at))
        self.transcript_path = str(bucket / "new-session.jsonl")

    def tearDown(self):
        self.temporary_directory.cleanup()

    def test_startup_shows_recap_and_injects_context(self):
        output = json.loads(self.run_recap({"source": "startup", "transcript_path": self.transcript_path}))
        self.assertTrue(output["systemMessage"].startswith("Last time here (3h ago): Wiring up"))
        self.assertIn("STATE: Exporter writes CSV", output["hookSpecificOutput"]["additionalContext"])

    def mark_pending(self):
        pending_path = Path(self.transcript_path).parent / "memory" / "last_session.pending"
        pending_path.write_text("SessionEnd")
        return pending_path

    def test_startup_while_pending_marks_note_as_updating(self):
        self.mark_pending()
        output = json.loads(self.run_recap({"source": "startup", "transcript_path": self.transcript_path}))
        self.assertIn("updating in the background", output["systemMessage"])

    def test_clear_shows_pointer_only_while_pending(self):
        payload = {"source": "clear", "transcript_path": self.transcript_path}
        self.assertEqual(self.run_recap(payload), "")
        self.mark_pending()
        self.assertIn("/recap", json.loads(self.run_recap(payload))["systemMessage"])

    def test_stale_pending_marker_is_ignored(self):
        pending_path = self.mark_pending()
        an_hour_ago = time.time() - 3600
        os.utime(pending_path, (an_hour_ago, an_hour_ago))
        output = json.loads(self.run_recap({"source": "startup", "transcript_path": self.transcript_path}))
        self.assertNotIn("updating", output["systemMessage"])

    def test_resume_and_compact_show_nothing(self):
        for source in ("resume", "compact"):
            self.assertEqual(self.run_recap({"source": source, "transcript_path": self.transcript_path}), "")

    def test_summarizer_child_shows_nothing(self):
        payload = {"source": "startup", "transcript_path": self.transcript_path}
        self.assertEqual(self.run_recap(payload, {"CLAUDE_RECAP_CHILD": "1"}), "")

    def test_missing_note_shows_nothing(self):
        payload = {"source": "startup", "transcript_path": "/nonexistent/bucket/x.jsonl"}
        self.assertEqual(self.run_recap(payload), "")


class WaitModeTests(unittest.TestCase):
    def test_bucket_name_matches_claude_code_convention(self):
        self.assertEqual(recap.bucket_for_working_directory("/Users/me/code/daily-brief").name,
                         "-Users-me-code-daily-brief")

    def test_wait_returns_note_once_pending_clears(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            original_projects = recap.PROJECTS_DIRECTORY
            recap.PROJECTS_DIRECTORY = Path(temporary_directory)
            original_poll = recap.WAIT_POLL_SECONDS
            recap.WAIT_POLL_SECONDS = 0.05
            try:
                memory_directory = recap.bucket_for_working_directory("/x/proj") / "memory"
                memory_directory.mkdir(parents=True)
                pending_path = memory_directory / "last_session.pending"
                pending_path.write_text("SessionEnd")
                (memory_directory / "last_session.md").write_text(
                    SAMPLE_NOTE.format(written_at=datetime.datetime.now().astimezone().isoformat()))
                threading.Timer(0.3, pending_path.unlink).start()
                captured = io.StringIO()
                with contextlib.redirect_stdout(captured):
                    recap.run_wait("/x/proj")
            finally:
                recap.PROJECTS_DIRECTORY = original_projects
                recap.WAIT_POLL_SECONDS = original_poll
        self.assertTrue(captured.getvalue().startswith("Last time here (0m ago): Wiring up"))
        self.assertNotIn("still updating", captured.getvalue())


if __name__ == "__main__":
    unittest.main()
