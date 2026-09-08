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

# ── Ancho del terminal → cuánto pueden medir las barras ─────────────────────
# La línea de medidores lleva tres barras. Si el terminal es estrecho se parte y
# entonces no se ve lo que se quería ver. Se estrechan las barras antes que perder
# información. Si no se puede medir el ancho, se asume estrecho: mejor corto que roto.
term_cols=$COLUMNS
[ -z "$term_cols" ] && term_cols=$(tput cols 2>/dev/null)
[ -z "$term_cols" ] && term_cols=80
# THRESHOLDS MEASURED, not guessed. The worst reasonable case for this line is level
# "medium" -- the longest name -- with all three bars at 100 %, i.e. three-digit
# figures. That case was run against this very script at eight terminal widths, and
# line 2 measured:
#   8-wide bars + 7-day window ... 115 columns
#   4-wide bars + 7-day window ... 103
#   4-wide bars, no 7-day .......  79
# Hence the two cuts. The previous ones (100 and 88) date from when the effort was
# abbreviated to two letters, and were already too generous back then: at 100 columns
# the line measured 104 and wrapped anyway. The 7-day cut is applied in the assembly.
if   [ "$term_cols" -ge 115 ] 2>/dev/null; then bar_total=8
else                                            bar_total=4
fi

# ── Color por umbral (ANSI) ───────────────────────────────────────────────────
C_RESET=$'\033[0m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_RED=$'\033[31m'
C_PURPLE=$'\033[38;5;135m'   # morado neón (256-color)
C_CYAN=$'\033[36m'
# color_for_pct <porcentaje>  →  verde <60, amarillo 60-84, rojo >=85
color_for_pct() {
  local p=${1%.*}          # quita decimales
  [ -z "$p" ] && p=0
  if   [ "$p" -ge 85 ]; then printf '%s' "$C_RED"
  elif [ "$p" -ge 60 ]; then printf '%s' "$C_YELLOW"
  else                       printf '%s' "$C_GREEN"
  fi
}

# ── 0.5 Cuenta de la sesión (correo) ─────────────────────────────────────────
# El JSON del statusLine NO trae el correo (verificado en el bundle 2.1.234),
# así que se lee de la config de Claude Code: oauthAccount.emailAddress.
cfg_json="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"
[ -f "$cfg_json" ] || cfg_json="$HOME/.claude.json"
account_email=""
[ -f "$cfg_json" ] && account_email=$(jq -r '.oauthAccount.emailAddress // empty' "$cfg_json" 2>/dev/null)
[ -z "$account_email" ] && [ -n "$ANTHROPIC_API_KEY" ] && account_email="api-key"
account_user="${account_email%%@*}"   # sin el dominio, para ahorrar espacio
account_str=""
[ -n "$account_user" ] && account_str="${C_CYAN}${account_user}${C_RESET}"

# ── 1. Model: strip leading "claude-" prefix ──────────────────────────────────
model_raw=$(printf '%s' "$input" | jq -r '.model.id // ""')
model_short="${model_raw#claude-}"

# -- 1.5 Effort: the reasoning effort level -----------------------------------
# WHY IT BELONGS ON THE BAR. A turn's cost is not set by the model alone, it is set
# by the pair model x effort: on the same opus-5, going from high to xhigh changes
# the reasoning tokens spent per turn. Without seeing the effort there is nothing to
# forecast the cost of a run with, which is why it is painted RIGHT NEXT to the
# model: they are one decision.
#
# WHERE IT COMES FROM, AND WHY NOT FROM settings.json. The statusLine payload carries
# effort.level ALREADY RESOLVED (measured on bundle 2.1.263 by capturing a real
# payload). On the machine this was written on, settings.json had effortLevel="high"
# globally and modelSettings["claude-opus-5"].effortLevel="xhigh", and the payload
# said "xhigh": reading settings.json would give the WRONG value whenever a per-model
# override exists. On top of that the effective level VARIES within a single session
# -the same capture saw xhigh and max on different turns- and no setting on disk
# reflects that. So the payload wins. settings.json is only the fallback for an older
# CLI that does not send the field, and there the same precedence is applied.
#
# THIRD VALUE. If neither source has it, the gap is NOT swallowed and no value is
# assumed: it paints "n/m" (not measured) in red. A blank space would read as
# "no extra effort", which is the opposite of what a missing value means.
effort_raw=$(printf '%s' "$input" | jq -r '.effort.level // empty')
if [ -z "$effort_raw" ]; then
  # The modelSettings key carries NO context-window suffix: the payload says
  # "claude-opus-5[1m]" while the setting key is "claude-opus-5".
  model_key="${model_raw%%[*}"
  effort_raw=$(jq -r --arg m "$model_key" \
    '(.modelSettings[$m].effortLevel // .effortLevel) // empty' \
    "${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}" 2>/dev/null)
fi
# Colour tracks what it costs, so the expensive levels stand out without reading.
# ULTRACODE. On bundle 2.1.263 ultracode is not one more level: it is a session
# switch meaning "xhigh plus standing workflow orchestration" -- literally
# U={ultracode:"xhigh"} in the code -- so with ultracode on, the payload might say
# "ultracode" or might already say "xhigh". WHICH ONE IS NOT MEASURED here, because
# measuring it means turning ultracode on in a live session. Both entrances are
# wired: the literal level below, and the standalone boolean right after. If it
# arrives either way it shows; if it arrives neither way the bar says "xhigh", which
# is the effort actually being spent and therefore not a lie.
case "$effort_raw" in
  low)       effort_lbl="low";    effort_col=$C_GREEN  ;;
  medium)    effort_lbl="medium"; effort_col=$C_GREEN  ;;
  high)      effort_lbl="high";   effort_col=$C_YELLOW ;;
  xhigh)     effort_lbl="xhigh";  effort_col=$C_RED    ;;
  max)       effort_lbl="max";    effort_col=$C_RED    ;;
  # "ultra", not "ultracode": it is the only name shortened here, and it is
  # shortened because those four characters sit on a line already competing with
  # two quota windows.
  ultracode) effort_lbl="ultra";  effort_col=$C_PURPLE ;;
  "")        effort_lbl="n/m";    effort_col=$C_RED    ;;
  # A level not on this list is NOT dropped and NOT truncated: it is painted WHOLE,
  # in purple. Truncating to three letters is how this read before, and a half name
  # is easy to mistake for a known one; whole, it reads as "the CLI shipped something".
  *)         effort_lbl="$effort_raw"; effort_col=$C_PURPLE ;;
esac
# Ultracode's second entrance: a boolean alongside the level. If the CLI sends it that
# way it wins over the level, because "ultracode" describes what is being spent better
# than the "xhigh" it translates to.
if [ "$(printf '%s' "$input" | jq -r '(.ultracode // .effort.ultracode) // empty')" = "true" ]; then
  effort_lbl="ultra"; effort_col=$C_PURPLE
fi
effort_str=$(printf "%s%s%s" "$effort_col" "$effort_lbl" "$C_RESET")

# Model and effort travel as a single field. If the payload carried no model, the
# effort still shows: making sure it appears is the whole point of this block.
if [ -n "$model_short" ]; then
  model_str="$model_short $effort_str"
else
  model_str="$effort_str"
fi

# ── 2. Git branch (only if cwd is inside a repo) ─────────────────────────────
cwd=$(printf '%s' "$input" | jq -r '.cwd // .workspace.current_dir // ""')
git_branch=""
if [ -n "$cwd" ]; then
  branch=$(git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)
  [ -n "$branch" ] && git_branch="$branch"
fi

# ── 2.5 Carpeta de trabajo (abreviada) ───────────────────────────────────────
dir_str=""
if [ -n "$cwd" ]; then
  if [ "$cwd" = "$HOME" ]; then
    dir_str="~"
  elif [ "${cwd#$HOME/}" != "$cwd" ]; then
    resto="${cwd#$HOME/}"
    # dentro de casa: ~/my-project, y si anida mucho, ~/…/lotus/motores
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

# ── 3. Context window bar ────────────────────────────────────────────────────
# THE BAR MEASURES TOWARDS AUTO-COMPACT, not towards the end of the window. The payload
# ships used_percentage computed against context_window_size, but compaction does not
# wait for the window to fill: it fires at `autoCompactWindow` (settings.json). With a
# 1M window and a 250k compact threshold, compaction hits at ~22% of the window, so a
# bar drawn against the window sits near a quarter full at the very moment it is about
# to compact -and any "you should compact" nudge placed above that never fires at all.
# When autoCompactWindow is not set, the code falls back to the plain window bar.
ctx_pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
ctx_tok=$(printf '%s' "$input" | jq -r '.context_window.total_input_tokens // empty')
acw=$(jq -r '.autoCompactWindow // empty' "$HOME/.claude/settings.json" 2>/dev/null)
ctx_cpt=""
if [ -n "$ctx_tok" ] && [ -n "$acw" ] && [ "$acw" -gt 0 ] 2>/dev/null; then
  ctx_cpt=1
  ctx_pct=$(awk -v t="$ctx_tok" -v w="$acw" 'BEGIN{p=t*100/w; printf "%.0f", (p>100?100:p)}')
fi
if [ -n "$ctx_pct" ]; then
  filled=$(awk -v n="$ctx_pct" -v d="$bar_total" 'BEGIN{printf "%.0f", n*d/100}')
  [ "$filled" -lt 0 ] 2>/dev/null && filled=0
  [ "$filled" -gt "$bar_total" ] 2>/dev/null && filled=$bar_total
  bar=""
  i=0
  while [ $i -lt "$filled" ]; do bar="${bar}█"; i=$(( i + 1 )); done
  while [ $i -lt "$bar_total" ]; do bar="${bar}░"; i=$(( i + 1 )); done
  c=$(color_for_pct "$ctx_pct")
  if [ -n "$ctx_cpt" ]; then
    # Only what changes a decision fits on this line:
    #   bar + %   how close the next compaction is, at a glance
    #   ·NNk      tokens left before the cut - the number you actually decide with
    #             ("do I send this instruction now, or compact first?")
    # The window percentage is deliberately NOT shown: with a fixed window and a fixed
    # threshold it is a constant fraction of the number already on screen.
    # Label is "cpt", not "compact": four characters back on a crowded line, and it
    # stays distinct from "ctx", which is the fallback bar measuring the window.
    ctx_rest=$(awk -v t="$ctx_tok" -v w="$acw" 'BEGIN{r=w-t; printf "%.0f", (r<0?0:r)/1000}')
    ctx_str=$(printf "%scpt [%s] %.0f%%·%sk%s" \
      "$c" "$bar" "$ctx_pct" "$ctx_rest" "$C_RESET")
    # Past 85% compaction is imminent. Worth knowing: an instruction typed in this band
    # gets folded into the summary as background rather than as a live order.
    if awk -v n="$ctx_pct" 'BEGIN{exit !(n>=85)}'; then
      ctx_str="${ctx_str} ${C_RED}◂now${C_RESET}"
    fi
  else
    ctx_str=$(printf "%sctx [%s] %.0f%%%s" "$c" "$bar" "$ctx_pct" "$C_RESET")
  fi

  # FALLBACK PATH ONLY. When the payload carries no total_input_tokens the bar is
  # back to measuring the window, and then it has to say what to do about it: past
  # CTX_COMPACT_NUDGE% it appends `/compact`. On the `cpt` path this nudge would be
  # noise -the bar already measures the distance to the cut.
  nudge_pct=${CTX_COMPACT_NUDGE:-50}
  if [ -z "$ctx_cpt" ] && awk -v n="$ctx_pct" -v u="$nudge_pct" 'BEGIN{exit !(n>=u)}'; then
    ctx_str="${ctx_str} ${C_YELLOW:-}/compact${C_RESET}"
  fi
else
  ctx_str=""
fi

# ── 4. Costo de la sesión: retirado a propósito (no se muestra) ──────────────

# ── 5. Rate limits (5h window) with reset time ──────────────────────────────
rl_5h_pct=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
rl_5h_resets=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
rl_5h_str=""
if [ -n "$rl_5h_pct" ]; then
  filled=$(awk -v n="$rl_5h_pct" -v d="$bar_total" 'BEGIN{printf "%.0f", n*d/100}')
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
    rl_5h_str=$(printf "%s5h [%s] %.0f%% ↻%s%s" "$c" "$bar" "$rl_5h_pct" "$countdown" "$C_RESET")
  else
    c=$(color_for_pct "$rl_5h_pct")
    rl_5h_str=$(printf "%s5h [%s] %.0f%%%s" "$c" "$bar" "$rl_5h_pct" "$C_RESET")
  fi
fi

# ── 6. Rate limits (7d window) with reset date ──────────────────────────────
rl_7d_pct=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
rl_7d_resets=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
rl_7d_str=""
if [ -n "$rl_7d_pct" ]; then
  filled=$(awk -v n="$rl_7d_pct" -v d="$bar_total" 'BEGIN{printf "%.0f", n*d/100}')
  [ "$filled" -lt 0 ] 2>/dev/null && filled=0
  [ "$filled" -gt "$bar_total" ] 2>/dev/null && filled=$bar_total
  bar=""
  i=0
  while [ $i -lt "$filled" ]; do bar="${bar}█"; i=$(( i + 1 )); done
  while [ $i -lt "$bar_total" ]; do bar="${bar}░"; i=$(( i + 1 )); done
  c=$(color_for_pct "$rl_7d_pct")
  if [ -n "$rl_7d_resets" ]; then
    # Fecha de reinicio (ej. "jul 08 06:00pm"). GNU date: -d @epoch ; BSD date (macOS): -r epoch
    reset_date=$(date -d "@$rl_7d_resets" '+%b %d %I:%M%p' 2>/dev/null || date -r "$rl_7d_resets" '+%b %d %I:%M%p' 2>/dev/null)
    reset_date=$(echo "$reset_date" | tr '[:upper:]' '[:lower:]')
    # ── Cuenta regresiva: tiempo restante hasta el reinicio (días/horas/min) ──
    now=$(date +%s)
    rem=$(( rl_7d_resets - now ))
    if [ "$rem" -gt 0 ]; then
      rem_d=$(( rem / 86400 ))
      rem_h=$(( (rem % 86400) / 3600 ))
      rem_m=$(( (rem % 3600) / 60 ))
      if [ "$rem_d" -gt 0 ]; then
        countdown=$(printf '%dd%02dh' "$rem_d" "$rem_h")
      else
        countdown=$(printf '%dh%02dm' "$rem_h" "$rem_m")
      fi
    else
      countdown="0h00m"
    fi
    rl_7d_str=$(printf "%s7d [%s] %.0f%% ↻%s%s" "$c" "$bar" "$rl_7d_pct" "$countdown" "$C_RESET")
  else
    rl_7d_str=$(printf "%s7d [%s] %.0f%%%s" "$c" "$bar" "$rl_7d_pct" "$C_RESET")
  fi
fi

# ── 7. Time worked with AI today (every tool, not just this one) ───────
# THIS BAR NO LONGER COUNTS: IT ONLY READS.
#
# The counter used to be a heartbeat of this very script, and this script only runs
# when Claude Code repaints its bar. Measured consequence: hours spent in Codex or
# Antigravity NEVER entered the number -on a day with all three open, the detector
# saw three tools while the figure reflected one. A counter bound to the program it
# measures cannot measure the others.
#
# The heartbeat now lives outside, in tools/worktime/tick.sh, run every 60 s by
# launchd, and it is the ONLY writer. Here we read. Two writers would double-count
# the time inside Claude windows and single-count everywhere else, which is the same
# bias wearing a different hat.
#
# macOS ONLY: the heartbeat needs the HID idle time, and `ioreg` is the only portable
# way to get it on a Mac. install.sh skips it elsewhere, and this block then leaves
# the segment out entirely rather than showing a permanent red marker.
wt_dir="$HOME/.claude/worktime"
wt_kv="$wt_dir/$(date +%Y-%m-%d).kv"
day_str=""
if [ -f "$wt_kv" ]; then
  acc=$(awk -F'\t' '$1=="total"{print $2+0; exit}' "$wt_kv" 2>/dev/null)
  wt_last=$(awk -F'\t' '$1=="last"{print $2+0; exit}' "$wt_kv" 2>/dev/null)
  [ -z "$acc" ] && acc=0
  [ -z "$wt_last" ] && wt_last=0
  day_h=$(( acc / 3600 )); day_m=$(( (acc % 3600) / 60 ))
  # THIRD VALUE. A dead heartbeat freezes the figure, and a frozen figure looks
  # exactly like a quiet day. If nothing has been written for over 3 minutes WHILE
  # this bar is repainting -that is, while work is demonstrably happening- it is
  # flagged with a red `!`. Reinstall with: bash tools/worktime/install.sh
  wt_now=$(date +%s)
  if [ $(( wt_now - wt_last )) -gt 180 ] 2>/dev/null; then
    day_str=$(printf "%s🕓 %dh%02dm%s!%s" "$C_PURPLE" "$day_h" "$day_m" "$C_RED" "$C_RESET")
  else
    day_str=$(printf "%s🕓 %dh%02dm%s" "$C_PURPLE" "$day_h" "$day_m" "$C_RESET")
  fi
elif [ -f "$HOME/.claude/worktime/.installed" ]; then
  # The heartbeat IS installed but wrote no file for today: that is a real failure
  # and it gets said out loud. Without the marker file we cannot tell this apart
  # from "never installed", so the segment is simply absent above.
  day_str=$(printf "%s🕓 n/a%s" "$C_RED" "$C_RESET")
fi


# ── 7.5 Aviso de registro: RETIRADO ─────────────────────────────────────────
# Mientras se trabaja, la intervención en curso todavía no está marcada, así que
# el aviso saltaba siempre: falso positivo estructural. Quien vigila eso es el
# hook Stop `cierre-tanda.py`, que bloquea el cierre. La barra no repite trabajo.

# ── 7.6 Open tasks of THIS terminal ─────────────────────────────
# Counts ONLY the tasks of this session (~/.claude/tasks/<session_id>/). Reading a
# global backlog here was a mistake worth naming: two unrelated terminals then showed
# the same count, which tells you nothing about the window you are looking at.
# The terminal paints this bar, not the prompt: it costs 0 context tokens.
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
pend_str=""
if [ -n "$sid" ]; then
  task_dir="$HOME/.claude/tasks/$sid"
  if [ -d "$task_dir" ]; then
    t_pend=$(grep -l '"status": *"pending"' "$task_dir"/*.json 2>/dev/null | wc -l | tr -d ' ')
    t_curso=$(grep -l '"status": *"in_progress"' "$task_dir"/*.json 2>/dev/null | wc -l | tr -d ' ')
    t_open=$((t_pend + t_curso))
    plural="tasks"; [ "$t_open" = "1" ] && plural="task"
    if [ "$t_open" -gt 0 ] 2>/dev/null; then
      if [ "$t_curso" -gt 0 ] 2>/dev/null; then
        pend_str=$(printf "%s⏳ %d %s · %d running%s" "$C_YELLOW" "$t_open" "$plural" "$t_curso" "$C_RESET")
      else
        pend_str=$(printf "%s⏳ %d %s%s" "$C_GREEN" "$t_open" "$plural" "$C_RESET")
      fi
    fi
  fi
fi


# -- 7.7 Task progress bar, at the END of line 1 (SHIPPED OFF) ----------------
# WHY IT EXISTS. An output style that renders a progress table spends OUTPUT tokens
# every turn to say "4 of 5 done". The terminal can paint the same thing for free:
# this bar costs 0 context tokens. So the progress lives here and the style can stop
# printing it. It is deliberately narrow -- 5 cells, not the 20 of a text table --
# because it rides at the end of a line that already carries account, path and branch.
#
# WHY IT SHIPS OFF. Nobody who installed this asked for a progress bar, and a segment
# that turns up uninvited is a regression for them. It is wired but not switched on.
# STATUSLINE_TASK_BAR is the switch:
#   unset | 0 | off | false   nothing is painted            (the default)
#   1 | on | true             always painted
#   <names>                   comma-separated output-style names; painted only while
#                             the payload's output_style.name is one of them -- which
#                             is how "only when I am running that output adapter" is
#                             said, since the adapter is exactly what stops printing
#                             its own table.
task_bar_str=""
tb_mode=$(printf '%s' "${STATUSLINE_TASK_BAR:-}" | tr '[:upper:]' '[:lower:]')
tb_on=""
case "$tb_mode" in
  ""|0|off|false) tb_on="" ;;
  1|on|true)      tb_on="yes" ;;
  *)
    tb_style=$(printf '%s' "$input" | jq -r '.output_style.name // empty' \
               | tr '[:upper:]' '[:lower:]')
    if [ -n "$tb_style" ]; then
      case ",$tb_mode," in
        *",$tb_style,"*) tb_on="yes" ;;
      esac
    fi
    ;;
esac
if [ -n "$tb_on" ] && [ -n "$task_dir" ] && [ -d "$task_dir" ]; then
  t_hecho=$(grep -l '"status": *"completed"' "$task_dir"/*.json 2>/dev/null | wc -l | tr -d ' ')
  t_total=$(( t_open + t_hecho ))
  if [ "$t_total" -gt 0 ] 2>/dev/null; then
    tb_w=5
    tb_fill=$(awk -v n="$t_hecho" -v t="$t_total" -v w="$tb_w" 'BEGIN{printf "%.0f", n*w/t}')
    # Two clamps, both about not lying at a glance. Rounding to 5 cells is coarse
    # enough that 1 of 12 rounds to an EMPTY bar and 11 of 12 rounds to a FULL one --
    # "nothing started" and "all done" are precisely the two readings that change what
    # you do next, so neither may be shown unless it is true.
    if [ "$t_hecho" -gt 0 ] && [ "$tb_fill" -lt 1 ]; then tb_fill=1; fi
    if [ "$t_hecho" -lt "$t_total" ] && [ "$tb_fill" -ge "$tb_w" ]; then
      tb_fill=$(( tb_w - 1 ))
    fi
    tb_bar=""
    i=0
    while [ $i -lt "$tb_fill" ]; do tb_bar="${tb_bar}█"; i=$(( i + 1 )); done
    while [ $i -lt "$tb_w" ];    do tb_bar="${tb_bar}░"; i=$(( i + 1 )); done
    # Green only when there is nothing left to do; yellow while work is open. The
    # usual color_for_pct is not reused on purpose: there a high number is bad, here
    # a high number is the goal, and reusing it would paint "almost finished" red.
    tb_col=$C_YELLOW
    [ "$t_hecho" = "$t_total" ] && tb_col=$C_GREEN
    task_bar_str=$(printf "%s%s %d/%d%s" "$tb_col" "$tb_bar" "$t_hecho" "$t_total" "$C_RESET")
  fi
fi

# ── Ensamblado en DOS líneas ─────────────────────────────────────────────────
# Línea 1 — dónde estoy: cuenta | carpeta | rama.
# Línea 2 — con qué y cuánto llevo: modelo | contexto | tiempo del día | ventanas 5h y 7d.
# El CLI pinta una fila por cada línea que imprime el script (doc oficial).
unir() {  # une los argumentos no vacíos con " | "
  local out="" p
  for p in "$@"; do
    [ -z "$p" ] && continue
    if [ -z "$out" ]; then out="$p"; else out="$out | $p"; fi
  done
  printf '%s' "$out"
}

linea1=$(unir "$account_str" "${dir_str:+$C_CYAN$dir_str$C_RESET}" "${git_branch:+$C_YELLOW$git_branch$C_RESET}" "$pend_str" "$task_bar_str")
if [ "$term_cols" -lt 103 ] 2>/dev/null; then
  # 103 is what the line measures once the bars are already narrow: below that it does
  # not fit even so, and the 7-day window is dropped -- the least urgent one -- rather
  # than letting the line wrap. This read 80 until it was measured: between 80 and 102
  # columns the line still wrapped.
  linea2=$(unir "$model_str" "$ctx_str" "$day_str" "$rl_5h_str")
else
  linea2=$(unir "$model_str" "$ctx_str" "$day_str" "$rl_5h_str" "$rl_7d_str")
fi

[ -n "$linea1" ] && printf '%s\n' "$linea1"
printf '%s' "$linea2"
