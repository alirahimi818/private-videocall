#!/usr/bin/env bash
# Standalone certbot helpers for the TURN_DOMAIN certificate (coturn needs
# its own cert — it doesn't share Caddy's automatic one, since that's issued
# for a different hostname/IP; see README.md).

certbot::is_installed() {
  command -v certbot >/dev/null 2>&1
}

certbot::cert_exists() {
  local domain="$1"
  [ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]
}

# certbot::cert_expiring_soon <domain> [days, default 30]
certbot::cert_expiring_soon() {
  local domain="$1"
  local days="${2:-30}"
  local cert="/etc/letsencrypt/live/${domain}/fullchain.pem"
  [ -f "$cert" ] || return 0
  ! openssl x509 -in "$cert" -noout -checkend "$((days * 86400))" >/dev/null 2>&1
}

# certbot::issue_standalone <domain> <email> <bind_ip>
# bind_ip pins certbot's temporary standalone server to that specific IP
# (--http-01-address) instead of 0.0.0.0 — matters once Caddy is already
# running and holding PRIMARY_IP:80, since a later renewal run would
# otherwise race it for the same port.
certbot::issue_standalone() {
  local domain="$1" email="$2" bind_ip="${3:-}"
  local staging_flag=""
  [ "${PVC_CERTBOT_STAGING:-0}" = "1" ] && staging_flag="--staging"

  local email_flag=(-m "$email")
  [ -z "$email" ] && email_flag=(--register-unsafely-without-email)

  local bind_flag=()
  [ -n "$bind_ip" ] && bind_flag=(--http-01-address "$bind_ip")

  if [ "${PVC_DRY_RUN:-0}" = "1" ]; then
    ui::info "[dry-run] would run: certbot certonly --standalone --non-interactive --agree-tos ${email_flag[*]} ${bind_flag[*]} -d $domain $staging_flag"
    return 0
  fi

  # shellcheck disable=SC2086
  certbot certonly --standalone --non-interactive --agree-tos \
    "${email_flag[@]}" "${bind_flag[@]}" -d "$domain" $staging_flag
}

# certbot::copy_into <domain> <dest_dir>
certbot::copy_into() {
  local domain="$1" dest="$2"
  mkdir -p "$dest"
  cp "/etc/letsencrypt/live/${domain}/fullchain.pem" "$dest/fullchain.pem"
  cp "/etc/letsencrypt/live/${domain}/privkey.pem" "$dest/privkey.pem"
}

# certbot::install_deploy_hook <hook_source_script> <domain>
# Symlinks the repo's renewal hook script into certbot's own deploy-hooks
# directory, so renewal is driven by certbot's native systemd timer/cron
# rather than a separate reimplementation.
certbot::install_deploy_hook() {
  local hook_source="$1"
  local hook_dest="/etc/letsencrypt/renewal-hooks/deploy/private-videocall-turn-cert.sh"

  if [ "${PVC_DRY_RUN:-0}" = "1" ]; then
    ui::info "[dry-run] would symlink $hook_dest -> $hook_source"
    return 0
  fi

  mkdir -p "$(dirname "$hook_dest")"
  ln -sf "$hook_source" "$hook_dest"
  chmod +x "$hook_source"
  ui::success "Installed certbot renewal deploy-hook -> $hook_dest"
}
