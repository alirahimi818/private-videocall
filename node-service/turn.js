import crypto from 'node:crypto';

const TTL_SECONDS = 60 * 60; // 1 hour, per coturn REST API spec

// Ephemeral TURN credentials per coturn's use-auth-secret REST API convention:
// username = "<expiry_unix>:<label>", credential = base64(HMAC-SHA1(username, secret))
export function generateTurnCredentials(secret, label) {
  const expiry = Math.floor(Date.now() / 1000) + TTL_SECONDS;
  const username = `${expiry}:${label}`;
  const credential = crypto
    .createHmac('sha1', secret)
    .update(username)
    .digest('base64');
  return { username, credential, ttl: TTL_SECONDS };
}

export function buildIceServers({ username, credential }, turnHost) {
  return [
    { urls: `turn:${turnHost}:3478?transport=udp`, username, credential },
    { urls: `turn:${turnHost}:3478?transport=tcp`, username, credential },
    { urls: `turns:${turnHost}:443?transport=tcp`, username, credential },
  ];
}
