---
description: Fork this Claude session into a new tmux pane
argument-hint: "[prefill text]"
allowed-tools:
  - Bash
effort: low
---

Fork the current Claude session into a new tmux split pane with full conversation context.

Rules:
- Run `~/.claude/scripts/forkoff.sh` via a single Bash command. Do not reimplement the logic.
- Pass `"$TMUX_PANE"` as the first argument and `"$(pwd)"` as the second.
- If the user supplied arguments to `/forkoff`, pass them as the fourth argument (prefill).
- Default split is right. If the user asks for below, pass `below` as the third argument.
- If `$TMUX_PANE` is unset, print a clear error: "forkoff requires tmux".
- After success, reply briefly with the new pane ID.

Example:
```bash
~/.claude/scripts/forkoff.sh "$TMUX_PANE" "$(pwd)" right "investigate the auth module"
```
