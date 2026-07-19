#!/usr/bin/env bash
# Single source of truth for "is this already installed", shared by
# 00-preflight.sh (routes to manage.sh) and manage.sh itself.

# Deliberately doesn't require containers to be *running* — a stack the
# user manually stopped should still route to the management menu, not
# trigger a fresh-install flow over existing config.
state::is_installed() {
  local dir="${1:-$INSTALL_DIR}"
  [ -f "$dir/.env" ] || return 1
  env::validate "$dir/.env" >/dev/null 2>&1 || return 1
  (cd "$dir" && docker compose config -q) >/dev/null 2>&1 || return 1
  return 0
}

state::compose_status() {
  local dir="${1:-$INSTALL_DIR}"
  (cd "$dir" && docker compose ps)
}
