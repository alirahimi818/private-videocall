#!/usr/bin/env bash

module_compose_up() {
  ui::header "Building and starting"

  if [ "${PVC_DRY_RUN:-0}" = "1" ]; then
    ui::info "[dry-run] would run: docker compose build && docker compose up -d"
    return 0
  fi

  (cd "$INSTALL_DIR" && ui::spin "Building images..." -- docker compose build)
  (cd "$INSTALL_DIR" && docker compose up -d)

  ui::success "Containers started."
}
