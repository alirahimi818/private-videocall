#!/usr/bin/env bash
# ufw setup. See lib/firewall.sh for the SSH-lockout-safe ordering this
# relies on: SSH is always allowed and verified before ufw is ever enabled.

module_firewall() {
  ui::header "Firewall (ufw)"
  env::load "$INSTALL_DIR/.env"

  if ! command -v ufw >/dev/null 2>&1; then
    ui::warn "ufw not installed — skipping firewall setup."
    return 0
  fi

  firewall::ensure_ssh_allowed || return 1

  local turn_second_ip turn_min turn_max
  turn_second_ip="$(env::get TURN_SECOND_IP)"
  turn_min="$(env::get TURN_MIN_PORT 49160)"
  turn_max="$(env::get TURN_MAX_PORT 49200)"

  firewall::allow_turn_ports "$turn_second_ip" "$turn_min" "$turn_max"

  ui::info "Note: Caddy's ports (80/443 on PRIMARY_IP) are Docker published-ports and bypass ufw's INPUT chain entirely — no ufw rule is needed or added for them. Only coturn's ports (network_mode: host) go through ufw."

  firewall::enable_if_confirmed
}
