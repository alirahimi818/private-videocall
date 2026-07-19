#!/usr/bin/env bash
# Sanity-checks DNS before continuing. Deliberately warns rather than
# hard-fails: DNS propagation delay is common, and an EDGE_DOMAIN proxied
# through Cloudflare legitimately won't resolve to PRIMARY_IP directly.

module__resolve() {
  local domain="$1"
  dig +short "$domain" A 2>/dev/null | tail -1
}

module_dns_check() {
  ui::header "DNS check"
  env::load "$INSTALL_DIR/.env"

  local domain primary_ip turn_domain turn_second_ip
  domain="$(env::get DOMAIN)"
  primary_ip="$(env::get PRIMARY_IP)"
  turn_domain="$(env::get TURN_DOMAIN)"
  turn_second_ip="$(env::get TURN_SECOND_IP)"

  local resolved_domain resolved_turn
  resolved_domain="$(module__resolve "$domain")"
  resolved_turn="$(module__resolve "$turn_domain")"

  local mismatch=0

  if [ -z "$resolved_domain" ]; then
    ui::warn "DOMAIN ($domain) doesn't resolve yet."
    mismatch=1
  elif [ "$resolved_domain" != "$primary_ip" ]; then
    ui::warn "DOMAIN ($domain) resolves to $resolved_domain, not PRIMARY_IP ($primary_ip)."
    mismatch=1
  else
    ui::success "DOMAIN resolves correctly."
  fi

  if [ -z "$resolved_turn" ]; then
    ui::warn "TURN_DOMAIN ($turn_domain) doesn't resolve yet."
    mismatch=1
  elif [ "$resolved_turn" != "$turn_second_ip" ]; then
    ui::warn "TURN_DOMAIN ($turn_domain) resolves to $resolved_turn, not TURN_SECOND_IP ($turn_second_ip)."
    mismatch=1
  else
    ui::success "TURN_DOMAIN resolves correctly."
  fi

  if [ "$mismatch" -eq 1 ]; then
    ui::warn "DNS isn't fully in place yet. Caddy's automatic HTTPS and the TURN cert issuance below will fail until it is."
    if ! ui::confirm "Continue anyway?" 0; then
      ui::info "Stopping here — fix DNS and re-run."
      exit 0
    fi
  fi
}
