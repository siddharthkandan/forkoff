#!/usr/bin/env bash
# install.sh — Install forkoff for Claude Code
#
# Usage:
#   bash install.sh [--uninstall]
#
# What it installs:
#   1. ~/.claude/scripts/forkoff.sh        — Core fork script
#   2. ~/.claude/scripts/forkoff-hook.sh   — UserPromptSubmit hook
#   3. ~/.claude/skills/forkoff/SKILL.md   — /forkoff fallback command
#   4. tmux keybinding: prefix+f (right), prefix+F (below)
#   5. Hook registration in ~/.claude/settings.json
#
# Zero dependencies beyond: tmux, claude, python3|jq, bash
set -euo pipefail

SCRIPTS_DIR="$HOME/.claude/scripts"
SKILLS_DIR="$HOME/.claude/skills"
SETTINGS="$HOME/.claude/settings.json"
TMUX_CONF="$HOME/.tmux.conf"
MARKER="# forkoff"

# --- Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[forkoff]${NC} $1"; }
warn() { echo -e "${YELLOW}[forkoff]${NC} $1"; }
fail() { echo -e "${RED}[forkoff]${NC} $1" >&2; exit 1; }

# --- Uninstall ---
if [ "${1:-}" = "--uninstall" ]; then
    info "Uninstalling forkoff..."
    rm -f "$SCRIPTS_DIR/forkoff.sh" "$SCRIPTS_DIR/forkoff-hook.sh"
    rm -rf "$SKILLS_DIR/forkoff"
    if [ -f "$TMUX_CONF" ]; then
        # Remove forkoff lines from tmux.conf (atomic via temp file)
        grep -v "$MARKER" "$TMUX_CONF" > "$TMUX_CONF.tmp" 2>/dev/null || true
        mv "$TMUX_CONF.tmp" "$TMUX_CONF"
        tmux unbind-key f 2>/dev/null || true
        tmux unbind-key F 2>/dev/null || true
    fi
    # Remove hook from settings.json (atomic via temp file)
    if [ -f "$SETTINGS" ] && command -v python3 >/dev/null 2>&1; then
        python3 -c "
import json, sys, os, tempfile

settings_path = sys.argv[1]
hook_cmd_fragment = 'forkoff-hook.sh'
try:
    with open(settings_path) as f: s = json.load(f)
    hooks = s.get('hooks', {})
    ups = hooks.get('UserPromptSubmit', [])
    ups = [h for h in ups
           if not any(hook_cmd_fragment in hh.get('command', '')
                      for hh in h.get('hooks', []))]
    if ups: hooks['UserPromptSubmit'] = ups
    else: hooks.pop('UserPromptSubmit', None)
    if not hooks: s.pop('hooks', None)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(settings_path))
    with os.fdopen(fd, 'w') as f:
        json.dump(s, f, indent=2)
        f.write('\n')
    os.replace(tmp, settings_path)
except Exception: pass
" "$SETTINGS" 2>/dev/null
    fi
    info "Uninstalled. Restart Claude Code sessions to take effect."
    exit 0
fi

# --- Preflight ---
command -v tmux >/dev/null 2>&1 || fail "tmux not found"
command -v claude >/dev/null 2>&1 || warn "claude not in PATH (needed at runtime)"
command -v python3 >/dev/null 2>&1 || command -v jq >/dev/null 2>&1 || fail "need python3 or jq"

# --- Determine source directory ---
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$SOURCE_DIR/forkoff.sh" ] || fail "Can't find forkoff.sh in $SOURCE_DIR. Run from the forkoff/ directory."

# --- Install scripts ---
mkdir -p "$SCRIPTS_DIR" "$SKILLS_DIR"

cp "$SOURCE_DIR/forkoff.sh" "$SCRIPTS_DIR/forkoff.sh"
cp "$SOURCE_DIR/forkoff-hook.sh" "$SCRIPTS_DIR/forkoff-hook.sh"
chmod +x "$SCRIPTS_DIR/forkoff.sh" "$SCRIPTS_DIR/forkoff-hook.sh"
info "Installed scripts to $SCRIPTS_DIR/"

# --- Install fallback skill ---
mkdir -p "$SKILLS_DIR/forkoff"
cp "$SOURCE_DIR/skills-forkoff/SKILL.md" "$SKILLS_DIR/forkoff/SKILL.md"
info "Installed /forkoff fallback skill to $SKILLS_DIR/forkoff/"

# --- Register tmux keybindings ---
FORKOFF_SH="$SCRIPTS_DIR/forkoff.sh"

# Persist in tmux.conf first (idempotent)
touch "$TMUX_CONF"
if ! grep -q "$MARKER" "$TMUX_CONF" 2>/dev/null; then
    cat >> "$TMUX_CONF" <<TMUX

$MARKER — mid-turn session fork
bind-key f run-shell -b 'bash $FORKOFF_SH "#{pane_id}" "#{pane_current_path}" right'   $MARKER
bind-key F run-shell -b 'bash $FORKOFF_SH "#{pane_id}" "#{pane_current_path}" below'  $MARKER
TMUX
    info "Added keybindings to $TMUX_CONF (prefix+f = right, prefix+F = below)"
else
    info "Keybindings already in $TMUX_CONF (skipped)"
fi

# Apply immediately by sourcing tmux.conf
tmux source-file "$TMUX_CONF" 2>/dev/null || true

# --- Register UserPromptSubmit hook in global settings ---
if command -v python3 >/dev/null 2>&1; then
    # Create settings file if it doesn't exist
    [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
    python3 -c "
import json, sys, os, tempfile

settings_path = sys.argv[1]
hook_cmd = sys.argv[2]

with open(settings_path) as f:
    s = json.load(f)

hooks = s.setdefault('hooks', {})
ups = hooks.setdefault('UserPromptSubmit', [])

# Check if already registered (match on exact script name)
already = any('forkoff-hook.sh' in hh.get('command', '')
              for h in ups for hh in h.get('hooks', []))
if already:
    print('[forkoff] Hook already registered (skipped)')
    sys.exit(0)

ups.append({
    'matcher': '',
    'hooks': [{'type': 'command', 'command': hook_cmd}]
})

# Atomic write via temp file + rename
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(settings_path))
with os.fdopen(fd, 'w') as f:
    json.dump(s, f, indent=2)
    f.write('\n')
os.replace(tmp, settings_path)

print('[forkoff] Registered UserPromptSubmit hook in ' + settings_path)
" "$SETTINGS" "bash $SCRIPTS_DIR/forkoff-hook.sh" 2>/dev/null || warn "Could not register hook in $SETTINGS (add manually)"
else
    warn "python3 not found — register UserPromptSubmit hook manually"
fi

# --- Done ---
echo ""
info "Installation complete!"
echo ""
echo "  Two ways to fork:"
echo ""
echo "    prefix+f           Mid-turn fork (right split, non-interruptive)"
echo "    prefix+F           Mid-turn fork (below split, non-interruptive)"
echo "    /forkoff [text]    Fork from prompt (hook intercepts, zero Claude turns)"
echo ""
echo "  A /forkoff fallback command is also installed in case the hook is"
echo "  unavailable. The hook takes priority when both are present."
echo ""
echo "  Restart Claude Code sessions to load the hook."
echo "  Uninstall: bash $SOURCE_DIR/install.sh --uninstall"
echo ""
