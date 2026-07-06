// Same-origin API base — Caddy reverse-proxies /api to node-service.
const API_BASE = '/api';

export async function createRoom() {
  const res = await fetch(`${API_BASE}/rooms`, { method: 'POST' });
  if (!res.ok) throw new Error('failed to create room');
  return res.json(); // { roomId }
}

export async function fetchIceServers(roomId) {
  const res = await fetch(`${API_BASE}/rooms/${roomId}/credentials`);
  if (!res.ok) throw new Error('failed to fetch TURN credentials');
  return res.json(); // { iceServers, ttl }
}

export function wsUrl(roomId) {
  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  return `${protocol}//${window.location.host}/ws?room=${roomId}`;
}

// Best-effort periodic telemetry (connection state / bitrate / loss) so the
// Iran side's connection quality can be diagnosed from server logs without a
// visible debug UI. Failures are swallowed — this must never affect the call.
export function postDebugLog(roomId, payload) {
  fetch(`${API_BASE}/rooms/${roomId}/debug`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
    keepalive: true,
  }).catch(() => {});
}
