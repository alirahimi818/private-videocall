#!/usr/bin/env bash
# Fixture-based unit tests for scripts/install/lib/env.sh — no root,
# docker, or network required.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURES="$ROOT_DIR/tests/install/fixtures"

# shellcheck source=/dev/null
. "$ROOT_DIR/scripts/install/lib/ui.sh"
# shellcheck source=/dev/null
. "$ROOT_DIR/scripts/install/lib/env.sh"

pass=0
fail=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc (expected '$expected', got '$actual')"
    fail=$((fail + 1))
  fi
}

assert_status() {
  local desc="$1" expected="$2" actual="$3"
  assert_eq "$desc" "$expected" "$actual"
}

# --- env::load / env::get ---
env::load "$FIXTURES/env.valid"
assert_eq "load: DOMAIN" "pvc.example.org" "$(env::get DOMAIN)"
assert_eq "load: TURN_MIN_PORT" "49160" "$(env::get TURN_MIN_PORT)"
assert_eq "load: unset key returns default" "fallback" "$(env::get NOPE fallback)"

# --- env::validate ---
env::validate "$FIXTURES/env.valid" >/dev/null 2>&1
assert_status "validate: valid fixture passes" "0" "$?"

env::validate "$FIXTURES/env.invalid-placeholder" >/dev/null 2>&1
assert_status "validate: placeholder fixture fails" "1" "$?"

# --- env::set (on a scratch copy, so fixtures stay pristine) ---
tmp="$(mktemp -d)"
cp "$FIXTURES/env.invalid-placeholder" "$tmp/.env"
env::set "$tmp/.env" DOMAIN "call.real-domain.com"
env::load "$tmp/.env"
assert_eq "set: value updated" "call.real-domain.com" "$(env::get DOMAIN)"
assert_eq "set: comments preserved" "1" "$(grep -c '^# Public domain' "$tmp/.env")"
assert_eq "set: other keys untouched" "203.0.113.1" "$(grep '^PRIMARY_IP=' "$tmp/.env" | cut -d= -f2)"

env::set "$tmp/.env" NEW_KEY "new-value"
env::load "$tmp/.env"
assert_eq "set: new key appended" "new-value" "$(env::get NEW_KEY)"
rm -rf "$tmp"

# --- env::generate_secret ---
secret="$(env::generate_secret)"
assert_eq "generate_secret: length" "64" "${#secret}"

# --- env::render_from_example ---
tmp="$(mktemp -d)"
env::render_from_example "$ROOT_DIR/.env.example" "$tmp/.env"
assert_eq "render_from_example: copied" "0" "$([ -f "$tmp/.env" ] && echo 0 || echo 1)"
echo "MODIFIED=1" >> "$tmp/.env"
env::render_from_example "$ROOT_DIR/.env.example" "$tmp/.env"
assert_eq "render_from_example: doesn't overwrite existing" "1" "$(grep -c '^MODIFIED=1' "$tmp/.env")"
rm -rf "$tmp"

echo
echo "env.sh: $pass passed, $fail failed"
exit "$([ "$fail" -eq 0 ] && echo 0 || echo 1)"
