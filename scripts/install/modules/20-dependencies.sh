#!/usr/bin/env bash
# Installs everything else the installer and the app need: Docker, certbot,
# ufw, gum (from here on, UI switches from plain to gum), jq, openssl,
# dnsutils (for the DNS check module).

module__install_gum() {
  if command -v gum >/dev/null 2>&1; then
    return 0
  fi

  if [ "${PVC_DRY_RUN:-0}" = "1" ]; then
    ui::info "[dry-run] would add Charm's apt repo and install gum"
    return 0
  fi

  mkdir -p /etc/apt/keyrings
  curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg
  echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
    > /etc/apt/sources.list.d/charm.list
  apt-get update -qq
  apt-get install -y -qq gum >/dev/null
}

module_dependencies() {
  ui::header "Installing dependencies"

  if [ "${PVC_DRY_RUN:-0}" = "1" ]; then
    ui::info "[dry-run] would apt-get install: certbot ufw jq openssl dnsutils gnupg"
  else
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y -qq certbot ufw jq openssl dnsutils gnupg >/dev/null
  fi

  module__install_gum
  ui::init # re-detect UI_MODE now that gum (should be) present

  docker::install

  ui::success "Dependencies installed."
}
