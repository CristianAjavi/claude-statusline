#!/usr/bin/env bash
# HEARTBEAT of the AI work-time counter. Runs every 60 s under launchd.
#
# WHY IT EXISTS -------------------------------------------------------------
# The counter used to live inside `statusline.sh`, which only runs when Claude Code
# repaints its bar. Measured result: hours spent in Codex or Antigravity were NEVER
# counted, because those tools do not repaint Claude's bar. The heartbeat had to
# leave the program it was bound to.
#
# WHAT IS MEASURED, EXACTLY (a definition, not an impression) ----------------
# An interval counts when BOTH hold:
#   (a) there was keyboard or mouse input in the last IDLE_LIMIT seconds, and
#   (b) at least one AI tool process is alive on the machine.
# That is "time at the machine with an AI open", NOT "model compute time". It counts
# ONCE even with three AIs open (`total` is the union); the per-tool breakdown does
# overlap, and can therefore add up to more than the total. Two different questions,
# and neither one is the other.
#
# WHAT IS NOT INVENTED -------------------------------------------------------
# If more than MAX_GAP passes between two beats we do not know what happened (machine
# asleep, daemon dead, session closed) and that gap is NOT charged: it is recorded in
# `gaps` so the report can say "there is unmeasured time" instead of hiding it. If the
# idle time cannot be read, nothing is charged either: it fails closed.
#
# macOS ONLY: the idle time comes from `ioreg -c IOHIDSystem`, which has no portable
# equivalent (X11 needs xprintidle, Wayland exposes nothing standard).
set -u

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$dir/detect.sh"

WORKTIME_DIR="${WORKTIME_DIR:-$HOME/.claude/worktime}"
IDLE_LIMIT="${WT_IDLE_LIMIT:-300}"     # 5 min without input = does not count
INTERVAL="${WT_INTERVAL:-60}"          # beat period (must match the plist)
MAX_GAP=$(( INTERVAL * 3 ))            # a longer gap is unmeasured, and not charged

mkdir -p "$WORKTIME_DIR" 2>/dev/null || exit 1

# -- now / idle / ais: substitutable so the tests can drive them ------------
now="${WT_FAKE_NOW:-$(date +%s)}"

if [ -n "${WT_FAKE_IDLE:-}" ] || [ "${WT_FAKE_IDLE:-x}" = "0" ]; then
  idle="${WT_FAKE_IDLE}"
else
  idle=$(ioreg -c IOHIDSystem 2>/dev/null \
         | awk '/HIDIdleTime/ {printf "%d", $NF/1000000000; exit}')
  [ -z "$idle" ] && idle=999999        # not readable -> charge nothing
fi

if [ -n "${WT_FAKE_AIS+x}" ]; then
  ais="$WT_FAKE_AIS"
else
  ais=$(ps_ai | active_ais | tr '\n' ' ')
fi

day=$(date -r "$now" +%F 2>/dev/null || date -d "@$now" +%F 2>/dev/null || date +%F)
kv="$WORKTIME_DIR/$day.kv"
legacy="$WORKTIME_DIR/$day"            # format inherited from statusline.sh

# -- lock: two beats must not step on each other ----------------------------
lock="$WORKTIME_DIR/.lock"
if ! mkdir "$lock" 2>/dev/null; then
  lock_mtime=$(stat -f %m "$lock" 2>/dev/null || stat -c %Y "$lock" 2>/dev/null || echo "$now")
  age=$(( now - lock_mtime ))
  if [ "$age" -gt 300 ] 2>/dev/null; then
    rmdir "$lock" 2>/dev/null
    mkdir "$lock" 2>/dev/null || exit 0
  else
    exit 0
  fi
fi
trap 'rmdir "$lock" 2>/dev/null' EXIT

# -- MIGRATION from the old "<epoch> <accumulated>" format ------------------
# Only when there is no .kv for the day yet. It is inherited as `claude` time, which
# is the only thing that old counter could see; labelling it anything else would be
# making it up.
if [ ! -f "$kv" ] && [ -f "$legacy" ]; then
  _acc=$(awk '{print $2+0; exit}' "$legacy" 2>/dev/null)
  [ -z "$_acc" ] && _acc=0
  {
    printf 'version\t1\n'
    printf 'last\t0\n'
    printf 'total\t%s\n' "$_acc"
    printf 'gaps\t0\n'
    printf 'migrated\t%s\n' "$_acc"
    printf 'tool:claude\t%s\n' "$_acc"
  } > "$kv"
fi

[ -f "$kv" ] || printf 'version\t1\nlast\t0\ntotal\t0\ngaps\t0\n' > "$kv"

# -- accumulate: all arithmetic in awk, which does have maps in bash 3.2 ----
tmpf="$kv.tmp.$$"
awk -F'\t' -v now="$now" -v idle="$idle" -v ais="$ais" \
           -v idle_limit="$IDLE_LIMIT" -v max_gap="$MAX_GAP" '
  { S[$1] = $2 }
  END {
    last  = (("last"  in S) ? S["last"]  + 0 : 0)
    total = (("total" in S) ? S["total"] + 0 : 0)
    gaps  = (("gaps"  in S) ? S["gaps"]  + 0 : 0)

    gap = now - last
    if (last <= 0)          gap = 0             # first beat: no previous stretch
    else if (gap < 0)       gap = 0             # clock went backwards
    else if (gap > max_gap) { gaps++; gap = 0 } # unmeasured: recorded, not charged

    n = split(ais, T, /[ \t]+/)
    alive = 0
    for (i = 1; i <= n; i++) if (T[i] != "") alive++

    if (gap > 0 && idle + 0 < idle_limit + 0 && alive > 0) {
      total += gap
      for (i = 1; i <= n; i++) {
        if (T[i] == "") continue
        k = "tool:" T[i]
        S[k] = (k in S ? S[k] + 0 : 0) + gap
      }
    }

    S["version"] = 1
    S["last"]    = now
    S["total"]   = total
    S["gaps"]    = gaps

    for (k in S) print k "\t" S[k]
  }
' "$kv" | sort > "$tmpf" && mv -f "$tmpf" "$kv"
