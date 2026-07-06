// In-memory room registry. No persistence — a restart drops active rooms,
// which is an accepted tradeoff for a 2-user service.
const rooms = new Map(); // roomId -> { peers: Set<WebSocket>, createdAt: number }

export function createRoom(roomId) {
  if (!rooms.has(roomId)) {
    rooms.set(roomId, { peers: new Set(), createdAt: Date.now() });
  }
  return rooms.get(roomId);
}

export function getRoom(roomId) {
  return rooms.get(roomId);
}

export function deleteRoomIfEmpty(roomId) {
  const room = rooms.get(roomId);
  if (room && room.peers.size === 0) {
    rooms.delete(roomId);
  }
}
