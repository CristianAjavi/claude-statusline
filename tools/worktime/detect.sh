#!/usr/bin/env bash
# Detector of LIVE AI TOOLS on the machine.
#
# Isolated in its own function on purpose: this is the piece that can go BLIND -a
# binary gets renamed and the detector answers "none" without failing- so it needs
# its own positive and negative controls (see tests/test-worktime.sh). It reads the
# output of `ps` from STDIN instead of calling it, which is the only thing that lets
# a test feed it synthetic lines and prove it can still see the YES.
#
# Each pattern matches the BASENAME of the executable, anchored at both ends: without
# the anchors "claude" would also match "claudette" and the counter would run on an
# idle machine.
#
# bash 3.2 (the one macOS ships): no associative arrays, and no `${arr[@]}` over an
# empty array under `set -u`. Space-separated strings are the only thing that behaves
# identically in 3.2 and 5.x.

# tool:basename-regex. Adding a line is all it takes.
AI_PATTERNS='claude:^claude$
codex:^codex(-[a-z-]+)?$
agy:^(agy|agy-bin|antigravity|Antigravity)$
gemini:^gemini$
cursor:^cursor-agent$
copilot:^(copilot|gh-copilot)$
aider:^aider$
opencode:^opencode$
amp:^amp$'

# active_ais < <output of `ps -Ao comm=`>
# Prints, one per line and without repeats, the key of every tool detected.
active_ais() {
  local line base key pattern pair seen=" "
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    base="${line##*/}"           # path -> basename
    base="${base%% *}"           # in case arguments come glued on
    base="${base#-}"             # login shells: "-zsh"
    while IFS= read -r pair; do
      [ -z "$pair" ] && continue
      key="${pair%%:*}"
      pattern="${pair#*:}"
      if [[ "$base" =~ $pattern ]]; then
        case "$seen" in *" $key "*) ;; *) seen="$seen$key " ;; esac
      fi
    done <<< "$AI_PATTERNS"
  done
  # No matches -> prints nothing and exits 0. "No AI running" is a valid result, not
  # an error; the one that can fail to MEASURE is tick.sh, and it says so with its
  # own state, not with this silence.
  for key in $seen; do printf '%s\n' "$key"; done
}

# ps_ai: the real source. Kept separate so the tests can avoid it.
ps_ai() { ps -Ao comm= 2>/dev/null; }
