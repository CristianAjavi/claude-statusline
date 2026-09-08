#!/usr/bin/env bash
# Install the status line into Claude Code (~/.claude/settings.json).
# Preserves every existing setting and makes a timestamped backup.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUS_SCRIPT="$SCRIPT_DIR/statusline.sh"
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS_FILE="$CONFIG_DIR/settings.json"

chmod +x "$STATUS_SCRIPT"
mkdir -p "$CONFIG_DIR"

if [ -f "$SETTINGS_FILE" ]; then
  BACKUP_FILE="$SETTINGS_FILE.backup.$(date +%Y%m%d%H%M%S)"
  cp "$SETTINGS_FILE" "$BACKUP_FILE"
else
  echo "{}" > "$SETTINGS_FILE"
  BACKUP_FILE=""
fi

if command -v jq >/dev/null 2>&1; then
  jq --arg cmd "$STATUS_SCRIPT" \
     '. + { statusLine: { type: "command", command: $cmd } }' \
     "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
else
  python3 -c "
import json
path = '$SETTINGS_FILE'
try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    data = {}
data['statusLine'] = {'type': 'command', 'command': '$STATUS_SCRIPT'}
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
"
fi

printf 'Claude Code status line installed in %s\n' "$SETTINGS_FILE"
[ -n "$BACKUP_FILE" ] && printf 'Backup created at %s\n' "$BACKUP_FILE"

# THE CONTEXT BAR NEEDS A THRESHOLD TO MEASURE AGAINST. Without `autoCompactWindow`
# the bar falls back to measuring the model window, which is not what compaction
# waits for. This is only reported, never set: it changes how the session behaves,
# and that is the user's call, not the installer's.
if command -v jq >/dev/null 2>&1; then
  if [ "$(jq -r '.autoCompactWindow // "unset"' "$SETTINGS_FILE")" = "unset" ]; then
    printf '\nNote: `autoCompactWindow` is not set, so the bar will show `ctx` (window)\n'
    printf 'instead of `cpt` (distance to auto-compaction). See the README for why.\n'
  fi
fi

printf 'Restart Claude Code, or run /statusline to check it.\n'
