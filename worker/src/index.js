// Transparent reverse proxy in front of the origin VPS, so the app is also
// reachable via Cloudflare's edge (workers.dev / a Cloudflare-proxied
// domain) for networks that block/throttle the origin IP directly.
//
// This only helps the HTTP(S)/WebSocket surface — static assets, /api/*,
// and /ws signaling. It can NOT proxy the actual TURN media relay (raw
// UDP/TCP to coturn): that's a different protocol entirely and still goes
// straight to turn.<domain> on the origin's second IP regardless of which
// link (direct or via this worker) the page was loaded from. Both links
// point at the same node-service backend, so a room created via either one
// is reachable from both.
export default {
  async fetch(request, env) {
    try {
      const url = new URL(request.url);
      url.hostname = env.ORIGIN_HOST;
      url.protocol = 'https:';
      url.port = '';

      // new Request(url, request) clones method/headers/body (including the
      // Upgrade/Connection headers for a WebSocket handshake) — fetch()-ing
      // that to an origin which responds 101 is enough for the Workers
      // runtime to pipe the raw WebSocket through automatically.
      const proxied = new Request(url.toString(), request);

      // Caddy's reverse_proxy appends whoever connects to it (here, this
      // Worker's outbound IP) to X-Forwarded-For — set it to the real
      // visitor IP first so node-service's getClientIp() (which takes the
      // first hop) still logs the actual client, not Cloudflare's edge.
      const clientIp = request.headers.get('CF-Connecting-IP');
      if (clientIp) proxied.headers.set('X-Forwarded-For', clientIp);

      return await fetch(proxied);
    } catch (err) {
      return new Response(`proxy error: ${err.stack || err}`, { status: 502 });
    }
  },
};
