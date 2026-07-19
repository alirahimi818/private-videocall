#!/usr/bin/env bash
# Distro detection — this installer intentionally targets Debian/Ubuntu only,
# matching the netplan/ufw/apt assumptions baked into the rest of the stack
# (see README.md and CLAUDE.md).

OS_ID=""
# shellcheck disable=SC2034 # read by modules/00-preflight.sh
OS_VERSION_ID=""

os::detect() {
  if [ ! -f /etc/os-release ]; then
    ui::error "Cannot detect OS: /etc/os-release not found."
    return 1
  fi
  # shellcheck source=/dev/null
  . /etc/os-release
  OS_ID="${ID:-unknown}"
  # shellcheck disable=SC2034 # read by modules/00-preflight.sh
  OS_VERSION_ID="${VERSION_ID:-unknown}"
}

os::require_debian_family() {
  os::detect
  case "$OS_ID" in
    debian|ubuntu) return 0 ;;
    *)
      ui::error "Unsupported OS '$OS_ID'. This installer targets Debian or Ubuntu only."
      return 1
      ;;
  esac
}

os::codename() {
  # shellcheck source=/dev/null
  . /etc/os-release
  echo "${VERSION_CODENAME:-}"
}
