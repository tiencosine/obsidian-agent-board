# obsidian-agent-board

**A live coordination board for concurrent [Claude Code](https://claude.com/claude-code) sessions — so your agents stop stepping on each other.**

When you run several Claude Code sessions at once on the same project, they have no idea the others exist. Two of them edit the same file; two of them do the same task; you find out at merge time. `obsidian-agent-board` gives every running session a shared, live view of **who's working where, on what, and which files they've claimed** — rendered as a dashboard in [Obsidian](https://obsidian.md) (optional) and queryable from any terminal.

It's just markdown files + a couple of hooks. No server, no daemon, no SaaS, no API keys.

```
        ~/.config/obsidian-agent-board/  +  <your vault>/Agent-Sessions/*.md
                                   │
        ┌──────────────┬──────────┴───────────┬───────────────────┐
   session A        session B              session C            session D
  (repo: app        (worktree:             (repo: api           (idle)
   /main)            feature-x)             /main)
        │                │                      │
        └── each writes its own note; reads everyone else's before editing ──┘
                                   │
                      Obsidian "Active Agents.base"  ◀── you watch this (desktop / phone)
```

---

## Why it works this way

- **One note per session** (`Agent-Sessions/<session_id>.md`) — sessions never write the same file, so there are no races on the board itself. A database-style view aggregates them.
- **Plain markdown + YAML frontmatter** — Obsidian live-reloads files from disk, so the board updates the instant a session writes. Works without Obsidian too (`agent-board who`).
- **Presence is automatic; detail is opt-in.** Hooks handle registration/heartbeat/cleanup with zero cooperation. Agents add task descriptions and file claims via a tiny CLI.

### Two reliability tiers (be honest about this)

| Layer | How | Reliability |
|---|---|---|
| **Presence** — who's live, in which repo/worktree, how fresh | Hooks (`SessionStart`/`Stop`/`SessionEnd`) | **Guaranteed** — not instruction-following |
| **Task + file claims + conflict warnings** | Agents run `agent-board task/claim/check`, prompted by your `CLAUDE.md` | **Best-effort** — agents follow the protocol |
| **Edit guardrail** | A `PreToolUse` hook auto-warns an agent when it's about to edit a file another live session claims | **Automatic**, non-blocking |

The guardrail closes the gap: even if an agent forgets to run `check`, it gets a warning the moment it tries to edit a claimed file.

---

## Requirements

- **Claude Code** (the `~/.claude` config dir).
- **Python 3** (standard library only — no pip installs).
- **git** (used to detect repos / worktrees).
- **Optional:** [Obsidian](https://obsidian.md) 1.9+ with the built-in **Bases** core plugin enabled, for the live dashboard. Without it, everything still works via the CLI.

---

## Install

```bash
git clone https://github.com/tiencosine/obsidian-agent-board.git
cd obsidian-agent-board
./install.sh
```

The installer:
1. copies `agent-board-hook` → `~/.claude/hooks/` and `agent-board` → `~/.local/bin/`;
2. picks a **board directory** — it auto-detects an Obsidian vault and proposes `<vault>/Agent-Sessions`, or falls back to `~/agent-board/sessions` (override with `--board-dir`);
3. writes `~/.config/obsidian-agent-board/config.json`;
4. drops the `Active Agents.base` dashboard at your vault root (if a vault was found);
5. **merges** the hook wiring into `~/.claude/settings.json` — idempotently, with a `.bak` backup, preserving everything else.

Then add the agent protocol to your global instructions so agents actually use it:

```bash
cat templates/CLAUDE-snippet.md >> ~/.claude/CLAUDE.md
# or let the installer do it:  ./install.sh --append-claude-md
```

Finally, **start a new Claude Code session** in a git repo — it'll register on the board.

### Install options

```bash
./install.sh \
  --board-dir "$HOME/Documents/MyVault/Agent-Sessions" \
  --roots "code/myapp:code/myapi" \
  --append-claude-md -y
```

- `--board-dir` — where session notes live (point it inside your Obsidian vault for the dashboard).
- `--roots` — colon-separated path substrings that activate the board. **Omit to activate in any git repo.**
- `-y` — non-interactive (accept detected defaults).

---

## Configuration

`~/.config/obsidian-agent-board/config.json`:

```json
{
  "board_dir": "/Users/you/Documents/MyVault/Agent-Sessions",
  "roots": []
}
```

- **`board_dir`** — folder holding the per-session notes. Put it inside an Obsidian vault to get the live dashboard.
- **`roots`** — list of path substrings; a session only joins the board when its working directory matches one. Empty `[]` means **any git repository** (the board ignores `~`, `/tmp`, and other non-repo dirs).

Environment overrides (handy per-shell): `AGENT_BOARD_DIR`, `AGENT_BOARD_ROOTS` (colon-separated).

---

## Usage

### What agents do

Driven by the protocol you added to `CLAUDE.md`:

```bash
agent-board task "refactoring the auth module"     # show up with context
agent-board check src/auth/session.ts              # before editing — warns if claimed
agent-board claim src/auth/session.ts              # stake it (release when done)
agent-board release src/auth/session.ts
agent-board who                                     # text view of everyone live
```

Registration, heartbeat (every turn), and cleanup on exit happen **automatically** — agents never run those.

### What you do

Basically nothing. Open **`Active Agents.base`** in Obsidian (desktop or phone via Obsidian Sync) and watch. Want a terminal view instead?

```bash
agent-board who
# [myapp/main] a1b2c3d4: refactoring the auth module        | claims: session.ts
# [myapp/feature-x] e5f6a7b8: writing tests for the parser  | claims: parser_test.ts
```

---

## The Obsidian dashboard

If `board_dir` is inside a vault, the installer writes `Active Agents.base` at the vault root. Open it in Obsidian (Bases core plugin must be enabled: **Settings → Core plugins → Bases**). You get a live table of every active session: session, repo, worktree, what they're working on, files claimed, and idle minutes.

> If the **Idle (min)** column errors on an older Bases build (missing `round`), delete the `formulas:` block and the two `idleMin` lines from the `.base` file — the **Updated** column still shows freshness.

---

## How it works (internals)

- **`agent-board-hook`** (one script, four events):
  - `SessionStart` → create/refresh `<board>/<session_id>.md`, write a `cwd → session_id` pointer, and print usage (Claude injects `SessionStart` stdout into the session's context).
  - `Stop` → bump `updated` each turn (liveness heartbeat).
  - `SessionEnd` → mark `status: done` and remove the pointer. Old `done` notes are pruned after 2 days.
  - `PreToolUse` (Edit/Write/MultiEdit) → if another live session claims the target file, emit a non-blocking warning. **Any error exits 0 — it can never block a tool call.**
- **`agent-board`** CLI → resolves "my note" from the `cwd → session_id` pointer, then edits its frontmatter (`task`, `claims`) or reads the board (`check`, `who`).
- **Scope guard** → a session only joins the board if its cwd matches a configured root, or (when no roots are set) is inside a git repo.

A session note:

```yaml
---
status: active
session: a1b2c3d4
session_id: a1b2c3d4-....
repo: myapp
worktree: feature-x
branch: feature-x
task: "refactoring the auth module"
claims: ["src/auth/session.ts"]
started: 2026-06-04T14:05:00
updated: 2026-06-04T14:33:00
---
```

### Known limitation

Two sessions in the **same** working directory (no worktree) share one `cwd → session_id` pointer, so the later one wins and the earlier one's `agent-board` writes target the wrong note. **Run one git worktree per concurrent session** and this can't happen. Presence/heartbeat are unaffected (keyed by `session_id`).

---

## Commands

| Command | What it does |
|---|---|
| `agent-board task "<text>"` | Set what you're working on |
| `agent-board claim <path...>` | Stake files you'll edit (warns on conflict) |
| `agent-board release <path...>` | Drop claims |
| `agent-board check <path>` | Who else (live) claims this path? |
| `agent-board note "<text>"` | Append a timestamped log line to your note |
| `agent-board who` | Text view of all active sessions |
| `agent-board where` | Print your note path + the board dir |

---

## Uninstall

```bash
./uninstall.sh
```

Removes the scripts and the hook wiring (backs up `settings.json`). Leaves your config and board notes in place — delete `~/.config/obsidian-agent-board`, the `Agent-Sessions` folder, `Active Agents.base`, and the `CLAUDE.md` section by hand to fully remove.

---

## Design notes / non-goals

- **No real-time push between agents.** This is a shared *blackboard*, not a chat bus — it's about awareness and claims, which is what prevents collisions. (If you want ad-hoc agent-to-agent messaging, see projects like `claude-peers-mcp`.)
- **No central server.** Everything is local files + git + Python stdlib.
- **Obsidian is a viewer, not a dependency.** The board is the markdown; Obsidian just renders it beautifully and syncs it to your phone.

## License

[MIT](./LICENSE)
