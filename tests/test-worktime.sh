#!/usr/bin/env bash
# Tests for the AI work-time counter (tools/worktime/).
#
# The defect this file exists to prevent: a detector that answers "no AI running"
# because it stopped recognising a binary, not because none was running. That zero
# looks exactly like the true zero, and the counter sits at 0h00m without anything
# failing.
#
# And the defect this file ITSELF committed in its first version: all five negative
# controls came out GREEN because the detector was blowing up with an "unbound
# variable" and printing nothing. A negative control that passes for lack of signal is
# worth nothing. That is why `expect` now also requires that the function write
# nothing to STDERR and exit 0: without it, any future crash would paint itself green
# all over again.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools/worktime" && pwd)"
. "$DIR/detect.sh"

fails=0
ok()  { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=$((fails+1)); }

expect() { # expect <description> <expected> <ps input>
  local desc="$1" want="$2" input="$3" got err rc
  err=$(mktemp)
  got=$(printf '%s\n' "$input" | active_ais 2>"$err" | sort | tr '\n' ',' | sed 's/,$//')
  rc=$?
  if [ -s "$err" ]; then
    bad "$desc - the detector wrote to STDERR: $(head -1 "$err")"
  elif [ "$rc" -ne 0 ]; then
    bad "$desc - the detector exited with code $rc"
  elif [ "$got" = "$want" ]; then ok "$desc"
  else bad "$desc - expected [$want], got [$got]"; fi
  rm -f "$err"
}

kvget() { awk -F'\t' -v k="$2" '$1==k{print $2}' "$1" 2>/dev/null; }

echo "== POSITIVE control: every tool is recognised =="
expect "claude by path"        "claude" "/opt/homebrew/bin/claude"
expect "codex by path"         "codex"  "/Users/x/.local/bin/codex"
expect "codex-code-mode-host"  "codex"  "/Users/x/.local/bin/codex-code-mode-host"
expect "agy wrapper"           "agy"    "/Users/x/.local/bin/agy"
expect "agy-bin"               "agy"    "/Users/x/.local/bin/agy-bin"
expect "Antigravity app"       "agy"    "/Applications/Antigravity.app/Contents/MacOS/Antigravity"
expect "gemini"                "gemini" "/usr/local/bin/gemini"
expect "cursor-agent"          "cursor" "/Users/x/.local/bin/cursor-agent"

echo "== POSITIVE control: several at once, no repeats =="
expect "claude+codex+agy" "agy,claude,codex" \
"/opt/homebrew/bin/claude
/opt/homebrew/bin/claude
/Users/x/.local/bin/codex
/Users/x/.local/bin/agy-bin"

echo "== NEGATIVE control: what must NOT count =="
expect "machine with no AI"          "" "/usr/sbin/cfprefsd
/usr/libexec/UserEventAgent
node
-zsh"
expect "the status line itself"      "" "/bin/bash /Users/x/.claude/statusline.sh"
expect "empty input"                 "" ""
expect "a name containing claude"    "" "/usr/local/bin/claudette"
expect "codexico is not codex"       "" "/usr/local/bin/codexico"

tick="$DIR/tick.sh"
beat() { WT_FAKE_NOW="$1" bash "$tick" 2>&1; }   # stderr visible: a crash must show

echo "== accumulator: a long gap is NOT charged =="
tmp=$(mktemp -d)
export WORKTIME_DIR="$tmp" WT_FAKE_IDLE=0 WT_FAKE_AIS="claude"
out=$( beat 1000; beat 1060; beat 9000; beat 9060 )
[ -n "$out" ] && bad "tick.sh wrote to STDERR: $(printf '%s' "$out" | head -1)"
f=$(ls "$tmp"/*.kv 2>/dev/null | head -1)
if [ -z "$f" ]; then bad "accumulator - tick.sh created no .kv"; else
  t=$(kvget "$f" total); g=$(kvget "$f" gaps)
  [ "$t" = "120" ] && ok "total=120 s (2 beats); the 2 h gap discarded" \
                   || bad "accumulator - expected total=120, got [$t]"
  [ "$g" = "1" ] && ok "the gap is RECORDED (gaps=1), not silenced" \
                 || bad "gaps - expected 1, got [$g]"
fi

echo "== accumulator: an absent user does NOT count =="
tmp2=$(mktemp -d); export WORKTIME_DIR="$tmp2" WT_FAKE_IDLE=600 WT_FAKE_AIS="claude"
beat 1000 >/dev/null; beat 1060 >/dev/null
t2=$(kvget "$(ls "$tmp2"/*.kv | head -1)" total)
[ "$t2" = "0" ] && ok "10 min idle -> total=0" || bad "idle - expected 0, got [$t2]"

echo "== accumulator: an UNREADABLE idle does not count either (fails closed) =="
tmp3=$(mktemp -d); export WORKTIME_DIR="$tmp3" WT_FAKE_IDLE=999999 WT_FAKE_AIS="claude"
beat 1000 >/dev/null; beat 1060 >/dev/null
t3=$(kvget "$(ls "$tmp3"/*.kv | head -1)" total)
[ "$t3" = "0" ] && ok "unreadable idle -> total=0" || bad "unreadable idle - expected 0, got [$t3]"

echo "== accumulator: no AI alive, nothing counts =="
tmp4=$(mktemp -d); export WORKTIME_DIR="$tmp4" WT_FAKE_IDLE=0 WT_FAKE_AIS=""
beat 1000 >/dev/null; beat 1060 >/dev/null
t4=$(kvget "$(ls "$tmp4"/*.kv | head -1)" total)
[ "$t4" = "0" ] && ok "no AI -> total=0" || bad "no AI - expected 0, got [$t4]"

echo "== per-tool split: the total is NOT double-counted =="
tmp5=$(mktemp -d); export WORKTIME_DIR="$tmp5" WT_FAKE_IDLE=0 WT_FAKE_AIS="claude codex agy"
beat 1000 >/dev/null; beat 1060 >/dev/null
f5=$(ls "$tmp5"/*.kv | head -1)
t5=$(kvget "$f5" total); c5=$(kvget "$f5" "tool:claude")
x5=$(kvget "$f5" "tool:codex"); a5=$(kvget "$f5" "tool:agy")
if [ "$t5" = "60" ] && [ "$c5" = "60" ] && [ "$x5" = "60" ] && [ "$a5" = "60" ]; then
  ok "3 AIs at once: total=60 (union), each tool=60 (overlap)"
else
  bad "split - total=[$t5] claude=[$c5] codex=[$x5] agy=[$a5], expected 60 in all four"
fi

echo "== THIS is the bug the daemon was built for: Codex alone also counts =="
tmp6=$(mktemp -d); export WORKTIME_DIR="$tmp6" WT_FAKE_IDLE=0 WT_FAKE_AIS="codex"
beat 1000 >/dev/null; beat 1060 >/dev/null; beat 1120 >/dev/null
f6=$(ls "$tmp6"/*.kv | head -1)
t6=$(kvget "$f6" total); x6=$(kvget "$f6" "tool:codex"); c6=$(kvget "$f6" "tool:claude")
if [ "$t6" = "120" ] && [ "$x6" = "120" ] && [ -z "$c6" ]; then
  ok "2 min with Codex only -> total=120, codex=120, no claude entry"
else
  bad "codex alone - total=[$t6] codex=[$x6] claude=[$c6], expected 120/120/empty"
fi

echo "== migration: what the old in-bar counter had is not thrown away =="
tmp7=$(mktemp -d); export WORKTIME_DIR="$tmp7" WT_FAKE_IDLE=0 WT_FAKE_AIS="claude"
d7=$(date -r 1000 +%F 2>/dev/null || date -d @1000 +%F)
printf '1000 3577\n' > "$tmp7/$d7"
beat 1000 >/dev/null; beat 1060 >/dev/null
t7=$(kvget "$tmp7/$d7.kv" total)
[ "$t7" = "3637" ] && ok "3577 s inherited + 60 s new = 3637" \
                   || bad "migration - expected 3637, got [$t7]"

rm -rf "$tmp" "$tmp2" "$tmp3" "$tmp4" "$tmp5" "$tmp6" "$tmp7" 2>/dev/null
echo
if [ "$fails" -eq 0 ]; then echo "ALL GREEN"; exit 0; else echo "$fails FAILURE(S)"; exit 1; fi
