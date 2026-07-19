#!/usr/bin/env bash
# Docker Engine + Compose plugin install/check helpers.

docker::is_installed() {
  command -v docker >/dev/null 2>&1
}

docker::compose_is_available() {
  docker compose version >/dev/null 2>&1
}

docker::install() {
  if docker::is_installed && docker::compose_is_available; then
    ui::info "Docker + Compose plugin already installed."
    return 0
  fi

  ui::info "Installing Docker Engine + Compose plugin (official convenience script)..."
  if [ "${PVC_DRY_RUN:-0}" = "1" ]; then
    ui::info "[dry-run] would run: curl -fsSL https://get.docker.com | sh"
    return 0
  fi

  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sh /tmp/get-docker.sh
  rm -f /tmp/get-docker.sh
  systemctl enable --now docker >/dev/null 2>&1 || true

  if ! docker::is_installed || ! docker::compose_is_available; then
    ui::error "Docker install finished but 'docker compose' still isn't available."
    return 1
  fi
  ui::success "Docker + Compose plugin installed."
}
