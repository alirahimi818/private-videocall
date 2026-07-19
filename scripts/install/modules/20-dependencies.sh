#!/usr/bin/env bash
# Installs everything else the installer and the app need: Docker, certbot,
# ufw, gum (from here on, UI switches from plain to gum), jq, openssl,
# dnsutils (for the DNS check module).

# Charm's own documented apt-repo method (https://github.com/charmbracelet/gum
# #installation). The one thing it's missing for an unattended install:
# `gpg --dearmor` tries to talk to a TTY by default and fails with "cannot
# open '/dev/tty'" when there isn't one — `--batch --yes` fixes that without
# needing a different install method.
module__install_gum() {
  if command -v gum >/dev/null 2>&1; then
    return 0
  fi

  if [ "${PVC_DRY_RUN:-0}" = "1" ]; then
    ui::info "[dry-run] would add Charm's apt repo and install gum"
    return 0
  fi

  mkdir -p /etc/apt/keyrings
  curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --batch --yes --dearmor -o /etc/apt/keyrings/charm.gpg
  echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
    > /etc/apt/sources.list.d/charm.list
  apt-get update -qq
  apt-get install -y -qq gum >/dev/null
}

module_dependencies() {
  ui::header "Installing dependencies"

  # curl/ca-certificates are normally already present by this point (install.sh's
  # bootstrap installs them before cloning) — but main.sh is also meant to be
  # runnable directly from an existing clone without going through install.sh,
  # so don't assume it; install them here too if missing.
  if [ "${PVC_DRY_RUN:-0}" = "1" ]; then
    ui::info "[dry-run] would apt-get install: curl ca-certificates gnupg certbot ufw jq openssl dnsutils"
  else
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y -qq curl ca-certificates gnupg certbot ufw jq openssl dnsutils >/dev/null
  fi

  module__install_gum
  ui::init # re-detect UI_MODE now that gum (should be) present

  docker::install

  ui::success "Dependencies installed."
}
