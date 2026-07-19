#!/usr/bin/env bash
# Management menu for an already-installed server — reached either by
# re-running install.sh (00-preflight.sh detects an existing install and
# execs here) or by running this script directly.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
export INSTALL_DIR

# shellcheck source=/dev/null
for lib in "$SCRIPT_DIR"/install/lib/*.sh; do
  . "$lib"
done
ui::init

if [ "$(id -u)" -ne 0 ]; then
  ui::error "This must run as root."
  exit 1
fi

load_module() {
  # shellcheck source=/dev/null
  . "$SCRIPT_DIR/install/modules/$1.sh"
}

action_status() {
  ui::header "Status"
  state::compose_status "$INSTALL_DIR"
}

action_update() {
  load_module "30-repo-sync"
  module_repo_sync
  load_module "90-compose-up"
  module_compose_up
}

action_logs() {
  local service
  service="$(ui::choose "Which service?" coturn node-service caddy)"
  (cd "$INSTALL_DIR" && docker compose logs -f --tail=200 "$service")
}

action_restart() {
  local service
  service="$(ui::choose "Restart which?" all coturn node-service caddy)"
  if [ "$service" = "all" ]; then
    (cd "$INSTALL_DIR" && docker compose restart)
  else
    (cd "$INSTALL_DIR" && docker compose restart "$service")
  fi
  ui::success "Restarted $service."
}

action_renew_cert() {
  env::load "$INSTALL_DIR/.env"
  local turn_domain
  turn_domain="$(env::get TURN_DOMAIN)"
  ui::info "Forcing renewal for $turn_domain..."
  certbot renew --force-renewal --cert-name "$turn_domain"
  bash "$INSTALL_DIR/scripts/renew-turn-cert.sh"
}

action_edit_config() {
  load_module "40-config-collect"
  module_config_collect
  if ui::confirm "Apply changes now (docker compose up -d)?" 0; then
    (cd "$INSTALL_DIR" && docker compose up -d)
  fi
}

action_firewall() {
  load_module "70-firewall"
  module_firewall
}

action_reinstall() {
  env::load "$INSTALL_DIR/.env"
  local domain
  domain="$(env::get DOMAIN)"
  ui::warn "This will re-run the full install sequence against $INSTALL_DIR."
  local typed
  typed="$(ui::input "Type the domain ($domain) to confirm a full reinstall" "")"
  if [ "$typed" != "$domain" ]; then
    ui::info "Confirmation didn't match — aborted."
    return 0
  fi
  if ui::confirm "Back up .env and coturn/certs/ first?" 0; then
    local backup_dir
    backup_dir="$INSTALL_DIR/backup-$(date +%s)"
    mkdir -p "$backup_dir"
    cp "$INSTALL_DIR/.env" "$backup_dir/" 2>/dev/null || true
    cp -r "$INSTALL_DIR/coturn/certs" "$backup_dir/" 2>/dev/null || true
    ui::success "Backed up to $backup_dir"
  fi
  exec "$SCRIPT_DIR/install/main.sh"
}

main() {
  while true; do
    ui::header "private-videocall — management menu"
    local choice
    choice="$(ui::choose "What do you want to do?" \
      "Status" "Update & rebuild" "View logs" "Restart a service" \
      "Renew TURN cert now" "Edit configuration" "Re-run firewall setup" \
      "Full reinstall" "Exit")"

    case "$choice" in
      "Status") action_status ;;
      "Update & rebuild") action_update ;;
      "View logs") action_logs ;;
      "Restart a service") action_restart ;;
      "Renew TURN cert now") action_renew_cert ;;
      "Edit configuration") action_edit_config ;;
      "Re-run firewall setup") action_firewall ;;
      "Full reinstall") action_reinstall ;;
      "Exit"|"") exit 0 ;;
    esac
  done
}

main
