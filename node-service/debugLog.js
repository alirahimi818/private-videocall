import fs from 'node:fs';
import path from 'node:path';

const LOG_DIR = process.env.DEBUG_LOG_DIR || '/var/log/app';
const LOG_FILE = path.join(LOG_DIR, 'debug.log');
const MAX_SIZE_BYTES = 5 * 1024 * 1024; // 5MB
const MAX_ROTATED_FILES = 3;

function rotateIfNeeded() {
  let size;
  try {
    size = fs.statSync(LOG_FILE).size;
  } catch {
    return; // file doesn't exist yet
  }
  if (size < MAX_SIZE_BYTES) return;

  for (let i = MAX_ROTATED_FILES - 1; i >= 1; i--) {
    const src = `${LOG_FILE}.${i}`;
    if (fs.existsSync(src)) fs.renameSync(src, `${LOG_FILE}.${i + 1}`);
  }
  fs.renameSync(LOG_FILE, `${LOG_FILE}.1`);
}

export function appendDebugLog(entry) {
  fs.mkdirSync(LOG_DIR, { recursive: true });
  rotateIfNeeded();
  fs.appendFileSync(LOG_FILE, `${JSON.stringify({ ts: new Date().toISOString(), ...entry })}\n`);
}
