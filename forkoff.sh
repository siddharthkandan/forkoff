#!/usr/bin/env bash
# forkoff — Fork a Claude Code session into a new tmux pane
#
# The forked session gets the full conversation context, independent context
# window, full tool access, and unlimited turns. The original session is not
# interrupted.
#
# Usage:
#   forkoff.sh <pane_id> <cwd> [right|below] [prefill]
#
# As tmux keybinding (registered by install.sh):
#   prefix+f  → fork right
#   prefix+F  → fork below
#
# As UserPromptSubmit hook:
#   User types "/forkoff [text]" → hook forks + blocks prompt (zero Claude turns)
#
# Requires: tmux, claude (Claude Code CLI), python3 or jq
set -euo pipefail

PANE_ID="${1:-${TMUX_PANE:-}}"
CWD="${2:-$(pwd)}"
SPLIT="${3:-right}"
PREFILL="${4:-}"

die() { tmux display-message "forkoff: $1" 2>/dev/null; echo "forkoff: $1" >&2; exit 1; }

# --- Validate environment ---
command -v tmux >/dev/null 2>&1 || die "tmux not found"
command -v claude >/dev/null 2>&1 || die "claude not found"
[ -n "$PANE_ID" ] || die "no pane ID (run inside tmux)"
echo "$PANE_ID" | grep -qE '^%[0-9]+$' || die "invalid pane ID: $PANE_ID"

# --- Find project root (walk up looking for .claude/) ---
PROJECT="$CWD"
while [ "$PROJECT" != "/" ]; do
    [ -d "$PROJECT/.claude" ] && break
    PROJECT="$(dirname "$PROJECT")"
done
[ "$PROJECT" = "/" ] && PROJECT="$CWD"

# --- Read session_id from context-state file ---
STATE_FILE="$PROJECT/.claude/context-state-${PANE_ID}.json"
[ -f "$STATE_FILE" ] || die "no Claude session in $PANE_ID (expected $STATE_FILE)"

# Try python3, fall back to jq
if command -v python3 >/dev/null 2>&1; then
    SID=$(python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    s = d.get('session_id', '')
    if s: print(s)
    else: sys.exit(1)
except: sys.exit(1)
" "$STATE_FILE" 2>/dev/null) || die "can't read session_id from $STATE_FILE"
elif command -v jq >/dev/null 2>&1; then
    SID=$(jq -r '.session_id // empty' "$STATE_FILE" 2>/dev/null) || die "can't read session_id"
    [ -n "$SID" ] || die "empty session_id in $STATE_FILE"
else
    die "need python3 or jq to parse session state"
fi

# Validate session_id looks like a UUID
echo "$SID" | grep -qE '^[0-9a-f-]{36}$' || die "session_id doesn't look like a UUID: $SID"

# --- Build claude command ---
CMD="claude --resume $SID --fork-session"
[ -n "$PREFILL" ] && CMD="$CMD --prefill $(printf '%q' "$PREFILL")"

# --- Fork via tmux ---
SPLIT_FLAG="-h"
[ "$SPLIT" = "below" ] && SPLIT_FLAG=""

NEW_PANE=$(tmux split-window -d -P -F '#{pane_id}' \
    -t "$PANE_ID" $SPLIT_FLAG -c "$PROJECT" \
    "exec $CMD" 2>/dev/null) || die "tmux split-window failed"

# --- Tag the child pane ---
tmux set-option -p -t "$NEW_PANE" @forkoff_parent "$PANE_ID" 2>/dev/null || true
tmux set-option -p -t "$NEW_PANE" @forkoff_session "$SID" 2>/dev/null || true
tmux set-option -p -t "$NEW_PANE" @forkoff_time "$(date +%s)" 2>/dev/null || true

# --- Feedback ---
tmux display-message "Forked → $NEW_PANE" 2>/dev/null || true
echo "$NEW_PANE"
