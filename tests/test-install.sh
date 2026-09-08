#!/usr/bin/env bash
# Tests for the detecting installer (install.sh).
#
# The defect this file exists to prevent: a detector that finds nothing and installs
# everything anyway, or one that finds everything because it is looking at the real
# machine instead of the one under test. Every case runs against a throwaway HOME and
# a PATH that contains only what the case is meant to find, and every positive case
# has a negative twin - a detector that always says yes passes no test here.
#
# Nothing is ever installed: every case runs --dry-run, and the assertions read what
# it says it WOULD run.
set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$DIR/install.sh"

fails=0
ok()   { printf '  ok    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; fails=$((fails+1)); }

# run_case <fake home> <fake bin dir> [args...] -> stdout+stderr, sets RC
run_case() {
  local home="$1" bin="$2"; shift 2
  OUT=$(HOME="$home" PATH="$bin:/usr/bin:/bin" bash "$INSTALL" --dry-run "$@" 2>&1)
  RC=$?
}

# A sandbox with a HOME nothing else writes to, and an empty bin dir to put fake CLIs
# in. Real binaries stay out of PATH, which is the only way the negative case means
# anything on a machine that has all three installed.
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
mkbin() { printf '#!/bin/sh\nexit 0\n' > "$1/$2"; chmod +x "$1/$2"; }

echo "== NEGATIVE control: a machine with no AI CLI at all =="
h="$SANDBOX/empty"; b="$SANDBOX/empty-bin"; mkdir -p "$h" "$b"
run_case "$h" "$b"
[ "$RC" -ne 0 ] && ok "exits non-zero" || bad "expected a non-zero exit, got $RC"
case "$OUT" in
  *"Nothing installed"*) ok "says nothing was installed" ;;
  *) bad "expected 'Nothing installed', got: $(printf '%s' "$OUT" | tr '\n' ' ')" ;;
esac
case "$OUT" in
  *"would run"*) bad "it planned to install something on an empty machine" ;;
  *) ok "plans no installation" ;;
esac

echo "== detection by BINARY on PATH, one at a time =="
for pair in "claude:install-claude.sh" "codex:install-codex.sh" "agy:install-antigravity.sh"; do
  bin_name="${pair%%:*}"; script="${pair#*:}"
  h="$SANDBOX/h-$bin_name"; b="$SANDBOX/b-$bin_name"; mkdir -p "$h" "$b"
  mkbin "$b" "$bin_name"
  run_case "$h" "$b"
  case "$OUT" in
    *"$script"*) ok "$bin_name on PATH -> $script" ;;
    *) bad "$bin_name on PATH did not schedule $script" ;;
  esac
  # The negative twin: finding one must not drag in the other two.
  for other in install-claude.sh install-codex.sh install-antigravity.sh; do
    [ "$other" = "$script" ] && continue
    case "$OUT" in
      *"$other"*) bad "$bin_name also pulled in $other" ;;
      *) : ;;
    esac
  done
done
ok "no CLI pulls in the installers of the others"

echo "== detection by CONFIG DIRECTORY, with no binary on PATH =="
for pair in ".claude:install-claude.sh" ".codex:install-codex.sh"; do
  cfg="${pair%%:*}"; script="${pair#*:}"
  h="$SANDBOX/d-$cfg"; b="$SANDBOX/db-$cfg"; mkdir -p "$h/$cfg" "$b"
  run_case "$h" "$b"
  case "$OUT" in
    *"$script"*) ok "~/$cfg exists -> $script" ;;
    *) bad "~/$cfg did not schedule $script" ;;
  esac
done
h="$SANDBOX/d-agy"; b="$SANDBOX/db-agy"; mkdir -p "$h/.gemini/antigravity-cli" "$b"
run_case "$h" "$b"
case "$OUT" in
  *install-antigravity.sh*) ok "~/.gemini/antigravity-cli exists -> install-antigravity.sh" ;;
  *) bad "the Antigravity config dir did not schedule its installer" ;;
esac

echo "== --all installs everything even with nothing detected =="
h="$SANDBOX/all"; b="$SANDBOX/all-bin"; mkdir -p "$h" "$b"
run_case "$h" "$b" --all
n=0
for s in install-claude.sh install-codex.sh install-antigravity.sh; do
  case "$OUT" in *"$s"*) n=$((n+1)) ;; esac
done
[ "$n" = "3" ] && ok "--all schedules the three installers" \
               || bad "--all scheduled $n of 3"
[ "$RC" -eq 0 ] && ok "--all exits 0" || bad "--all exited $RC"

echo "== the work-time counter rides along with any CLI =="
h="$SANDBOX/wt"; b="$SANDBOX/wt-bin"; mkdir -p "$h" "$b"; mkbin "$b" claude
run_case "$h" "$b"
case "$OUT" in
  *tools/worktime/install.sh*) ok "scheduled with a single CLI detected" ;;
  *) bad "the work-time installer was not scheduled" ;;
esac

echo "== a dry run writes nothing =="
h="$SANDBOX/clean"; b="$SANDBOX/clean-bin"; mkdir -p "$h" "$b"; mkbin "$b" claude
before=$(find "$h" | wc -l | tr -d ' ')
run_case "$h" "$b"
after=$(find "$h" | wc -l | tr -d ' ')
[ "$before" = "$after" ] && ok "HOME untouched ($before entries before and after)" \
                         || bad "the dry run created files: $before -> $after"

echo "== REAL install into a sandbox HOME (not a dry run) =="
# Everything above only checked what the installer SAYS it would do. This is the part
# that actually writes, because "preserves your existing settings" is a promise nobody
# here had ever tested. The per-CLI installers are called directly rather than through
# install.sh: the master would also run the work-time installer, and that one wires a
# launchd agent into the real machine, which a test has no business doing.
h="$SANDBOX/real"; mkdir -p "$h/.claude" "$h/.codex" "$h/.gemini/antigravity-cli"
printf '{"model":"opus","permissions":{"allow":["Bash"]}}\n' > "$h/.claude/settings.json"
printf '{"theme":"dark"}\n' > "$h/.gemini/antigravity-cli/settings.json"
printf 'model = "gpt-5"\n\n[tui]\nnotifications = true\n' > "$h/.codex/config.toml"

if HOME="$h" bash "$DIR/install-claude.sh" >/dev/null 2>&1; then
  ok "install-claude.sh exits 0"
else
  bad "install-claude.sh failed"
fi
if command -v jq >/dev/null 2>&1; then
  got=$(jq -r '.statusLine.command // "none"' "$h/.claude/settings.json")
  [ "$got" = "$DIR/statusline.sh" ] && ok "statusLine points at the repo script" \
    || bad "statusLine is [$got]"
  kept=$(jq -r '.permissions.allow[0] // "gone"' "$h/.claude/settings.json")
  [ "$kept" = "Bash" ] && ok "pre-existing Claude settings survived" \
    || bad "existing settings were lost: permissions.allow[0] is [$kept]"
  ls "$h/.claude/settings.json.backup."* >/dev/null 2>&1 \
    && ok "a backup was written" || bad "no backup was written"
fi

if HOME="$h" bash "$DIR/install-antigravity.sh" >/dev/null 2>&1; then
  ok "install-antigravity.sh exits 0"
else
  bad "install-antigravity.sh failed"
fi
if command -v jq >/dev/null 2>&1; then
  kept=$(jq -r '.theme // "gone"' "$h/.gemini/antigravity-cli/settings.json")
  [ "$kept" = "dark" ] && ok "pre-existing Antigravity settings survived" \
    || bad "Antigravity settings were lost: theme is [$kept]"
fi

if HOME="$h" bash "$DIR/install-codex.sh" >/dev/null 2>&1; then
  ok "install-codex.sh exits 0"
else
  bad "install-codex.sh failed"
fi
grep -q '^model = "gpt-5"' "$h/.codex/config.toml" \
  && ok "pre-existing Codex keys survived" || bad "the Codex model key was lost"
grep -q '^notifications = true' "$h/.codex/config.toml" \
  && ok "keys inside [tui] survived" || bad "the [tui] notifications key was lost"
grep -q 'status_line = \[' "$h/.codex/config.toml" \
  && ok "status_line was written into [tui]" || bad "status_line was not written"

echo "== the installed Claude script runs against a real payload =="
# Wiring a path into settings.json proves nothing about whether that path runs. This
# feeds the script the payload shape Claude Code actually sends.
payload='{"session_id":"t","model":{"id":"claude-opus-5"},"context_window":{"total_input_tokens":50000,"used_percentage":5}}'
if line=$(printf '%s' "$payload" | HOME="$h" bash "$DIR/statusline.sh" 2>&1); then
  case "$line" in
    *"["*"]"*) ok "it prints a bar" ;;
    *) bad "no bar in the output: $line" ;;
  esac
  case "$line" in
    *"n/a"*) bad "shows the dead-heartbeat marker with no heartbeat installed" ;;
    *) ok "omits the work-time segment when the heartbeat was never installed" ;;
  esac
else
  bad "statusline.sh failed on a real payload: $line"
fi

echo
if [ "$fails" -eq 0 ]; then echo "ALL GREEN"; exit 0; else echo "$fails FAILURE(S)"; exit 1; fi
