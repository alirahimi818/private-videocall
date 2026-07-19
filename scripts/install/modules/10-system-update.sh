#!/usr/bin/env bash
# Runs first, in plain-bash mode — gum isn't installed yet at this point.

module_system_update() {
  ui::header "System update"

  if [ "${PVC_DRY_RUN:-0}" = "1" ]; then
    ui::info "[dry-run] would run: apt-get update && apt-get -y upgrade"
    return 0
  fi

  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_MODE=a
  apt-get update -qq
  apt-get -y -qq upgrade
  ui::success "System packages up to date."
}
