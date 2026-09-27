---
name: recap
description: Show where the last session in this project left off, waiting for the background session-recap summary to finish if it's still being written. Use when the user types /recap, or asks "where were we", "what was I doing", or "is the recap ready" right after a /clear or restart.
---

Run this and wait for it. It returns as soon as the background summary finishes, or after about two minutes:

```bash
python3 ~/.claude/hooks/session-recap/recap.py --wait "$PWD"
```

Show its output exactly as printed, then ask in one short sentence whether to pick that thread back up or do something else. Say nothing else. Don't explain the hook or the waiting.

If it printed "No recap yet for this project.", say so in one line and ask what they'd like to work on.
