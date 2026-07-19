#!/usr/bin/env bash
# Interface/IP helpers, including the netplan second-IP persistence fix
# documented in README.md (a real incident: a manually-added secondary IP
# not persisted in netplan gets silently wiped by a systemd-networkd
# restart or reboot, crash-looping coturn with no obvious symptom).

network::primary_iface() {
  ip -o -4 route show to default 2>/dev/null | awk '{print $5; exit}'
}

network::iface_mac() {
  local iface="$1"
  cat "/sys/class/net/${iface}/address" 2>/dev/null
}

network::detect_public_ip() {
  local ip
  ip="$(curl -4 -s --max-time 5 https://ifconfig.me 2>/dev/null || true)"
  if [ -z "$ip" ]; then
    ip="$(curl -4 -s --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  fi
  echo "$ip"
}

network::ip_present() {
  local ip="$1"
  ip -4 addr show 2>/dev/null | grep -q "inet ${ip}/"
}

# network::write_netplan_secondip <iface> <mac> <ip> <path>
# Idempotent: does nothing if the file already contains this exact config.
network::write_netplan_secondip() {
  local iface="$1" mac="$2" ip="$3" path="$4"

  local content
  content=$(cat <<EOF
network:
  version: 2
  ethernets:
    ${iface}:
      match:
        macaddress: "${mac}"
      set-name: "${iface}"
      addresses:
        - "${ip}/32"
EOF
)

  if [ -f "$path" ] && [ "$(cat "$path")" = "$content" ]; then
    ui::info "netplan config for the second IP is already up to date ($path)."
    return 0
  fi

  if [ -f "$path" ]; then
    ui::warn "$path already exists with different content."
    if [ "$UI_MODE" = "gum" ]; then
      diff -u "$path" <(echo "$content") | gum pager || true
    else
      diff -u "$path" <(echo "$content") || true
    fi
    if ! ui::confirm "Overwrite $path with the config above?" 1; then
      ui::info "Skipped netplan changes."
      return 1
    fi
  fi

  if [ "${PVC_DRY_RUN:-0}" = "1" ]; then
    ui::info "[dry-run] would write $path:"
    echo "$content"
    return 0
  fi

  echo "$content" > "$path"
  chmod 600 "$path"
  ui::success "Wrote $path"
}
