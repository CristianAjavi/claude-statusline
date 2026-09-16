#!/usr/bin/env bash
# Tests for the `cpt` bar: the context segment of line 2 of statusline.sh.
#
# The defect this file exists to prevent: the bar measuring against `autoCompactWindow`
# instead of against the point where the CLI actually compacts. The CLI cuts 33k EARLIER
# than that setting (min(output, 20k) plus a 13k cushion; on bundle 2.1.273 `claude
# --debug` prints effectiveWindow = window - 20k). Measured against the raw window, the
# bar read 86%·33k at the very moment it compacted, and the 85% warning fired 1k before
# the cut instead of ahead of it. That is worse than no bar: `·NNk` is the number you
# decide with -- "do I send this instruction now, or compact first?" -- and it was
# overstating the room left by exactly one margin. Mutants M1 and M3 are that defect,
# injected on purpose.
#
# The third value matters too. With no window configured anywhere the code must NOT
# invent a cut: it falls back to the plain `ctx` window bar. An assertion that only ever
# checked "does cpt look right" would pass with a hardcoded threshold nobody set.
#
# What this actually measures: it RUNS statusline.sh against a throwaway HOME with a
# crafted settings.json and reads the `cpt` field out of its output. It does not grep the
# source -- a field can be computed correctly and then dropped from the assembled line.
#
# Negative control: `bash tests/test-compact.sh --mutants`.
set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SL="$DIR/statusline.sh"

fails=0
ok()  { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=$((fails+1)); }

plain() { sed $'s/\033\\[[0-9;]*m//g'; }

# run <script> <acw-or-"-"> <env-or-"-"> <tokens>  ->  the cpt field, or "none"
run() {
  local script="$1" acw="$2" ev="$3" tok="$4" out
  rm -rf "$FAKEHOME/.claude"; mkdir -p "$FAKEHOME/.claude"
  if [ "$acw" = "-" ]; then
    printf '{}' > "$FAKEHOME/.claude/settings.json"
  else
    printf '{"autoCompactWindow":%s}' "$acw" > "$FAKEHOME/.claude/settings.json"
  fi
  local pl
  pl=$(printf '{"session_id":"t","model":{"id":"claude-opus-5"},"version":"test","cwd":"%s","workspace":{"current_dir":"%s"},"context_window":{"used_percentage":1,"total_input_tokens":%s}}' \
       "$FAKEHOME" "$FAKEHOME" "$tok")
  if [ "$ev" = "-" ]; then
    out=$(printf '%s' "$pl" | env -u CLAUDE_CODE_AUTO_COMPACT_WINDOW HOME="$FAKEHOME" COLUMNS=200 bash "$script" 2>/dev/null | plain)
  else
    out=$(printf '%s' "$pl" | env HOME="$FAKEHOME" COLUMNS=200 CLAUDE_CODE_AUTO_COMPACT_WINDOW="$ev" bash "$script" 2>/dev/null | plain)
  fi
  printf '%s' "$out" | grep -oE 'cpt \[[^]]*\] [0-9]+%·[0-9]+k( ◂(ya|now))?' || printf 'none'
}

# case <description> <acw> <env> <tokens> <expected>
cases() {
  local script="$1" quiet="${2:-}" desc acw ev tok want got
  while IFS='|' read -r desc acw ev tok want; do
    [ -z "${desc:-}" ] && continue
    got=$(run "$script" "$acw" "$ev" "$tok")
    if [ "$got" = "$want" ]; then
      [ -n "$quiet" ] || ok "$desc"
    else
      [ -n "$quiet" ] || bad "$desc -- wanted [$want], got [$got]"
      [ -n "$quiet" ] && fails=$((fails+1))
    fi
  done <<'EOF'
at the 228000 cut it reads 100%·0k|228000|-|195000|cpt [████████] 100%·0k ◂now
halfway there|228000|-|97500|cpt [████░░░░] 50%·98k
the warning arrives with room: 85% is 30k early|228000|-|165750|cpt [███████░] 85%·29k ◂now
one step before the warning it stays quiet|228000|-|163000|cpt [███████░] 84%·32k
the environment variable beats settings.json|228000|250000|195000|cpt [███████░] 90%·22k ◂now
no settings, variable only|-|250000|217000|cpt [████████] 100%·0k ◂now
no window configured invents no cut|-|-|195000|none
EOF
}

FAKEHOME=$(mktemp -d); trap 'rm -rf "$FAKEHOME"' EXIT
mkdir -p "$FAKEHOME/.claude"

if [ "${1:-}" = "--mutants" ]; then
  echo "Negative control -- every mutant must turn this suite red:"
  survivors=0
  copy="$FAKEHOME/mutant.sh"
  while IFS='|' read -r name from to; do
    [ -z "${name:-}" ] && continue
    if ! grep -qF -- "$from" "$SL"; then
      printf '  NOT MEASURED  %s -- anchor missing\n' "$name"; survivors=$((survivors+1)); continue
    fi
    awk -v f="$from" -v t="$to" '{ i=index($0,f); if (i) $0=substr($0,1,i-1) t substr($0,i+length(f)); print }' "$SL" > "$copy"
    fails=0; cases "$copy" quiet
    if [ "$fails" -gt 0 ]; then
      printf '  dies  %s  (%s failing case/s)\n' "$name" "$fails"
    else
      printf '  SURVIVES  %s\n' "$name"; survivors=$((survivors+1))
    fi
  done <<'EOF'
M1 measures against the window, margin not subtracted|acw=$(( acw - cpt_margin ))|acw=$(( acw - 0 ))
M2 ignores the environment variable|acw=${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-$(jq|acw=${NOTHING_FROM_ENV:-$(jq
M3 wrong margin (20k)|cpt_margin=33000|cpt_margin=20000
EOF
  if [ "$survivors" -gt 0 ]; then echo; echo "RED -- $survivors mutant/s survived"; exit 1; fi
  echo; echo "GREEN -- all 3 mutants die"; exit 0
fi

if ! command -v jq >/dev/null 2>&1; then echo "NOT MEASURED -- jq is missing"; exit 2; fi
echo "The cpt bar measures to the real compaction cut"
cases "$SL"
echo
if [ "$fails" -gt 0 ]; then echo "RED -- $fails failing case/s"; exit 1; fi
echo "GREEN -- the bar reaches 100% at the cut and warns ~30k ahead"
