# Work-time counter (`🕓`)

Counts the time you actually spend working with an AI tool, across **every** CLI on
the machine - not just the one drawing the status line.

## What it measures

An interval counts when both hold:

- there was keyboard or mouse input in the last 5 minutes, and
- at least one AI tool process is alive (`claude`, `codex`, `agy`, `gemini`,
  `cursor-agent`, `copilot`, `aider`, `opencode`, `amp`).

That is *time at the machine with an AI open*, not model compute time. `TOTAL` is the
**union**: three tools open at once are not worth triple. The per-tool breakdown does
overlap, and can add up to more than `TOTAL` - they answer two different questions.

## Why it is a daemon and not part of the status line

The counter used to be a heartbeat inside `statusline.sh`, which only runs when Claude
Code repaints its bar. Hours spent in Codex or Antigravity were therefore never
counted. A counter bound to the program it measures cannot measure the others, so the
heartbeat moved out and became the single writer. `statusline.sh` only reads.

## What it refuses to invent

- A gap longer than 3 beats is **not charged**. It is recorded in `gaps`, so the
  report can say there is unmeasured time instead of hiding it.
- If the idle time cannot be read, nothing is charged. It fails closed.
- A dead heartbeat freezes the figure, and a frozen figure looks like a quiet day, so
  the status line flags it with a red `!` when nothing has been written for 3 minutes
  while the bar is demonstrably repainting.

## Install

```bash
bash tools/worktime/install.sh
```

macOS only: the idle time comes from `ioreg -c IOHIDSystem`, which has no portable
equivalent. Elsewhere the installer exits cleanly and the status line simply omits the
segment.

## Report

```bash
tools/worktime/worktime-today            # today
tools/worktime/worktime-today --week     # the last 7 days
tools/worktime/worktime-today 2026-08-30 # a specific day
```

## Files

| File | Role |
|---|---|
| `tick.sh` | The heartbeat. The only writer of `~/.claude/worktime/<date>.kv`. |
| `detect.sh` | Which AI tools are alive. Reads `ps` output from stdin so it can be tested. |
| `worktime-today` | The report. |
| `install.sh` | Wires the heartbeat into launchd and verifies it beat. |

Tested by `tests/test-worktime.sh`, which drives the detector with synthetic `ps`
lines and includes the negative controls - a detector that answers "none" because it
stopped recognising a binary looks exactly like an idle machine.
