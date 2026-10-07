// Actual bridge routes with a synthetic upstream, temporary config and a random
// loopback test port. Never contacts the daily host/bridge, microphone or cloud.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, mkdir, readFile, writeFile, copyFile, rm } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const arg = process.argv.indexOf('--work-directory');
const fixture = await mkdtemp(join(arg < 0 ? tmpdir() : resolve(process.argv[arg + 1]), 'bridge-ownership-'));
const configDir = join(fixture, 'dsh-voice-bridge');
const dataRoot = join(fixture, 'epicenter');
const id = 'blob_' + 'a'.repeat(21);
const marker = join(configDir, 'recording-owners', id + '.json');
const token = randomUUID() + randomUUID();
let cancels = 0;
let child;
const host = createServer(async (req, res) => {
  for await (const chunk of req) { /* consume synthetic request */ }
  if (req.url === '/cancel') cancels++;
  res.writeHead(200, { 'content-type': 'application/json' });
  res.end(JSON.stringify(req.url === '/start' ? { recordingId: id } : { ok: true }));
});
const reservation = createServer();
try {
  host.listen(0, '127.0.0.1'); await once(host, 'listening');
  reservation.listen(0, '127.0.0.1'); await once(reservation, 'listening');
  const port = reservation.address().port;
  await new Promise(r => reservation.close(r));
  await mkdir(configDir); await mkdir(dataRoot);
  await writeFile(join(configDir, 'config.json'), JSON.stringify({ token, requireToken: true }));
  await writeFile(join(dataRoot, 'voice-bridge.json'), JSON.stringify({ port: host.address().port, token }));
  const sourceArg = process.argv.indexOf('--bridge-source');
  const source = await readFile(sourceArg < 0 ? new URL('../bridge/bridge.mjs', import.meta.url) : resolve(process.argv[sourceArg + 1]), 'utf8');
  assert.equal(source.split('const LISTEN_PORT = 39152;').length, 2);
  await writeFile(join(fixture, 'bridge.mjs'), source.replace('const LISTEN_PORT = 39152;', `const LISTEN_PORT = ${port};`));
  await copyFile(new URL('../bridge/recording-history.mjs', import.meta.url), join(fixture, 'recording-history.mjs'));
  child = spawn(process.execPath, [join(fixture, 'bridge.mjs')], {
    env: { ...process.env, APPDATA: fixture, EPICENTER_DATA_DIR: dataRoot }, windowsHide: true, stdio: ['ignore', 'ignore', 'pipe'],
  });
  let diagnostics = '';
  child.stderr.on('data', chunk => { diagnostics += chunk.toString(); });
  const call = async (route, method = 'POST') => {
    const res = await fetch(`http://127.0.0.1:${port}${route}`, {
      method, headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: method === 'POST' ? JSON.stringify({ requestId: 'SYNTHETIC', recordingId: id }) : undefined,
      signal: AbortSignal.timeout(2000),
    });
    return { status: res.status, body: await res.json() };
  };
  let ready = false;
  for (let n = 0; n < 100; n++) {
    try { ready = (await call('/health', 'GET')).status === 200; } catch { /* wait for child */ }
    if (ready) break;
    await new Promise(r => setTimeout(r, 50));
  }
  assert.ok(ready, `Synthetic bridge readiness failed (exit=${child.exitCode}): ${diagnostics.split(fixture).join('<fixture>')}`);
  assert.equal((await call('/start')).status, 200);
  assert.equal(JSON.parse(await readFile(marker, 'utf8')).blobRoot, join(dataRoot, 'blobs'));
  assert.equal((await call('/stop')).status, 200);
  assert.equal(JSON.parse(await readFile(marker, 'utf8')).owner, 'voice-bridge');
  assert.equal(JSON.parse(await readFile(join(configDir, 'state.json'), 'utf8')).recordingId, null);
  assert.equal((await call('/start')).status, 200);
  assert.equal((await call('/cancel')).status, 200);
  await assert.rejects(readFile(marker), { code: 'ENOENT' });
  await rm(join(configDir, 'recording-owners'), { recursive: true });
  await writeFile(join(configDir, 'recording-owners'), 'SYNTHETIC obstruction');
  const failed = await call('/start');
  assert.equal(failed.status, 503);
  assert.equal(failed.body.error.code, 'HistoryUnavailable');
  assert.equal(failed.body.recordingId, undefined);
  assert.equal(cancels, 2);
  assert.equal(JSON.parse(await readFile(join(configDir, 'state.json'), 'utf8')).recordingId, null);
  console.log(JSON.stringify({ ok: true, tests: ['start-registers-before-success', 'stop-retains-marker', 'cancel-removes-marker', 'marker-failure-cancels-and-rejects-start'], cloud_calls: 0, microphone_used: false }));
} finally {
  if (child && child.exitCode === null) { const closed = once(child, 'close'); child.kill(); await closed; }
  await new Promise(r => host.close(r));
  reservation.close();
  await rm(fixture, { recursive: true, force: true });
}
