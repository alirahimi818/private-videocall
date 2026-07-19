#!/usr/bin/env bash
# Wires scripts/renew-turn-cert.sh into certbot's own deploy-hooks
# directory, so renewal is driven by certbot's native systemd timer/cron
# instead of a separate reimplementation of its scheduling.

module_turn_cert_renewal() {
  ui::header "TURN certificate renewal hook"

  certbot::install_deploy_hook "$INSTALL_DIR/scripts/renew-turn-cert.sh"
}
