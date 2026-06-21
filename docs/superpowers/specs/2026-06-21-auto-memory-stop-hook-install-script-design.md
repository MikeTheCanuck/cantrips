# auto-memory-stop-hook: install script — design spec

## Problem

The `auto-memory-stop-hook` spell's README currently requires 4 manual steps to install: copy the hook script, merge `settings.snippet.json` into `~/.claude/settings.json` (with a hand-written `jq` command that the README itself warns can silently clobber other `Stop` hooks via `jq`'s `*` operator), optionally append a CLAUDE.md snippet, and restart Claude Code. This is too fussy for a casual user who just wants the trick installed — the manual `jq` step in particular asks the reader to understand a real footgun (array-replacement semantics) before running it.

## Solution

Add `install.sh` to the spell folder, automating all of the above into one command, while keeping the manual path documented for people who want fine-grained control or don't have `jq`.

## `install.sh` behavior

Runs from a checkout of the repo (relative paths: `hooks/save-session-memory.sh`, `settings.snippet.json`, `claude-md-snippet.md` in the same directory as the script).

1. **Check for `jq`.** If not found on `PATH`, print an install hint (`brew install jq` on macOS, `apt install jq` / equivalent on Linux) and exit 1 without touching anything else.
2. **Install the hook.** `mkdir -p ~/.claude/hooks`, copy `hooks/save-session-memory.sh` to `~/.claude/hooks/save-session-memory.sh`, `chmod +x` it.
3. **Merge settings**, with a backup taken first if the file exists: `~/.claude/settings.json` → `~/.claude/settings.json.bak.<ISO-8601-timestamp>` (filename-safe form, e.g. `2026-06-21T14-32-05Z` — colons replaced with dashes; never a raw Unix epoch in any filename). Then:
   - No `~/.claude/settings.json` exists → write `settings.snippet.json`'s content as the new file. (No backup needed — nothing existed to lose.)
   - `~/.claude/settings.json` exists and its `hooks.Stop` array already contains an entry whose `command` is `bash ~/.claude/hooks/save-session-memory.sh` → skip the merge entirely (no backup taken either — nothing is changing), print "already installed, no changes made."
   - `~/.claude/settings.json` exists with a `hooks.Stop` array that does NOT already contain this hook → append the snippet's single `Stop` array entry into the existing array (not a blind `*` merge — this is the exact danger case the manual README instructions warn about by hand).
   - `~/.claude/settings.json` exists with no `hooks.Stop` key at all → set `.hooks.Stop` directly to the snippet's `hooks.Stop` value. The snippet's `hooks.Stop` is already a correctly-shaped one-element array of hook-group objects (per the settings schema: `Stop` is always an array of `{matcher?, hooks: [...]}` groups) — this produces a properly-shaped array on the first install, not a flattened value needing a later refactor.
4. **Prompt for the optional CLAUDE.md snippet**, with wording that's self-explanatory to someone who just cloned the repo and ran the script without reading the README first:
   ```
   Also append a CLAUDE.md snippet that tells Claude to save memory proactively during a session (not just when this hook checkpoints it) and to write memory to the correct per-project bucket when working across multiple projects? [y/N]
   ```
   If yes: check `~/.claude/CLAUDE.md` for an existing `## Memory Management` heading first — if present, skip and print "already present, no changes made"; if absent (or the file doesn't exist yet), append `claude-md-snippet.md`'s content.
5. **Print a closing summary that distinguishes a no-op rerun from a real install/update**, so a second run never leaves the user wondering whether anything just happened (or was duplicated) under the hood:
   - If every step above was a no-op (hook file already byte-identical, settings already contain the hook, CLAUDE.md already has the section or user declined): print `Already installed. No changes made.`
   - If anything changed: print `Installed/updated. Restart Claude Code to pick up the new hook.`

Every step is idempotent — running `install.sh` twice in a row produces the same end state as running it once, with no duplicate hook entries, no duplicate CLAUDE.md sections, and no accidental data loss (the settings.json backup exists before any merge is attempted, and is skipped entirely when no merge is needed).

## README restructure

The spell's `README.md` gets three changes:

1. **New "Prerequisites" section**, placed near the existing "Hard dependency" section: states `jq` and `bash` are required to run `install.sh`. (The Claude Code auto-memory requirement stays in its own existing "Hard dependency" section — this new section is just the install script's own tooling requirements.)
2. **"Install" section is rewritten** to lead with the one-liner: `./install.sh`, with a short description of what it does (copies the hook, merges settings safely, optionally offers the CLAUDE.md snippet).
3. **New "Manual install (advanced)" section**, placed after the scripted install: contains the original 4 numbered steps verbatim, reframed with an intro sentence along the lines of "If you'd rather control each step yourself, or don't have `jq` installed, here's exactly what `install.sh` does under the hood." This keeps the by-hand path fully documented for selective users, just demoted from primary to secondary.

The "Caveats" section is unchanged.

## `--dry-run` flag

`install.sh --dry-run` runs every detection step above (jq check, whether the hook file would change, whether settings.json would change and how, whether the CLAUDE.md section is already present) but performs zero writes — no file copies, no settings.json edits, no backup file created, no CLAUDE.md append, and the y/N prompt is skipped (nothing to confirm if nothing will be written). For each step, print what *would* happen, e.g.:

```
Would copy hooks/save-session-memory.sh -> ~/.claude/hooks/save-session-memory.sh
Would back up ~/.claude/settings.json -> ~/.claude/settings.json.bak.<timestamp>, then append this hook to its existing hooks.Stop array
Would append claude-md-snippet.md to ~/.claude/CLAUDE.md (no existing ## Memory Management section found) -- skipped without --dry-run unless you answer 'y' to the prompt
```

This exists specifically so a cautious user can see the exact effect on their `settings.json` and `CLAUDE.md` before trusting the script to touch either file.

## Out of scope

- No uninstall script — not requested, and removing a hook is already a one-line manual edit per the existing Caveats section.
- No Windows/PowerShell support — the hook itself is bash-only (per the original source script), so the installer matches that constraint.
- No `--yes` or other non-interactive flags — not requested; the single y/N prompt (skipped automatically under `--dry-run`, since there's nothing to confirm) is the only interactive point.
