# Claude Code + Codex + Antigravity status line

Compact status-line presets for [Claude Code](https://claude.com/claude-code), [Codex CLI](https://developers.openai.com/codex/cli/), and [Google Antigravity CLI (`agy`)](https://antigravity.google/docs/cli/statusline).

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
opus-4-8 | main | cpt [████░░░░░░] 43%·112k | chat $1.23 | 🕓 6h12m | 5h [████░░░░░░] 35% ⟳06:00pm (2h14m) | 7d [█░░░░░░░░░] 12%
```

| Segment | Meaning |
|---------|---------|
| `opus-4-8` | Active model (the `claude-` prefix is stripped) |
| `main` | Current git branch (only when the cwd is a repo) |
| `cpt [██░░] 43%·112k` | How close the next **auto-compaction** is, and the tokens left before it (see below) |
| `chat $1.23` | Session cost in USD |
| `🕓 6h12m` | Total active work time on this machine **today** (see below) |
| `5h [██░░] 35% ⟳06:00pm (2h14m)` | 5-hour rate-limit usage + reset time + live countdown |
| `7d [█░░░] 12%` | 7-day rate-limit usage |

The three usage bars are **color-coded by threshold**: green `<60%`, yellow `60–84%`, red `≥85%` — so you can read the state at a glance.

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

### Daily work-time counter (`🕓`)

A purple counter that accumulates how long you've actually been working on the
machine **today**, across **all** Claude Code sessions combined.

It works by heartbeat: every time the status line re-renders it stamps a
timestamp in `~/.claude/worktime/YYYY-MM-DD` and adds the gap since the previous
heartbeat **only if that gap is under 5 minutes** (`IDLE_LIMIT`). Longer gaps are
treated as idle and ignored. Because it sums wall-clock gaps (not just API time),
it naturally includes tool-execution and reading time, and because all sessions
share one daily file it does **not** double-count parallel windows. The file is
per-day, so the counter resets automatically each day.

Note: it only counts time while a Claude Code status line is rendering — not your
whole workday outside Claude. Tune `IDLE_LIMIT` in the script to be more/less
forgiving about pauses.

### Requirements

- `bash`
- [`jq`](https://jqlang.github.io/jq/)
- `git`, `awk`, `date` (standard on macOS/Linux and in Git-Bash on Windows)

The script is cross-platform: it uses `awk` for math (no `bc`), handles both GNU
and BSD `date`, and auto-locates a winget-installed `jq` on Windows.

### Install for Claude Code

1. Copy `statusline.sh` into your Claude Code config dir:

   **macOS / Linux**
   ```bash
   curl -fsSL https://raw.githubusercontent.com/CristianAjavi/claude-statusline/main/statusline.sh \
     -o ~/.claude/statusline.sh
   chmod +x ~/.claude/statusline.sh
   ```

   **Windows (Git-Bash)**
   ```bash
   curl -fsSL https://raw.githubusercontent.com/CristianAjavi/claude-statusline/main/statusline.sh \
     -o "$HOME/.claude/statusline.sh"
   ```

2. Point Claude Code at it in `~/.claude/settings.json`:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash ~/.claude/statusline.sh",
       "padding": 0
     }
   }
   ```

   On Windows use the absolute path:
   ```json
   "command": "bash C:/Users/<you>/.claude/statusline.sh"
   ```

3. Restart Claude Code (or run `/statusline`).

### Test the Claude Code script

The script reads the status JSON from stdin, so you can dry-run it:

```bash
echo '{"model":{"id":"claude-opus-4-8"},"cwd":".","context_window":{"used_percentage":42.7},"cost":{"total_cost_usd":1.23},"rate_limits":{"five_hour":{"used_percentage":35,"resets_at":1750460400},"seven_day":{"used_percentage":12}}}' \
  | bash statusline.sh
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
bash tests/test-install-codex.sh
bash tests/test-codex-usage.sh
```

## License

MIT

