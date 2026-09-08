#!/usr/bin/env bash
# Tests for the task progress bar at the end of line 1 of statusline.sh.
#
# The defect this file exists to prevent, first and above all the others: the segment
# turning ITSELF ON. It ships off. Every existing installation must look byte for byte
# the way it looked before this segment was written, and an opt-in that quietly opts
# you in is worse than no feature -- nothing errors, nothing is logged, a line just
# grows a bar its owner never asked for. Mutant M2 is that defect, injected on purpose.
#
# The second defect is the bar lying at a glance. Five cells is a coarse ruler: 1 of 12
# rounds to an empty bar and 11 of 12 rounds to a full one. "Nothing started" and "all
# done" are exactly the two readings that change what you do next, so the code clamps
# both and mutants M3 and M4 exist to prove this suite would see the clamps removed.
#
# What this actually measures: it RUNS statusline.sh against a throwaway HOME with
# crafted task files and reads LINE 1 of its output. It does not grep the source, and
# it does not look at line 2 -- line 2 is full of the very block characters this
# segment paints, so a naive "is there a bar" assertion would pass with the segment
# deleted. That confusion is mutant M1.
#
# Negative control: `bash tests/test-task-bar.sh --mutants`.
set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SL="$DIR/statusline.sh"

fails=0
ok()  { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=$((fails+1)); }

# strip ANSI so the assertions compare text, not colour codes
plain() { sed $'s/\033\\[[0-9;]*m//g'; }

mktasks() { # mktasks <session-id> <completed> <pending>
  local sid="$1" hechas="$2" abiertas="$3" i d
  d="$FAKEHOME/.claude/tasks/$sid"
  rm -rf "$d"; mkdir -p "$d"
  i=0; while [ "$i" -lt "$hechas" ];  do printf '{"status": "completed"}' > "$d/c$i.json"; i=$((i+1)); done
  i=0; while [ "$i" -lt "$abiertas" ]; do printf '{"status": "pending"}'   > "$d/p$i.json"; i=$((i+1)); done
}

payload() { # payload <session-id> <output-style-name-or-empty>
  local sid="$1" st="$2" style=""
  [ -n "$st" ] && style="\"output_style\":{\"name\":\"$st\"},"
  printf '{%s"session_id":"%s","model":{"id":"claude-opus-5"},"effort":{"level":"high"},"cwd":"%s","workspace":{"current_dir":"%s"},"version":"test"}' \
    "$style" "$sid" "$FAKEHOME" "$FAKEHOME"
}

# line1 <knob-or-UNSET> <payload> -> the FIRST line only, no ANSI.
# UNSET is not the same as empty: an unset variable is what everyone who installed
# this already has, and an empty one is what a shell profile that exports it blank
# gives you. Both must stay silent, and only one of them can be tested with `VAR=`.
line1() {
  local knob="$1" pl="$2" out
  if [ "$knob" = "UNSET" ]; then
    out=$(printf '%s' "$pl" | env -u STATUSLINE_TASK_BAR HOME="$FAKEHOME" COLUMNS=200 \
          bash "$SL" 2>"$TMP/err" | plain)
  else
    out=$(printf '%s' "$pl" | env HOME="$FAKEHOME" COLUMNS=200 \
          STATUSLINE_TASK_BAR="$knob" bash "$SL" 2>"$TMP/err" | plain)
  fi
  printf '%s' "$out" | head -1
}

expect() { # <description> <expected substring> <knob> <payload>
  local desc="$1" want="$2" got
  got=$(line1 "$3" "$4")
  if [ -s "$TMP/err" ]; then
    bad "$desc - statusline wrote to STDERR: $(head -1 "$TMP/err")"
  elif [ -z "$got" ]; then
    bad "$desc - line 1 came out empty"
  elif [[ "$got" == *"$want"* ]]; then
    ok "$desc -> $want"
  else
    bad "$desc - expected [$want] in line 1, got [$got]"
  fi
}

expect_absent() { # <description> <substring that must NOT be there> <knob> <payload>
  local desc="$1" unwanted="$2" got
  got=$(line1 "$3" "$4")
  if [ -s "$TMP/err" ]; then
    bad "$desc - statusline wrote to STDERR: $(head -1 "$TMP/err")"
  elif [ -z "$got" ]; then
    # Without this, a crash would read as "the string is absent" and the case would
    # go green precisely because the script died.
    bad "$desc - line 1 came out empty"
  elif [[ "$got" == *"$unwanted"* ]]; then
    bad "$desc - [$unwanted] should not be on line 1, got [$got]"
  else
    ok "$desc"
  fi
}

expect_ends() { # <description> <expected tail> <knob> <payload>
  local desc="$1" want="$2" got
  got=$(line1 "$3" "$4")
  if [ -z "$got" ]; then
    bad "$desc - line 1 came out empty"
  elif [[ "$got" == *"$want" ]]; then
    ok "$desc -> line 1 ends with $want"
  else
    bad "$desc - line 1 should end with [$want], got [$got]"
  fi
}

suite() {
  echo "== the switch is OFF: nothing changes for anyone who did not ask =="
  mktasks off 4 1
  expect_absent "unset variable"  "4/5" UNSET   "$(payload off '')"
  expect_absent "empty variable"  "4/5" ""      "$(payload off '')"
  expect_absent "0"               "4/5" "0"     "$(payload off '')"
  expect_absent "off"             "4/5" "off"   "$(payload off '')"
  expect_absent "false"           "4/5" "false" "$(payload off '')"
  # Line 2 is full of these blocks, so the absence has to be asserted on line 1 alone.
  expect_absent "no bar on line 1 while off" "█" UNSET "$(payload off '')"

  echo "== switched on, the bar rides at the END of line 1 =="
  expect     "on"          "████░ 4/5" "on"   "$(payload off '')"
  expect     "1"           "████░ 4/5" "1"    "$(payload off '')"
  expect     "true"        "████░ 4/5" "true" "$(payload off '')"
  expect     "ON, upper"   "████░ 4/5" "ON"   "$(payload off '')"
  expect_ends "it is the last thing on the line" "████░ 4/5" on "$(payload off '')"

  echo "== the two ends of the scale are told apart =="
  mktasks full 5 0
  expect "all done"     "█████ 5/5" on "$(payload full '')"
  mktasks none 0 5
  expect "none done"    "░░░░░ 0/5" on "$(payload none '')"

  echo "== five cells must not round into a lie =="
  # 1 of 12 rounds to 0 cells and 11 of 12 rounds to 5. Both are clamped, because an
  # empty bar means "not started" and a full one means "finished", and neither is true.
  mktasks casi_cero 1 11
  expect_absent "1 of 12 is not an empty bar" "░░░░░ 1/12" on "$(payload casi_cero '')"
  expect        "1 of 12 shows one cell"      "█░░░░ 1/12" on "$(payload casi_cero '')"
  mktasks casi_full 11 1
  expect_absent "11 of 12 is not a full bar"  "█████ 11/12" on "$(payload casi_full '')"
  expect        "11 of 12 shows four cells"   "████░ 11/12" on "$(payload casi_full '')"

  echo "== nothing to show is shown as nothing, not as a division by zero =="
  mktasks vacio 0 0
  expect_absent "session with no tasks" "0/0" on "$(payload vacio '')"
  expect_absent "session with no task directory at all" "/" on "$(payload no_existe_esta_sesion '')"

  echo "== named output styles: on only while that adapter is running =="
  mktasks estilo 4 1
  expect        "style matches"              "████░ 4/5" "conciso"        "$(payload estilo Conciso)"
  expect        "style matches, one of many" "████░ 4/5" "otro,conciso"   "$(payload estilo Conciso)"
  expect        "match is case-insensitive"  "████░ 4/5" "CONCISO"        "$(payload estilo conciso)"
  expect_absent "a different style is off"   "4/5"       "conciso"        "$(payload estilo default)"
  expect_absent "no style in the payload"    "4/5"       "conciso"        "$(payload estilo '')"
  # "conc" must not open the door for "conciso": the list is matched whole, not by
  # prefix. A prefix match is how a switch ends up on for names nobody listed.
  expect_absent "a prefix of the name is not the name" "4/5" "conc" "$(payload estilo Conciso)"
}

# ------------------------------------------------------------------ mutants ---
mutants() {
  local backup="$TMP/statusline.orig" name old new before survivors=()
  cp "$SL" "$backup"
  # shellcheck disable=SC2064
  trap "cp '$backup' '$SL'" EXIT

  # The fields are split on "@@", not on "|". M2's anchor is a `case` branch whose own
  # text is full of pipes, and with "|" as the delimiter it silently split in the wrong
  # place: the anchor came out mangled, no match was found, and the mutant reported
  # itself NOT MEASURED instead of dying. A delimiter that can appear inside the data
  # is not a delimiter.
  local specs=(
    'M1 bar computed but never assembled@@"$pend_str" "$task_bar_str"@@"$pend_str"'
    'M2 the switch is ignored and it paints anyway@@""|0|off|false) tb_on="" ;;@@""|0|off|false) tb_on="yes" ;;'
    'M3 a barely-started bar is allowed to read empty@@[ "$t_hecho" -gt 0 ] && [ "$tb_fill" -lt 1 ]@@false'
    'M4 an almost-finished bar is allowed to read full@@[ "$t_hecho" -lt "$t_total" ] && [ "$tb_fill" -ge "$tb_w" ]@@false'
    'M5 the style list matches anything@@*",$tb_style,"*@@*'
  )
  for spec in "${specs[@]}"; do
    name="${spec%%@@*}"
    new="${spec##*@@}"
    old="${spec#*@@}"; old="${old%@@*}"
    if ! grep -qF -- "$old" "$backup"; then
      survivors+=("$name: could not be injected (anchor missing) -> NOT MEASURED")
      continue
    fi
    awk -v o="$old" -v n="$new" '
      { out=""; rest=$0
        while ((i=index(rest,o))>0) { out=out substr(rest,1,i-1) n; rest=substr(rest,i+length(o)) }
        print out rest }
    ' "$backup" > "$SL"
    if cmp -s "$backup" "$SL"; then
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
FAKEHOME="$TMP/home"
mkdir -p "$FAKEHOME"
trap 'rm -rf "$TMP"' EXIT

if [ ! -f "$SL" ]; then
  echo "NOT MEASURED - $SL does not exist"
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
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
printf '\nGREEN - the task bar stays off until asked, and does not lie when on\n'
