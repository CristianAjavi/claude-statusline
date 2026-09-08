#!/usr/bin/env bash
# Tests for the effort segment of statusline.sh.
#
# The defect this file exists to prevent: the effort quietly leaving the bar. A turn's
# cost is the pair model x effort, so a bar that shows "opus-5" and says nothing about
# the effort looks perfectly fine and is useless for forecasting. Nothing fails, no
# error is printed, and the loss is invisible until someone goes looking for a number
# that was never there.
#
# What this actually measures: it RUNS statusline.sh with crafted payloads and reads
# its OUTPUT. It does not grep the source. Grepping the source would pass just as
# happily with the field computed and then dropped from the final assembly, which is
# exactly mutant M1 below.
#
# The second defect it guards against is subtler: a MISSING effort being painted as a
# blank. A gap reads as "no extra effort", the opposite of "I could not read it". So
# the no-data path has its own expected string, "n/m", and mutant M2 exists to
# prove the test would catch its removal.
#
# Negative control: `bash tests/test-effort.sh --mutants` breaks statusline.sh three
# concrete ways and demands the suite go RED on all three. A check that has never
# failed has not shown it knows how to fail.
set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SL="$DIR/statusline.sh"

fails=0
ok()  { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=$((fails+1)); }

# strip ANSI so the assertions compare text, not colour codes
plain() { sed $'s/\033\\[[0-9;]*m//g'; }

# run <payload-json> <settings-json-or-NONE> <columns> -> statusline output, no ANSI
run() {
  local payload="$1" settings="$2" cols="${3:-120}" sfile
  if [ "$settings" = "NONE" ]; then
    # A path that does not exist, to force the "nothing to read anywhere" branch.
    sfile="$TMP/absent-settings.json"
  else
    sfile="$TMP/settings.json"
    printf '%s' "$settings" > "$sfile"
  fi
  printf '%s' "$payload" | COLUMNS="$cols" CLAUDE_SETTINGS="$sfile" bash "$SL" 2>"$TMP/err" | plain
}

# A deliberately THIN payload: no rate_limits, no context_window. If the effort only
# showed up on a full payload, this suite would not be measuring the degraded path.
payload() { # payload <effort-level-or-empty> <with-model:yes|no>
  local lvl="$1" model="$2" eff="" mdl=""
  [ -n "$lvl" ] && eff="\"effort\":{\"level\":\"$lvl\"},"
  [ "$model" = "yes" ] && mdl="\"model\":{\"id\":\"claude-opus-5[1m]\",\"display_name\":\"Opus 5\"},"
  printf '{%s%s"session_id":"test-effort","cwd":"%s","workspace":{"current_dir":"%s"},"version":"test"}' \
    "$eff" "$mdl" "$HOME" "$HOME"
}

expect_line2_starts() { # <description> <wanted prefix> <payload> <settings>
  local desc="$1" want="$2" got
  got=$(run "$3" "$4" | tail -1)
  if [ -s "$TMP/err" ]; then
    bad "$desc - statusline wrote to STDERR: $(head -1 "$TMP/err")"
  elif [ -z "$got" ]; then
    bad "$desc - statusline printed nothing"
  elif [ "${got#"$want"}" != "$got" ]; then
    ok "$desc -> line 2 opens with $want"
  else
    bad "$desc - line 2 should open with [$want], got [$got]"
  fi
}

expect() { # expect <description> <wanted substring> <payload> <settings> [columns]
  local desc="$1" want="$2" got
  got=$(run "$3" "$4" "${5:-120}")
  if [ -s "$TMP/err" ]; then
    bad "$desc - statusline wrote to STDERR: $(head -1 "$TMP/err")"
  elif [ -z "$got" ]; then
    # A silent crash prints nothing, and "nothing" contains no wrong answer either.
    # Without this branch every case would go green for lack of signal.
    bad "$desc - statusline printed nothing"
  elif [[ "$got" == *"$want"* ]]; then
    ok "$desc -> $want"
  else
    bad "$desc - expected [$want], got [$(printf '%s' "$got" | tail -1)]"
  fi
}

# The level is painted bare, with no prefix, so asserting on "hi" or "lo" alone would
# be a two-letter substring that matches almost anything else on the bar. Every case
# anchors to the WHOLE field -- the model, a space, then the level -- which is exactly
# what the user reads.
M="opus-5[1m]"

suite() {
  echo "== POSITIVE control: every level reaches the bar =="
  expect "level low"       "$M lo"  "$(payload low yes)"    '{"effortLevel":"medium"}'
  expect "level medium"    "$M md"  "$(payload medium yes)" '{"effortLevel":"low"}'
  expect "level high"      "$M hi"  "$(payload high yes)"   '{"effortLevel":"low"}'
  expect "level xhigh"     "$M xhi" "$(payload xhigh yes)"  '{"effortLevel":"low"}'
  expect "level max"       "$M max" "$(payload max yes)"    '{"effortLevel":"low"}'
  # The payload must win over settings.json, or the bar would show a stale level.
  expect "payload beats settings" "$M max" "$(payload max yes)" '{"effortLevel":"low"}'

  echo "== a level this script has never seen must not vanish =="
  expect "unknown level" "$M tur" "$(payload turbo yes)" '{}'

  echo "== the effort survives what it does not depend on =="
  # With no model there is nothing to anchor to, so the level has to OPEN line 2.
  expect_line2_starts "no model in payload" "hi" "$(payload high no)" '{}'
  expect "narrow terminal" "$M max" "$(payload max yes)" '{}' 70

  echo "== fallback for a CLI that does not send the field =="
  # The case that separates reading the payload from reading settings.json naively:
  # the global says high, the per-model override says xhigh, and the override wins.
  expect "per-model override wins" "$M xhi" "$(payload '' yes)" \
    '{"effortLevel":"high","modelSettings":{"claude-opus-5":{"effortLevel":"xhigh"}}}'
  expect "global only"             "$M lo"  "$(payload '' yes)" '{"effortLevel":"low"}'

  echo "== NEGATIVE control: no data is declared, never blank =="
  expect "no payload, no settings" "$M n/m" "$(payload '' yes)" NONE
}

# ------------------------------------------------------------------ mutants ---
# Each mutant is a real, plausible way this segment breaks. The suite has to go red
# on all three; one that survives means the suite does not watch what it claims to.
mutants() {
  local backup="$TMP/statusline.orig" name old new before survivors=()
  cp "$SL" "$backup"
  # shellcheck disable=SC2064
  trap "cp '$backup' '$SL'" EXIT

  local specs=(
    'M1 field computed but never assembled|"$model_str" "$ctx_str"|"$model_short" "$ctx_str"'
    'M2 missing data painted as a blank|effort_lbl="n/m"|effort_lbl=""'
    'M3 fallback ignores the per-model override|(.modelSettings[$m].effortLevel // .effortLevel)|.effortLevel'
  )
  for spec in "${specs[@]}"; do
    name="${spec%%|*}"; local rest="${spec#*|}"
    old="${rest%%|*}"; new="${rest#*|}"
    if ! grep -qF -- "$old" "$backup"; then
      survivors+=("$name: could not be injected (anchor missing) -> NOT MEASURED")
      continue
    fi
    # EVERY occurrence, not just the first. The first version of this replaced one
    # and M1 came out killing a single case -the narrow-terminal branch- because the
    # main assembly line further down was left untouched. The mutant went red, so it
    # looked fine, while testing a fraction of what it claimed to.
    awk -v o="$old" -v n="$new" '
      { out=""; rest=$0
        while ((i=index(rest,o))>0) { out=out substr(rest,1,i-1) n; rest=substr(rest,i+length(o)) }
        print out rest }
    ' "$backup" > "$SL"
    if ! grep -qF -- "$new" "$SL"; then
      survivors+=("$name: injection did not change the file -> NOT MEASURED")
      cp "$backup" "$SL"; continue
    fi
    before=$fails
    suite >/dev/null 2>&1
    if [ "$fails" -gt "$before" ]; then
      printf '  killed  %s  (%d failing case/s)\n' "$name" $((fails - before))
    else
      survivors+=("$name: SURVIVES, the suite does not see it")
    fi
    fails=$before
    cp "$backup" "$SL"
  done

  if [ ${#survivors[@]} -gt 0 ]; then
    printf '\nRED - surviving mutants:\n'
    printf '  - %s\n' "${survivors[@]}"
    return 1
  fi
  printf '\nGREEN - all %d mutants die\n' "${#specs[@]}"
  return 0
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if [ ! -f "$SL" ]; then
  echo "NOT MEASURED - $SL does not exist"
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  # Saying "green" here would be approving without measuring: statusline.sh cannot
  # read a single field of the payload without jq.
  echo "NOT MEASURED - jq is missing, statusline.sh cannot parse the payload"
  exit 2
fi

if [ "${1:-}" = "--mutants" ]; then
  echo "Negative control: the suite must go red on every mutant"
  mutants
  exit $?
fi

suite
if [ "$fails" -gt 0 ]; then
  printf '\nRED - %d failing case/s\n' "$fails"
  exit 1
fi
printf '\nGREEN - the effort reaches the bar on every path\n'
