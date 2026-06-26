#!/usr/bin/env bash
# Claude Code statusLine script
# Input: JSON via stdin from Claude Code
# Output: single compact line
#
# Cross-platform (macOS / Linux / Windows Git-Bash). Requires: jq, git, awk, date.

# ── 0. Locate jq if installed via winget but PATH wasn't refreshed (Windows) ──
if ! command -v jq >/dev/null 2>&1; then
  for d in \
    "$HOME/AppData/Local/Microsoft/WinGet/Links" \
    "$HOME/AppData/Local/Microsoft/WinGet/Packages"/jqlang.jq_*; do
    [ -d "$d" ] && PATH="$PATH:$d"
  done
fi

input=$(cat)

# ── Color por umbral (ANSI) ───────────────────────────────────────────────────
C_RESET=$'\033[0m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_RED=$'\033[31m'
C_PURPLE=$'\033[38;5;135m'   # morado neón (256-color)
# color_for_pct <porcentaje>  →  verde <60, amarillo 60-84, rojo >=85
color_for_pct() {
  local p=${1%.*}          # quita decimales
  [ -z "$p" ] && p=0
  if   [ "$p" -ge 85 ]; then printf '%s' "$C_RED"
  elif [ "$p" -ge 60 ]; then printf '%s' "$C_YELLOW"
  else                       printf '%s' "$C_GREEN"
  fi
}

# ── 1. Model: strip leading "claude-" prefix ──────────────────────────────────
model_raw=$(printf '%s' "$input" | jq -r '.model.id // ""')
model_short="${model_raw#claude-}"

# ── 2. Git branch (only if cwd is inside a repo) ─────────────────────────────
cwd=$(printf '%s' "$input" | jq -r '.cwd // .workspace.current_dir // ""')
git_branch=""
if [ -n "$cwd" ]; then
  branch=$(git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)
  [ -n "$branch" ] && git_branch="$branch"
fi

# ── 3. Context window bar ────────────────────────────────────────────────────
ctx_pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$ctx_pct" ]; then
  bar_total=10
  filled=$(awk -v n="$ctx_pct" -v d="$bar_total" 'BEGIN{printf "%.0f", n/d}')
  [ "$filled" -lt 0 ] 2>/dev/null && filled=0
  [ "$filled" -gt "$bar_total" ] 2>/dev/null && filled=$bar_total
  bar=""
  i=0
  while [ $i -lt "$filled" ]; do bar="${bar}█"; i=$(( i + 1 )); done
  while [ $i -lt "$bar_total" ]; do bar="${bar}░"; i=$(( i + 1 )); done
  c=$(color_for_pct "$ctx_pct")
  ctx_str=$(printf "%sctx [%s] %.0f%%%s" "$c" "$bar" "$ctx_pct" "$C_RESET")
else
  ctx_str=""
fi

# ── 4. Session cost ──────────────────────────────────────────────────────────
cost_raw=$(printf '%s' "$input" | jq -r '(.cost.total_cost_usd // (.cost | numbers)) // empty')
if [ -n "$cost_raw" ]; then
  cost_str=$(printf 'chat $%.2f' "$cost_raw")
else
  cost_str=""
fi

# ── 5. Rate limits (5h window) with reset time ──────────────────────────────
rl_5h_pct=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
rl_5h_resets=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
rl_5h_str=""
if [ -n "$rl_5h_pct" ]; then
  bar_total=10
  filled=$(awk -v n="$rl_5h_pct" -v d="$bar_total" 'BEGIN{printf "%.0f", n/d}')
  [ "$filled" -lt 0 ] 2>/dev/null && filled=0
  [ "$filled" -gt "$bar_total" ] 2>/dev/null && filled=$bar_total
  bar=""
  i=0
  while [ $i -lt "$filled" ]; do bar="${bar}█"; i=$(( i + 1 )); done
  while [ $i -lt "$bar_total" ]; do bar="${bar}░"; i=$(( i + 1 )); done
  if [ -n "$rl_5h_resets" ]; then
    # GNU date (Linux/Git-Bash): -d @epoch ; BSD date (macOS): -r epoch
    reset_time=$(date -d "@$rl_5h_resets" '+%I:%M%p' 2>/dev/null || date -r "$rl_5h_resets" '+%I:%M%p' 2>/dev/null)
    reset_time=$(echo "$reset_time" | tr '[:upper:]' '[:lower:]')
    # ── Cuenta regresiva: tiempo restante hasta el reinicio ──
    now=$(date +%s)
    rem=$(( rl_5h_resets - now ))
    if [ "$rem" -gt 0 ]; then
      rem_h=$(( rem / 3600 ))
      rem_m=$(( (rem % 3600) / 60 ))
      countdown=$(printf '%dh%02dm' "$rem_h" "$rem_m")
    else
      countdown="0h00m"
    fi
    c=$(color_for_pct "$rl_5h_pct")
    rl_5h_str=$(printf "%s5h [%s] %.0f%% ⟳%s (%s)%s" "$c" "$bar" "$rl_5h_pct" "$reset_time" "$countdown" "$C_RESET")
  else
    c=$(color_for_pct "$rl_5h_pct")
    rl_5h_str=$(printf "%s5h [%s] %.0f%%%s" "$c" "$bar" "$rl_5h_pct" "$C_RESET")
  fi
fi

# ── 6. Rate limits (7d window) ──────────────────────────────────────────────
rl_7d_pct=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
rl_7d_str=""
if [ -n "$rl_7d_pct" ]; then
  bar_total=10
  filled=$(awk -v n="$rl_7d_pct" -v d="$bar_total" 'BEGIN{printf "%.0f", n/d}')
  [ "$filled" -lt 0 ] 2>/dev/null && filled=0
  [ "$filled" -gt "$bar_total" ] 2>/dev/null && filled=$bar_total
  bar=""
  i=0
  while [ $i -lt "$filled" ]; do bar="${bar}█"; i=$(( i + 1 )); done
  while [ $i -lt "$bar_total" ]; do bar="${bar}░"; i=$(( i + 1 )); done
  c=$(color_for_pct "$rl_7d_pct")
  rl_7d_str=$(printf "%s7d [%s] %.0f%%%s" "$c" "$bar" "$rl_7d_pct" "$C_RESET")
fi

# ── 7. Tiempo total de trabajo en máquina HOY (heartbeat, incluye tools) ─────
# Suma los huecos entre redibujados de la barra que sean < IDLE_LIMIT.
# Huecos mayores = tiempo muerto y no se cuentan. Se reinicia cada día.
# Es un total general de la máquina: todas las sesiones comparten el mismo
# archivo diario, así que no duplica el tiempo de ventanas en paralelo.
wt_dir="$HOME/.claude/worktime"
mkdir -p "$wt_dir" 2>/dev/null
wt_file="$wt_dir/$(date +%Y-%m-%d)"
now_epoch=$(date +%s)
IDLE_LIMIT=300            # 5 min sin actividad = idle, no cuenta
last=0; acc=0
[ -f "$wt_file" ] && read -r last acc < "$wt_file" 2>/dev/null
[ -z "$last" ] && last=0
[ -z "$acc" ]  && acc=0
if [ "$last" -gt 0 ] 2>/dev/null; then
  gap=$(( now_epoch - last ))
  if [ "$gap" -ge 0 ] && [ "$gap" -lt "$IDLE_LIMIT" ]; then
    acc=$(( acc + gap ))
  fi
fi
printf '%s %s\n' "$now_epoch" "$acc" > "$wt_file"
day_h=$(( acc / 3600 ))
day_m=$(( (acc % 3600) / 60 ))
day_str=$(printf "%s🕓 %dh%02dm%s" "$C_PURPLE" "$day_h" "$day_m" "$C_RESET")

# ── Assemble the line, skipping empty segments ────────────────────────────────
parts=()
[ -n "$model_short" ]  && parts+=("$model_short")
[ -n "$git_branch" ]   && parts+=("$git_branch")
[ -n "$ctx_str" ]      && parts+=("$ctx_str")
[ -n "$cost_str" ]     && parts+=("$cost_str")
[ -n "$day_str" ]      && parts+=("$day_str")
[ -n "$rl_5h_str" ]    && parts+=("$rl_5h_str")
[ -n "$rl_7d_str" ]    && parts+=("$rl_7d_str")

# Join with " | "
result=""
for part in "${parts[@]}"; do
  if [ -z "$result" ]; then
    result="$part"
  else
    result="$result | $part"
  fi
done

printf '%s' "$result"
