#!/usr/bin/env bash
# certbot deploy-hook: copies the renewed TURN_DOMAIN cert into
# coturn/certs/ and restarts the coturn container (it doesn't hot-reload
# certs). Symlinked from /etc/letsencrypt/renewal-hooks/deploy/ by
# scripts/install/modules/81-turn-cert-renewal.sh — certbot runs every
# deploy-hook automatically after a successful renewal, passing the
# renewed domain(s) via $RENEWED_LINEAGE/$RENEWED_DOMAINS.
set -euo pipefail

INSTALL_DIR="${PVC_INSTALL_DIR:-/opt/private-videocall}"
ENV_FILE="$INSTALL_DIR/.env"

turn_domain=""
if [ -f "$ENV_FILE" ]; then
  turn_domain="$(grep -E '^TURN_DOMAIN=' "$ENV_FILE" | head -1 | cut -d= -f2-)"
fi
# Fall back to whatever certbot itself renewed, in case TURN_DOMAIN in .env
# doesn't match for some reason.
turn_domain="${turn_domain:-${RENEWED_DOMAINS%% *}}"

if [ -z "$turn_domain" ]; then
  echo "renew-turn-cert.sh: could not determine TURN_DOMAIN" >&2
  exit 1
fi

live_dir="/etc/letsencrypt/live/${turn_domain}"
dest_dir="$INSTALL_DIR/coturn/certs"

mkdir -p "$dest_dir"
cp "$live_dir/fullchain.pem" "$dest_dir/fullchain.pem"
cp "$live_dir/privkey.pem" "$dest_dir/privkey.pem"

(cd "$INSTALL_DIR" && docker compose restart coturn)

echo "renew-turn-cert.sh: renewed cert copied and coturn restarted."
