#!/usr/bin/env bash
# Standalone certbot for TURN_DOMAIN — coturn needs its own cert (doesn't
# share Caddy's automatic one for DOMAIN). Skips reissuance if a valid,
# non-expiring-soon cert already exists.

module_turn_cert() {
  ui::header "TURN certificate"
  env::load "$INSTALL_DIR/.env"

  local turn_domain turn_second_ip
  turn_domain="$(env::get TURN_DOMAIN)"
  turn_second_ip="$(env::get TURN_SECOND_IP)"

  if [ -z "$turn_domain" ]; then
    ui::error "TURN_DOMAIN not set — run configuration collection first."
    return 1
  fi

  if certbot::cert_exists "$turn_domain" && ! certbot::cert_expiring_soon "$turn_domain"; then
    ui::success "Valid certbot certificate for $turn_domain already exists."
  else
    local email="${PVC_CERTBOT_EMAIL:-}"
    if [ -z "$email" ] && [ "${PVC_NONINTERACTIVE:-0}" != "1" ]; then
      email="$(ui::input "Email for Let's Encrypt (blank to skip, --register-unsafely-without-email)" "")"
    fi

    ui::info "Issuing certificate for $turn_domain via standalone certbot, bound to $turn_second_ip:80..."
    if ! certbot::issue_standalone "$turn_domain" "$email" "$turn_second_ip"; then
      ui::error "Certificate issuance failed. Common causes: DNS not pointing at $turn_second_ip yet, or port 80 on that IP already in use."
      return 1
    fi
    ui::success "Certificate issued for $turn_domain."
  fi

  if [ "${PVC_DRY_RUN:-0}" = "1" ]; then
    ui::info "[dry-run] would copy /etc/letsencrypt/live/${turn_domain}/{fullchain,privkey}.pem into coturn/certs/"
    return 0
  fi

  certbot::copy_into "$turn_domain" "$INSTALL_DIR/coturn/certs"
  ui::success "Copied certs into coturn/certs/."
}
