#!/usr/bin/env bash
# Installs (or reinstalls) the work-time heartbeat under launchd, and CHECKS that it
# is actually running. Idempotent: safe to run again.
#
# macOS only. The heartbeat needs the HID idle time and `ioreg` is the only portable
# way to read it on a Mac; there is no equivalent under Wayland. On any other system
# this exits 0 without installing anything, and statusline.sh then leaves the 🕓
# segment out altogether instead of showing a permanent error marker.
set -eu
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
label="com.github.claude-statusline.worktime"
target="$HOME/Library/LaunchAgents/$label.plist"
log="$HOME/.claude/worktime/heartbeat.err"
marker="$HOME/.claude/worktime/.installed"

if [ "$(uname -s)" != "Darwin" ] || ! command -v ioreg >/dev/null 2>&1; then
  echo "worktime: skipped (macOS only - needs ioreg for the HID idle time)"
  exit 0
fi

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.claude/worktime"

sed -e "s|PLACEHOLDER_TICK|$dir/tick.sh|" \
    -e "s|PLACEHOLDER_LOG|$log|" \
    "$dir/$label.plist" > "$target"

launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$target"
launchctl kickstart -k "gui/$(id -u)/$label"

# VERIFY, do not assume: launchd must list it AND today's file must exist. Installing
# without checking is the same as not installing.
sleep 2
if ! launchctl list | grep -q "$label"; then
  echo "FAILED: launchd does not list $label" >&2; exit 1
fi
kv="$HOME/.claude/worktime/$(date +%F).kv"
if [ ! -f "$kv" ]; then
  echo "FAILED: the heartbeat did not write $kv" >&2
  [ -s "$log" ] && sed -n '1,20p' "$log" >&2
  exit 1
fi

# The marker is what lets the status line tell "never installed" (segment hidden)
# apart from "installed and dead" (red marker). Without it both look the same.
date +%s > "$marker"
echo "OK  $label installed and beating -> $kv"
