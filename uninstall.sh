#!/usr/bin/env bash
# obsidian-agent-board uninstaller. Removes the scripts and the hook wiring.
# Leaves your config + board notes in place (delete them manually if you want).
set -euo pipefail

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
CFG_DIR="$HOME/.config/obsidian-agent-board"
HOOK_CMD_LITERAL="~/.claude/hooks/agent-board-hook"

rm -f "$CLAUDE_DIR/hooks/agent-board-hook" "$BIN_DIR/agent-board"
echo "removed scripts"

if [ -f "$CLAUDE_DIR/settings.json" ]; then
  python3 - "$CLAUDE_DIR/settings.json" "$HOOK_CMD_LITERAL" <<'PY'
import json, sys, shutil
path, cmd = sys.argv[1], sys.argv[2]
try:
    with open(path) as f: data = json.load(f)
except Exception:
    sys.exit(0)
shutil.copyfile(path, path + ".bak")
hooks = data.get("hooks", {})
for ev in list(hooks):
    hooks[ev] = [g for g in hooks[ev]
                 if not any(h.get("command") == cmd for h in g.get("hooks", []))]
    if not hooks[ev]:
        del hooks[ev]
with open(path, "w") as f:
    json.dump(data, f, indent=2)
print("removed hook wiring from settings.json (backup: settings.json.bak)")
PY
fi

echo
echo "Left intact:"
echo "  - $CFG_DIR  (config + pointers)"
echo "  - your board notes + 'Active Agents.base' in your vault"
echo "  - any 'Live Agent Coordination Board' section you added to $CLAUDE_DIR/CLAUDE.md"
echo "Remove those by hand to fully uninstall."
