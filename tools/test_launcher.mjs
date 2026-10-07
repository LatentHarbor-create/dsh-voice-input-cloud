// Synthetic subprocesses only; no listeners, real DSH, cloud, or microphone.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { EventEmitter, once } from 'node:events';
import { mkdtempSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { localLaunchURL, dshArguments, startDetached, startDsh, writeStatus } from '../launcher/launch-service.mjs';

const tests = [];
const workArg = process.argv.indexOf('--work-directory');
const root = mkdtempSync(join(workArg >= 0 ? resolve(process.argv[workArg + 1]) : tmpdir(), 'dsh-launcher-'));
const loginValue = 'SYNTHETIC-' + randomUUID();
const url = 'http://127.0.0.1:3080/?token=' + loginValue;
assert.equal(localLaunchURL('dsh web: ' + url, 3080), url);
assert.equal(localLaunchURL('dsh web: https://example.invalid/?token=' + loginValue, 3080), null);
assert.equal(localLaunchURL('dsh web: http://127.0.0.1:3081/', 3080), null);
assert.equal(localLaunchURL('dsh web: http://' + 'user:password@127.0.0.1:3080/', 3080), null);
assert.equal(localLaunchURL('other output ' + url, 3080), null);
tests.push('authenticated-url-loopback-port-and-userinfo-fence');
assert.deepEqual(dshArguments(3080), ['web', '--host', '127.0.0.1', '--port', '3080', '--no-open']);
tests.push('dsh-loopback-no-auto-open-arguments');
const status = join(root, 'status.json');
writeStatus(status, { ready: true, port: 3080 });
assert.ok(!readFileSync(status, 'utf8').includes(loginValue));
tests.push('status-excludes-authentication-url');
const entry = join(root, '測試 space & cli.mjs');
writeFileSync(entry, `process.stdout.write(${JSON.stringify('dsh web: ' + url + '\n')});setTimeout(()=>{},150);`);
const launched = [];
const events = [];
function launch(exe, args, options) {
  launched.push({ exe, args, options });
  if (exe === process.execPath) return spawn(exe, args, options);
  const browser = new EventEmitter();
  setImmediate(() => browser.emit('exit', 0));
  return browser;
}
const child = startDsh({ nodeExe: process.execPath, dshEntry: entry, dshPort: 3080 }, status, false, {
  spawn: launch, save: (path, value) => { events.push(value); writeStatus(path, value); }, env: {},
});
await once(child, 'exit');
assert.equal(events.length, 1);
assert.equal(events[0].ready, true);
assert.equal(events[0].browserOpened, true);
assert.equal(launched.length, 2);
assert.equal(launched[1].options.env.DSH_VOICE_BROWSER_URL, url);
assert.ok(!JSON.stringify(launched.map(item => item.args)).includes(loginValue));
assert.ok(!readFileSync(status, 'utf8').includes(loginValue));
tests.push('real-synthetic-subprocess-path-and-private-browser-url');
const browserFailures = [];
const browserFailChild = startDsh({ nodeExe: process.execPath, dshEntry: entry, dshPort: 3080 }, status, false, {
  spawn: (exe, args, options) => {
    if (exe === process.execPath) return spawn(exe, args, options);
    const browser = new EventEmitter();
    setImmediate(() => browser.emit('error', new Error('synthetic-private-' + loginValue)));
    return browser;
  },
  save: (path, value) => browserFailures.push(value), env: {},
});
await once(browserFailChild, 'exit');
assert.deepEqual(browserFailures, [{ready:true, port:3080, browserOpened:false}]);
assert.ok(!JSON.stringify(browserFailures).includes(loginValue));
tests.push('browser-error-is-reported-without-authentication-url');
const badEntry = join(root, 'failed.mjs');
writeFileSync(badEntry, `process.stderr.write(${JSON.stringify('private synthetic value ' + loginValue)});process.exit(1);`);
const failures = [];
const bad = startDsh({ nodeExe: process.execPath, dshEntry: badEntry, dshPort: 3080 }, status, true, {
  save: (path, value) => failures.push(value), env: {},
});
await once(bad, 'exit');
assert.deepEqual(failures, [{ ready: false, reason: 'DshStartupFailed' }]);
assert.ok(!JSON.stringify(failures).includes(loginValue));
tests.push('failed-dsh-output-discarded-and-safe-status');
let detachedOptions;
const fake = new EventEmitter(); fake.unref = () => {};
startDetached(process.execPath, [entry], {}, (exe, args, options) => { detachedOptions = options; return fake; });
assert.equal(detachedOptions.stdio, 'ignore');
assert.equal(detachedOptions.windowsHide, true);
assert.equal(detachedOptions.detached, true);
tests.push('background-host-bridge-output-not-persisted');
if (process.platform === 'win32') {
  const marker = join(root, 'detached-marker.json');
  const bridgeEntry = join(root, '獨立 bridge & stub.mjs');
  writeFileSync(bridgeEntry, `import{writeFileSync}from'node:fs';writeFileSync(${JSON.stringify(marker)},'{}');`);
  const paths = join(root, 'paths.json');
  writeFileSync(paths, JSON.stringify({nodeExe:process.execPath,epicenterExe:process.execPath,bridgeEntry,dshEntry:entry,dshPort:3080}));
  const helper = new URL('../launcher/launch-service.mjs', import.meta.url);
  const worker = spawn(process.execPath, [fileURLToPath(helper), '--settings', paths, '--role', 'bridge'], {stdio:'ignore', windowsHide:true});
  const [code] = await once(worker, 'exit');
  assert.equal(code, 0);
  for (let attempt=0;attempt<30;attempt++) {
    try { readFileSync(marker); break; } catch { await new Promise(resolve => setTimeout(resolve,50)); }
  }
  assert.equal(readFileSync(marker, 'utf8'), '{}');
  tests.push('actual-windows-detached-helper-with-synthetic-bridge');
  const invalidPaths = join(root, 'invalid-paths.json');
  writeFileSync(invalidPaths, JSON.stringify({nodeExe:process.execPath,epicenterExe:process.execPath,bridgeEntry,dshEntry:entry,dshPort:'3080'}));
  const invalidWorker = spawn(process.execPath, [fileURLToPath(helper), '--settings', invalidPaths, '--role', 'bridge'], {stdio:'ignore', windowsHide:true});
  const [invalidCode] = await once(invalidWorker, 'exit');
  assert.equal(invalidCode, 1);
  tests.push('helper-invalid-settings-refused-before-spawn');
}
console.log(JSON.stringify({ok:true, tests, real_cloud_calls:0, real_services_started:0, microphone_used:false}));
