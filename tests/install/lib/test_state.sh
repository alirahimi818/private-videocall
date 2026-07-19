#!/usr/bin/env bash
# Fixture-based unit tests for scripts/install/lib/state.sh, using a fake
# `docker` shim on PATH so no real Docker install is needed.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURES="$ROOT_DIR/tests/install/fixtures"

# shellcheck source=/dev/null
. "$ROOT_DIR/scripts/install/lib/ui.sh"
# shellcheck source=/dev/null
. "$ROOT_DIR/scripts/install/lib/env.sh"
# shellcheck source=/dev/null
. "$ROOT_DIR/scripts/install/lib/state.sh"

pass=0
fail=0

assert_status() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc (expected exit $expected, got $actual)"
    fail=$((fail + 1))
  fi
}

make_fake_docker_bin() {
  local mode="$1" # "ok" or "fail"
  local bin_dir
  bin_dir="$(mktemp -d)"
  cat > "$bin_dir/docker" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "compose" ]; then
  shift
  if [ "\$1" = "config" ]; then
    [ "$mode" = "ok" ] && exit 0 || exit 1
  fi
  if [ "\$1" = "ps" ]; then
    echo "[]"
    exit 0
  fi
fi
exit 0
EOF
  chmod +x "$bin_dir/docker"
  echo "$bin_dir"
}

# --- no .env at all ---
tmp="$(mktemp -d)"
state::is_installed "$tmp" >/dev/null 2>&1
assert_status "no .env -> not installed" "1" "$?"
rm -rf "$tmp"

# --- placeholder .env ---
tmp="$(mktemp -d)"
cp "$FIXTURES/env.invalid-placeholder" "$tmp/.env"
cp "$FIXTURES/docker-compose.mock.yml" "$tmp/docker-compose.yml"
state::is_installed "$tmp" >/dev/null 2>&1
assert_status "placeholder .env -> not installed" "1" "$?"
rm -rf "$tmp"

# --- valid .env, docker compose config succeeds ---
tmp="$(mktemp -d)"
cp "$FIXTURES/env.valid" "$tmp/.env"
cp "$FIXTURES/docker-compose.mock.yml" "$tmp/docker-compose.yml"
fake_bin="$(make_fake_docker_bin ok)"
PATH="$fake_bin:$PATH" state::is_installed "$tmp" >/dev/null 2>&1
assert_status "valid .env + working compose config -> installed" "0" "$?"
rm -rf "$tmp" "$fake_bin"

# --- valid .env, but docker compose config fails (e.g. bad compose file) ---
tmp="$(mktemp -d)"
cp "$FIXTURES/env.valid" "$tmp/.env"
cp "$FIXTURES/docker-compose.mock.yml" "$tmp/docker-compose.yml"
fake_bin="$(make_fake_docker_bin fail)"
PATH="$fake_bin:$PATH" state::is_installed "$tmp" >/dev/null 2>&1
assert_status "valid .env but compose config fails -> not installed" "1" "$?"
rm -rf "$tmp" "$fake_bin"

echo
echo "state.sh: $pass passed, $fail failed"
exit "$([ "$fail" -eq 0 ] && echo 0 || echo 1)"
