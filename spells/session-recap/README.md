# session-recap

Start `claude` in a project folder and the first thing on screen is where you left off last time:

```
Last time here (2h ago): Wiring up the widget exporter
Next: Add a JSON round-trip test.
Open: Keep CSV as the default, or switch to JSON?
```

No `--continue`, no `--resume`, no scrolling back through a transcript trying to remember which of your half-dozen projects this tab even belongs to. Claude gets the full note too, so if you open with "hey" or "what's next" it'll offer to pick the thread back up. Open with something else and it stays out of the way.

This replaces [auto-memory-stop-hook](../auto-memory-stop-hook/). That one forced a memory check on every single turn, which worked, but it meant every answer got followed by a second little "memory is current" exchange. Turns out the thing I actually needed wasn't *more saving*. It was a reliable way to get my bearings back at the start of the next session. (Also: a hook that wakes Claude up can never be silent. A woken turn always renders.)

## How it works

Three hooks, none of which ever puts anything in your session while you're working.

`hooks/summarize.py` runs on `SessionEnd` (you quit, or `/clear`) and `PreCompact` (right before context gets squashed, which is exactly when details get lost). It returns immediately and hands off to a detached background process, so it never holds up your exit. That process feeds the transcript to a headless `claude -p` on Haiku and writes a four-line note (HEADLINE, STATE, NEXT, OPEN QUESTION) to `~/.claude/projects/<bucket>/memory/last_session.md`. Sessions with fewer than two real prompts don't overwrite an existing note, so opening Claude to ask one quick question doesn't wipe out your real place.

`hooks/recap.py` runs on `SessionStart` for fresh starts and `/clear`, not for resume or compaction. It shows the note on screen and hands the whole thing to Claude as context.

Each project folder has its own memory bucket, so each project gets its own recap.

## /clear, and the one-minute gap

The summary takes 15 to 60 seconds, but `/clear` starts the new session instantly. So while a summary is still being written, `summarize.py` leaves a `last_session.pending` marker, and the recap adjusts. After `/clear` you get one line ("Recap of what you just cleared is being written. /recap shows it when it's ready.") instead of a stale recap of a conversation you were literally just in. A quick quit-and-restart shows the previous note with an "updating" tag.

Type `/recap` whenever you want it. It waits for the background summary to finish (up to about two minutes), then shows the fresh note and asks whether to pick the thread back up. I `/clear` constantly, so this is the one I actually use.

## Adding your own lines

Drop an `extra-prompt.md` next to the scripts in `~/.claude/hooks/session-recap/` and the summariser will add whatever lines it describes, in the same `KEY: value` format. The recap shows any extra line that isn't "none". Mine asks whether the session produced anything worth sharing with my work setup:

```
BRIDGE: <if this session produced something worth sharing with my work notes, name it in one sentence; otherwise "none">
```

## Prerequisites

`python3`, `jq`, and the `claude` CLI on your PATH. Each summary is a small Haiku call, so it counts against your plan or API usage like any other session.

## Install

```bash
./install.sh
```

Copies both scripts into `~/.claude/hooks/session-recap/` and the `/recap` skill into `~/.claude/skills/recap/`, backs up your `settings.json`, and adds the three hooks alongside whatever hooks you already have. If it finds the old auto-memory-stop-hook `Stop` hook, it asks whether to remove it. Safe to re-run. `./install.sh --dry-run` shows what it would do without touching anything.

Tests: `python3 -m unittest discover tests` for the hook scripts, `bash tests/test_install.sh` for the installer (runs against a throwaway `$HOME`).

## Things I tripped over, so you don't have to

The headless summariser is itself a Claude Code session, which means by default it loads *your* hooks. Mine picked up the old per-turn Stop hook, got nudged into a second turn, and overwrote its own summary with "I'm only a summariser." It now runs with `--setting-sources project` from a temp directory, plus an environment flag both scripts check so nothing recurses.

Without its own `--system-prompt`, Haiku read the transcript and just... kept the conversation going. It answered my last question instead of summarising it.

If a note isn't showing up, check `~/.claude/hooks/session-recap/recap.log`. It logs every write and every failure.
