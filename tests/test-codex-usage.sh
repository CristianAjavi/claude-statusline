#!/usr/bin/env bash

set -eu

REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FIXTURE_DIR="$REPO_DIR/tests/fixtures"
output=$(NO_COLOR=1 CODEX_SESSIONS_DIR="$FIXTURE_DIR" bash "$REPO_DIR/codex-usage.sh")

printf '%s' "$output" | grep -F '5 horas' >/dev/null
printf '%s' "$output" | grep -F '35% usado' >/dev/null
printf '%s' "$output" | grep -F '65% disponible' >/dev/null
printf '%s' "$output" | grep -F 'Semanal' >/dev/null
printf '%s' "$output" | grep -F '22% usado' >/dev/null
printf '%s' "$output" | grep -F '78% disponible' >/dev/null
printf '%s' "$output" | grep -F 'Reinicio:' >/dev/null

printf 'Codex usage tests passed.\n'
