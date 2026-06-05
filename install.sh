#!/usr/bin/env bash
# obsidian-agent-board installer
#
# Usage:
#   ./install.sh [--board-dir <path>] [--roots a:b:c] [--append-claude-md] [-y]
#
#   --board-dir   Where session notes live. Default: auto-detect an Obsidian
#                 vault and use <vault>/Agent-Sessions, else ~/agent-board/sessions.
#   --roots       Colon-separated path substrings that activate the board.
#                 Default: empty => active in ANY git repo.
#   --append-claude-md  Append the agent protocol to ~/.claude/CLAUDE.md
#                       (idempotent). Otherwise the snippet path is printed.
#   -y, --yes     Non-interactive; accept detected defaults.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
CFG_DIR="$HOME/.config/obsidian-agent-board"
HOOK_CMD_LITERAL="~/.claude/hooks/agent-board-hook"

BOARD_DIR=""; ROOTS=""; APPEND_CLAUDE=0; ASSUME_YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --board-dir) BOARD_DIR="$2"; shift 2;;
    --roots) ROOTS="$2"; shift 2;;
    --append-claude-md) APPEND_CLAUDE=1; shift;;
    -y|--yes) ASSUME_YES=1; shift;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }
[ -d "$CLAUDE_DIR" ] || { echo "Claude Code dir not found: $CLAUDE_DIR" >&2; exit 1; }

echo "==> Installing scripts"
mkdir -p "$CLAUDE_DIR/hooks" "$BIN_DIR" "$CFG_DIR/pointers"
install -m 0755 "$HERE/hooks/agent-board-hook" "$CLAUDE_DIR/hooks/agent-board-hook"
install -m 0755 "$HERE/bin/agent-board" "$BIN_DIR/agent-board"

# --- resolve board dir ---------------------------------------------------
if [ -z "$BOARD_DIR" ]; then
  CAND="$(find "$HOME/Documents" "$HOME" -maxdepth 4 -type d -name .obsidian 2>/dev/null | head -1 || true)"
  if [ -n "$CAND" ]; then
    BOARD_DIR="$(dirname "$CAND")/Agent-Sessions"
    if [ "$ASSUME_YES" -eq 0 ]; then
      read -r -p "Board dir [$BOARD_DIR] (Enter to accept): " ANS || true
      [ -n "${ANS:-}" ] && BOARD_DIR="$ANS"
    fi
  else
    BOARD_DIR="$HOME/agent-board/sessions"
    if [ "$ASSUME_YES" -eq 0 ]; then
      read -r -p "No Obsidian vault found. Board dir [$BOARD_DIR]: " ANS || true
      [ -n "${ANS:-}" ] && BOARD_DIR="$ANS"
    fi
  fi
fi
mkdir -p "$BOARD_DIR"
cp "$HERE/templates/sessions-README.md" "$BOARD_DIR/_README.md"
echo "  board dir: $BOARD_DIR"

# --- write config --------------------------------------------------------
python3 - "$CFG_DIR/config.json" "$BOARD_DIR" "$ROOTS" <<'PY'
import json, sys
path, board, roots = sys.argv[1], sys.argv[2], sys.argv[3]
data = {"board_dir": board, "roots": [r for r in roots.split(":") if r]}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
print("  config:", path, "(roots:", data["roots"] or "any git repo", ")")
PY

# --- drop the Bases dashboard if board dir is inside an Obsidian vault ----
VAULT_ROOT=""; D="$BOARD_DIR"
while [ "$D" != "/" ] && [ "$D" != "$HOME" ]; do
  [ -d "$D/.obsidian" ] && { VAULT_ROOT="$D"; break; }
  D="$(dirname "$D")"
done
if [ -n "$VAULT_ROOT" ]; then
  REL="${BOARD_DIR#"$VAULT_ROOT"/}"
  sed "s#__BOARD_FOLDER__#$REL#g" "$HERE/templates/Active Agents.base" > "$VAULT_ROOT/Active Agents.base"
  echo "  dashboard: $VAULT_ROOT/Active Agents.base  (open in Obsidian)"
else
  echo "  (no Obsidian vault around board dir — 'agent-board who' still works;"
  echo "   install Obsidian + the Bases core plugin for the live dashboard)"
fi

# --- merge hooks into settings.json (idempotent, backed up) --------------
python3 - "$CLAUDE_DIR/settings.json" "$HOOK_CMD_LITERAL" <<'PY'
import json, sys, os, shutil
path, cmd = sys.argv[1], sys.argv[2]
try:
    with open(path) as f: data = json.load(f)
except Exception:
    data = {}
if os.path.exists(path):
    shutil.copyfile(path, path + ".bak")
hooks = data.setdefault("hooks", {})
def ensure(event, matcher):
    groups = hooks.setdefault(event, [])
    for g in groups:
        if g.get("matcher", "") == (matcher or "") and \
           any(h.get("command") == cmd for h in g.get("hooks", [])):
            return False
    g = {"hooks": [{"type": "command", "command": cmd}]}
    if matcher:
        g["matcher"] = matcher
    groups.append(g)
    return True
added = []
for ev, mt in [("SessionStart", "startup"), ("SessionStart", "resume"),
               ("Stop", ""), ("SessionEnd", ""), ("PreToolUse", "Edit|Write|MultiEdit")]:
    if ensure(ev, mt):
        added.append(f"{ev}:{mt or '*'}")
with open(path, "w") as f:
    json.dump(data, f, indent=2)
print("  settings.json:", ", ".join(added) if added else "already wired")
PY

# --- protocol snippet for CLAUDE.md --------------------------------------
CM="$CLAUDE_DIR/CLAUDE.md"
if [ "$APPEND_CLAUDE" -eq 1 ]; then
  if [ -f "$CM" ] && grep -q "Live Agent Coordination Board" "$CM" 2>/dev/null; then
    echo "  CLAUDE.md: protocol already present"
  else
    printf '\n' >> "$CM"; cat "$HERE/templates/CLAUDE-snippet.md" >> "$CM"
    echo "  CLAUDE.md: protocol appended"
  fi
else
  echo "  NEXT: add the agent protocol to your global instructions so agents use the board:"
  echo "        cat '$HERE/templates/CLAUDE-snippet.md' >> $CM"
fi

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "  WARNING: $BIN_DIR is not on PATH — add it, or call $BIN_DIR/agent-board";;
esac

echo "==> Done. Start a NEW Claude Code session in a git repo to see it register on the board."
