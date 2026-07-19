#!/usr/bin/env bash
# Real, modular installer — runs from a real checkout on disk (invoked by
# install.sh after cloning), so it's safe to source sibling files here.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
export INSTALL_DIR

# shellcheck source=/dev/null
for lib in "$SCRIPT_DIR"/lib/*.sh; do
  . "$lib"
done

mkdir -p "$INSTALL_DIR/logs"
LOG_FILE="$INSTALL_DIR/logs/install-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

trap::install "$LOG_FILE"
ui::init

CURRENT_MODULE="00-preflight"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/modules/00-preflight.sh"
module_preflight

run_module() {
  local name="$1" fn="$2"
  # shellcheck disable=SC2034 # read by lib/trap.sh's ERR trap
  CURRENT_MODULE="$name"
  # shellcheck source=/dev/null
  . "$SCRIPT_DIR/modules/${name}.sh"
  "$fn"
}

run_module "10-system-update"     module_system_update
run_module "20-dependencies"      module_dependencies
run_module "30-repo-sync"         module_repo_sync
run_module "40-config-collect"    module_config_collect
run_module "50-dns-check"         module_dns_check
run_module "60-network-secondip"  module_network_secondip
run_module "70-firewall"          module_firewall
run_module "80-turn-cert"         module_turn_cert
run_module "81-turn-cert-renewal" module_turn_cert_renewal
run_module "90-compose-up"        module_compose_up
run_module "95-verify"            module_verify
run_module "99-summary"           module_summary
