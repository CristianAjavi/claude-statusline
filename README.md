# claude-statusline

A custom [Claude Code](https://claude.com/claude-code) status line that shows, in one compact bar:

```
opus-4-8 | main | ctx [████░░░░░░] 43% | chat $1.23 | 5h [████░░░░░░] 35% ⟳06:00pm | 7d [█░░░░░░░░░] 12%
```

| Segment | Meaning |
|---------|---------|
| `opus-4-8` | Active model (the `claude-` prefix is stripped) |
| `main` | Current git branch (only when the cwd is a repo) |
| `ctx [██░░] 43%` | Context window used |
| `chat $1.23` | Session cost in USD |
| `5h [██░░] 35% ⟳06:00pm` | 5-hour rate-limit usage + reset time |
| `7d [█░░░] 12%` | 7-day rate-limit usage |

Empty segments are skipped automatically (e.g. branch is hidden outside a repo).

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
