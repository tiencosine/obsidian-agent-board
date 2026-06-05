# Agent Sessions (live coordination board)

Each running Claude Code session writes one note here named `<session_id>.md`,
maintained automatically by `~/.claude/hooks/agent-board-hook`. The
`Active Agents.base` view (in your vault root) renders all `status: active` notes.

- Files starting with `_` (this README, samples) are ignored by the Base.
- `status: done` notes drop off the board automatically and are pruned after 2 days.
- Don't edit these by hand while sessions are live — use the `agent-board` CLI.

Part of **obsidian-agent-board**: https://github.com/<you>/obsidian-agent-board
