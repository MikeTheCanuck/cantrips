# cantrips — design spec

## What this repo is

A small public catalog of reusable Claude Code (and, later, other agent/dev tooling) tricks. Each trick lives in its own self-contained folder under `spells/`, with everything needed to reproduce it on a fresh machine. The repo is an index, not a single tool — it's named `cantrips` deliberately so it can outlive any one trick.

Audience: public GitHub repo, casual tone. No marketing push, just a link you can hand a friend.

## First spell: `auto-memory-stop-hook`

### Problem it solves

Claude Code ships a native "auto-memory" feature (writes structured memory files to `~/.claude/projects/<bucket>/memory/`, indexed by `MEMORY.md`). It's on by default but triggers heuristically — the model decides when a turn is "worth" a memory save. In practice this means good context gets dropped silently.

### What the hook actually does

A `Stop` hook (`hooks/save-session-memory.sh`) fires every time a session ends. It uses a sentinel file (`/tmp/claude-memory-wakeup-<session_id>`) plus `asyncRewake: true` to:

1. On first `Stop`: drop a sentinel, emit `exit 2` with a `systemMessage` telling Claude to review the conversation and save anything worth keeping via the `Write` tool, then re-wake Claude to act on it.
2. On the second `Stop` (after the wake-triggered turn completes): find the sentinel, delete it, `exit 0` cleanly — no infinite loop.

This doesn't reimplement memory. It forces the existing native feature to fire reliably every turn instead of only when the model's own judgment calls for it.

### Hard dependency

Requires a Claude Code build with auto-memory support (current as of 2026; disabled entirely by `--bare` mode). The hook is a no-op shell of a feature without it — call this out clearly in the spell's README so nobody installs it on a build that doesn't support memory and wonders why nothing happens.

### Included artifacts

- `hooks/save-session-memory.sh` — the hook script, verbatim.
- `settings.snippet.json` — just the `hooks.Stop` block from `settings.json`, with a one-line merge instruction.
- `claude-md-snippet.md` — optional "Memory Management" policy paragraph (proactive save guidance, cross-project path sanitization rule) that shapes *what* gets saved once the hook makes saving reliable. Optional because the hook works without it, but pairs naturally.
- `README.md` — what it does, why, install steps, the hard dependency callout.

### Install pattern (same shape for every future spell)

Copy the spell's files into `~/.claude/` at the matching relative path, merge the settings snippet into `~/.claude/settings.json` (manual paste or `jq -s '.[0] * .[1]' settings.json settings.snippet.json`), restart Claude Code.

## Repo structure

```
cantrips/
  README.md              — index: table of spells, one-line each, link in
  LICENSE                 (MIT)
  spells/
    auto-memory-stop-hook/
      README.md
      hooks/save-session-memory.sh
      settings.snippet.json
      claude-md-snippet.md
```

## Out of scope (future spells, not this pass)

- rtk / other-agent bootstrap tricks
- dotfiles-style tricks
- broader CLAUDE.md policy entries (project bucket registry, GitHub voice checklist, etc.) — personal/Mike-specific, not generically reusable as-is

## License

MIT.
