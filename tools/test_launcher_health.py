"""Synthetic loopback health server; no installed service, cloud or microphone."""
import json
import os
from pathlib import Path
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
code = r'''
const http = require('node:http');
const server = http.createServer((req,res) => {
  if (req.headers.authorization !== 'Bearer ' + process.env.DSH_LAUNCHER_TEST_TOKEN) {
    res.writeHead(401);res.end('{}');return;
  }
  if (process.env.DSH_LAUNCHER_TEST_REDIRECT === 'yes') {
    res.writeHead(302,{location:'https://example.invalid/never-visit'});res.end();return;
  }
  res.writeHead(200,{'content-type':'application/json'});
  res.end(JSON.stringify({ok:true,epicenter:'ok'}));
});
server.listen(0,'127.0.0.1',()=>console.log(server.address().port));
'''

def check(redirect=False, wrong_token=False):
    value = 'SYNTHETIC-' + uuid.uuid4().hex
    env = dict(os.environ, DSH_LAUNCHER_TEST_TOKEN=value,
               DSH_LAUNCHER_TEST_REDIRECT='yes' if redirect else 'no')
    env.pop('NODE_OPTIONS', None)
    server = subprocess.Popen(['node', '-e', code], env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    try:
        port = int(server.stdout.readline().strip())
        client_env = dict(env, DSH_LAUNCHER_TEST_PORT=str(port),
                          DSH_LAUNCHER_TEST_SCRIPT=str(ROOT / 'launcher/start-voice.ps1'))
        if wrong_token:
            client_env['DSH_LAUNCHER_TEST_TOKEN'] = 'SYNTHETIC-WRONG-' + uuid.uuid4().hex
        script = ". $env:DSH_LAUNCHER_TEST_SCRIPT; $cfg=[pscustomobject]@{requireToken=$true;token=$env:DSH_LAUNCHER_TEST_TOKEN}; $answer=Get-BridgeHealth $cfg ([int]$env:DSH_LAUNCHER_TEST_PORT); [Console]::WriteLine(($answer | ConvertTo-Json -Compress))"
        result = subprocess.run(['powershell.exe', '-NoLogo', '-NoProfile', '-NonInteractive', '-Command', script],
                                env=client_env, capture_output=True, timeout=15)
        if result.returncode or value.encode() in result.stdout + result.stderr:
            raise RuntimeError('Synthetic health check failed; private diagnostics suppressed')
        return json.loads(result.stdout.strip())
    finally:
        # This handle belongs only to this newly spawned synthetic server.
        server.terminate()
        server.wait(timeout=5)

def main():
    if os.name != 'nt':
        raise RuntimeError('Windows-only test')
    assert check() is True
    assert check(wrong_token=True) is False
    assert check(redirect=True) is False
    print(json.dumps({'ok': True, 'tests': ['real-loopback-health-with-synthetic-token',
          'invalid-pairing-health-rejected', 'health-redirect-not-followed'],
          'real_cloud_calls': 0, 'real_services_started': 0, 'microphone_used': False}))

if __name__ == '__main__':
    main()
