#!/usr/bin/env python3
"""Offline synthetic privacy smoke test; no microphone or real provider calls."""
import argparse
import base64
import http.client
import json
import os
import pathlib
import socket
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = pathlib.Path(__file__).resolve().parents[1]
PORT = 39152
FAKE_SPEECH_KEY = 'SYNTHETIC_SPEECH_CREDENTIAL_NOT_VALID'
FAKE_POLISH_KEY = 'SYNTHETIC_POLISH_CREDENTIAL_NOT_VALID'
RAW_TEXT = 'SYNTHETIC_RAW_TRANSCRIPT_NOT_A_REAL_RECORDING'
POLISHED_TEXT = 'SYNTHETIC_POLISHED_TRANSCRIPT_NOT_A_REAL_RECORDING'
CALLER_ID = 'SYNTHETIC_CALLER_ID_NOT_FOR_LOGS'
QUERY_CANARY = 'SYNTHETIC_URL_CONTENT_NOT_FOR_LOGS'
TOKEN = 'SYNTHETIC_PAIRING_CREDENTIAL_NOT_VALID_32'
INVALID_CANARY = 'SYNTHETIC_INVALID_JSON_CONTENT'
PROMPT_CANARY = 'SYNTHETIC_PRIVATE_SYSTEM_PROMPT_NOT_FOR_LOGS'

def request(method, path, body=None, host=None, token=None, origin=None, content_type='application/json'):
    connection = http.client.HTTPConnection('127.0.0.1', PORT, timeout=5)
    headers = {'content-type': content_type}
    if origin:
        headers['origin'] = origin
    if host:
        headers['host'] = host
    if token:
        headers['authorization'] = 'Bearer ' + token
    try:
        connection.request(method, path, None if body is None else json.dumps(body), headers)
        response = connection.getresponse()
        raw = response.read()
        return response.status, raw
    finally:
        connection.close()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bridge', type=pathlib.Path, default=ROOT / 'bridge/bridge.mjs')
    args = parser.parse_args()
    bridge = args.bridge.resolve()
    # Refuse to interact with or stop an existing user process on the fixed port.
    with socket.socket() as guard:
        guard.bind(('127.0.0.1', PORT))
    state = {'mode': 'success', 'calls': [], 'failure': None,
             'speech_text': RAW_TEXT, 'expected_user': RAW_TEXT,
             'expected_system': None, 'polish_messages': None}
    wav = b'RIFF' + b'\0' * 36 + b'WAVE'
    class Mock(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass
        def do_GET(self):
            self.reply(200, {'ok': True})
        def do_POST(self):
            body = self.rfile.read(int(self.headers.get('content-length', '0')))
            state['calls'].append(self.path)
            if self.path == '/audio':
                if self.headers.get('authorization') != 'Bearer ' + TOKEN:
                    state['failure'] = 'synthetic upstream auth mismatch'
                self.reply(200, {'audioBase64': base64.b64encode(wav).decode(), 'contentType': 'audio/wav'})
            elif self.path == '/v1/audio/transcriptions':
                if self.headers.get('authorization') != 'Bearer ' + FAKE_SPEECH_KEY or wav not in body:
                    state['failure'] = 'synthetic speech request mismatch'
                if state['mode'] == 'speech-failure':
                    self.reply(401, {'error': {'message': FAKE_SPEECH_KEY + RAW_TEXT}})
                else:
                    self.reply(200, {'text': state['speech_text']})
            elif self.path == '/v1/chat/completions':
                parsed = json.loads(body)
                state['polish_messages'] = parsed['messages']
                if (self.headers.get('authorization') != 'Bearer ' + FAKE_POLISH_KEY
                        or parsed['messages'][1]['role'] != 'user'
                        or parsed['messages'][1]['content'] != state['expected_user']
                        or parsed['messages'][0]['role'] != 'system'
                        or (state['expected_system'] is not None
                            and parsed['messages'][0]['content'] != state['expected_system'])):
                    state['failure'] = 'synthetic polish request mismatch'
                if state['mode'] == 'polish-failure':
                    self.reply(500, {'error': {'message': FAKE_POLISH_KEY + RAW_TEXT}})
                else:
                    self.reply(200, {'choices': [{'message': {'content': POLISHED_TEXT}}]})
            else:
                self.reply(404, {})
        def reply(self, status, body):
            raw = json.dumps(body).encode()
            self.send_response(status)
            self.send_header('content-type', 'application/json')
            self.send_header('content-length', str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)
    server = ThreadingHTTPServer(('127.0.0.1', 0), Mock)
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    passed = []
    with tempfile.TemporaryDirectory(prefix='synthetic-bridge-privacy-') as directory:
        home = pathlib.Path(directory)
        config_dir = home / 'dsh-voice-bridge'
        config_dir.mkdir()
        config_path = config_dir / 'config.json'
        discovery_dir = home / 'custom-epicenter-root'
        discovery_dir.mkdir()
        discovery = {'port': server.server_port, 'token': TOKEN}
        (discovery_dir / 'voice-bridge.json').write_text(json.dumps(discovery))
        config = {'token': TOKEN, 'requireToken': False, 'transcription': {'apiKey': '',
                  'baseURL': 'http://127.0.0.1:' + str(server.server_port) + '/v1'},
                  'transformation': {'enabled': False, 'apiKey': '',
                  'baseURL': 'http://127.0.0.1:' + str(server.server_port) + '/v1'}}
        def save():
            config_path.write_text(json.dumps(config), encoding='utf-8')
        save()
        environment = dict(os.environ, APPDATA=str(home), EPICENTER_DATA_DIR=str(discovery_dir))
        environment.pop('NODE_OPTIONS', None)
        process = None
        log_path = home / 'private-test.log'
        with log_path.open('wb') as log:
            def start():
                nonlocal process
                process = subprocess.Popen(['node', str(bridge)], env=environment, stdout=log, stderr=log)
                for _ in range(50):
                    if process.poll() is not None:
                        raise RuntimeError('synthetic bridge startup failed')
                    try:
                        request('GET', '/health')
                        return
                    except OSError:
                        time.sleep(0.1)
                raise RuntimeError('synthetic bridge startup timed out')
            def stop():
                nonlocal process
                if process is not None and process.poll() is None:
                    process.terminate()
                    process.wait(timeout=10)
                process = None
            def check(condition, name):
                if not condition:
                    raise RuntimeError(name)
                passed.append(name)
            body = {'requestId': CALLER_ID, 'recordingId': 'SYNTHETIC_RECORDING_ID'}
            try:
                start()
                status, raw = request('GET', '/health', host='evil.example.invalid')
                check(status == 403, 'host-fence')
                calls_before = len(state['calls'])
                status, _ = request('POST', '/start', body, origin='https://evil.example.invalid', content_type='text/plain')
                check(status == 403 and len(state['calls']) == calls_before, 'external-origin-post-rejected-before-upstream')
                check(request('OPTIONS', '/transcribe-cloud', origin='http://127.0.0.1:3080')[0] == 204, 'loopback-origin-preflight-allowed')
                request('GET', '/unknown?' + QUERY_CANARY)
                status, raw = request('POST', '/transcribe-cloud', body)
                check(status == 503 and json.loads(raw)['error']['code'] == 'CloudNotConfigured', 'missing-speech-key')
                config['transcription']['apiKey'] = FAKE_SPEECH_KEY
                save()
                status, raw = request('POST', '/transcribe-cloud', body)
                check(status == 200 and json.loads(raw)['text'] == RAW_TEXT and '/v1/chat/completions' not in state['calls'], 'raw-text-without-polish')
                config['transformation']['enabled'] = True
                save()
                status, raw = request('POST', '/transcribe-cloud', body)
                check(status == 200 and json.loads(raw)['text'] == RAW_TEXT and '/v1/chat/completions' not in state['calls'], 'enabled-polish-without-key-returns-raw')
                config['transformation'].update(enabled=True, apiKey=FAKE_POLISH_KEY)
                save()
                status, raw = request('POST', '/transcribe-cloud', body)
                check(status == 200 and json.loads(raw)['text'] == POLISHED_TEXT and json.loads(raw)['transformed'], 'two-distinct-keys-and-polish')
                config['transformation'].update(prompt=PROMPT_CANARY,
                    userPromptTemplate='SYNTHETIC_LEGACY_TEMPLATE_IGNORED {{input}}')
                state['expected_system'] = PROMPT_CANARY
                state['speech_text'] = RAW_TEXT + ' {{input}} $&'
                state['expected_user'] = state['speech_text']
                save()
                status, raw = request('POST', '/transcribe-cloud', body)
                check(status == 200 and json.loads(raw)['transformed'] and state['failure'] is None,
                    'single-system-prompt-and-unaltered-user-transcript')
                state['speech_text'] = RAW_TEXT
                state['expected_user'] = RAW_TEXT
                config['transformation'].pop('userPromptTemplate')
                save()
                state['mode'] = 'polish-failure'
                status, raw = request('POST', '/transcribe-cloud', body)
                check(status == 200 and json.loads(raw)['text'] == RAW_TEXT and not json.loads(raw)['transformed'], 'polish-failure-raw-fallback')
                state['mode'] = 'speech-failure'
                status, raw = request('POST', '/transcribe-cloud', body)
                check(status == 401 and FAKE_SPEECH_KEY.encode() not in raw and RAW_TEXT.encode() not in raw, 'provider-error-redaction')
                invalid = json.dumps({'apiKey': INVALID_CANARY}).encode()[:-1]
                config_path.write_bytes(invalid)
                status, raw = request('POST', '/transcribe-cloud', body)
                check(status == 500 and config_path.read_bytes() == invalid and b'SYNTHETIC_INVALID_JSON_CONTENT' not in raw, 'invalid-config-preserved-and-redacted')
                stop()
                config['requireToken'] = True
                save()
                start()
                check(request('GET', '/health')[0] == 401, 'pairing-auth-required-after-restart')
                check(request('GET', '/health', token=TOKEN)[0] == 200, 'pairing-auth-valid')
                state['mode'] = 'success'
                check(request('POST', '/transcribe-cloud', body, token=TOKEN)[0] == 200, 'configured-discovery-root-after-restart')
                check(state['failure'] is None, 'mock-provider-payload-contract')
            finally:
                stop()
                server.shutdown()
                server.server_close()
        logs = log_path.read_text(encoding='utf-8')
        for marker in [FAKE_SPEECH_KEY, FAKE_POLISH_KEY, RAW_TEXT, POLISHED_TEXT, CALLER_ID, QUERY_CANARY, TOKEN, 'SYNTHETIC_INVALID_JSON_CONTENT', PROMPT_CANARY, 'SYNTHETIC_LEGACY_TEMPLATE_IGNORED']:
            if marker in logs:
                raise RuntimeError('synthetic log privacy assertion failed')
        passed.append('logs-exclude-all-synthetic-sensitive-canaries')
    print(json.dumps({'ok': True, 'tests': passed, 'real_cloud_calls': 0, 'microphone_used': False}, indent=2))

if __name__ == '__main__':
    try:
        main()
    except Exception:
        # Never print captured bridge logs or assertion payloads.
        print(json.dumps({'ok': False, 'error': 'synthetic privacy smoke failed; no private data printed'}))
        raise SystemExit(1)
