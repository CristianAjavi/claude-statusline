# claude-statusline

A custom [Claude Code](https://claude.com/claude-code) status line that shows, in one compact bar:

```
opus-4-8 | main | ctx [████░░░░░░] 43% | chat $1.23 | 🕓 6h12m | 5h [████░░░░░░] 35% ⟳06:00pm (2h14m) | 7d [█░░░░░░░░░] 12%
```

| Segment | Meaning |
|---------|---------|
| `opus-4-8` | Active model (the `claude-` prefix is stripped) |
| `main` | Current git branch (only when the cwd is a repo) |
| `ctx [██░░] 43%` | Context window used |
| `chat $1.23` | Session cost in USD |
| `🕓 6h12m` | Total active work time on this machine **today** (see below) |
| `5h [██░░] 35% ⟳06:00pm (2h14m)` | 5-hour rate-limit usage + reset time + live countdown |
| `7d [█░░░] 12%` | 7-day rate-limit usage |

The three usage bars are **color-coded by threshold**: green `<60%`, yellow `60–84%`, red `≥85%` — so you can read the state at a glance.

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

## Requirements

- `bash`
- [`jq`](https://jqlang.github.io/jq/)
- `git`, `awk`, `date` (standard on macOS/Linux and in Git-Bash on Windows)

The script is cross-platform: it uses `awk` for math (no `bc`), handles both GNU
and BSD `date`, and auto-locates a winget-installed `jq` on Windows.

## Install

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

## Test it

The script reads the status JSON from stdin, so you can dry-run it:

```bash
echo '{"model":{"id":"claude-opus-4-8"},"cwd":".","context_window":{"used_percentage":42.7},"cost":{"total_cost_usd":1.23},"rate_limits":{"five_hour":{"used_percentage":35,"resets_at":1750460400},"seven_day":{"used_percentage":12}}}' \
  | bash statusline.sh
```

## License

MIT
