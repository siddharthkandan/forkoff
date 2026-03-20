# forkoff

Fork a Claude Code session into a new tmux pane. Mid-turn. Full tools. Persistent.

**You must be running Claude Code inside tmux.** This won't work in VS Code terminal, iTerm2 without tmux, Windows without WSL+tmux, or any non-tmux environment. tmux is the whole trick.

```
prefix+f  →  instant fork (even while Claude is mid-turn)
/forkoff  →  fork from prompt
```

It's `/btw` but instead of a disposable one-shot answer, you get a whole new Claude with your full conversation context, its own context window, and all tools available. Named after what you mutter when you need two of yourself.

## Install

```bash
git clone https://github.com/user/forkoff.git
cd forkoff && bash install.sh
```

Needs tmux (obviously), `claude` in PATH, and python3 or jq.

`bash install.sh --uninstall` to clean up.

## Usage

**`prefix+f`** — fork right. Works while Claude is busy. Doesn't interrupt anything. This is the one you want most of the time.

**`prefix+F`** — same but splits below.

**`/forkoff [text]`** — type at the prompt. A UserPromptSubmit hook catches it, forks, and blocks the prompt so Claude never sees it (zero API turns). If you type this mid-turn it'll interrupt the current work though — use the keybinding instead if you don't want that.

**`forkoff.sh`** — direct invocation for scripts: `~/.claude/scripts/forkoff.sh "$TMUX_PANE" "$(pwd)" right "go investigate auth"`

Under the hood it reads `session_id` from `.claude/context-state-$TMUX_PANE.json` and runs `claude --resume <id> --fork-session` in a new split pane. The `-d` flag keeps focus on your current pane.

## Limitations

- **Requires tmux.** No tmux, no forkoff. VS Code terminal, Windows without WSL — won't work.
- **Mid-turn via keybinding only.** The keybinding runs outside Claude entirely (tmux does the work). The `/forkoff` prompt path can't avoid interrupting a busy turn — that needs a privileged `immediate` + `local-jsx` command type that only built-ins get.
- **Forks from current state.** `/btw` trimmed the unfinished assistant tail before forking. `--fork-session` takes the session as-is. Usually fine.

## How `/btw` actually worked

We traced this from the v2.1.80 binary (`cli.js`, 12MB minified). The interesting part isn't that `/btw` existed — it's *how* it ran mid-turn without interrupting anything.

`/btw` was registered as `type: "local-jsx"` with `immediate: true`. That's a privileged command type. When you typed during a busy turn, the input handler hit an early-exit branch (offset 11561216) that checked for immediate local-jsx commands *before* the normal interrupt+queue path:

```javascript
let e = _.find((q6) => q6.immediate && q6.isEnabled() && ...);
if (e && e.type === "local-jsx" && (K.isActive || Y)) {
    o = await (await e.load()).call(H6, q6, t);
    return   // exits before the interrupt path ever runs
}
```

The actual side question ran through `kh8() → xf()` (the fork kernel at offset 9258609) with `querySource: "side_question"`, `maxTurns: 1`, `skipCacheWrite: true`, `canUseTool: deny`. In-process, same Node.js runtime, result displayed inline then thrown away.

That fork profile still lives in the RC control protocol's `side_question` handler — same identity, same kernel, just routed through the WebSocket bridge now instead of a local slash command.

The full call chain: `BiY` (registration, offset 9643268) → `miY` (handler, 9642907) → `IiY` (React component) → `uiY` (context assembly, trims unfinished tail via `xiY`) → `kh8` (side-question fork, 9638640) → `xf` (fork kernel, 9258609).

### Different tools for different jobs

`/btw` was purpose-built for quick side questions — fast, lightweight, zero disruption. It did exactly what it was designed to do. `/forkoff` solves a different problem: when you need a full independent session, not just a quick answer.

| | `/btw` | `/forkoff` |
|---|---|---|
| **Purpose** | quick side question | full independent session |
| Tools | denied (by design — keeps it fast) | full access |
| Turns | 1 | unlimited |
| Persistence | ephemeral (by design — no clutter) | full session |
| Context window | shared with parent | independent |
| Mid-turn | yes (privileged built-in) | yes (tmux keybinding) |

They're complementary. `/btw` is a post-it note, `/forkoff` is a second desk.

## Wishlist

Things that would make this better if they existed in Claude Code:

1. **Plugin-level `immediate` commands** — if plugins could register `immediate: true` commands, the `/forkoff` hook could trigger mid-turn without interrupting, using the same privileged path `/btw` used. Currently only built-ins get that.

2. **Fork context in prompt commands** — public prompt commands with `context: "fork"` use `HEY() → kk()` which seeds the child with fresh messages, not the parent transcript. If `HEY()` passed through `forkContextMessages` like `uiY()` does, we wouldn't need `--resume --fork-session` at all.

3. **`--trim-pending` flag on `--fork-session`** — `/btw` trimmed the unfinished assistant tail before forking via `xiY()`. Would be nice to have that for external forks too.

4. **`/btw` with tool access** — a `--tools` flag or configurable profile would cover the gap between "quick disposable question" and "full independent session."

## License

MIT
