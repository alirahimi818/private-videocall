#!/usr/bin/env bash
# Root check (redundant with install.sh's, but this module can also be
# invoked directly from an existing clone), OS check, and routing to the
# management menu if this server is already installed.

module_preflight() {
  if [ "$(id -u)" -ne 0 ]; then
    ui::error "This installer must run as root."
    exit 1
  fi

  os::require_debian_family || exit 1
  ui::info "Detected OS: $OS_ID $OS_VERSION_ID"

  if state::is_installed "$INSTALL_DIR"; then
    ui::info "Existing installation detected at $INSTALL_DIR — opening the management menu instead of reinstalling."
    exec "$INSTALL_DIR/scripts/manage.sh"
  fi
}
