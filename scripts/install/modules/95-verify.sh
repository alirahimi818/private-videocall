#!/usr/bin/env bash

module_verify() {
  ui::header "Verifying"

  if [ "${PVC_DRY_RUN:-0}" = "1" ]; then
    ui::info "[dry-run] skipping verification."
    return 0
  fi

  env::load "$INSTALL_DIR/.env"
  local domain
  domain="$(env::get DOMAIN)"

  ui::info "Waiting for containers to report healthy/running..."
  local tries=0
  local ok=0
  while [ "$tries" -lt 15 ]; do
    if (cd "$INSTALL_DIR" && docker compose ps --status running --format json 2>/dev/null | grep -q coturn) \
       && (cd "$INSTALL_DIR" && docker compose ps --status running --format json 2>/dev/null | grep -q node-service) \
       && (cd "$INSTALL_DIR" && docker compose ps --status running --format json 2>/dev/null | grep -q caddy); then
      ok=1
      break
    fi
    sleep 2
    tries=$((tries + 1))
  done

  if [ "$ok" -eq 0 ]; then
    ui::error "Not all containers reached the running state. Check: docker compose logs"
    return 1
  fi
  ui::success "coturn, node-service, and caddy are all running."

  ui::info "Checking https://$domain/ ..."
  local http_code
  http_code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://${domain}/" || echo "000")"
  if [ "$http_code" = "200" ]; then
    ui::success "https://$domain/ responded 200."
  else
    ui::warn "https://$domain/ responded '$http_code' (expected 200) — may just be DNS/cert propagation delay. Try again in a minute."
  fi
}
