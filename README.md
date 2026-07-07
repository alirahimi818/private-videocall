# private-videocall

Private 1:1 web video calling for family use. One peer is behind heavy DPI
and CGNAT; this stack assumes most calls will be relayed through TURN over
TLS on port 443, not just fall back to it.

Everything runs on a single VPS in Germany: coturn (TURN/STUN), a Node.js
service (REST API + WebSocket signaling), and Caddy (TLS + static SPA +
reverse proxy). No database — room state lives in memory and is dropped on
restart.

## Requirements

- A VPS with **two public IPv4 addresses**. Caddy needs 443 on the primary
  IP for the SPA/API; coturn needs its own 443 on a second IP for
  `turns:` (TURN over TLS), since Iranian DPI can flag connections that
  aren't on a "normal" HTTPS port.
- Two DNS A records, one per IP (see below).
- Docker + Docker Compose.
- Ports open in the firewall (see below).

## DNS

| Record                    | Points to    | Used for                      |
| -------------------------- | ------------ | ------------------------------ |
| `call.example.com` (DOMAIN)      | primary IP   | SPA, REST API, WebSocket signaling |
| `turn.example.com` (TURN_DOMAIN) | second IP    | TURN/STUN, including `turns:443` |

## Firewall

Primary IP:
- `80/tcp`, `443/tcp` — Caddy (HTTP-01 challenge + HTTPS)

Second IP:
- `443/tcp` — coturn TLS listener (`turns:`)
- `3478/udp`, `3478/tcp` — plain STUN/TURN
- `49160-49200/udp` (or whatever `TURN_MIN_PORT`/`TURN_MAX_PORT` you set) — TURN relay media

coturn runs with `network_mode: host` because the relay port range must be
reachable directly; it can't go through Docker's NAT.

## Setup

1. Clone this repo onto the VPS.
2. Copy `.env.example` to `.env` and fill in both domains, the second IP,
   and a random secret:
   ```sh
   cp .env.example .env
   openssl rand -hex 32   # paste into TURN_SHARED_SECRET
   ```
3. Get a real certificate for `TURN_DOMAIN` (coturn needs its own — it
   doesn't share Caddy's automatic cert, since that's issued for a
   different hostname/IP). Standalone certbot works well since nothing
   else listens on port 80 of the second IP:
   ```sh
   sudo certbot certonly --standalone -d turn.example.com
   sudo mkdir -p coturn/certs
   sudo cp /etc/letsencrypt/live/turn.example.com/fullchain.pem coturn/certs/
   sudo cp /etc/letsencrypt/live/turn.example.com/privkey.pem coturn/certs/
   ```
   Renewal: add a cron/systemd timer that re-runs certbot, re-copies the
   two files into `coturn/certs/`, then runs
   `docker compose restart coturn` (coturn doesn't hot-reload certs).
4. Build and start everything:
   ```sh
   docker compose up -d --build
   ```
   Caddy will automatically obtain/renew its own certificate for `DOMAIN`.
5. Open `https://call.example.com`, click "Start a call", and share the
   `/call/:uuid` link with the other person. That link is the only secret
   — there's no login.

## Fallback ingress via a CDN (optional)

If the primary `DOMAIN`/IP gets blocked or throttled on the restrictive side,
set `EDGE_DOMAIN` to a second hostname proxied through a CDN (e.g.
Cloudflare, orange-cloud on) pointed at `PRIMARY_IP`. Caddy serves the exact
same app on both hostnames and manages a separate cert for each — a room
link works interchangeably from either one, since both reach the same
node-service backend. TURN media relay is unaffected regardless of which
link loaded the page; it always goes straight to `TURN_DOMAIN`, not through
the CDN (CDNs proxy HTTP(S)/WebSocket, not the TURN protocol).

Notes if using Cloudflare specifically:
- SSL/TLS mode must be **Full** or **Full (strict)** so Cloudflare connects
  to the origin over real HTTPS.
- The TLS-ALPN-01 ACME challenge can't work behind a proxied (orange-cloud)
  record, since Cloudflare terminates TLS at the edge — Caddy automatically
  falls back to HTTP-01 instead, and Cloudflare passes `/.well-known/acme-challenge/`
  through to the origin, so no extra configuration is needed.
- A Cloudflare *Worker* as a reverse proxy was tried first instead of a
  proxied DNS record, but hit an unrelated account-level Cloudflare bug
  (new-account Workers execution failing outright, even for an empty
  Hello World worker). That code is kept in `worker/` for whenever that's
  resolved; it's not required for the DNS-proxy approach above.

## Testing TURN

From a machine outside the VPS (ideally simulating the restrictive side):

```sh
# Get ephemeral credentials from the API
curl https://call.example.com/api/rooms/<some-uuid>/credentials

# Then plug username/credential into turnutils_uclient, e.g.:
turnutils_uclient -T -y -u <username> -w <credential> turn.example.com

# Or use https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/
# with the iceServers array from the credentials response — confirm you
# get a "relay" candidate over turns:443, not just host/srflx.
```

There's no visible debug UI in the app — instead, each client ships its
connection stats (candidate-pair type, protocol, bitrate, loss, RTT) to the
server every 10s, logged to a rotated file:

```sh
docker compose exec node-service tail -f /var/log/app/debug.log
```

Relay fallback is automatic: calls start with `iceTransportPolicy: 'all'`,
and if ICE ends up `failed`, the client rebuilds the connection forced to
`iceTransportPolicy: 'relay'` (visible as `"relayOnly": true` in the debug
log) — no manual toggle needed to diagnose or work around a blocked direct
path.

## Repo layout

```
node-service/   REST API + WebSocket signaling (plain ws, no framework)
frontend/       Vue 3 SPA (Vite)
caddy/          Caddyfile + Dockerfile (builds the SPA, serves it, proxies /api and /ws)
coturn/         TURN server config template + entrypoint
worker/         Cloudflare Worker reverse-proxy (currently unused — see
                "Fallback ingress via a CDN" above)
docker-compose.yml
.env.example
```
