## Memory Management

**Save memory proactively.** Don't wait for the Stop hook — save during the session when meaningful context accumulates. Lost context from a single missed save can cost real time re-establishing it later.

**Cross-project memory path sanitization.** When working across multiple projects, write memory files to *that project's* `~/.claude/projects/<sanitized-path>/memory/` directory. Sanitize by replacing `/` with `-` and dropping the leading slash (e.g. `/Users/you/code/foo` → `-Users-you-code-foo`). Claude Code memory is bucketed by working directory — saving to the wrong bucket means the other project's sessions never see it.
