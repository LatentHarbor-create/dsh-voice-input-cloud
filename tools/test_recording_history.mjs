// Synthetic IDs and temporary files only; no recording, services or cloud.
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, rm, symlink, lstat } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { registerRecordingOwnership, removeRecordingOwnership } from '../bridge/recording-history.mjs';

const arg = process.argv.indexOf('--work-directory');
const fixture = await mkdtemp(join(arg < 0 ? tmpdir() : resolve(process.argv[arg + 1]), 'recording-history-'));
const config = join(fixture, 'config');
const root = join(fixture, 'blobs');
const id = 'blob_' + 'a'.repeat(21);
const path = join(config, 'recording-owners', id + '.json');
const tests = [];
try {
  await registerRecordingOwnership(config, root, id);
  assert.deepEqual(JSON.parse(await readFile(path, 'utf8')), { version: 1, owner: 'voice-bridge', blobId: id, blobRoot: root });
  await registerRecordingOwnership(config, root, id);
  tests.push('marker-has-only-ownership-and-store-idempotent-registration');
  await assert.rejects(registerRecordingOwnership(config, join(fixture, 'other'), id));
  await assert.rejects(registerRecordingOwnership(config, root, '../escape'));
  await assert.rejects(registerRecordingOwnership(config, 'relative', id));
  const other = { version: 1, owner: 'other-app', blobId: id, blobRoot: root };
  await writeFile(path, JSON.stringify(other));
  await assert.rejects(registerRecordingOwnership(config, root, id));
  assert.deepEqual(JSON.parse(await readFile(path, 'utf8')), other);
  tests.push('path-escape-relative-store-owner-and-store-conflicts-refused');
  await removeRecordingOwnership(config, id);
  await removeRecordingOwnership(config, id);
  await assert.rejects(lstat(path), { code: 'ENOENT' });
  tests.push('cancel-marker-removal-idempotent');
  const linked = join(fixture, 'linked');
  await symlink(config, linked, 'junction');
  try { await assert.rejects(registerRecordingOwnership(linked, root, id)); }
  finally { await rm(linked); }
  tests.push('junction-marker-store-refused');
  console.log(JSON.stringify({ ok: true, tests, real_recordings_deleted: 0, cloud_calls: 0 }));
} finally { await rm(fixture, { recursive: true, force: true }); }
