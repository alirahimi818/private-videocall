// Same app, reachable through different ingress paths (direct / Cloudflare /
// BunnyCDN) — if one is blocked or throttled, another might not be.
export const DOMAINS = ['pvc.ali-rahimi.me', 'pvc.elido-srv.com', 'pvc-videocall.b-cdn.net'];
