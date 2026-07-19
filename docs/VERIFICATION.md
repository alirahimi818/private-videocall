# Post-install verification checklist

The installer (`install.sh` → `scripts/install/main.sh`) can be dry-run and
unit-tested without a real VPS (see `tests/install/`), but a handful of
things only mean something on the real two-public-IP box. Go through this
checklist once, top to bottom, after a real install — ideally on a
disposable/snapshotted VPS the first time, since two of these steps
(firewall, netplan) are genuinely risky if something's misconfigured.

## Module 60 — second IP persists

```sh
ip -4 addr show <primary-iface>          # confirm both IPs are listed
systemctl restart systemd-networkd
ip -4 addr show <primary-iface>          # confirm both IPs are STILL listed
```

If the second IP disappears after the restart, `/etc/netplan/60-secondary-ip.yaml`
either wasn't written or doesn't match the interface's actual MAC —
check with `ip link show <primary-iface>` and compare.

## Module 70 — firewall doesn't lock you out

**Before closing your current SSH session**, open a **second** terminal and
confirm you can start a brand new SSH session to the box. Only close the
first session once the second one connects successfully. If ufw was
enabled and the second connection hangs/refuses, use the VPS provider's
web console (not SSH) to run `ufw disable` and re-check
`scripts/install/lib/firewall.sh`'s SSH-port detection.

```sh
ufw status verbose        # confirm your SSH port shows ALLOW
```

## Module 80 — TURN certificate is real and valid

```sh
curl -v https://<TURN_DOMAIN>:443 2>&1 | grep -E "subject:|issuer:|SSL certificate verify"
```

Expect a real Let's Encrypt chain, not a self-signed/expired one. If you
used `PVC_CERTBOT_STAGING=1` to avoid burning rate limits while testing,
re-run without it for the real cert before going live — staging certs
aren't trusted by real browsers/clients.

## Module 81 — renewal hook actually works

Don't wait for the real 60-90 day renewal window to find out it's broken:

```sh
certbot renew --force-renewal --cert-name <TURN_DOMAIN> --dry-run
# then, for real:
bash /opt/private-videocall/scripts/renew-turn-cert.sh
docker compose -f /opt/private-videocall/docker-compose.yml logs coturn --tail 20
```

Confirm coturn restarted cleanly (no `bind: Address not available` or TLS
handshake errors) and `coturn/certs/*.pem` timestamps are fresh.

## Module 90/95 — the app actually works end-to-end

Use the existing TURN-testing recipe from the main README ("Testing TURN")
— `turnutils_uclient` or the trickle-ice sample page — to confirm you get a
`relay` candidate over `turns:443`, not just `host`/`srflx`. Then actually
open the app from two devices/networks and complete a call.

## Rerun safety

Run `scripts/manage.sh` (or re-run the same `curl | bash` command) a second
time and confirm it opens the management menu instead of re-running the
full install — this is `state::is_installed` in
`scripts/install/lib/state.sh`, and getting it wrong would mean every
future re-run risks clobbering a working `.env`/certs.
