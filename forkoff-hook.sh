#!/usr/bin/env bash
# forkoff-hook.sh — UserPromptSubmit hook for zero-cost /forkoff
#
# When the user types "/forkoff [prefill]":
#   1. Runs forkoff.sh to spawn a forked Claude session
#   2. Returns exit 2 to BLOCK the prompt (Claude never sees it — zero turns consumed)
#
# When the user types anything else: exit 0 (passthrough)
#
# Install in .claude/settings.json or ~/.claude/settings.json:
#   "UserPromptSubmit": [{
#     "matcher": "",
#     "hooks": [{"type": "command", "command": "bash /path/to/forkoff-hook.sh"}]
#   }]
#
# Note: if typed while Claude is mid-turn, this WILL interrupt the current turn.
# For non-interruptive mid-turn forking, use the tmux keybinding (prefix+f) instead.
set -euo pipefail

# Read hook input
INPUT=$(cat)
if command -v python3 >/dev/null 2>&1; then
    PROMPT=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('prompt',''))" <<< "$INPUT" 2>/dev/null || echo "")
elif command -v jq >/dev/null 2>&1; then
    PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || echo "")
else
    exit 0  # can't parse hook input, let Claude handle it
fi

# Only intercept exact /forkoff (with optional space + args)
case "$PROMPT" in
    /forkoff) ;;         # bare /forkoff
    /forkoff\ *) ;;      # /forkoff with arguments
    *) exit 0 ;;         # not ours — passthrough
esac

# Extract prefill (everything after "/forkoff ")
PREFILL="${PROMPT#/forkoff}"
PREFILL="${PREFILL# }"

PANE_ID="${TMUX_PANE:-}"
[ -z "$PANE_ID" ] && exit 0  # no tmux = can't fork, let Claude handle it

# Find forkoff.sh relative to this script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FORKOFF="$SCRIPT_DIR/forkoff.sh"
[ -x "$FORKOFF" ] || FORKOFF="$HOME/.claude/scripts/forkoff.sh"
[ -x "$FORKOFF" ] || exit 0  # can't find script, let Claude handle it

# Run the fork
NEW_PANE=$("$FORKOFF" "$PANE_ID" "$(pwd)" right "$PREFILL" 2>/dev/null) || {
    # Fork failed — let Claude see the prompt as fallback
    exit 0
}

# Block the prompt and tell Claude what happened
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"UserPromptSubmit\",\"additionalContext\":\"Session forked to pane $NEW_PANE\"}}"
exit 2
