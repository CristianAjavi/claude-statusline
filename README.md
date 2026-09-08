# Claude Code + Codex + Antigravity status line

Compact status-line presets for [Claude Code](https://claude.com/claude-code), [Codex CLI](https://developers.openai.com/codex/cli/), and [Google Antigravity CLI (`agy`)](https://antigravity.google/docs/cli/statusline).

## Install

```bash
git clone https://github.com/CristianAjavi/claude-statusline.git
cd claude-statusline
./install.sh
```

It asks nothing. It detects which of the three CLIs this machine actually uses and
installs the matching status line for each — Claude Code and Antigravity get the
shell script, Codex gets its native TUI field list, since Codex does not execute a
script at all. The work-time counter is installed alongside, whichever CLI was found.

A CLI counts as *in use* when its binary is on `PATH` **or** its config directory
exists. Either signal alone is wrong: a binary behind an alias or a version manager
may not be on `PATH`, and a config directory can outlive an uninstall. The detection
is printed before anything is written, so a wrong guess is visible rather than silent.

```text
Detected:
  Claude Code    found (claude on PATH)
  Codex          found (~/.codex exists)
  Antigravity    not found
```

| Flag | Effect |
|---|---|
| `--dry-run` | Print what it would do and write nothing |
| `--all` | Install all three, detected or not |

If nothing is detected it exits non-zero without writing anything: a status line
wired into a CLI that is not there is just a config file nobody asked for. Existing
settings are always preserved and backed up with a timestamp. Each CLI can also be
installed on its own with `install-claude.sh`, `install-codex.sh` or
`install-antigravity.sh`.

## Codex

Codex has a native TUI footer, so it does not execute `statusline.sh` or consume
Claude Code's status JSON. This repository provides the closest native mapping:

```text
gpt-5 · high | main | 43% used | 5h 35% | weekly 12% | 42.1K tokens
```

| Codex item | Meaning |
|------------|---------|
| `model-with-reasoning` | Active model and reasoning effort |
| `fast-mode` | Fast mode, when enabled |
| `git-branch` | Current Git branch |
| `context-used` | Context window used |
| `five-hour-limit` | Five-hour account limit and reset |
| `weekly-limit` | Weekly account limit and reset |
| `used-tokens` | Tokens used in the current session |

### Install for Codex

```bash
git clone https://github.com/CristianAjavi/claude-statusline.git
cd claude-statusline
bash install-codex.sh
```

The installer updates only the status-line setting in
`~/.codex/config.toml`, preserves other settings, and creates a timestamped
backup when the file already exists. Restart Codex after installing.

You can also configure it manually:

```toml
[tui]
status_line = ["model-with-reasoning", "fast-mode", "git-branch", "context-used", "five-hour-limit", "weekly-limit", "used-tokens"]
```

Inside Codex, `/statusline` opens the native picker so you can reorder or toggle
fields interactively.

### Detailed usage and reset countdowns

The native footer is intentionally compact. For a Claude-style detailed view of
every limit that Codex reports, run:

```bash
bash codex-usage.sh
```

To keep it visible and refreshed in a small Warp split pane:

```bash
bash codex-usage.sh --watch
```

The display includes the used and available percentage, a color-coded bar, the
local reset date/time, and a live countdown. Codex sometimes reports only the
weekly window; unavailable windows are omitted rather than estimated.

### Platform differences

Codex currently exposes native footer fields rather than a command hook. The
Claude-specific session cost, custom colored bars, and daily heartbeat counter
therefore cannot be injected into the Codex footer. Codex renders its own colors
and limit-reset information for supported native fields.

## Claude Code

A custom [Claude Code](https://claude.com/claude-code) status line that shows, in one compact bar:

```
you@example.com | ~/project | main | ⏳ 3 tasks · 1 running
opus-4-8 e:xhi | cpt [████░░░░] 43%·112k | 🕓 6h12m | 5h [███░░░░░] 35% ↻2h14m | 7d [█░░░░░░░] 12%
```

| Segment | Meaning |
|---------|---------|
| `opus-4-8` | Active model (the `claude-` prefix is stripped) |
| `e:xhi` | **Reasoning effort** in force, colour-coded by what it costs (see below) |
| `main` | Current git branch (only when the cwd is a repo) |
| `cpt [██░░] 43%·112k` | How close the next **auto-compaction** is, and the tokens left before it (see below) |
| `🕓 6h12m` | Total active work time on this machine **today** (see below) |
| `5h [██░░] 35% ↻2h14m` | 5-hour rate-limit usage + countdown to the reset |
| `7d [█░░░] 12%` | 7-day rate-limit usage |
| `⏳ 3 tasks · 1 running` | Open tasks **of this terminal's session** |

The three usage bars are **color-coded by threshold**: green `<60%`, yellow `60–84%`, red `≥85%` — so you can read the state at a glance.

### Why the reasoning effort is on the bar (`e:xhi`)

What a turn costs is not set by the model alone, it is set by the pair **model ×
effort**. On the same `opus-5`, going from `high` to `xhigh` changes the reasoning
tokens spent per turn. A bar that names the model and says nothing about the effort
looks complete and gives you nothing to forecast a run's cost with.

| Shown | Level | Colour |
|-------|-------|--------|
| `e:lo` | `low` | green |
| `e:md` | `medium` | green |
| `e:hi` | `high` | yellow |
| `e:xhi` | `xhigh` | red |
| `e:max` | `max` | red |
| `e:s/med` | could not be read | red |

The value comes from `effort.level` in the status JSON, **already resolved** by the
CLI. It is deliberately not read from `settings.json`, for two measured reasons:

- `settings.json` can hold a global `effortLevel` **and** a per-model override in
  `modelSettings`. On the machine this was written on the global said `high` and the
  override said `xhigh`, and the payload said `xhigh` — reading the file naively gives
  the wrong answer whenever an override exists.
- the effective level **changes within a single session** (a capture on bundle
  `2.1.263` saw `xhigh` and `max` on different turns). Nothing on disk reflects that.

`settings.json` is used only as a fallback for a CLI old enough not to send the field,
and there the same precedence is applied (override beats global). A level this script
has never heard of is not dropped — it is printed truncated, in purple, which is how
you find out the CLI shipped a new one.

If neither source has it, the bar prints `e:s/med` in red rather than leaving a gap.
A gap would read as *"no extra effort"*, which is the opposite of *"I could not read
it"*. `tests/test-effort.sh` covers that path, and its mutant `M2` exists to prove the
suite would notice if it were ever turned back into a blank.

### Why the context bar measures auto-compaction, not the window

Claude Code ships `context_window.used_percentage` computed against the **model window**,
but compaction does not wait for the window to fill: it fires at `autoCompactWindow` in
`settings.json`. With a 1M window and a 250k threshold, compaction hits at ~22% of the
window — so a bar drawn against the window sits barely a quarter full at the exact moment
it is about to compact, and any "time to compact" nudge above that never fires at all.

So `cpt` measures the distance to the **cut**: the bar and `%` for the glance, and `·NNk`
for the tokens left, which is the number you actually decide with. Past 85% it appends a
red `◂now`: an instruction typed in that band tends to land in the compaction summary as
background rather than as a live order.

If `autoCompactWindow` is not set in `settings.json`, the segment falls back to the plain
window bar, labelled `ctx [██░░] 43%`.

Empty segments are skipped automatically (e.g. branch is hidden outside a repo).

### Work-time counter (`🕓`)

A purple counter of how long you have actually been working with an AI **today**,
across **every** CLI on the machine — not just the one drawing this bar.

It used to be a heartbeat inside `statusline.sh`, which only runs when Claude Code
repaints its bar. Hours spent in Codex or Antigravity were therefore never counted: a
counter bound to the program it measures cannot measure the others. The heartbeat now
lives in `tools/worktime/tick.sh`, runs every 60 s under launchd and is the only
writer; this script only reads. An interval counts when there was keyboard or mouse
input in the last 5 minutes **and** at least one AI tool is alive. `TOTAL` is the
union — three tools open at once are not worth triple.

A red `!` after the figure means the heartbeat has not written for 3 minutes while
this bar is demonstrably repainting: the number is frozen, not low. If the heartbeat
was never installed the segment is simply absent — an uninstalled counter and a dead
one must not look the same.

macOS only: the idle time comes from `ioreg -c IOHIDSystem`, which has no portable
equivalent (X11 needs `xprintidle`, Wayland exposes nothing standard). `install.sh`
skips it elsewhere. See [`tools/worktime/README.md`](tools/worktime/README.md).

### Requirements

- `bash`
- [`jq`](https://jqlang.github.io/jq/)
- `git`, `awk`, `date` (standard on macOS/Linux and in Git-Bash on Windows)

The script is cross-platform: it uses `awk` for math (no `bc`), handles both GNU
and BSD `date`, and auto-locates a winget-installed `jq` on Windows.

### Install for Claude Code

```bash
./install-claude.sh
```

Wires `statusline.sh` into `~/.claude/settings.json`, preserving every other key and
leaving a timestamped backup. It also warns when `autoCompactWindow` is unset — it
reports it and never sets it, because that key changes how your sessions behave and
is yours to decide.

<details>
<summary>Manual install (or Windows / Git-Bash)</summary>

```bash
curl -fsSL https://raw.githubusercontent.com/CristianAjavi/claude-statusline/main/statusline.sh \
  -o ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

Then in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline.sh",
    "padding": 0
  }
}
```

On Windows use the absolute path: `"command": "bash C:/Users/<you>/.claude/statusline.sh"`.

Restart Claude Code, or run `/statusline`.
</details>

### Test the Claude Code script

The script reads the status JSON from stdin, so you can dry-run it:

```bash
echo '{"model":{"id":"claude-opus-4-8"},"effort":{"level":"xhigh"},"cwd":".","context_window":{"used_percentage":42.7},"rate_limits":{"five_hour":{"used_percentage":35,"resets_at":1750460400},"seven_day":{"used_percentage":12}}}' \
  | bash statusline.sh
```

Drop the `effort` key from that payload to see the fallback, and point
`CLAUDE_SETTINGS` at a throwaway file to drive it:

```bash
echo '{"effortLevel":"high","modelSettings":{"claude-opus-4-8":{"effortLevel":"max"}}}' > /tmp/s.json
echo '{"model":{"id":"claude-opus-4-8"},"cwd":"."}' | CLAUDE_SETTINGS=/tmp/s.json bash statusline.sh
```

## Google Antigravity CLI (`agy`)

A custom status line for [Google Antigravity CLI (`agy`)](https://antigravity.google/docs/cli/statusline) that renders:

```
cristianajavi(Pro) | ~/my-project | main
gemini-3.7-flash | ctx [█░░░░░░░] 14% | 🕓 6h12m | quota [█░░░░░░░] 12% ↻2d02h
```

| Segment | Meaning |
|---------|---------|
| `cristianajavi(Pro)` | User account / subscription plan tier |
| `~/my-project` | Abbreviated working directory |
| `main` | Current Git branch |
| `gemini-3.7-flash` | Active model |
| `ctx [█░░░] 14%` | Context window token usage bar |
| `🕓 6h12m` | Daily work time counter (shared heartbeat) |
| `quota [█░░░] 12%` | Quota percentage and countdown to next reset |
| `⚙ 2 tasks` | Active background tasks (shown when `task_count > 0`) |

### Install for Antigravity

```bash
bash install-antigravity.sh
```

Or configure manually in `~/.gemini/antigravity-cli/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.gemini/antigravity-cli/statusline.sh"
  }
}
```

### Test Antigravity status line

```bash
echo '{"cwd":".","email":"user@gmail.com","plan_tier":"Pro","model":{"id":"Gemini 3.7 Flash (High)"},"context_window":{"used_percentage":14.5},"quota":{"gemini-weekly":{"remaining_fraction":0.88,"reset_in_seconds":180000}}}' \
  | bash antigravity-statusline.sh
```

## Test

Run the test suites with:

```bash
bash tests/test-install.sh      # the detecting installer, with its negative controls
bash tests/test-worktime.sh     # the work-time counter and its AI detector
bash tests/test-effort.sh       # the reasoning-effort segment on every path
bash tests/test-install-codex.sh
bash tests/test-codex-usage.sh
```

`tests/test-effort.sh --mutants` is its negative control: it breaks `statusline.sh`
three concrete ways — the field computed but never assembled, missing data painted as
a blank, and the fallback ignoring the per-model override — and demands the suite go
red on all three. A check that has never failed has not shown it knows how to fail.

`tests/test-install.sh` runs every case against a throwaway `HOME` and a `PATH` that
holds only what the case is meant to find — on a machine with all three CLIs
installed, that is the only way the "nothing detected" case means anything.

## License

MIT

