// Windows-only helper. No persistent stdout/stderr logs; no cloud or microphone calls.
import { spawn } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync, renameSync } from 'node:fs';
import { dirname, join, resolve, isAbsolute } from 'node:path';
import { homedir } from 'node:os';
import { pathToFileURL } from 'node:url';

export function localLaunchURL(line, port) {
  const match = /dsh web:\s+(https?:\/\/\S+)/.exec(line);
  if (!match) return null;
  try {
    const url = new URL(match[1]);
    if (url.protocol !== 'http:' || url.hostname !== '127.0.0.1' || Number(url.port) !== port || url.username || url.password) return null;
    return url.href;
  } catch { return null; }
}
export function writeStatus(path, value) {
  const temp = path + '.tmp';
  writeFileSync(temp, JSON.stringify(value), { encoding: 'utf8', mode: 0o600 });
  renameSync(temp, path);
}
export function dshArguments(port) {
  return ['web', '--host', '127.0.0.1', '--port', String(port), '--no-open'];
}
export function startDetached(executable, args, env, spawnFn = spawn, report = () => {}) {
  const child = spawnFn(executable, args, { cwd: dirname(executable), env, windowsHide: true, detached: true, stdio: 'ignore' });
  child.on('spawn', () => report({ ready: true, pid: child.pid }));
  child.on('error', () => { report({ ready: false, reason: 'WorkerSpawnFailed' }); process.exitCode = 1; });
  child.unref();
  return child;
}
export function startDsh(settings, status, noBrowser, dependencies = {}) {
  const spawnFn = dependencies.spawn || spawn;
  const save = dependencies.save || writeStatus;
  const env = dependencies.env || process.env;
  let announced = false;
  let pending = '';
  const child = spawnFn(settings.nodeExe, [settings.dshEntry, ...dshArguments(settings.dshPort)], {
    cwd: dirname(settings.dshEntry), env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'],
  });
  function failed() { if (!announced) { announced = true; save(status, { ready: false, reason: 'DshStartupFailed' }); } }
  function lineReceived(line) {
    if (announced) return;
    const url = localLaunchURL(line, settings.dshPort);
    if (!url) return;
    announced = true;
    if (noBrowser) { save(status, { ready: true, port: settings.dshPort, browserOpened: false }); }
    else {
      // The URL may contain a login token. Pass it internally via environment, not arguments/logs.
      let reported = false;
      let timer;
      function browserResult(opened) {
        if (reported) return;
        reported = true;
        clearTimeout(timer);
        save(status, { ready: true, port: settings.dshPort, browserOpened: opened });
      }
      try {
        const browser = spawnFn('powershell.exe', ['-NoLogo', '-NoProfile', '-Command', 'Start-Process -FilePath $env:DSH_VOICE_BROWSER_URL -ErrorAction Stop'], {
          env: { ...env, DSH_VOICE_BROWSER_URL: url }, windowsHide: true, stdio: 'ignore',
        });
        timer = setTimeout(() => browserResult(false), 8000);
        browser.on('error', () => browserResult(false));
        browser.on('exit', code => browserResult(code === 0));
      } catch { browserResult(false); }
    }
  }
  child.stdout.on('data', chunk => {
    pending += chunk.toString('utf8');
    const lines = pending.split(/\r?\n/);
    pending = lines.pop();
    for (const line of lines) lineReceived(line);
    if (pending.length > 16384) pending = '';
  });
  // Drain arbitrary stderr without logging provider bodies, keys or authentication URLs.
  child.stderr.on('data', () => {});
  child.on('error', failed);
  child.on('exit', () => { if (pending) lineReceived(pending); failed(); });
  return child;
}
function main() {
  if (process.platform !== 'win32') throw new Error('WindowsOnly');
  const args = process.argv.slice(2);
  const argument = name => args[args.indexOf(name) + 1];
  if (!args.includes('--settings') || !args.includes('--role')) throw new Error('InvalidArguments');
  const settings = JSON.parse(readFileSync(argument('--settings'), 'utf8'));
  for (const field of ['nodeExe', 'epicenterExe', 'bridgeEntry', 'dshEntry']) {
    if (typeof settings[field] !== 'string' || !isAbsolute(settings[field]) || !existsSync(settings[field])) throw new Error('InvalidPaths');
  }
  if (!Number.isInteger(settings.dshPort) || settings.dshPort < 1024 || settings.dshPort > 65535 || settings.dshPort === 39152) throw new Error('InvalidPort');
  const env = { ...process.env };
  const bun = join(homedir(), '.bun', 'bin');
  const pathValue = Object.keys(env).find(key => key.toLowerCase() === 'path');
  const searchPath = pathValue ? env[pathValue] : '';
  for (const key of Object.keys(env)) if (key.toLowerCase() === 'path') delete env[key];
  env.PATH = (existsSync(bun) ? bun + ';' : '') + searchPath;
  delete env.NODE_OPTIONS;
  const role = argument('--role');
  const report = value => { if (args.includes('--status')) writeStatus(argument('--status'), value); };
  if (role === 'host') startDetached(settings.epicenterExe, [], env, spawn, report);
  else if (role === 'bridge') startDetached(settings.nodeExe, [settings.bridgeEntry], env, spawn, report);
  else if (role === 'dsh' && args.includes('--status')) startDsh(settings, argument('--status'), args.includes('--no-browser'), { env });
  else throw new Error('InvalidRole');
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try { main(); } catch { process.exitCode = 1; }
}
