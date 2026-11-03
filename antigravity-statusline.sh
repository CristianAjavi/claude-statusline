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

if   [ "$term_cols" -ge 115 ] 2>/dev/null; then bar_total=8
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

# ── 4. Modelo activo (simplificado con nivel de esfuerzo coloreado) ─────────
model_raw=$(printf '%s' "$input" | jq -r '.model.display_name // .model.id // ""')
effort_json=$(printf '%s' "$input" | jq -r '.model.effort // empty')
if [ -n "$effort_json" ]; then
  effort=$(printf '%s' "$effort_json" | tr '[:upper:]' '[:lower:]')
else
  effort=$(printf '%s' "$model_raw" | grep -ioE "\(high\)|\(medium\)|\(low\)" | tr -d '()' | tr '[:upper:]' '[:lower:]' || true)
fi

model_base=$(printf '%s' "$model_raw" | sed -E 's/ \((high|medium|low)\)//I' | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
[ -z "$model_base" ] && model_base="$model_raw"

case "$effort" in
  low|medium) effort_col=$C_GREEN ;;
  high)       effort_col=$C_YELLOW ;;
  xhigh|max)  effort_col=$C_RED ;;
  ultra*)     effort_col=$C_PURPLE ;;
  *)          effort_col=$C_GRAY ;;
esac

if [ -n "$effort" ]; then
  model_short="${model_base}${C_GRAY}·${effort_col}${effort}${C_RESET}"
else
  model_short="$model_base"
fi

# ── 5. Barra de Context Window con conteo de tokens ─────────────────────────
ctx_pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
ctx_tok=$(printf '%s' "$input" | jq -r '.context_window.total_input_tokens // empty')
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

  tok_str=""
  if [ -n "$ctx_tok" ] && [ "$ctx_tok" -gt 0 ] 2>/dev/null; then
    tok_str=$(awk -v t="$ctx_tok" 'BEGIN{printf "·%.0fk", t/1000}')
  fi

  ctx_str=$(printf "%sctx [%s] %.0f%%%s%s" "$c" "$bar" "$ctx_pct" "$tok_str" "$C_RESET")
fi

# ── 6. Rate limits / Cuotas inteligentes por modelo ─────────────────────────
format_quota_segment() {
  local lbl="$1"
  local used_pct="$2"
  local resets_in="$3"
  local unmetered="$4"
  local bt="${5:-$bar_total}"

  if [ "$unmetered" = "true" ] || [ -z "$used_pct" ]; then
    printf "%s%s [∞]%s" "$C_GREEN" "$lbl" "$C_RESET"
    return
  fi

  local filled bar i c
  filled=$(awk -v n="$used_pct" -v d="$bt" 'BEGIN{printf "%.0f", n*d/100}')
  [ "$filled" -lt 0 ] 2>/dev/null && filled=0
  [ "$filled" -gt "$bt" ] 2>/dev/null && filled=$bt
  bar=""
  i=0
  while [ $i -lt "$filled" ]; do bar="${bar}█"; i=$(( i + 1 )); done
  while [ $i -lt "$bt" ]; do bar="${bar}░"; i=$(( i + 1 )); done
  c=$(color_for_pct "$used_pct")

  local countdown=""
  if [ -n "$resets_in" ] && [ "$resets_in" -gt 0 ] 2>/dev/null; then
    local rem_d=$(( resets_in / 86400 ))
    local rem_h=$(( (resets_in % 86400) / 3600 ))
    local rem_m=$(( (resets_in % 3600) / 60 ))
    if [ "$rem_d" -gt 0 ]; then
      countdown=$(printf ' ↻%dd%02dh' "$rem_d" "$rem_h")
    else
      countdown=$(printf ' ↻%dh%02dm' "$rem_h" "$rem_m")
    fi
  fi

  printf "%s%s [%s] %.0f%%%s%s" "$c" "$lbl" "$bar" "$used_pct" "$countdown" "$C_RESET"
}

mid=$(printf '%s' "$model_raw" | tr '[:upper:]' '[:lower:]')

q_parsed=$(printf '%s' "$input" | jq -c --arg mid "$mid" '
  (.quota // {}) as $q |
  def get_entry($k; $lbl):
    if ($q[$k] != null) then
      {
        label: $lbl,
        bucket: $k,
        used_pct: (if $q[$k].remaining_fraction != null then ((1 - $q[$k].remaining_fraction) * 100) else null end),
        resets_in: ($q[$k].reset_in_seconds // null),
        unmetered: ($q[$k].remaining_fraction == null)
      }
    else null end;

  if ($q | length == 0) then
    { short: { label: "quota", bucket: "unmetered", used_pct: null, resets_in: null, unmetered: true }, long: null, extra: null }
  elif ($mid | contains("argon")) then
    {
      short: get_entry("gemini-5h"; "5h"),
      long: (get_entry("gemini-argon-wtu-weekly"; "argon") // get_entry("gemini-weekly"; "weekly")),
      extra: (
        if ($q["gemini-argon-wtu-weekly"] != null and $q["gemini-weekly"] != null) then
          get_entry("gemini-weekly"; "weekly")
        else null end
      )
    }
  elif ($mid | contains("claude") or ($mid | contains("sonnet")) or ($mid | contains("opus")) or ($mid | contains("3p"))) then
    {
      short: get_entry("3p-5h"; "3p-5h"),
      long: get_entry("3p-weekly"; "3p-7d"),
      extra: null
    }
  elif ($mid | contains("gemini") or ($mid | contains("flash")) or ($mid | contains("pro"))) then
    {
      short: get_entry("gemini-5h"; "5h"),
      long: get_entry("gemini-weekly"; "weekly"),
      extra: null
    }
  else
    # Fallback genérico para modelos custom o nuevos (no muestra argon si el modelo no es argon)
    ($q | to_entries | map(select((.key | contains("argon") | not) or ($mid | contains("argon")))) | map({
      label: (
        if (.key | contains("5h")) then "5h"
        elif (.key | contains("argon")) then "argon"
        elif (.key | contains("weekly")) then "weekly"
        else "quota" end
      ),
      bucket: .key,
      used_pct: (if .value.remaining_fraction != null then ((1 - .value.remaining_fraction) * 100) else null end),
      resets_in: (.value.reset_in_seconds // null),
      unmetered: (.value.remaining_fraction == null)
    })) as $all |
    {
      short: ($all[0] // null),
      long: ($all[1] // null),
      extra: null
    }
  end
' 2>/dev/null)

s_lbl=$(printf '%s' "$q_parsed" | jq -r '.short.label // empty' 2>/dev/null)
s_pct=$(printf '%s' "$q_parsed" | jq -r '.short.used_pct // empty' 2>/dev/null)
s_rst=$(printf '%s' "$q_parsed" | jq -r '.short.resets_in // empty' 2>/dev/null)
s_unm=$(printf '%s' "$q_parsed" | jq -r '.short.unmetered // false' 2>/dev/null)

l_lbl=$(printf '%s' "$q_parsed" | jq -r '.long.label // empty' 2>/dev/null)
l_pct=$(printf '%s' "$q_parsed" | jq -r '.long.used_pct // empty' 2>/dev/null)
l_rst=$(printf '%s' "$q_parsed" | jq -r '.long.resets_in // empty' 2>/dev/null)
l_unm=$(printf '%s' "$q_parsed" | jq -r '.long.unmetered // false' 2>/dev/null)

e_lbl=$(printf '%s' "$q_parsed" | jq -r '.extra.label // empty' 2>/dev/null)
e_pct=$(printf '%s' "$q_parsed" | jq -r '.extra.used_pct // empty' 2>/dev/null)
e_rst=$(printf '%s' "$q_parsed" | jq -r '.extra.resets_in // empty' 2>/dev/null)
e_unm=$(printf '%s' "$q_parsed" | jq -r '.extra.unmetered // false' 2>/dev/null)

seg_short=""
seg_long=""
seg_extra=""
[ -n "$s_lbl" ] && seg_short=$(format_quota_segment "$s_lbl" "$s_pct" "$s_rst" "$s_unm" "$bar_total")
[ -n "$l_lbl" ] && seg_long=$(format_quota_segment "$l_lbl" "$l_pct" "$l_rst" "$l_unm" "$bar_total")
[ -n "$e_lbl" ] && seg_extra=$(format_quota_segment "$e_lbl" "$e_pct" "$e_rst" "$e_unm" "$bar_total")

# Cuota crítica única para terminales angostos (< 88 columnas)
seg_critical="$seg_short"
if [ -n "$l_pct" ] && [ -n "$s_pct" ]; then
  if awk -v l="$l_pct" -v s="$s_pct" 'BEGIN{exit !(l > s)}' 2>/dev/null; then
    seg_critical="$seg_long"
  fi
elif [ -n "$l_pct" ]; then
  seg_critical="$seg_long"
fi

# ── 7. Background Tasks ─────────────────────────────────────────────────────
task_count=$(printf '%s' "$input" | jq -r '.task_count // 0' 2>/dev/null)
task_str=""
if [ "$task_count" -gt 0 ] 2>/dev/null; then
  task_str="${C_YELLOW}⚙ ${task_count} task(s)${C_RESET}"
fi

# ── 8. Tiempo total de trabajo diario (Heartbeat compartido .kv) ────────────
wt_dir="${WORKTIME_DIR:-$HOME/.claude/worktime}"
wt_kv="$wt_dir/$(date +%Y-%m-%d).kv"
marker="$wt_dir/.installed"
day_str=""

if [ -f "$wt_kv" ]; then
  acc=$(awk -F'\t' '$1=="total"{print $2+0; exit}' "$wt_kv" 2>/dev/null)
  wt_last=$(awk -F'\t' '$1=="last"{print $2+0; exit}' "$wt_kv" 2>/dev/null)
  [ -z "$acc" ] && acc=0
  [ -z "$wt_last" ] && wt_last=0

  day_h=$(( acc / 3600 ))
  day_m=$(( (acc % 3600) / 60 ))
  day_str=$(printf "%s🕓 %dh%02dm%s" "$C_PURPLE" "$day_h" "$day_m" "$C_RESET")

  # Si el demonio no ha emitido latidos en 3 minutos mientras la barra se dibuja, avisar
  if [ -f "$marker" ] && [ "$wt_last" -gt 0 ] 2>/dev/null; then
    now_epoch=$(date +%s)
    if [ $(( now_epoch - wt_last )) -ge 180 ] 2>/dev/null; then
      day_str="${day_str}${C_RED}!${C_RESET}"
    fi
  fi
fi

# ── Ensamblado en DOS líneas ─────────────────────────────────────────────────
# Línea 1 — Dónde estoy: cuenta (plan) | carpeta | rama | [estado]
# Línea 2 — Con qué y cuánto: modelo | contexto | tiempo del día | cuotas | [tareas]
unir() {
  local out="" p
  for p in "$@"; do
    [ -z "$p" ] && continue
    if [ -z "$out" ]; then out="$p"; else out="$out | $p"; fi
  done
  printf '%s' "$out"
}

linea1=$(unir "$account_str" "${dir_str:+$C_CYAN$dir_str$C_RESET}" "${git_branch:+$C_YELLOW$git_branch$C_RESET}" "$state_str")

if [ "$term_cols" -ge 115 ] 2>/dev/null; then
  linea2=$(unir "$model_short" "$ctx_str" "$day_str" "$seg_short" "$seg_long" "$seg_extra" "$task_str")
elif [ "$term_cols" -ge 88 ] 2>/dev/null; then
  linea2=$(unir "$model_short" "$ctx_str" "$day_str" "$seg_short" "$seg_long" "$task_str")
elif [ "$term_cols" -ge 70 ] 2>/dev/null; then
  linea2=$(unir "$model_short" "$ctx_str" "$day_str" "$seg_critical")
else
  linea2=$(unir "$model_short" "$ctx_str" "$seg_critical")
fi

[ -n "$linea1" ] && printf '%s\n' "$linea1"
printf '%s' "$linea2"
