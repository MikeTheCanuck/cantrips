# auto-memory-stop-hook: install script — design spec

## Problem

The `auto-memory-stop-hook` spell's README currently requires 4 manual steps to install: copy the hook script, merge `settings.snippet.json` into `~/.claude/settings.json` (with a hand-written `jq` command that the README itself warns can silently clobber other `Stop` hooks via `jq`'s `*` operator), optionally append a CLAUDE.md snippet, and restart Claude Code. This is too fussy for a casual user who just wants the trick installed — the manual `jq` step in particular asks the reader to understand a real footgun (array-replacement semantics) before running it.

## Solution

Add `install.sh` to the spell folder, automating all of the above into one command, while keeping the manual path documented for people who want fine-grained control or don't have `jq`.

## `install.sh` behavior

Runs from a checkout of the repo (relative paths: `hooks/save-session-memory.sh`, `settings.snippet.json`, `claude-md-snippet.md` in the same directory as the script).

1. **Check for `jq`.** If not found on `PATH`, print an install hint (`brew install jq` on macOS, `apt install jq` / equivalent on Linux) and exit 1 without touching anything else.
2. **Install the hook.** `mkdir -p ~/.claude/hooks`, copy `hooks/save-session-memory.sh` to `~/.claude/hooks/save-session-memory.sh`, `chmod +x` it.
3. **Merge settings**, with a backup taken first (`~/.claude/settings.json` → `~/.claude/settings.json.bak.<unix-timestamp>` if the file exists):
   - No `~/.claude/settings.json` exists → write `settings.snippet.json`'s content as the new file.
   - `~/.claude/settings.json` exists and its `hooks.Stop` array already contains an entry whose `command` is `bash ~/.claude/hooks/save-session-memory.sh` → skip the merge, print "already installed."
   - `~/.claude/settings.json` exists with a `hooks.Stop` array that does NOT already contain this hook → append the snippet's single `Stop` array entry into the existing array (not a blind `*` merge — this is the exact danger case the manual README instructions warn about by hand).
   - `~/.claude/settings.json` exists with no `hooks.Stop` key at all → merge the snippet's `hooks.Stop` key in cleanly (deep-merge at the `hooks` level is sufficient since there's no array to clobber).
4. **Prompt for the optional CLAUDE.md snippet:** `Also add the Memory Management policy snippet to your CLAUDE.md? [y/N]`. If yes: check `~/.claude/CLAUDE.md` for an existing `## Memory Management` heading first — if present, skip and print "already present"; if absent (or the file doesn't exist yet), append `claude-md-snippet.md`'s content.
5. **Print a closing line:** "Done. Restart Claude Code to pick up the new hook."

Every step is idempotent — running `install.sh` twice in a row produces the same end state as running it once, with no duplicate hook entries, no duplicate CLAUDE.md sections, and no accidental data loss (the settings.json backup exists before any merge is attempted).

## README restructure

The spell's `README.md` gets three changes:

1. **New "Prerequisites" section**, placed near the existing "Hard dependency" section: states `jq` and `bash` are required to run `install.sh`. (The Claude Code auto-memory requirement stays in its own existing "Hard dependency" section — this new section is just the install script's own tooling requirements.)
2. **"Install" section is rewritten** to lead with the one-liner: `./install.sh`, with a short description of what it does (copies the hook, merges settings safely, optionally offers the CLAUDE.md snippet).
3. **New "Manual install (advanced)" section**, placed after the scripted install: contains the original 4 numbered steps verbatim, reframed with an intro sentence along the lines of "If you'd rather control each step yourself, or don't have `jq` installed, here's exactly what `install.sh` does under the hood." This keeps the by-hand path fully documented for selective users, just demoted from primary to secondary.

The "Caveats" section is unchanged.

## Out of scope

- No uninstall script — not requested, and removing a hook is already a one-line manual edit per the existing Caveats section.
- No Windows/PowerShell support — the hook itself is bash-only (per the original source script), so the installer matches that constraint.
- No flags/options on `install.sh` (e.g. `--yes`, `--dry-run`) — not requested; the single y/N prompt is the only interactive point.
