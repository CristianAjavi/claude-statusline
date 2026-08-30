#!/usr/bin/env bash
# Antigravity CLI (agy) statusLine script
# Input: JSON via stdin from Antigravity CLI
# Output: 1 or 2 compact formatted status lines with ANSI colors
#
# Cross-platform (macOS / Linux). Requires: jq, git, awk, date.

# ── 0. Locate jq if installed via homebrew or custom PATH ──────────────────────
if ! command -v jq >/dev/null 2>&1; then
  for d in "/opt/homebrew/bin" "/usr/local/bin" "$HOME/.nvm/versions"/*/*/bin; do
    [ -d "$d" ] && PATH="$PATH:$d"
  done
fi

input=$(cat)
[ -z "$input" ] && exit 0

# ── Ancho del terminal → cuánto pueden medir las barras ─────────────────────
term_cols=$(printf '%s' "$input" | jq -r '.terminal_width // empty' 2>/dev/null)
[ -z "$term_cols" ] && term_cols=$COLUMNS
[ -z "$term_cols" ] && term_cols=$(tput cols 2>/dev/null)
[ -z "$term_cols" ] && term_cols=80

if   [ "$term_cols" -ge 100 ] 2>/dev/null; then bar_total=8
elif [ "$term_cols" -ge 88 ]  2>/dev/null; then bar_total=6
else                                            bar_total=4
fi

# ── Color por umbral (ANSI) ───────────────────────────────────────────────────
C_RESET=$'\033[0m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_RED=$'\033[31m'
C_PURPLE=$'\033[38;5;135m'   # morado neón (256-color)
C_CYAN=$'\033[36m'
C_BLUE=$'\033[34m'
C_GRAY=$'\033[90m'

# color_for_pct <porcentaje>  →  verde <60, amarillo 60-84, rojo >=85
color_for_pct() {
  local p=${1%.*}          # quita decimales
  [ -z "$p" ] && p=0
  if   [ "$p" -ge 85 ]; then printf '%s' "$C_RED"
  elif [ "$p" -ge 60 ]; then printf '%s' "$C_YELLOW"
  else                       printf '%s' "$C_GREEN"
  fi
}

# ── 1. Cuenta / Plan Tier ───────────────────────────────────────────────────
email=$(printf '%s' "$input" | jq -r '.email // empty')
account_user="${email%%@*}"
plan_tier=$(printf '%s' "$input" | jq -r '.plan_tier // empty')

account_str=""
if [ -n "$account_user" ]; then
  if [ -n "$plan_tier" ] && [ "$plan_tier" != "null" ]; then
    account_str="${C_CYAN}${account_user}${C_GRAY}(${plan_tier})${C_RESET}"
  else
    account_str="${C_CYAN}${account_user}${C_RESET}"
  fi
elif [ -n "$plan_tier" ] && [ "$plan_tier" != "null" ]; then
  account_str="${C_CYAN}${plan_tier}${C_RESET}"
fi

# ── 2. Carpeta de trabajo (abreviada) ───────────────────────────────────────
cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // ""')
dir_str=""
if [ -n "$cwd" ]; then
  if [ "$cwd" = "$HOME" ]; then
    dir_str="~"
  elif [ "${cwd#$HOME/}" != "$cwd" ]; then
    resto="${cwd#$HOME/}"
    case "$resto" in
      */*/*) dir_str="~/…/$(basename "$(dirname "$cwd")")/$(basename "$cwd")" ;;
      *)     dir_str="~/$resto" ;;
    esac
  elif [ ${#cwd} -le 24 ]; then
    dir_str="$cwd"
  else
    padre=$(basename "$(dirname "$cwd")")
    dir_str="…/${padre:+$padre/}$(basename "$cwd")"
  fi
fi

# ── 3. Git branch (del JSON o de git directo) ───────────────────────────────
git_branch=$(printf '%s' "$input" | jq -r '.vcs.branch // empty')
if [ -z "$git_branch" ] && [ -n "$cwd" ]; then
  git_branch=$(git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null || true)
fi

# ── 3.5 Estado del agente / modo de ejecución ───────────────────────────────
agent_state=$(printf '%s' "$input" | jq -r '.agent_state // empty')
exec_mode=$(printf '%s' "$input" | jq -r '.execution_mode // empty')
state_str=""
if [ "$agent_state" = "thinking" ] || [ "$agent_state" = "working" ]; then
  state_str="${C_YELLOW}⚙ ${agent_state}${C_RESET}"
elif [ -n "$exec_mode" ] && [ "$exec_mode" != "default" ]; then
  state_str="${C_BLUE}${exec_mode}${C_RESET}"
fi

# ── 4. Modelo activo (simplificado con nivel de esfuerzo) ───────────────────
model_raw=$(printf '%s' "$input" | jq -r '.model.display_name // .model.id // ""')
effort=$(printf '%s' "$model_raw" | grep -ioE "\(high\)|\(medium\)|\(low\)" | tr -d '()' | tr '[:upper:]' '[:lower:]' || true)
model_base=$(printf '%s' "$model_raw" | sed -E 's/ \((high|medium|low)\)//I' | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
[ -z "$model_base" ] && model_base="$model_raw"

if [ -n "$effort" ]; then
  model_short="${model_base}${C_GRAY}·${effort}${C_RESET}"
else
  model_short="$model_base"
fi

# ── 5. Barra de Context Window ──────────────────────────────────────────────
ctx_pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
ctx_str=""
if [ -n "$ctx_pct" ]; then
  filled=$(awk -v n="$ctx_pct" -v d="$bar_total" 'BEGIN{printf "%.0f", n*d/100}')
  [ "$filled" -lt 0 ] 2>/dev/null && filled=0
  [ "$filled" -gt "$bar_total" ] 2>/dev/null && filled=$bar_total
  bar=""
  i=0
  while [ $i -lt "$filled" ]; do bar="${bar}█"; i=$(( i + 1 )); done
  while [ $i -lt "$bar_total" ]; do bar="${bar}░"; i=$(( i + 1 )); done
  c=$(color_for_pct "$ctx_pct")
  ctx_str=$(printf "%sctx [%s] %.0f%%%s" "$c" "$bar" "$ctx_pct" "$C_RESET")
fi

# ── 6. Rate limits / Cuota por modelo ────────────────────────────────────────
quota_info=$(printf '%s' "$input" | jq -c '
  .model as $m |
  (($m.id // $m.display_name // "") | ascii_downcase) as $mid |
  .quota as $q |
  if $q == null or ($q | length == 0) then
    { bucket: "none", used_pct: null, resets_in: null, unmetered: true }
  else
    ($q | to_entries | map(
      .key as $k |
      ($k | ascii_downcase) as $k_low |
      select(
        ($mid != "" and ($k_low | contains($mid))) or
        ($mid != "" and ($mid | contains($k_low))) or
        (if ($mid | contains("sonnet")) then ($k_low | contains("sonnet") or contains("claude"))
         elif ($mid | contains("flash")) then ($k_low | contains("flash") or contains("gemini"))
         elif ($mid | contains("pro")) then ($k_low | contains("pro") or contains("gemini"))
         elif ($mid | contains("gemini")) then ($k_low | contains("gemini"))
         else false end)
      )
    ) | .[0]) as $match |
    (if $match != null then $match else ($q | to_entries | .[0]) end) as $target |
    if $target.value.remaining_fraction != null then
      {
        bucket: $target.key,
        used_pct: ((1 - $target.value.remaining_fraction) * 100),
        resets_in: ($target.value.reset_in_seconds // null),
        unmetered: false
      }
    else
      { bucket: $target.key, used_pct: null, resets_in: null, unmetered: true }
    end
  end
' 2>/dev/null)

quota_unmetered=$(printf '%s' "$quota_info" | jq -r '.unmetered // false' 2>/dev/null)
quota_used_pct=$(printf '%s' "$quota_info" | jq -r '.used_pct // empty' 2>/dev/null)
quota_resets_in=$(printf '%s' "$quota_info" | jq -r '.resets_in // empty' 2>/dev/null)
quota_bucket=$(printf '%s' "$quota_info" | jq -r '.bucket // empty' 2>/dev/null)

bucket_label=""
case "$quota_bucket" in
  *sonnet*|*claude*) bucket_label="sonnet" ;;
  *flash*)          bucket_label="flash" ;;
  *pro*)            bucket_label="pro" ;;
  *weekly*)         bucket_label="weekly" ;;
  *)                bucket_label="" ;;
esac

quota_str=""
if [ "$quota_unmetered" = "true" ] || [ "$quota_bucket" = "none" ]; then
  quota_str="${C_GREEN}quota [∞]${C_RESET}"
elif [ -n "$quota_used_pct" ]; then
  filled=$(awk -v n="$quota_used_pct" -v d="$bar_total" 'BEGIN{printf "%.0f", n*d/100}')
  [ "$filled" -lt 0 ] 2>/dev/null && filled=0
  [ "$filled" -gt "$bar_total" ] 2>/dev/null && filled=$bar_total
  bar=""
  i=0
  while [ $i -lt "$filled" ]; do bar="${bar}█"; i=$(( i + 1 )); done
  while [ $i -lt "$bar_total" ]; do bar="${bar}░"; i=$(( i + 1 )); done
  c=$(color_for_pct "$quota_used_pct")

  lbl="quota"
  [ -n "$bucket_label" ] && lbl="$bucket_label"

  if [ -n "$quota_resets_in" ] && [ "$quota_resets_in" -gt 0 ] 2>/dev/null; then
    rem_d=$(( quota_resets_in / 86400 ))
    rem_h=$(( (quota_resets_in % 86400) / 3600 ))
    rem_m=$(( (quota_resets_in % 3600) / 60 ))
    if [ "$rem_d" -gt 0 ]; then
      countdown=$(printf '%dd%02dh' "$rem_d" "$rem_h")
    else
      countdown=$(printf '%dh%02dm' "$rem_h" "$rem_m")
    fi
    quota_str=$(printf "%s%s [%s] %.0f%% ↻%s%s" "$c" "$lbl" "$bar" "$quota_used_pct" "$countdown" "$C_RESET")
  else
    quota_str=$(printf "%s%s [%s] %.0f%%%s" "$c" "$lbl" "$bar" "$quota_used_pct" "$C_RESET")
  fi
fi

# ── 7. Background Tasks ─────────────────────────────────────────────────────
task_count=$(printf '%s' "$input" | jq -r '.task_count // 0')
task_str=""
if [ "$task_count" -gt 0 ] 2>/dev/null; then
  task_str="${C_YELLOW}⚙ ${task_count} task(s)${C_RESET}"
fi

# ── 8. Tiempo total de trabajo diario (Heartbeat compartido) ────────────────
wt_dir="$HOME/.claude/worktime"
mkdir -p "$wt_dir" 2>/dev/null
wt_file="$wt_dir/$(date +%Y-%m-%d)"
now_epoch=$(date +%s)
IDLE_LIMIT=300            # 5 min sin actividad = idle
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
printf '%s %s\n' "$now_epoch" "$acc" > "$wt_file" 2>/dev/null || true
day_h=$(( acc / 3600 ))
day_m=$(( (acc % 3600) / 60 ))
day_str=$(printf "%s🕓 %dh%02dm%s" "$C_PURPLE" "$day_h" "$day_m" "$C_RESET")

# ── Ensamblado en DOS líneas ─────────────────────────────────────────────────
# Línea 1 — Dónde estoy: cuenta (plan) | carpeta | rama | [estado]
# Línea 2 — Con qué y cuánto: modelo | contexto | tiempo del día | cuota | [tareas]
unir() {
  local out="" p
  for p in "$@"; do
    [ -z "$p" ] && continue
    if [ -z "$out" ]; then out="$p"; else out="$out | $p"; fi
  done
  printf '%s' "$out"
}

linea1=$(unir "$account_str" "${dir_str:+$C_CYAN$dir_str$C_RESET}" "${git_branch:+$C_YELLOW$git_branch$C_RESET}" "$state_str")

if [ "$term_cols" -lt 80 ] 2>/dev/null; then
  linea2=$(unir "$model_short" "$ctx_str" "$day_str")
else
  linea2=$(unir "$model_short" "$ctx_str" "$day_str" "$quota_str" "$task_str")
fi

[ -n "$linea1" ] && printf '%s\n' "$linea1"
printf '%s' "$linea2"
