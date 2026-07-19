#!/usr/bin/env bash
# ERR trap that reports which module/line/command failed, instead of a bare
# "set -e" exit with no context.

CURRENT_MODULE="(startup)"
INSTALL_LOG=""

trap::install() {
  INSTALL_LOG="$1"
  trap 'trap::on_error $? "$CURRENT_MODULE" "$LINENO" "$BASH_COMMAND"' ERR
}

trap::on_error() {
  local exit_code="$1" module="$2" line="$3" command="$4"
  ui::error "Install failed in module '$module' (line $line): $command (exit $exit_code)"
  if [ -n "$INSTALL_LOG" ]; then
    ui::error "Full log: $INSTALL_LOG"
  fi
  exit "$exit_code"
}
