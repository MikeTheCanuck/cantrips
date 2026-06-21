# Cantrips: auto-memory-stop-hook Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the `cantrips` repo with its first spell, `auto-memory-stop-hook`, and push it public to GitHub.

**Architecture:** Static file repo, no build step. Root `README.md` is an index table pointing into `spells/<name>/`. Each spell folder is self-contained: a README explaining what/why/how-to-install, plus the literal files to copy into `~/.claude/`. No code runs as part of "building" this repo — verification is syntax/format checks on the artifacts (valid bash, valid JSON, required content present), since there's no application logic to unit test.

**Tech Stack:** Bash, JSON, Markdown. `gh` CLI for repo creation/push.

## Global Constraints

- Repo is public, casual tone (per spec) — no heavy README ceremony.
- License: MIT, copyright holder "Mike", year 2026.
- GitHub owner: `MikeTheCanuck` (confirmed available, not yet created).
- Spec lives at `docs/superpowers/specs/2026-06-20-auto-memory-stop-hook-design.md` — already committed.
- Every spell must state its hard dependency (Claude Code build with native auto-memory support) explicitly — this is a spec requirement, not optional polish.

---

### Task 1: Root index + license

**Files:**
- Create: `README.md`
- Create: `LICENSE`

**Interfaces:**
- Produces: a `README.md` containing a markdown table with a row linking to `spells/auto-memory-stop-hook/README.md` — Task 2 and Task 3 rely on this link target existing by the time the repo is pushed.

- [ ] **Step 1: Write `LICENSE`**

```text
MIT License

Copyright (c) 2026 Mike

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: Verify LICENSE looks right**

Run: `head -1 LICENSE`
Expected: `MIT License`

- [ ] **Step 3: Write `README.md`**

```markdown
# cantrips

Small, reusable tricks for agentic CLI tools — mostly Claude Code, for now. Each one is a self-contained "spell": copy a few files into place, get the behavior.

Not a framework, not a plugin system. Just a place to keep the tricks that are easy to forget you set up and annoying to reconstruct from memory.

## Spells

| Spell | What it does |
|---|---|
| [auto-memory-stop-hook](spells/auto-memory-stop-hook/) | Forces Claude Code's native memory feature to actually save on every turn, instead of only when the model feels like it. |

## Install pattern

Every spell follows the same shape: copy its files into the matching path under `~/.claude/`, merge its `settings.snippet.json` into your `~/.claude/settings.json`, restart Claude Code. Each spell's own README has the exact paths.

## License

MIT
```

- [ ] **Step 4: Verify the spell link is present**

Run: `grep -c "spells/auto-memory-stop-hook/" README.md`
Expected: `1` (the table row link)

- [ ] **Step 5: Commit**

```bash
cd ~/code/cantrips
git add README.md LICENSE
git commit -m "Add root README and MIT license"
```

---

### Task 2: `auto-memory-stop-hook` spell contents

**Files:**
- Create: `spells/auto-memory-stop-hook/hooks/save-session-memory.sh`
- Create: `spells/auto-memory-stop-hook/settings.snippet.json`
- Create: `spells/auto-memory-stop-hook/claude-md-snippet.md`
- Create: `spells/auto-memory-stop-hook/README.md`

**Interfaces:**
- Consumes: nothing from Task 1 except the link target path (`spells/auto-memory-stop-hook/README.md`) already referenced in root `README.md`.
- Produces: the four files above, complete and self-contained — Task 3 just commits and pushes them, no further edits.

- [ ] **Step 1: Write the hook script**

```bash
#!/bin/bash
# Fires on Stop. On first Stop, wakes Claude to save memory. On second Stop (after save), exits cleanly.
INPUT=$(cat)
SESSION_ID=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id','unknown'))" <<< "$INPUT" 2>/dev/null || echo "unknown")
SENTINEL="/tmp/claude-memory-wakeup-${SESSION_ID}"

if [ -f "$SENTINEL" ]; then
    rm -f "$SENTINEL"
    exit 0
fi

touch "$SENTINEL"
echo '{"systemMessage": "MEMORY CHECKPOINT: This session is ending. Review the conversation and save any important context — decisions, user preferences, project goals, key facts — to the memory system using the Write tool. Memory files live in ~/.claude/projects/<project>/memory/. If nothing new is worth saving, you can skip."}'
exit 2
```

Save to `spells/auto-memory-stop-hook/hooks/save-session-memory.sh`. Note: the original includes a second paragraph in the `systemMessage` referencing a personal "context bridge" file — dropped here since that's specific to one user's setup, not the generic trick.

- [ ] **Step 2: Make it executable and check syntax**

Run:
```bash
chmod +x spells/auto-memory-stop-hook/hooks/save-session-memory.sh
bash -n spells/auto-memory-stop-hook/hooks/save-session-memory.sh
```
Expected: no output, exit code 0 (clean syntax check).

- [ ] **Step 3: Write the settings snippet**

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/save-session-memory.sh",
            "statusMessage": "Saving session memory...",
            "asyncRewake": true
          }
        ]
      }
    ]
  }
}
```

Save to `spells/auto-memory-stop-hook/settings.snippet.json`.

- [ ] **Step 4: Validate the JSON**

Run: `jq . spells/auto-memory-stop-hook/settings.snippet.json`
Expected: pretty-printed JSON echoed back, exit code 0.

- [ ] **Step 5: Write the optional CLAUDE.md snippet**

```markdown
## Memory Management

**Save memory proactively.** Don't wait for the Stop hook — save during the session when meaningful context accumulates. Lost context from a single missed save can cost real time re-establishing it later.

**Cross-project memory path sanitization.** When working across multiple projects, write memory files to *that project's* `~/.claude/projects/<sanitized-path>/memory/` directory. Sanitize by replacing `/` with `-` and dropping the leading slash (e.g. `/Users/you/code/foo` → `-Users-you-code-foo`). Claude Code memory is bucketed by working directory — saving to the wrong bucket means the other project's sessions never see it.
```

Save to `spells/auto-memory-stop-hook/claude-md-snippet.md`.

- [ ] **Step 6: Write the spell README**

```markdown
# auto-memory-stop-hook

Claude Code has a native "auto-memory" feature: it writes structured memory files to `~/.claude/projects/<bucket>/memory/`, indexed by a `MEMORY.md`. It's on by default — but it fires *heuristically*. The model decides, turn by turn, whether something was "worth" saving. In practice, useful context gets dropped silently more often than you'd like.

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
   If you already have other `Stop` hooks configured, merge by hand instead — `jq`'s `*` operator on objects doesn't merge array values, it replaces them.
3. (Optional) Append `claude-md-snippet.md` to your global `~/.claude/CLAUDE.md`. This shapes *what* gets saved (proactive saving, cross-project bucket sanitization) once the hook makes saving reliable. The hook works without it.
4. Restart Claude Code.

## Caveats

- The sentinel file lives in `/tmp` and is keyed by session ID — if `/tmp` is cleared mid-session (unusual, but possible on some setups) the hook will treat the next `Stop` as a "first" one again. Harmless: worst case is one extra wake-and-check cycle.
- This hook fires every turn. On a very chatty session that's a lot of wake cycles. If that becomes annoying, the heuristic-only native behavior is the fallback — just remove the hook.
```

Save to `spells/auto-memory-stop-hook/README.md`.

- [ ] **Step 7: Verify the hard-dependency callout is present**

Run: `grep -c "Hard dependency" spells/auto-memory-stop-hook/README.md`
Expected: `1`

- [ ] **Step 8: Commit**

```bash
cd ~/code/cantrips
git add spells/auto-memory-stop-hook/
git commit -m "Add auto-memory-stop-hook spell"
```

---

### Task 3: Push to GitHub

**Files:** none created — this task operates on the existing git history from Tasks 1-2 (plus the spec commit already in place).

**Interfaces:**
- Consumes: a local git repo at `~/code/cantrips` with at least 3 commits (spec, Task 1, Task 2).
- Produces: a public GitHub repo at `github.com/MikeTheCanuck/cantrips` with `origin` set and all commits pushed.

- [ ] **Step 1: Confirm local history is clean**

Run: `cd ~/code/cantrips && git log --oneline && git status --short`
Expected: 3 commits listed (oldest-to-newest: spec, README/LICENSE, spell contents), and `git status --short` prints nothing (clean tree).

- [ ] **Step 2: Create the GitHub repo and push**

```bash
cd ~/code/cantrips
gh repo create MikeTheCanuck/cantrips --public --source=. --remote=origin --push
```

Expected: command prints the new repo URL (`https://github.com/MikeTheCanuck/cantrips`) and pushes `main`.

- [ ] **Step 3: Verify it's live**

Run: `gh repo view MikeTheCanuck/cantrips --json url,visibility`
Expected: JSON with `"url":"https://github.com/MikeTheCanuck/cantrips"` and `"visibility":"PUBLIC"`.

---

## Out of scope (per spec)

rtk/other-agent bootstrap, dotfiles-style tricks, broader CLAUDE.md policy entries — future spells, not this plan.
