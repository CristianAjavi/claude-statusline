#!/usr/bin/env bash
# Detailed Codex usage display based on the latest local session event.

set -eu

SESSIONS_DIR="${CODEX_SESSIONS_DIR:-${CODEX_HOME:-$HOME/.codex}/sessions}"
WATCH=0
INTERVAL=5

usage() {
  printf 'Usage: %s [--watch] [--interval SECONDS]\n' "${0##*/}"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --watch)
      WATCH=1
      shift
      ;;
    --interval)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      INTERVAL=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

case "$INTERVAL" in
  ''|*[!0-9]*) printf 'Interval must be a positive integer.\n' >&2; exit 2 ;;
  0) printf 'Interval must be greater than zero.\n' >&2; exit 2 ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  printf 'jq is required. Install it and try again.\n' >&2
  exit 1
fi

C_RESET=$'\033[0m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_RED=$'\033[31m'
C_DIM=$'\033[2m'

color_for_used() {
  used=${1%.*}
  [ -n "$used" ] || used=0
  if [ "$used" -ge 85 ]; then
    printf '%s' "$C_RED"
  elif [ "$used" -ge 60 ]; then
    printf '%s' "$C_YELLOW"
  else
    printf '%s' "$C_GREEN"
  fi
}

make_bar() {
  used=$1
  total=20
  filled=$(awk -v n="$used" -v d="$total" 'BEGIN { printf "%.0f", n*d/100 }')
  [ "$filled" -lt 0 ] && filled=0
  [ "$filled" -gt "$total" ] && filled=$total
  bar=""
  i=0
  while [ "$i" -lt "$filled" ]; do bar="${bar}█"; i=$((i + 1)); done
  while [ "$i" -lt "$total" ]; do bar="${bar}░"; i=$((i + 1)); done
  printf '%s' "$bar"
}

format_countdown() {
  reset_epoch=$1
  now_epoch=$(date +%s)
  remaining=$((reset_epoch - now_epoch))
  [ "$remaining" -gt 0 ] || { printf '0m'; return; }

  days=$((remaining / 86400))
  hours=$(((remaining % 86400) / 3600))
  minutes=$(((remaining % 3600) / 60))
  if [ "$days" -gt 0 ]; then
    printf '%dd %02dh %02dm' "$days" "$hours" "$minutes"
  elif [ "$hours" -gt 0 ]; then
    printf '%dh %02dm' "$hours" "$minutes"
  else
    printf '%dm' "$minutes"
  fi
}

format_reset_time() {
  reset_epoch=$1
  date -r "$reset_epoch" '+%a %d %b, %I:%M%p' 2>/dev/null || \
    date -d "@$reset_epoch" '+%a %d %b, %I:%M%p' 2>/dev/null || \
    printf '%s' "$reset_epoch"
}

window_label() {
  minutes=$1
  case "$minutes" in
    300) printf '5 horas' ;;
    10080) printf 'Semanal' ;;
    *)
      if [ "$minutes" -ge 1440 ] && [ $((minutes % 1440)) -eq 0 ]; then
        printf '%d días' $((minutes / 1440))
      elif [ "$minutes" -ge 60 ] && [ $((minutes % 60)) -eq 0 ]; then
        printf '%d horas' $((minutes / 60))
      else
        printf '%d minutos' "$minutes"
      fi
      ;;
  esac
}

latest_event() {
  [ -d "$SESSIONS_DIR" ] || return 1
  if command -v rg >/dev/null 2>&1; then
    latest_file=$(rg -l '"type":"token_count"' "$SESSIONS_DIR" 2>/dev/null | sort | tail -n 1)
    [ -n "$latest_file" ] || return 1
    rg --no-filename '"type":"token_count"' "$latest_file" | tail -n 1
  else
    latest_file=$(grep -rl '"type":"token_count"' "$SESSIONS_DIR" 2>/dev/null | sort | tail -n 1)
    [ -n "$latest_file" ] || return 1
    grep -h '"type":"token_count"' "$latest_file" | tail -n 1
  fi
}

render_window() {
  data=$1
  used=$(printf '%s' "$data" | jq -r '.used_percent')
  minutes=$(printf '%s' "$data" | jq -r '.window_minutes')
  reset_epoch=$(printf '%s' "$data" | jq -r '.resets_at')
  available=$(awk -v n="$used" 'BEGIN { printf "%.0f", 100-n }')
  label=$(window_label "$minutes")
  bar=$(make_bar "$used")
  color=$(color_for_used "$used")
  reset_time=$(format_reset_time "$reset_epoch")
  countdown=$(format_countdown "$reset_epoch")

  printf '%-8s %s[%s]%s %3.0f%% usado · %3s%% disponible\n' \
    "$label" "$color" "$bar" "$C_RESET" "$used" "$available"
  printf '         %sReinicio: %s · faltan %s%s\n' \
    "$C_DIM" "$reset_time" "$countdown" "$C_RESET"
}

render() {
  event=$(latest_event || true)
  if [ -z "$event" ]; then
    printf 'No hay datos locales de uso. Envía un mensaje en Codex y vuelve a intentar.\n'
    return
  fi

  rate_limits=$(printf '%s' "$event" | jq -c '.payload.rate_limits // empty')
  if [ -z "$rate_limits" ]; then
    printf 'El último evento de Codex no contiene límites de uso.\n'
    return
  fi

  printf 'Codex · uso del plan\n'
  found=0
  for key in primary secondary; do
    window=$(printf '%s' "$rate_limits" | jq -c --arg key "$key" '.[$key] // empty')
    if [ -n "$window" ]; then
      render_window "$window"
      found=1
    fi
  done

  if [ "$found" -eq 0 ]; then
    printf 'Codex no informó ventanas horarias o semanales en la última respuesta.\n'
  fi
}

if [ "$WATCH" -eq 1 ]; then
  while :; do
    printf '\033[2J\033[H'
    render
    printf '\n%sActualización cada %ss · Ctrl-C para salir%s\n' "$C_DIM" "$INTERVAL" "$C_RESET"
    sleep "$INTERVAL"
  done
else
  render
fi
