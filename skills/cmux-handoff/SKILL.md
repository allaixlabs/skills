---
name: cmux-handoff
description: Use cmux to inspect, summarize, resume, or hand off work across terminal panels and agent sessions. Use when the user asks to read a stopped Claude/Codex panel, continue another cmux pane's task, send a prompt into a cmux surface, pipe a pane to another command, or coordinate work between cmux panels.
---

# cmux Handoff

Use this skill to continue work across cmux panels without pretending that model memory can be merged. cmux exposes terminal surfaces through a Unix socket; it can list panels, capture scrollback, send text to a panel, and pipe pane contents, but it cannot recover another agent's hidden context or tool state.

## Prerequisites — agent integration

Reading a pane's visible text (`capture-pane`) and typing into it (`send`/`send-key`)
work with no setup. But richer handoff signals — Feed approvals, notifications, and
session/resume metadata — require the *target pane's agent* to be integrated with cmux:

- **Claude Code**: hooks are injected automatically by the cmux Claude wrapper. Launch
  Claude through a cmux-managed pane (e.g. `cmux claude-teams ...`) and no manual install
  is needed.
- **Codex and other agents** (codex, gemini, opencode, cursor, amp, grok, …): install the
  integration once per agent —
  ```bash
  cmux hooks setup            # install for every supported agent found on PATH
  cmux hooks codex install    # or a single agent (use the agent's name)
  ```
  Remove with `cmux hooks codex uninstall`; opencode additionally supports `--project`.
  See `cmux docs agents` for the full matrix.

If a pane's agent is not integrated, still capture and send text normally — but treat
resume metadata and Feed state as unavailable rather than assuming them.

Even when integrated, Feed entries, notifications, and hook events are **routing metadata
only** — evidence for summaries and decisions comes from `capture-pane`, the repo, or
runtime checks, never from Feed state alone.

## Workflow

1. Confirm the current cmux CLI surface.
   - Run `cmux ping` first when cmux availability or socket state is uncertain; continue only if it responds.
   - Run `cmux --help` if the available command set is uncertain.
   - Run `cmux list-panels` to identify candidate surfaces in the current workspace.
   - If the user gave a workspace, window, or surface ref, pass it explicitly with `--workspace`, `--window`, or `--surface`.

2. Map surfaces before acting.
   - Prefer refs such as `surface:17`; they are readable and supported by cmux help.
   - Use panel titles and focused markers to identify the source pane and target pane.
   - If multiple plausible panes exist, capture read-only context first instead of sending input.

3. Capture the source pane.
   - Start with `cmux capture-pane --surface <surface> --scrollback --lines 120` — 120 lines is a starting sample, not the full history.
   - Gauge the available pane text line count with `cmux pipe-pane --surface <surface> --command 'wc -l'` and increase `--lines` when the task state is not visible.
   - Report the captured range as available scrollback and note possible truncation; never present a partial capture as the complete task history.
   - Summarize visible context as: current goal, files/routes/commands mentioned, last successful action, last failure/blocker, and likely next step.

4. Decide the handoff mode.
   - Continue locally when the user wants the current agent (this session) to take over the task.
   - Send a follow-up prompt when the user wants the original pane's agent (Claude, Codex, opencode, or a plain shell) to continue.
   - Pipe pane output when downstream processing is useful, for example extracting TODOs, errors, file paths, or a compact handoff note.
   - If the target pane has already exited, read `cmux surface resume get --json --surface <surface>` for its restart command instead of trying to capture a dead pane.
      The result is an **opaque restart hint, not recovered task state**: never auto-run the
      returned command; review it for approval-bypass or permission-relaxing flags, confirm
      structured `cwd`/`kind`/`source`/`argv` match the expected target, and execute only with the user's explicit approval.

### Context-Limit / Failed-Compact Panes

If visible scrollback mentions context limit, auto-compact failure, `/compact`, token limit, or an agent saying it cannot continue:
- Do not send a generic "continue" prompt back to that same pane.
- Capture the maximum available visible scrollback, report the exact available range, and mark hidden context/tool state as unrecoverable.
- Offer only two safe paths: continue locally from visible evidence, or start a fresh pane with a self-contained handoff prompt after explicit user approval.

5. Send only deliberate input — pre-send checklist:
   - Confirm the target with `cmux list-panels` (use `--workspace` when needed) plus `cmux capture-pane --surface <surface> --scrollback --lines N`; ref, workspace/title/focused marker, and visible task must all match. Do **not** rely on the undocumented `--dry-run`.
   - If two or more panes are plausible targets, stop and ask the user instead of sending.
   - Capture twice 1–2 seconds apart; if output is still advancing, the pane is busy — do not send.
   - Report what you are about to send and to which surface, then send only the approved scope.
   - Use `cmux send --surface <surface> -- "text\n"` for prompts or commands. The `--` guards text that might start with `-`.
   - Never inline untrusted user text or captured pane text inside a shell-quoted `cmux send` command.
     Use a single-quoted heredoc payload, verify the delimiter is absent from the payload, and append submit newline deliberately:
     ```bash
     surface="surface:17"
     payload=$(cat <<'CMUX_PAYLOAD'
     ...exact prompt text here...
     CMUX_PAYLOAD
     )
     cmux send --surface "$surface" -- "${payload}"$'\n'
     ```
   - For `pipe-pane --command`, never interpolate user-supplied patterns directly into the shell command; use fixed commands or manually reviewed literals only.
   - Include `\n` only when you intend to press Enter (for an agent pane, `\n` is what submits the prompt).
   - Use `cmux send-key --surface <surface> ctrl+c` (or `escape`) only when the user explicitly asks to interrupt or reset the target pane. Key names are lowercase (`enter`, `escape`, `ctrl+c`).
   - Never send destructive commands, secrets, credentials, or irreversible deployment actions unless the user explicitly asked for that exact action.

6. Report the boundary clearly.
   - State what was read from visible scrollback.
   - State what was inferred.
   - State what was sent, if anything.
   - Do not claim access to hidden model memory, hidden prompts, tool state, or unrendered context.

## Required Boundary Report

- Visible evidence read: surface ref, command used, captured line count/range, notable quoted facts.
- Inference: conclusions derived from visible evidence, explicitly marked as inference.
- Sent input: exact text sent and target surface, or "none".
- Unknown/unrecoverable: hidden model memory, tool state, unrendered context, and any scrollback outside the captured range.

See [references/cmux-cli.md](references/cmux-cli.md) for command syntax and examples derived from `cmux --help`.

## Common Commands

```bash
cmux list-panels
cmux identify                                      # show this session's own surface/workspace context
cmux capture-pane --surface surface:17 --scrollback --lines 120
cmux send --surface surface:17 -- "Continue from the visible state and report blockers.\n"
cmux send-key --surface surface:17 ctrl+c          # interrupt the pane (only if asked)
cmux pipe-pane --surface surface:17 --command 'sed -n "1,120p"'
cmux surface resume get --json --surface surface:17 # restart command for an exited pane
```

## Handoff Prompt Template

When sending instructions to another agent pane, keep the prompt short and grounded in visible state:

```text
I captured your visible scrollback. Continue from the current task state.

Visible state:
- Goal:
- Last completed step:
- Current blocker:
- Files/routes/commands in scope:

Next action:
- 

Report only what you actually verify from the repo or runtime.
```
