#!/usr/bin/env node
/**
 * dsh-voice-bridge — the standalone Voice Bridge between the DeepSeek Harness
 * voice input plugin (browser) and the Epicenter host's voice-bridge surface.
 *
 *   DSH web plugin ──HTTP(own token, localhost CORS fence)──▶ HERE
 *   HERE ──HTTP(per-launch token from discovery file)──────▶ Epicenter host
 *
 * Upstream credential: Epicenter writes %APPDATA%/so.epicenter/voice-bridge.json
 * ({"port","token"}) on every launch; the file is re-read per upstream call, so
 * Epicenter restarts are transparent. Downstream credential: one persistent
 * token in %APPDATA%/dsh-voice-bridge/config.json (browser clients cannot read
 * files, so this one is stable across restarts by design).
 *
 * Logging: request id, state transition, duration, error class. Transcript
 * text is proxied but NEVER logged. No telemetry. Binds 127.0.0.1 only.
 *
 * Zero npm dependencies. Node >= 18.
 */
import { createServer } from 'node:http';
import { randomBytes, randomUUID } from 'node:crypto';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { isAbsolute, join } from 'node:path';
import { homedir } from 'node:os';

const APPDATA = process.env.APPDATA || join(homedir(), 'AppData', 'Roaming');
const CONFIG_DIR = join(APPDATA, 'dsh-voice-bridge');
const CONFIG_PATH = join(CONFIG_DIR, 'config.json');
const STATE_PATH = join(CONFIG_DIR, 'state.json');
const EPICENTER_DATA_DIR = process.env.EPICENTER_DATA_DIR;
if (EPICENTER_DATA_DIR && !isAbsolute(EPICENTER_DATA_DIR)) {
  throw new Error('EPICENTER_DATA_DIR must be an absolute path.');
}
const EPICENTER_DISCOVERY_PATH = join(
  EPICENTER_DATA_DIR || join(APPDATA, 'so.epicenter'), 'voice-bridge.json');
const LISTEN_PORT = 39152;
const UPSTREAM_TIMEOUT_MS = 30_000;
const TRANSCRIBE_TIMEOUT_MS = 180_000;
const MAX_BODY_BYTES = 64 * 1024;

// ── config ──────────────────────────────────────────────────────────────
const DEFAULT_TRANSCRIPTION = {
  baseURL: 'https://api.groq.com/openai/v1',
  apiKey: '',
  model: 'whisper-large-v3',
  language: '',
};
const DEFAULT_TRANSFORMATION = {
  enabled: false,
  baseURL: 'https://api.openai.com/v1',
  apiKey: '',
  model: 'gpt-4o-mini',
  prompt: '你是語音轉寫潤飾器。修正錯字、標點與語順，保留原意、語言與專業詞彙，不要添加內容，只輸出潤飾後的文字。',
};

async function loadConfig() {
  try {
    const raw = await readFile(CONFIG_PATH, 'utf8');
    const stored = JSON.parse(raw);
    const cfg = {
      port: LISTEN_PORT,
      token: typeof stored.token === 'string' && stored.token.length >= 32 ? stored.token : randomBytes(32).toString('base64url'),
      requireToken: stored.requireToken === true,
      transcription: { ...DEFAULT_TRANSCRIPTION, ...(stored.transcription || {}) },
      transformation: { enabled: false, ...DEFAULT_TRANSFORMATION, ...(stored.transformation || {}) },
    };
    return cfg;
  } catch (error) {
    // Only a missing file is first-run setup. Preserve malformed/private configs.
    if (error?.code !== 'ENOENT') {
      throw new Error('Voice Bridge config is invalid or unreadable; correct it locally.');
    }
    const cfg = {
      port: LISTEN_PORT,
      token: randomBytes(32).toString('base64url'),
      requireToken: false,
      transcription: { ...DEFAULT_TRANSCRIPTION },
      transformation: { enabled: false, ...DEFAULT_TRANSFORMATION },
    };
    await mkdir(CONFIG_DIR, { recursive: true });
    await writeFile(CONFIG_PATH, JSON.stringify(cfg, null, 2));
    console.log(`[voice-bridge] wrote first-run config: ${CONFIG_PATH}`);
    return cfg;
  }
}

// ── in-flight recording tracking (orphan recovery) ─────────────────────
// A recording whose page died before "stop" would otherwise occupy the
// single recorder slot forever. The bridge remembers the id it minted
// (memory + state file, surviving bridge restarts) and cancels it when a
// new /start comes back Busy.

let trackedRecordingId = null;

async function loadTrackedId() {
  if (trackedRecordingId) return trackedRecordingId;
  try {
    const s = JSON.parse(await readFile(STATE_PATH, 'utf8'));
    if (typeof s.recordingId === 'string' && s.recordingId) {
      trackedRecordingId = s.recordingId;
    }
  } catch { /* no state yet */ }
  return trackedRecordingId;
}

async function saveTrackedId(id) {
  trackedRecordingId = id;
  try {
    await writeFile(STATE_PATH, JSON.stringify({ recordingId: id }));
  } catch { /* best-effort */ }
}

// ── upstream (Epicenter host) ───────────────────────────────────────────
async function readEpicenterDiscovery() {
  const raw = await readFile(EPICENTER_DISCOVERY_PATH, 'utf8');
  const d = JSON.parse(raw);
  if (typeof d.port !== 'number' || typeof d.token !== 'string') {
    throw new Error('discovery file malformed');
  }
  return d;
}

async function upstreamCall(method, path, body, timeoutMs) {
  let discovery;
  try {
    discovery = await readEpicenterDiscovery();
  } catch {
    return {
      status: 503,
      body: {
        requestId: body?.requestId ?? null,
        error: {
          code: 'EpicenterUnreachable',
          message:
            'Epicenter is not running or its voice-bridge discovery file is missing. Start Epicenter desktop, then retry.',
        },
      },
    };
  }
  const url = `http://127.0.0.1:${discovery.port}${path}`;
  let res;
  try {
    res = await fetch(url, {
      method,
      headers: {
        'content-type': 'application/json',
        authorization: `Bearer ${discovery.token}`,
        host: `127.0.0.1:${discovery.port}`,
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (error) {
    const code = error?.name === 'TimeoutError' ? 'UpstreamTimeout' : 'EpicenterUnreachable';
    return {
      status: code === 'UpstreamTimeout' ? 504 : 503,
      body: {
        requestId: body?.requestId ?? null,
        error: { code, message: 'Epicenter voice-bridge request failed; check the local host.' },
      },
    };
  }
  const text = await res.text();
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    parsed = { error: { code: 'UpstreamBadResponse', message: 'non-JSON response from Epicenter' } };
  }
  return { status: res.status, body: parsed };
}

// ── downstream helpers ──────────────────────────────────────────────────
const LOOPBACK_ORIGIN = /^https?:\/\/(127\.0\.0\.1|localhost|\[::1\])(:\d+)?$/i;

function corsHeaders(origin) {
  // Reflect only loopback origins, never "*". A remote page cannot pass the
  // Host/Origin fence, so CORS is belt-and-braces over the same fence.
  const headers = { 'content-type': 'application/json' };
  if (origin && LOOPBACK_ORIGIN.test(origin)) {
    headers['access-control-allow-origin'] = origin;
    headers['vary'] = 'Origin';
    headers['access-control-allow-headers'] = 'content-type, authorization';
    headers['access-control-allow-methods'] = 'GET, POST, OPTIONS';
  }
  return headers;
}

function authorized(req, cfg) {
  if (!cfg.requireToken) return true;
  const presented = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  const a = Buffer.from(presented);
  const b = Buffer.from(cfg.token);
  return a.length === b.length && a.equals(b); // Buffer#equals is length-checked first
}

function hostFenceOk(req, port) {
  return (req.headers.host || '') === `127.0.0.1:${port}`;
}

function readBody(req, limit = MAX_BODY_BYTES) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > limit) {
        reject(Object.assign(new Error('payload too large'), { code: 413 }));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

// ── cloud transcription (Groq / OpenAI-compatible wire) ───────────────
//
// The recorded WAV arrives from Epicenter's /audio, then goes out as one
// multipart POST to {baseURL}/audio/transcriptions — the same OpenAI-
// compatible wire Whispering's own cloud providers speak. Optional second
// call: an OpenAI chat-completions polish (Whispering's "transformations"
// step). Keys live in config.json (file ACL); never logged, never in URLs.

const CLOUD_TIMEOUT_MS = 90_000;

function multipartWav(wav, cloud) {
  const boundary = '----dshvoicebridge' + randomUUID().replaceAll('-', '');
  const parts = [
    Buffer.from(
      `--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="audio.wav"\r\nContent-Type: audio/wav\r\n\r\n`,
    ),
    wav,
    Buffer.from(`\r\n--${boundary}\r\nContent-Disposition: form-data; name="model"\r\n\r\n${cloud.model}\r\n`),
  ];
  if (cloud.language) {
    parts.push(Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="language"\r\n\r\n${cloud.language}\r\n`));
  }
  parts.push(Buffer.from(`--${boundary}--\r\n`));
  return { body: Buffer.concat(parts), contentType: `multipart/form-data; boundary=${boundary}` };
}

async function transcribeCloud(body, cfg, logId) {
  const requestId = body.requestId ?? null;
  const recordingId = body.recordingId;
  if (!recordingId) {
    return [400, { requestId, error: { code: 'BadRequest', message: 'recordingId is required' } }];
  }
  const cloud = cfg.transcription || {};
  if (!cloud.apiKey || !cloud.baseURL) {
    return [
      503,
      {
        requestId,
        error: {
          code: 'CloudNotConfigured',
          message: 'Set transcription.apiKey and transcription.baseURL in the local Voice Bridge config. This plugin uses cloud transcription.',
        },
      },
    ];
  }

  // 1. The recording's WAV from Epicenter.
  const audio = await upstreamCall('POST', '/audio', { requestId, recordingId }, UPSTREAM_TIMEOUT_MS);
  if (audio.status !== 200 || !audio.body?.audioBase64) return [audio.status, audio.body];
  const wav = Buffer.from(audio.body.audioBase64, 'base64');

  // 2. Groq / OpenAI-compatible transcription.
  const { body: form, contentType } = multipartWav(wav, cloud);
  let res;
  try {
    res = await fetch(cloud.baseURL.replace(/\/+$/, '') + '/audio/transcriptions', {
      method: 'POST',
      headers: { authorization: `Bearer ${cloud.apiKey}`, 'content-type': contentType },
      body: form,
      signal: AbortSignal.timeout(CLOUD_TIMEOUT_MS),
    });
  } catch (error) {
    const code = error?.name === 'TimeoutError' ? 'CloudTimeout' : 'CloudRequestFailed';
    return [502, { requestId, error: { code, message: 'Transcription request failed; check the configured provider locally.' } }];
  }
  const data = await res.json().catch(() => ({}));
  if (!res.ok || typeof data.text !== 'string') {
    // Provider error bodies can echo credentials or transcript content.
    const message = `Transcription endpoint returned HTTP ${res.status}; check the provider and key locally.`;
    console.log(`[voice-bridge] state: transcribe-cloud [${logId}] -> provider HTTP ${res.status}`);
    return [res.status === 401 ? 401 : 502, { requestId, error: { code: 'CloudTranscriptionFailed', message } }];
  }
  const rawText = data.text;

  // 3. Optional OpenAI-compatible polish (best-effort; raw text is the
  // fallback, and neither text enters a log line).
  let transformed = null;
  const tf = cfg.transformation || {};
  if (tf.enabled && tf.apiKey && rawText.length > 0) {
    try {
      const tRes = await fetch((tf.baseURL || 'https://api.openai.com/v1').replace(/\/+$/, '') + '/chat/completions', {
        method: 'POST',
        headers: { authorization: `Bearer ${tf.apiKey}`, 'content-type': 'application/json' },
        body: JSON.stringify({
          model: tf.model || 'gpt-4o-mini',
          temperature: 0.2,
          messages: [
            { role: 'system', content: tf.prompt },
            { role: 'user', content: rawText },
          ],
        }),
        signal: AbortSignal.timeout(CLOUD_TIMEOUT_MS),
      });
      const tData = await tRes.json().catch(() => ({}));
      if (tRes.ok && typeof tData?.choices?.[0]?.message?.content === 'string') {
        transformed = tData.choices[0].message.content;
      }
    } catch {
      /* best-effort: fall back to the raw transcript */
    }
  }

  console.log(
    `[voice-bridge] state: transcribe-cloud [${logId}] -> raw ${rawText.length} chars, polished=${transformed !== null}`,
  );
  return [200, { requestId, text: transformed ?? rawText, transformed: transformed !== null }];
}

// ── server ──────────────────────────────────────────────────────────────
async function main() {
  const cfg = await loadConfig();
  const startedAt = Date.now();
  console.log(`[voice-bridge] listening on http://127.0.0.1:${cfg.port}`);
  console.log(`[voice-bridge] downstream token: (stored in ${CONFIG_PATH})`);
  console.log('[voice-bridge] upstream discovery: ' + EPICENTER_DISCOVERY_PATH);

  const server = createServer(async (req, res) => {
    const started = Date.now();
    const requestIdBase = randomUUID().slice(0, 8);
    const routeLabel = ['/health', '/', '/index.html', '/start', '/stop', '/cancel', '/audio', '/transcribe-cloud'].includes(req.url)
      ? req.url : '(unknown route)';
    const methodLabel = ['GET', 'POST', 'OPTIONS'].includes(req.method) ? req.method : 'OTHER';
    const send = (status, body) => {
      res.writeHead(status, corsHeaders(req.headers.origin));
      res.end(JSON.stringify(body));
      console.log(
        `[voice-bridge] ${methodLabel} ${routeLabel} -> ${status} (${Date.now() - started} ms) [${requestIdBase}]`,
      );
    };

    try {
      // The fence, before anything else.
      if (!hostFenceOk(req, cfg.port)) {
        return send(403, { error: { code: 'Forbidden', message: 'Host header must be 127.0.0.1:<port>' } });
      }

      // CORS alone only controls response visibility; reject side effects too.
      if (req.headers.origin && !LOOPBACK_ORIGIN.test(req.headers.origin)) {
        return send(403, { error: { code: 'Forbidden', message: 'Origin must be a loopback web origin.' } });
      }

      if (req.method === 'OPTIONS') {
        res.writeHead(204, corsHeaders(req.headers.origin));
        return res.end();
      }

      if (!authorized(req, cfg)) {
        return send(401, { error: { code: 'AuthFailed', message: 'missing or invalid bearer token' } });
      }

      if (req.method === 'GET' && req.url === '/health') {
        const probe = await upstreamCall('GET', '/health', undefined, 5_000).catch(() => null);
        const epicenter = probe && probe.status === 200 ? 'ok' : 'unreachable';
        return send(200, { ok: true, uptimeMs: Date.now() - startedAt, epicenter });
      }

      // Pairing page: shows the exact one-time localStorage snippet for the
      // DSH tab. GET only; the token is the downstream credential by design
      // (file-ACL + localhost fence), and the page is loopback-only.
      if (req.method === 'GET' && (req.url === '/' || req.url === '/index.html')) {
        const page = `<!doctype html><meta charset="utf-8"><title>dsh-voice-bridge</title>
<h2>DSH Voice Bridge</h2>
<p>epicenter: <b id=s>checking</b>; listening on 127.0.0.1:${cfg.port}</p>
<p>One-time pairing: open the DSH web tab, press F12, and run:</p>
<pre id=code style="background:#111;color:#0f0;padding:8px;user-select:all">localStorage.setItem('dsh-voice-bridge', JSON.stringify({url:'http://127.0.0.1:${cfg.port}',token:'${cfg.token}'}))</pre>
<p>Cloud transcription keys live in <code>${CONFIG_PATH}</code> (never logged).</p>
<script>fetch('/health').then(r=>r.json()).then(j=>{document.getElementById('s').textContent=j.epicenter})</script>`;
        res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
        return res.end(page);
      }

      if (req.method !== 'POST') {
        return send(404, { error: { code: 'NotFound', message: 'routes: /health /start /stop /cancel /audio /transcribe-cloud' } });
      }

      const raw = await readBody(req);
      let body = {};
      try {
        body = raw ? JSON.parse(raw) : {};
      } catch {
        return send(400, { error: { code: 'BadRequest', message: 'request body is not valid JSON' } });
      }
      if (typeof body.requestId !== 'string' || body.requestId.length === 0) {
        return send(400, { error: { code: 'BadRequest', message: 'requestId is required' } });
      }

      // Pure proxy: the bridge adds credentials and correlation context, and
      // otherwise passes request and response through verbatim.
      if (req.url === '/start') {
        let up = await upstreamCall('POST', '/start', body, UPSTREAM_TIMEOUT_MS);
        if (up.status === 409 && up.body?.error?.code === 'Busy') {
          // Orphan recovery: the slot is held by a recording this bridge
          // started earlier (its page died before stop). Cancel it, then
          // retry exactly once.
          const staleId = await loadTrackedId();
          console.log(`[voice-bridge] start busy [${requestIdBase}] -> tracked recording ${staleId ? 'present' : 'absent'}`);
          if (staleId) {
            await upstreamCall('POST', '/cancel', { requestId: body.requestId + '-recover', recordingId: staleId }, UPSTREAM_TIMEOUT_MS);
            up = await upstreamCall('POST', '/start', body, UPSTREAM_TIMEOUT_MS);
          }
        }
        if (up.status === 200 && up.body?.recordingId) {
          await saveTrackedId(up.body.recordingId);
        }
        console.log(`[voice-bridge] state: start [${requestIdBase}] -> ${up.status}`);
        return send(up.status, up.body);
      }
      if (req.url === '/stop') {
        const up = await upstreamCall('POST', '/stop', body, UPSTREAM_TIMEOUT_MS);
        if (up.status === 200) await saveTrackedId(null);
        console.log(`[voice-bridge] state: stop [${requestIdBase}] -> ${up.status}`);
        return send(up.status, up.body);
      }
      if (req.url === '/cancel') {
        const up = await upstreamCall('POST', '/cancel', body, UPSTREAM_TIMEOUT_MS);
        if (up.status === 200) await saveTrackedId(null);
        console.log(`[voice-bridge] state: cancel [${requestIdBase}] -> ${up.status}`);
        return send(up.status, up.body);
      }
      if (req.url === '/audio') {
        const up = await upstreamCall('POST', '/audio', body, UPSTREAM_TIMEOUT_MS);
        // Pass the base64 WAV through verbatim; the caller decodes it.
        return send(up.status, up.body);
      }
      if (req.url === '/transcribe-cloud') {
        // Re-read the config per call: the user edits the key file and the
        // next voice request picks it up — no restart step.
        return send(...(await transcribeCloud(body, await loadConfig(), requestIdBase)));
      }
      return send(404, { error: { code: 'NotFound', message: 'unknown route' } });
    } catch (error) {
      const tooLarge = error?.code === 413;
      return send(tooLarge ? 413 : 500, {
        requestId: null,
        error: { code: tooLarge ? 'PayloadTooLarge' : 'Internal', message: tooLarge ? 'Request body is too large.' : 'Voice Bridge request failed; check the local config and host.' },
      });
    }
  });

  // Bind loopback only, IPv4, never remote.
  server.on('error', (error) => {
    if (error && error.code === 'EADDRINUSE') {
      console.log('[voice-bridge] already running on port ' + cfg.port + ' - nothing to do');
      process.exit(0);
    }
    console.error('[voice-bridge] listen failed; check the local port and permissions.');
    process.exit(1);
  });
  server.listen(cfg.port, '127.0.0.1');
  process.on('SIGINT', () => server.close(() => process.exit(0)));
}

main().catch((error) => {
  console.error('[voice-bridge] startup failed; check the local config, port and permissions.');
  process.exit(1);
});
