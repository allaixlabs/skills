# cmux CLI Notes

These notes are based on `cmux --help` and the help output for `list-panels`, `capture-pane`, `send`, `send-key`, `surface resume`, and `pipe-pane`.

## Top-Level Behavior

`cmux` controls cmux through a Unix socket. The CLI accepts UUIDs and short refs such as `workspace:2` and `surface:17`. Output defaults to refs; the `--id-format` flag accepts `refs` (default), `uuids`, or `both`. Use `--id-format uuids` (or `both`) only when exact IDs are needed.

Relevant environment variables:

- `CMUX_WORKSPACE_ID`: auto-set in cmux terminals and used as the default workspace for commands.
- `CMUX_SURFACE_ID`: auto-set in cmux terminals and used as the default surface.
- `CMUX_TAB_ID`: used by tab-related actions.
- `CMUX_SOCKET_PATH`: overrides the Unix socket path.
- `CMUX_SOCKET_PASSWORD`: socket password source when needed.

If no socket path is provided, cmux defaults to `~/.local/state/cmux/cmux.sock` and can auto-discover tagged/debug sockets.

## Agent Integration (hooks)

Text capture/send work without setup, but Feed, notifications, and session restore need
the agent integrated:

```bash
cmux hooks setup                 # install hooks for all supported agents on PATH
cmux hooks <agent> install       # install one (codex, gemini, opencode, cursor, amp, grok, ...)
cmux hooks <agent> uninstall     # remove one
```

- **Claude Code** needs no manual install — the cmux Claude wrapper injects hooks
  automatically when Claude runs inside a cmux-managed pane.
- Supported agents (per `cmux hooks setup` help): `codex, grok, opencode, pi, omp, amp, cursor,
  gemini, kiro, antigravity (agy), rovodev (rovo), hermes-agent, copilot, codebuddy, factory,
  qoder`. `opencode` accepts `--project`.
- Full matrix: `cmux docs agents` → `docs/agent-hooks.md`.

## Panel Discovery

```bash
cmux list-panels [--workspace <id|ref|index>] [--window <id|ref|index>]
```

Use this first to identify terminal surfaces in the current workspace. Output includes refs like `surface:51`, surface type, focused marker, and title.

Examples:

```bash
cmux list-panels
cmux list-panels --workspace workspace:2
```

## Pane Capture

```bash
cmux capture-pane [--workspace <id|ref|index>] [--surface <id|ref|index>] [--window <id|ref|index>] [--scrollback] [--lines <n>]
```

In this skill, prefer `cmux capture-pane` consistently because all examples and checklists use it.
`read-screen` is the regular top-level equivalent, but do not mix the two in one handoff unless `capture-pane` is unavailable. `--surface`
defaults to `CMUX_SURFACE_ID`; pass it explicitly when reading another panel.

The default `--lines` value is a sample, not the full history. Gauge the available pane text line count with
`cmux pipe-pane --surface <ref> --command 'wc -l'` and report the captured range as available scrollback —
scrollback may be truncated, so never present a partial capture as the complete history.

Examples:

```bash
cmux capture-pane --surface surface:17 --scrollback --lines 120
cmux capture-pane --workspace workspace:2 --surface surface:1 --scrollback --lines 200
```

## Sending Input

```bash
cmux send [flags] [--] <text>
```

Useful flags:

- `--workspace <id|ref|index>`: target workspace, defaulting to `CMUX_WORKSPACE_ID`.
- `--surface <id|ref|index>`: target terminal surface.
- `--window <id|ref|index>`: window context for workspace/surface refs and indexes.

Escape sequences:

- `\n` and `\r` send Enter.
- `\t` sends Tab.

Examples:

```bash
cmux send --surface surface:2 -- "ls -la\n"
cmux send --surface surface:17 -- "Please summarize the current blocker without changing files.\n"
```

Pre-send checklist (agreed with the integrated-agent side):

1. List candidate targets with `cmux list-panels` (add `--workspace` when needed) and compare ref, title, and focused marker.
   Do **not** rely on `send --dry-run`: it is absent from `cmux send --help` (undocumented).
2. Cross-check actual visible content with `cmux capture-pane --surface <ref> --scrollback --lines N`; visible task context must match.
3. Two or more plausible target panes → stop and ask the user.
4. Capture twice 1–2 seconds apart; output still advancing = busy → do not send.
5. Do not include `\n`/`\r` unless submission/execution is intended.
6. Report the text and target surface before sending; send only the approved scope.
7. Avoid sending secrets or destructive shell commands; prefer prompts over commands when controlling another agent.

## Sending Key Events

```bash
cmux send-key [--workspace <id|ref|index>] [--surface <id|ref|index>] [--window <id|ref|index>] [--] <key>
```

`send` types text; `send-key` sends a single key *event*. Use it to drive a pane that
is waiting on a keypress rather than on typed text — for example to interrupt a runaway
process or dismiss a prompt before handing off.

Examples:

```bash
cmux send-key --surface surface:17 enter
cmux send-key --surface surface:17 ctrl+c        # interrupt
cmux send-key --surface surface:17 escape
```

Key names are lowercase with `+` for combos (e.g. `enter`, `escape`, `ctrl+c`), not the
tmux `C-c` style.

Safety: `ctrl+c` and similar control keys can abort the other pane's in-flight work. Only
send them when the user explicitly asked to stop or reset that pane.

## Resume Metadata

```bash
cmux surface resume set [--surface <id|ref|index>] [--cwd <path>] [--name <name>] [--kind <kind>] -- <argv...>
cmux surface resume show [--json] [--surface <id|ref|index>]
cmux surface resume get  [--json] [--surface <id|ref|index>]
cmux surface resume clear [--surface <id|ref|index>]
```

Attaches restart-command metadata to a surface so the pane can be manually restored
later (e.g. relaunching an agent in the same `--cwd`). `show`/`get` inspect the stored
binding; this is the native counterpart to the handoff workflow when a pane has exited
and needs to be brought back rather than read.

Hard limits (do not blur them):

- The result is an **opaque restart hint**, not evidence of recovered task state.
- Never auto-run the returned command.
- Review the command for approval-bypass or permission-relaxing flags before showing it.
- Treat these as high-risk examples, non-exhaustive:
  `--dangerously-skip-permissions`, `--dangerously-bypass-approvals-and-sandbox`,
  `--approval-mode`, `--sandbox danger-full-access`, `--full-auto`,
  `--force`, `--yes`, `--no-confirm`.
  If present, show the risk plainly and require the user to re-confirm before execution.
- Confirm `cwd`, `kind`, `source`, and the surface match the expected target.
- Execute only after the user's explicit approval.

## Piping Pane Text

```bash
cmux pipe-pane [--workspace <id|ref|index>] [--surface <id|ref|index>] [--window <id|ref|index>] [--command <shell-command> | <shell-command>]
```

This captures pane text and pipes it to a shell command through stdin.

Examples:

```bash
cmux pipe-pane --surface surface:17 --command 'grep -n "FAIL\\|ERROR\\|TODO"'
cmux pipe-pane --surface surface:17 --command 'tail -120'
```

Use `pipe-pane` for extraction and summarization workflows where the raw scrollback is too large to inspect directly.

## Handoff Limits

cmux can provide terminal-visible state only:

- It can read scrollback from a terminal surface.
- It can send text to a terminal surface.
- It can pipe pane text to another command.

cmux cannot provide:

- hidden model context,
- hidden system prompts,
- tool-call state not printed in the terminal,
- another model's private memory,
- a guaranteed complete task history if scrollback was truncated.
