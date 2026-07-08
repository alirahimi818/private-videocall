import { ref } from 'vue';
import { wsUrl } from './api.js';

const MAX_BACKOFF_MS = 10_000;
// If nothing (message or app-level ping) arrives for this long, treat the
// socket as dead and force a reconnect rather than waiting on the browser's
// own TCP timeout — DPI-style silent drops (no close frame) can otherwise
// take far longer than this to surface as a 'close' event.
const LIVENESS_TIMEOUT_MS = 20_000;
const LIVENESS_CHECK_INTERVAL_MS = 5_000;

// Thin reconnecting WebSocket wrapper around an EventTarget so callers can
// addEventListener for 'joined' | 'peer-joined' | 'peer-left' | 'signal' |
// 'open' | 'close' | 'reconnect-scheduled'.
export function useSignaling(roomId) {
  const events = new EventTarget();
  const status = ref('connecting'); // connecting | open | closed
  const reconnectAttempt = ref(0);
  let ws = null;
  let attempt = 0;
  let closedByUser = false;
  let reconnectTimer = null;
  let livenessTimer = null;
  let lastMessageAt = 0;
  // Callers (e.g. onnegotiationneeded) can fire before the handshake
  // finishes; queue outbound messages instead of silently dropping them.
  const outbox = [];

  function connect() {
    ws = new WebSocket(wsUrl(roomId));

    ws.addEventListener('open', () => {
      attempt = 0;
      reconnectAttempt.value = 0;
      status.value = 'open';
      lastMessageAt = Date.now();
      clearInterval(livenessTimer);
      livenessTimer = setInterval(() => {
        if (Date.now() - lastMessageAt > LIVENESS_TIMEOUT_MS) {
          ws.close();
        }
      }, LIVENESS_CHECK_INTERVAL_MS);
      while (outbox.length > 0) {
        ws.send(outbox.shift());
      }
      events.dispatchEvent(new Event('open'));
    });

    ws.addEventListener('message', (event) => {
      lastMessageAt = Date.now();
      let msg;
      try {
        msg = JSON.parse(event.data);
      } catch {
        return;
      }
      if (msg.type === 'ping') {
        // Server's app-level liveness signal — nothing else to do with it.
      } else if (msg.type === 'joined' || msg.type === 'peer-joined' || msg.type === 'peer-left') {
        events.dispatchEvent(new CustomEvent(msg.type, { detail: msg }));
      } else {
        // SDP offer/answer or ICE candidate — relayed blindly by the server.
        events.dispatchEvent(new CustomEvent('signal', { detail: msg }));
      }
    });

    ws.addEventListener('close', (event) => {
      status.value = 'closed';
      clearInterval(livenessTimer);
      events.dispatchEvent(
        new CustomEvent('close', {
          detail: { code: event.code, reason: event.reason, wasClean: event.wasClean },
        }),
      );
      if (!closedByUser) scheduleReconnect();
    });

    ws.addEventListener('error', () => {
      ws.close();
    });
  }

  function scheduleReconnect() {
    const delay = Math.min(1000 * 2 ** attempt, MAX_BACKOFF_MS);
    attempt += 1;
    reconnectAttempt.value = attempt;
    status.value = 'connecting';
    events.dispatchEvent(new CustomEvent('reconnect-scheduled', { detail: { attempt, delay } }));
    reconnectTimer = setTimeout(connect, delay);
  }

  function send(data) {
    const payload = JSON.stringify(data);
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(payload);
    } else {
      outbox.push(payload);
    }
  }

  function close() {
    closedByUser = true;
    clearTimeout(reconnectTimer);
    clearInterval(livenessTimer);
    ws?.close();
  }

  connect();

  return { events, status, reconnectAttempt, send, close };
}
