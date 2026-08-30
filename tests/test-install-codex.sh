#!/usr/bin/env bash

set -eu

REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

expected='status_line = ["model-with-reasoning", "fast-mode", "git-branch", "context-used", "five-hour-limit", "weekly-limit", "used-tokens"]'

assert_count() {
  expected_count=$1
  file=$2
  actual_count=$(grep -F -c "$expected" "$file" || true)
  if [ "$actual_count" -ne "$expected_count" ]; then
    printf 'Expected %s status line(s) in %s, found %s\n' "$expected_count" "$file" "$actual_count" >&2
    exit 1
  fi
}

# New config.
new_home="$TEST_ROOT/new"
CODEX_HOME="$new_home" bash "$REPO_DIR/install-codex.sh" >/dev/null
assert_count 1 "$new_home/config.toml"
grep -Fx '[tui]' "$new_home/config.toml" >/dev/null

# Existing [tui] settings are preserved and an old status line is replaced.
existing_home="$TEST_ROOT/existing"
mkdir -p "$existing_home"
printf '%s\n' \
  'model = "gpt-test"' \
  '' \
  '[tui]' \
  'animations = false' \
  'status_line = ["model"]' \
  '' \
  '[projects."/tmp/example"]' \
  'trust_level = "trusted"' > "$existing_home/config.toml"
CODEX_HOME="$existing_home" bash "$REPO_DIR/install-codex.sh" >/dev/null
assert_count 1 "$existing_home/config.toml"
grep -Fx 'animations = false' "$existing_home/config.toml" >/dev/null
grep -Fx 'model = "gpt-test"' "$existing_home/config.toml" >/dev/null
grep -Fx 'trust_level = "trusted"' "$existing_home/config.toml" >/dev/null
test "$(find "$existing_home" -name 'config.toml.backup.*' | wc -l | tr -d ' ')" -eq 1

# Re-running is idempotent.
CODEX_HOME="$existing_home" bash "$REPO_DIR/install-codex.sh" >/dev/null
assert_count 1 "$existing_home/config.toml"

# Dotted root-level syntax remains dotted and is replaced once.
dotted_home="$TEST_ROOT/dotted"
mkdir -p "$dotted_home"
printf '%s\n' 'tui.status_line = ["model"]' > "$dotted_home/config.toml"
CODEX_HOME="$dotted_home" bash "$REPO_DIR/install-codex.sh" >/dev/null
grep -Fx "tui.$expected" "$dotted_home/config.toml" >/dev/null

printf 'All Codex installer tests passed.\n'
