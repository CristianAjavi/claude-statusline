#!/usr/bin/env bash
# Install the custom status line into Antigravity CLI (~/.gemini/antigravity-cli/settings.json)
# Preserves existing settings and creates a timestamped backup.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUS_SCRIPT="$SCRIPT_DIR/antigravity-statusline.sh"
CONFIG_DIR="${GEMINI_CONFIG_DIR:-$HOME/.gemini/antigravity-cli}"
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

# Update settings.json using jq to safely preserve all existing keys
if command -v jq >/dev/null 2>&1; then
  jq --arg cmd "$STATUS_SCRIPT" '. + { statusLine: { type: "command", command: $cmd } }' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
else
  # Fallback if jq is not installed
  python3 -c "
import json, sys
path = '$SETTINGS_FILE'
try:
    with open(path, 'r') as f:
        data = json.load(f)
except Exception:
    data = {}
data['statusLine'] = {'type': 'command', 'command': '$STATUS_SCRIPT'}
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
"
fi

printf 'Antigravity status line installed in %s\n' "$SETTINGS_FILE"
if [ -n "$BACKUP_FILE" ]; then
  printf 'Backup created at %s\n' "$BACKUP_FILE"
fi
printf 'Status script set to: %s\n' "$STATUS_SCRIPT"
printf 'Next time you open or run agy, the new status line will be active!\n'
