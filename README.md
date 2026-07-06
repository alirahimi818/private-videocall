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

In the app itself, use the "Debug" toggle during a call to see the active
candidate-pair type (`host` / `srflx` / `relay`) and protocol
(`udp` / `tcp` / `tls`) live — this is the main tool for diagnosing the
Iran side remotely. The "Force relay" toggle in settings forces
`iceTransportPolicy: 'relay'` so you can verify the relay-only path works
even when a direct connection would otherwise succeed.

## Repo layout

```
node-service/   REST API + WebSocket signaling (plain ws, no framework)
frontend/       Vue 3 SPA (Vite)
caddy/          Caddyfile + Dockerfile (builds the SPA, serves it, proxies /api and /ws)
coturn/         TURN server config template + entrypoint
docker-compose.yml
.env.example
```
