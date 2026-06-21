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
