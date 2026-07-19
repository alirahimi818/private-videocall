#!/usr/bin/env bash

module_summary() {
  env::load "$INSTALL_DIR/.env"
  local domain edge_domain turn_domain secret
  domain="$(env::get DOMAIN)"
  edge_domain="$(env::get EDGE_DOMAIN)"
  turn_domain="$(env::get TURN_DOMAIN)"
  secret="$(env::get TURN_SHARED_SECRET)"

  local masked_secret="${secret:0:4}...${secret: -4}"

  local body
  body="Install complete.

App:        https://${domain}/"
  [ -n "$edge_domain" ] && body="${body}
Fallback:   https://${edge_domain}/"
  body="${body}
TURN:       ${turn_domain} (turns:443, turn:3478)

Config:     $INSTALL_DIR/.env (TURN_SHARED_SECRET: $masked_secret)
Logs:       docker compose -f $INSTALL_DIR/docker-compose.yml logs -f
Debug log:  docker compose exec node-service tail -f /var/log/app/*.log

Manage this install later:
  $INSTALL_DIR/scripts/manage.sh
(or re-run this same curl command — it detects the existing install)

Real-VPS checklist (netplan/firewall/cert survival):
  $INSTALL_DIR/docs/VERIFICATION.md"

  ui::header "Done"
  if [ "$UI_MODE" = "gum" ]; then
    gum style --border double --padding "1 2" --border-foreground 42 "$body"
  else
    echo "$body"
  fi
}
