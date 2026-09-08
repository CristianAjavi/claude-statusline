#!/usr/bin/env bash
# ONE ENTRY POINT. Detects which AI CLIs this machine actually uses and installs the
# matching status line for each of them. It asks nothing: what is installed is decided
# by what is found, and what is found is printed before anything is touched.
#
# DETECTION, and why it is two signals and not one. A CLI counts as "in use" when its
# binary is on PATH OR its config directory exists. Either alone is wrong: a binary
# behind an alias or a version manager may not be on PATH, and a config directory can
# survive an uninstall. Two signals also mean the report can say WHICH one matched,
# so a wrong guess is visible rather than silent.
#
#   ./install.sh              install for everything detected
#   ./install.sh --dry-run    print what it would do, touch nothing
#   ./install.sh --all        install for all three, detected or not
set -eu

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY=0
ALL=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY=1 ;;
    --all|-a)     ALL=1 ;;
    --help|-h)
      sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

found_any=0
report() { printf '  %-14s %s\n' "$1" "$2"; }

# -- detection --------------------------------------------------------------
detect() { # detect <binary> <config dir>  -> prints the reason, or nothing
  if command -v "$1" >/dev/null 2>&1; then
    printf 'found (%s on PATH)' "$1"
  elif [ -d "$2" ]; then
    printf 'found (%s exists)' "${2/#$HOME/\~}"
  fi
}

claude_why=$(detect claude "${CLAUDE_CONFIG_DIR:-$HOME/.claude}")
codex_why=$(detect codex "${CODEX_HOME:-$HOME/.codex}")
agy_why=$(detect agy "${GEMINI_CONFIG_DIR:-$HOME/.gemini/antigravity-cli}")

echo "Detected:"
report "Claude Code" "${claude_why:-not found}"
report "Codex"       "${codex_why:-not found}"
report "Antigravity" "${agy_why:-not found}"
echo

if [ "$ALL" = "1" ]; then
  claude_why="${claude_why:-forced by --all}"
  codex_why="${codex_why:-forced by --all}"
  agy_why="${agy_why:-forced by --all}"
fi

if [ -z "$claude_why" ] && [ -z "$codex_why" ] && [ -z "$agy_why" ]; then
  # Nothing found is a result, not a reason to install blindly: a status line wired
  # into a CLI that is not there is a config file nobody asked for.
  echo "No supported AI CLI found. Nothing installed." >&2
  echo "Use --all to install anyway." >&2
  exit 1
fi

run() { # run <label> <script...>
  found_any=1
  if [ "$DRY" = "1" ]; then
    echo "[dry-run] would run: ${*:2}"
  else
    echo "== $1"
    bash "${@:2}"
    echo
  fi
}

[ -n "$claude_why" ] && run "Claude Code" "$DIR/install-claude.sh"
[ -n "$codex_why" ]  && run "Codex"       "$DIR/install-codex.sh"
[ -n "$agy_why" ]    && run "Antigravity" "$DIR/install-antigravity.sh"

# The work-time counter is shared by all three: it counts hours across every AI tool,
# so it is installed once, whichever CLI was found. It skips itself off macOS.
run "Work-time counter" "$DIR/tools/worktime/install.sh"

[ "$DRY" = "1" ] && echo "(dry run: nothing was written)"
exit 0
