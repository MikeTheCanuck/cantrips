# cantrips

Small, reusable tricks for agentic CLI tools - mostly Claude Code, for now. Each one is a self-contained "spell": copy a few files into place, get the behavior.

Not a framework, not a plugin system. Just a place to keep the tricks that are easy to forget you set up and annoying to reconstruct from memory.

## Spells

| Spell | What it does |
|---|---|
| [session-recap](spells/session-recap/) | Shows where you left off in this project every time you start `claude`. Summarises in the background when you quit or compact, so nothing shows up mid-session. |
| [auto-memory-stop-hook](spells/auto-memory-stop-hook/) | Superseded by session-recap. Forces a memory check after every turn. |

## Install pattern

Every spell follows the same shape: copy its files into the matching path under `~/.claude/`, merge its `settings.snippet.json` into your `~/.claude/settings.json`, restart Claude Code. Each spell's own README has the exact paths.

## License

MIT
