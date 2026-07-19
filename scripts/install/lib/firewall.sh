#!/usr/bin/env bash
# ufw helpers. The one genuinely dangerous step in this whole installer is
# enabling ufw on a remote box without first guaranteeing the current SSH
# session stays allowed — every function here is written around avoiding
# that lockout.
#
# Per CLAUDE.md: Caddy's ports are Docker published-ports bound explicitly
# to PRIMARY_IP, which bypass ufw's INPUT chain entirely (Docker manipulates
# iptables directly) — so ufw rules here are only load-bearing for coturn's
# ports (network_mode: host goes through the normal INPUT chain).

firewall::ssh_port() {
  local port
  port=$(sshd_config_port=$(grep -iE '^\s*Port\s+[0-9]+' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | tail -1); echo "${sshd_config_port:-22}")
  echo "${port:-22}"
}

firewall::current_ssh_client_ip() {
  if [ -n "${SSH_CONNECTION:-}" ]; then
    awk '{print $1}' <<<"$SSH_CONNECTION"
  fi
}

firewall::status_has_rule() {
  local pattern="$1"
  ufw status 2>/dev/null | grep -qE "$pattern"
}

# Ensures the current SSH port is allowed BEFORE ufw is ever enabled.
firewall::ensure_ssh_allowed() {
  local port
  port="$(firewall::ssh_port)"

  if firewall::status_has_rule "^${port}/tcp\b.*ALLOW"; then
    ui::info "ufw already allows SSH on port $port."
    return 0
  fi

  ui::info "Allowing SSH on port $port before touching ufw further..."
  if [ "${PVC_DRY_RUN:-0}" = "1" ]; then
    ui::info "[dry-run] would run: ufw allow ${port}/tcp"
    return 0
  fi
  ufw allow "${port}/tcp" comment "SSH (auto-detected)" >/dev/null

  if ! firewall::status_has_rule "^${port}/tcp\b.*ALLOW"; then
    ui::error "Failed to confirm SSH port $port is allowed in ufw — refusing to continue with firewall setup."
    return 1
  fi
  ui::success "SSH port $port is allowed."
}

# firewall::allow_turn_ports <second_ip> <min_port> <max_port>
firewall::allow_turn_ports() {
  local second_ip="$1" min_port="$2" max_port="$3"
  local rules=(
    "443/tcp"
    "3478/tcp"
    "3478/udp"
    "${min_port}:${max_port}/udp"
  )
  for rule in "${rules[@]}"; do
    if firewall::status_has_rule "^${rule//\//\\/}\b.*ALLOW"; then
      ui::info "ufw rule for $rule already present."
      continue
    fi
    if [ "${PVC_DRY_RUN:-0}" = "1" ]; then
      ui::info "[dry-run] would run: ufw allow $rule"
      continue
    fi
    ufw allow "$rule" comment "coturn (TURN_SECOND_IP=$second_ip)" >/dev/null
    ui::success "Allowed $rule"
  done
}

firewall::enable_if_confirmed() {
  if ufw status 2>/dev/null | grep -q "^Status: active"; then
    ui::info "ufw is already active."
    return 0
  fi

  local port
  port="$(firewall::ssh_port)"
  ui::warn "About to enable ufw. SSH on port $port has already been allowed and verified above."

  if [ "${PVC_NONINTERACTIVE:-0}" = "1" ] && [ "${PVC_FORCE_UFW:-0}" != "1" ]; then
    ui::info "Non-interactive run without PVC_FORCE_UFW=1 — skipping 'ufw enable'. Run scripts/manage.sh later to enable it."
    return 0
  fi

  if ! ui::confirm "Enable ufw now? (SSH port $port will remain allowed)" 1; then
    ui::info "Skipped enabling ufw. coturn's ports are allowed but the firewall itself stays off until you enable it."
    return 0
  fi

  if [ "${PVC_DRY_RUN:-0}" = "1" ]; then
    ui::info "[dry-run] would run: ufw --force enable"
    return 0
  fi
  ufw --force enable
  ui::success "ufw enabled."
}
