# auto-memory-stop-hook

Claude Code has a native "auto-memory" feature: it writes structured memory files to `~/.claude/projects/<bucket>/memory/`, indexed by a `MEMORY.md`. It's on by default, but it fires *heuristically*. The model decides, turn by turn, whether something was "worth" saving. In practice, useful context gets dropped silently more often than you'd like.

This spell doesn't reimplement memory. It adds a `Stop` hook that forces Claude to actually check in on memory at the end of every single turn, instead of leaving it to the model's judgment.

## Hard dependency

**Requires a Claude Code build with native auto-memory support.** This is on by default in current versions, but is fully disabled in `--bare` mode. If your build doesn't have auto-memory, this hook has nothing to nudge — it'll fire, tell Claude to check memory, and there'll be no memory system there to write to.

## How it works

`hooks/save-session-memory.sh` runs on every `Stop` event:

1. **First `Stop`** of a turn: no sentinel file exists yet. It creates one (`/tmp/claude-memory-wakeup-<session_id>`), then exits with code `2` and a `systemMessage` telling Claude to review the conversation and save anything worth keeping via the `Write` tool. Exit code `2` plus `asyncRewake: true` (set in the settings snippet) wakes Claude back up to act on that message.
2. **Second `Stop`**, after Claude finishes the memory-save turn: the sentinel exists, so the script deletes it and exits `0` cleanly. No loop.

## Install

1. Copy the hook script:
   ```bash
   mkdir -p ~/.claude/hooks
   cp hooks/save-session-memory.sh ~/.claude/hooks/save-session-memory.sh
   ```
2. Merge `settings.snippet.json` into `~/.claude/settings.json`. If you don't already have a `hooks.Stop` entry, you can merge with `jq`:
   ```bash
   jq -s '.[0] * .[1]' ~/.claude/settings.json settings.snippet.json > /tmp/settings.merged.json \
     && mv /tmp/settings.merged.json ~/.claude/settings.json
   ```
   If you already have other `Stop` hooks configured, merge by hand instead: `jq`'s `*` operator on objects doesn't merge array values, it replaces them.
3. (Optional) Append `claude-md-snippet.md` to your global `~/.claude/CLAUDE.md`. This shapes *what* gets saved (proactive saving, cross-project bucket sanitization) once the hook makes saving reliable. The hook works without it.
4. Restart Claude Code.

## Caveats

- The sentinel file lives in `/tmp` and is keyed by session ID — if `/tmp` is cleared mid-session (unusual, but possible on some setups) the hook will treat the next `Stop` as a "first" one again. Harmless: worst case is one extra wake-and-check cycle.
- This hook fires every turn. On a very chatty session that's a lot of wake cycles. If that becomes annoying, the heuristic-only native behavior is the fallback — just remove the hook.
