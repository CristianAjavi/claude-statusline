#!/usr/bin/env bash
# Claude Code statusLine script
# Input: JSON via stdin from Claude Code
# Output: single compact line

input=$(cat)

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
  filled=$(printf '%.0f' "$(echo "scale=4; $ctx_pct / $bar_total" | bc)")
  [ "$filled" -lt 0 ] 2>/dev/null && filled=0
  [ "$filled" -gt "$bar_total" ] 2>/dev/null && filled=$bar_total
  bar=""
  i=0
  while [ $i -lt "$filled" ]; do bar="${bar}█"; i=$(( i + 1 )); done
  while [ $i -lt "$bar_total" ]; do bar="${bar}░"; i=$(( i + 1 )); done
  ctx_str=$(printf "ctx [%s] %.0f%%" "$bar" "$ctx_pct")
else
  ctx_str=""
fi

# ── 4. Session cost ──────────────────────────────────────────────────────────
cost_raw=$(printf '%s' "$input" | jq -r '.cost.total_cost_usd // .cost // empty')
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
  filled=$(printf '%.0f' "$(echo "scale=4; $rl_5h_pct / $bar_total" | bc)")
  [ "$filled" -lt 0 ] 2>/dev/null && filled=0
  [ "$filled" -gt "$bar_total" ] 2>/dev/null && filled=$bar_total
  bar=""
  i=0
  while [ $i -lt "$filled" ]; do bar="${bar}█"; i=$(( i + 1 )); done
  while [ $i -lt "$bar_total" ]; do bar="${bar}░"; i=$(( i + 1 )); done
  if [ -n "$rl_5h_resets" ]; then
    reset_time=$(date -r "$rl_5h_resets" '+%I:%M%p' 2>/dev/null || date -d "@$rl_5h_resets" '+%I:%M%p' 2>/dev/null)
    reset_time=$(echo "$reset_time" | tr '[:upper:]' '[:lower:]')
    rl_5h_str=$(printf "5h [%s] %.0f%% ⟳%s" "$bar" "$rl_5h_pct" "$reset_time")
  else
    rl_5h_str=$(printf "5h [%s] %.0f%%" "$bar" "$rl_5h_pct")
  fi
fi

# ── 6. Rate limits (7d window) ──────────────────────────────────────────────
rl_7d_pct=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
rl_7d_str=""
if [ -n "$rl_7d_pct" ]; then
  bar_total=10
  filled=$(printf '%.0f' "$(echo "scale=4; $rl_7d_pct / $bar_total" | bc)")
  [ "$filled" -lt 0 ] 2>/dev/null && filled=0
  [ "$filled" -gt "$bar_total" ] 2>/dev/null && filled=$bar_total
  bar=""
  i=0
  while [ $i -lt "$filled" ]; do bar="${bar}█"; i=$(( i + 1 )); done
  while [ $i -lt "$bar_total" ]; do bar="${bar}░"; i=$(( i + 1 )); done
  rl_7d_str=$(printf "7d [%s] %.0f%%" "$bar" "$rl_7d_pct")
fi

# ── Assemble the line, skipping empty segments ────────────────────────────────
parts=()
[ -n "$model_short" ]  && parts+=("$model_short")
[ -n "$git_branch" ]   && parts+=("$git_branch")
[ -n "$ctx_str" ]      && parts+=("$ctx_str")
[ -n "$cost_str" ]     && parts+=("$cost_str")
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
