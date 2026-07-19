#!/usr/bin/env bash
# Interactive .env collection. Every field checks a PVC_<KEY> environment
# variable first so a power user can pre-seed values and skip the prompt
# entirely (see PVC_NONINTERACTIVE in lib/ui.sh). Existing .env values (on
# a re-run) are used as defaults rather than silently overwritten —
# TURN_SHARED_SECRET in particular is never regenerated if one already
# exists, since that would break a live coturn/node-service pairing.

# module__ask <key> <prompt> <default> [--password]
module__ask() {
  local key="$1" prompt="$2" default="$3" password="${4:-}"
  local override_var="PVC_${key}"
  local override_value="${!override_var:-}"

  if [ -n "$override_value" ]; then
    echo "$override_value"
    return
  fi

  local current
  current="$(env::get "$key" "$default")"
  ui::input "$prompt" "$current" "$password"
}

module_config_collect() {
  ui::header "Configuration"

  local env_file="$INSTALL_DIR/.env"
  local example_file="$INSTALL_DIR/.env.example"

  env::render_from_example "$example_file" "$env_file"
  env::load "$env_file"

  if env::validate "$env_file" >/dev/null 2>&1; then
    if ! ui::confirm "A valid .env already exists. Re-collect configuration?" 1; then
      ui::info "Keeping existing .env as-is."
      return 0
    fi
  fi

  local detected_ip
  detected_ip="$(network::detect_public_ip)"

  local domain primary_ip edge_domain turn_domain turn_second_ip turn_realm turn_secret turn_min turn_max

  domain="$(module__ask DOMAIN "Public domain for the app (DOMAIN)" "$(env::get DOMAIN)")"
  primary_ip="$(module__ask PRIMARY_IP "Primary public IP (PRIMARY_IP)" "$(env::get PRIMARY_IP "$detected_ip")")"
  edge_domain="$(module__ask EDGE_DOMAIN "Optional CDN-fronted fallback domain (EDGE_DOMAIN, blank to skip)" "$(env::get EDGE_DOMAIN)")"
  turn_domain="$(module__ask TURN_DOMAIN "TURN domain, second IP (TURN_DOMAIN)" "$(env::get TURN_DOMAIN)")"
  turn_second_ip="$(module__ask TURN_SECOND_IP "Second public IP for TURN (TURN_SECOND_IP)" "$(env::get TURN_SECOND_IP)")"
  turn_realm="$(module__ask TURN_REALM "TURN realm" "$(env::get TURN_REALM "$turn_domain")")"

  local existing_secret
  existing_secret="$(env::get TURN_SHARED_SECRET)"
  if [ -n "$existing_secret" ] && [ "$existing_secret" != "change-me-to-a-long-random-value" ]; then
    turn_secret="$existing_secret"
    ui::info "Keeping existing TURN_SHARED_SECRET."
  elif [ -n "${PVC_TURN_SHARED_SECRET:-}" ]; then
    turn_secret="$PVC_TURN_SHARED_SECRET"
  else
    turn_secret="$(env::generate_secret)"
    ui::warn "Generated TURN_SHARED_SECRET: $turn_secret
Save this if you ever need it outside this VPS — it won't be shown again after setup."
  fi

  turn_min="$(module__ask TURN_MIN_PORT "TURN relay port range, min" "$(env::get TURN_MIN_PORT 49160)")"
  turn_max="$(module__ask TURN_MAX_PORT "TURN relay port range, max" "$(env::get TURN_MAX_PORT 49200)")"

  env::set "$env_file" DOMAIN "$domain"
  env::set "$env_file" PRIMARY_IP "$primary_ip"
  env::set "$env_file" EDGE_DOMAIN "$edge_domain"
  env::set "$env_file" TURN_DOMAIN "$turn_domain"
  env::set "$env_file" TURN_SECOND_IP "$turn_second_ip"
  env::set "$env_file" TURN_REALM "$turn_realm"
  env::set "$env_file" TURN_SHARED_SECRET "$turn_secret"
  env::set "$env_file" TURN_MIN_PORT "$turn_min"
  env::set "$env_file" TURN_MAX_PORT "$turn_max"

  if ! env::validate "$env_file"; then
    ui::error "Configuration is still incomplete — see above."
    return 1
  fi

  ui::success ".env written."
}
