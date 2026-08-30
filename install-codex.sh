#!/usr/bin/env bash
# Install the native Codex status line without replacing unrelated settings.

set -eu

CODEX_CONFIG_DIR="${CODEX_HOME:-$HOME/.codex}"
CONFIG_FILE="$CODEX_CONFIG_DIR/config.toml"
STATUS_LINE='status_line = ["model-with-reasoning", "fast-mode", "git-branch", "context-used", "five-hour-limit", "weekly-limit", "used-tokens"]'

mkdir -p "$CODEX_CONFIG_DIR"

if [ -f "$CONFIG_FILE" ]; then
  BACKUP_FILE="$CONFIG_FILE.backup.$(date +%Y%m%d%H%M%S)"
  cp "$CONFIG_FILE" "$BACKUP_FILE"
else
  : > "$CONFIG_FILE"
  BACKUP_FILE=""
fi

TEMP_FILE="$CONFIG_FILE.tmp.$$"
trap 'rm -f "$TEMP_FILE"' EXIT HUP INT TERM

awk -v status_line="$STATUS_LINE" '
  BEGIN {
    in_tui = 0
    found_tui = 0
    wrote_status = 0
  }

  # Support a dotted root-level key if a user configured it manually.
  /^[[:space:]]*tui\.status_line[[:space:]]*=/ {
    if (!wrote_status) {
      print "tui." status_line
      wrote_status = 1
    }
    next
  }

  /^[[:space:]]*\[tui\][[:space:]]*$/ {
    in_tui = 1
    found_tui = 1
    print
    if (!wrote_status) {
      print status_line
      wrote_status = 1
    }
    next
  }

  /^[[:space:]]*\[/ {
    in_tui = 0
  }

  in_tui && /^[[:space:]]*status_line[[:space:]]*=/ {
    next
  }

  { print }

  END {
    if (!wrote_status) {
      if (NR > 0) print ""
      print "[tui]"
      print status_line
    }
  }
' "$CONFIG_FILE" > "$TEMP_FILE"

mv "$TEMP_FILE" "$CONFIG_FILE"
trap - EXIT HUP INT TERM

printf 'Codex status line installed in %s\n' "$CONFIG_FILE"
if [ -n "$BACKUP_FILE" ]; then
  printf 'Backup created at %s\n' "$BACKUP_FILE"
fi
printf 'Restart Codex, or open /statusline to inspect the configured fields.\n'
