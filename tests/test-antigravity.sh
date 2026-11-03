#!/usr/bin/env bash
# Tests for antigravity-statusline.sh:
# Validates model extraction, effort coloring, context window token formatting,
# smart quota matching (Argon WTU, Flash, Pro, Claude 3P), and shared work-time (.kv).
#
# Negative controls / mutants: `bash tests/test-antigravity.sh --mutants`
set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SL="$DIR/antigravity-statusline.sh"

fails=0
ok()  { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=$((fails+1)); }

plain() { sed $'s/\033\\[[0-9;]*m//g'; }

FAKEHOME=$(mktemp -d "${TMPDIR:-/tmp}/agy-test.XXXXXX")
trap 'rm -rf "$FAKEHOME"' EXIT

# Helper to run antigravity-statusline.sh with JSON payload
run_sl() {
  local json="$1" cols="${2:-148}"
  printf '%s' "$json" | jq --argjson c "$cols" '.terminal_width = $c' | WORKTIME_DIR="$FAKEHOME/worktime" COLUMNS="$cols" bash "$SL" 2>/dev/null | plain
}

# Base fixture JSON
base_json() {
  cat << 'EOF'
{
  "cwd": "/Users/macbookair/my-project",
  "email": "user@test.com",
  "plan_tier": "Google AI Pro",
  "model": {
    "id": "Gemini 3.8 Flash (High)",
    "display_name": "Gemini 3.8 Flash (High)",
    "effort": "high"
  },
  "workspace": { "current_dir": "/Users/macbookair/my-project" },
  "context_window": {
    "total_input_tokens": 125000,
    "context_window_size": 1048576,
    "used_percentage": 11.9
  },
  "quota": {
    "3p-5h": { "remaining_fraction": 1.0, "reset_in_seconds": 18000 },
    "3p-weekly": { "remaining_fraction": 1.0, "reset_in_seconds": 604800 },
    "gemini-5h": { "remaining_fraction": 0.97, "reset_in_seconds": 15000 },
    "gemini-argon-wtu-weekly": { "remaining_fraction": 0.005, "reset_in_seconds": 490000 },
    "gemini-weekly": { "remaining_fraction": 0.96, "reset_in_seconds": 560000 }
  },
  "terminal_width": 148
}
EOF
}

# Setup dummy worktime .kv
mkdir -p "$FAKEHOME/worktime"
printf 'version\t1\nlast\t%s\ntotal\t12092\n' "$(date +%s)" > "$FAKEHOME/worktime/$(date +%Y-%m-%d).kv"

echo "== Argon Model Quota Recognition =="
argon_json=$(base_json | jq '.model = {"id":"Gemini 4 Argon (Medium)","display_name":"Gemini 4 Argon (Medium)","effort":"medium"}')
out_argon=$(run_sl "$argon_json" 148)

if printf '%s\n' "$out_argon" | grep -q "gemini-4-argon·medium"; then
  ok "Argon model name and effort badge extracted correctly"
else
  bad "Argon model name failed: got $out_argon"
fi

if printf '%s\n' "$out_argon" | grep -qE "argon \[[^]]*\] 100% ↻5d16h|argon \[[^]]*\] 99% ↻5d16h"; then
  ok "Argon dedicated quota bucket (gemini-argon-wtu-weekly) recognized at 99-100%"
else
  bad "Argon quota bucket failed: got $out_argon"
fi

if printf '%s\n' "$out_argon" | grep -q "5h \["; then
  ok "Argon displays 5h rolling window alongside dedicated weekly quota"
else
  bad "5h window missing for Argon: got $out_argon"
fi

echo "== Standard Gemini (Flash / Pro) Quota Recognition =="
flash_json=$(base_json)
out_flash=$(run_sl "$flash_json" 148)

if printf '%s\n' "$out_flash" | grep -q "gemini-3.8-flash·high"; then
  ok "Flash model and effort badge formatted correctly"
else
  bad "Flash model failed: got $out_flash"
fi

if printf '%s\n' "$out_flash" | grep -q "5h \[" && printf '%s\n' "$out_flash" | grep -q "weekly \["; then
  ok "Flash displays both 5h window and weekly general pool"
else
  bad "Flash quotas missing: got $out_flash"
fi

if ! printf '%s\n' "$out_flash" | grep -q "argon"; then
  ok "Argon does NOT appear when active model is Flash (only active model quotas shown)"
else
  bad "Argon unexpectedly appeared when Flash was active: got $out_flash"
fi

echo "== 3P / Claude Model Quota Recognition =="
claude_json=$(base_json | jq '.model = {"id":"Claude 3.7 Sonnet (High)","display_name":"Claude 3.7 Sonnet (High)","effort":"high"}')
out_claude=$(run_sl "$claude_json" 148)

if printf '%s\n' "$out_claude" | grep -q "claude-3.7-sonnet·high"; then
  ok "Claude Sonnet model formatted correctly"
else
  bad "Claude Sonnet model failed: got $out_claude"
fi

if printf '%s\n' "$out_claude" | grep -q "3p-5h \[" && printf '%s\n' "$out_claude" | grep -q "3p-7d \["; then
  ok "Claude model matches 3p-5h and 3p-7d quota buckets"
else
  bad "Claude 3P quotas failed: got $out_claude"
fi

echo "== Context Window Token Counting =="
if printf '%s\n' "$out_argon" | grep -q "ctx \[[^]]*\] 12%·125k"; then
  ok "Context window formats both percentage and token count (·125k)"
else
  bad "Context window token formatting failed: got $out_argon"
fi

echo "== Shared Work-Time Counter =="
if printf '%s\n' "$out_argon" | grep -q "🕓 3h21m"; then
  ok "Shared worktime reads .kv total (3h21m)"
else
  bad "Worktime .kv reading failed: got $out_argon"
fi

if [ -f "$FAKEHOME/worktime/$(date +%Y-%m-%d)" ]; then
  bad "Statusline wrote legacy uncoordinated file (must be read-only on .kv)"
else
  ok "Statusline does NOT write legacy file; reader is purely read-only"
fi

echo "== Terminal Width Responsiveness =="
out_narrow=$(run_sl "$argon_json" 80)
if printf '%s\n' "$out_narrow" | grep -qE "argon \[[^]]*\] (99%|100%)" && ! printf '%s\n' "$out_narrow" | grep -q "5h \["; then
  ok "Narrow terminal (80 cols) selects the single most critical quota (argon)"
else
  bad "Narrow terminal selection failed: got $out_narrow"
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "ALL GREEN"
  exit 0
else
  echo "FAILURES: $fails"
  exit 1
fi
