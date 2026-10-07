// Ownership markers contain IDs and the store path, never audio/text/credentials.
import { lstat, mkdir, readFile, writeFile, unlink } from 'node:fs/promises';
import { dirname, isAbsolute, join, resolve } from 'node:path';

function markerPath(configDir, id) {
  if (!isAbsolute(configDir) || !/^blob_[a-z0-9]{21}$/.test(id)) {
    throw new Error('Invalid recording ownership path or ID.');
  }
  return join(configDir, 'recording-owners', `${id}.json`);
}

async function assertPlainPath(path) {
  let current = resolve(path);
  while (true) {
    try {
      if ((await lstat(current)).isSymbolicLink()) throw new Error('Linked ownership path.');
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
    const parent = dirname(current);
    if (parent === current) break;
    current = parent;
  }
}

export async function registerRecordingOwnership(configDir, blobRoot, id) {
  const path = markerPath(configDir, id);
  if (!isAbsolute(blobRoot)) throw new Error('Recording store must be absolute.');
  await assertPlainPath(path);
  await mkdir(dirname(path), { recursive: true });
  await assertPlainPath(path);
  const marker = { version: 1, owner: 'voice-bridge', blobId: id, blobRoot: resolve(blobRoot) };
  try {
    await writeFile(path, JSON.stringify(marker), { encoding: 'utf8', flag: 'wx', mode: 0o600 });
  } catch (error) {
    if (error.code !== 'EEXIST') throw error;
    const existing = JSON.parse(await readFile(path, 'utf8'));
    if (existing.version !== 1 || existing.owner !== marker.owner || existing.blobId !== id ||
        existing.blobRoot !== marker.blobRoot) throw new Error('Ownership marker conflict.');
  }
}

export async function removeRecordingOwnership(configDir, id) {
  const path = markerPath(configDir, id);
  await assertPlainPath(path);
  try { await unlink(path); } catch (error) { if (error.code !== 'ENOENT') throw error; }
}
