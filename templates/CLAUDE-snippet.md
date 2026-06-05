<!-- obsidian-agent-board: paste this into your global ~/.claude/CLAUDE.md so agents use the board -->
## Live Agent Coordination Board

Active when cwd is in scope (any git repo, or a configured root); a no-op elsewhere.
Concurrent Claude Code sessions announce themselves to a live board
(`<board>/Agent-Sessions/<session_id>.md`, rendered by `Active Agents.base` in Obsidian).
Presence + heartbeat are automatic (the `agent-board-hook` SessionStart/Stop/SessionEnd hook).
You only maintain task/claims:
- **At task start:** `agent-board task "<one line of what you're doing>"`
- **Before editing a shared file:** `agent-board check <path>` — if a live session claims it, coordinate or pick different work (don't clobber).
- **When you start editing files:** `agent-board claim <path...>` (and `release` when done).
- **To see who's live:** `agent-board who`.

Pair with one git worktree per concurrent session so file edits can't physically collide.
(If `agent-board` isn't on PATH, call `~/.local/bin/agent-board`.)
<!-- /obsidian-agent-board -->
