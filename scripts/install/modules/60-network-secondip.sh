#!/usr/bin/env bash
# The netplan persistence fix from README.md, made idempotent + interactive.
# Without this, a secondary IP added out-of-band (control panel / manual
# `ip addr add`) can be silently wiped by a systemd-networkd restart or
# reboot, crash-looping coturn (`bind: Address not available`).

module_network_secondip() {
  ui::header "Second IP persistence"
  env::load "$INSTALL_DIR/.env"

  local turn_second_ip
  turn_second_ip="$(env::get TURN_SECOND_IP)"
  if [ -z "$turn_second_ip" ]; then
    ui::warn "TURN_SECOND_IP isn't set — skipping."
    return 0
  fi

  local iface mac
  iface="$(network::primary_iface)"
  if [ -z "$iface" ]; then
    ui::warn "Couldn't auto-detect the primary network interface — skipping netplan setup. You'll need to persist $turn_second_ip manually (see README.md)."
    return 0
  fi
  mac="$(network::iface_mac "$iface")"

  if network::ip_present "$turn_second_ip"; then
    ui::success "$turn_second_ip is already present on $iface."
  else
    ui::warn "$turn_second_ip is not currently on $iface."
    if ui::confirm "Add it now (live, ip addr add)?" 0; then
      if [ "${PVC_DRY_RUN:-0}" = "1" ]; then
        ui::info "[dry-run] would run: ip addr add ${turn_second_ip}/32 dev $iface"
      else
        ip addr add "${turn_second_ip}/32" dev "$iface"
        ui::success "Added $turn_second_ip to $iface."
      fi
    fi
  fi

  if ui::confirm "Persist $turn_second_ip in netplan so it survives reboots/network restarts?" 0; then
    network::write_netplan_secondip "$iface" "$mac" "$turn_second_ip" \
      "/etc/netplan/60-secondary-ip.yaml"

    if [ "${PVC_DRY_RUN:-0}" != "1" ] && [ -f /etc/netplan/60-secondary-ip.yaml ]; then
      netplan apply
      if network::ip_present "$turn_second_ip"; then
        ui::success "netplan applied — $turn_second_ip confirmed present."
      else
        ui::error "netplan applied but $turn_second_ip is no longer present. Check /etc/netplan/60-secondary-ip.yaml manually."
      fi
    fi
  else
    ui::warn "Skipped netplan persistence — see README.md's 'Second IP must be persisted' note to do this manually later."
  fi
}
