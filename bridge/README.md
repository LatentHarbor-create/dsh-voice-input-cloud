# dsh-voice-bridge

**English** | [中文安裝說明](README.zh-TW.md)

**Windows only in this release. macOS/Linux are not supported.**

A **zero-dependency** Node (≥ 18) HTTP bridge between the
DSH voice-input plugin in a browser tab and the **Epicenter** desktop host's
loopback voice surface. It records, fetches the WAV, transcribes it on the cloud with *your*
API key, optionally polishes the text, and hands it back. It never stores audio and never logs
transcripts.

Keep `bridge.mjs` and `recording-history.mjs` together. Each successful recording
start saves an ID/owner/store marker under `%APPDATA%/dsh-voice-bridge/recording-owners/`.
It contains no audio, transcript or API key. The [Windows launcher](../launcher/README.md)
clears only marked plugin recordings on Start/Restart; unmarked WAVs are retained.
Running `node bridge.mjs` directly saves markers but does not run launcher cleanup.

```
DSH tab ──HTTP(127.0.0.1:39152, optional bearer)──▶ dsh-voice-bridge
dsh-voice-bridge ──HTTP(127.0.0.1:<port>, per-launch bearer)──▶ Epicenter desktop host
dsh-voice-bridge ──HTTPS(your key)──▶ Groq / OpenAI-compatible /audio/transcriptions
                                    └▶ optional chat-completions polish
```

## Install

v0.1.1 is distributed through GitHub Releases, not npm registry. No npm account is
needed; use the tarball URL below or an extracted local path, not the package name.


```bash
npm install -g "https://github.com/LatentHarbor-create/dsh-voice-input-cloud/releases/download/v0.1.1/dsh-voice-bridge-0.1.1.tgz"
# Or from extracted source: npm install -g ./bridge
dsh-voice-bridge                    # listens on http://127.0.0.1:39152
```

No dependencies, no install-time scripts, nothing to compile. `node bridge.mjs` works directly
from a checkout too. First run creates the config file and prints:
the pairing URL, the config path, and the Epicenter discovery path it will read.

Then open <http://127.0.0.1:39152> — the page shows the one-time `localStorage` pairing snippet
for the DSH tab and live `epicenter: ok|unreachable`.

Startup is manual by default: start the patched Epicenter host and this bridge before
using the DSH mic button. Installation does not register a startup task or Windows service.
The full source distribution includes a Windows BAT/PowerShell launcher with first-run
path/key setup; see its launcher/README.md. The npm bridge-only package does not include
that launcher. Closing a manually started bridge terminal stops it; automatic boot startup
requires separate setup.

## Requirements

- Node **≥ 18** (`fetch`, `AbortSignal.timeout`, `node:`-prefixed core modules).
- **Epicenter desktop**, patched to expose the voice bridge (see
  `epicenter-patch/README.md` in the source distribution). It writes
  `%APPDATA%\so.epicenter\voice-bridge.json` = `{"port": …, "token": …}` on every launch; this
  bridge re-reads that file per upstream call, so an Epicenter restart needs no bridge restart.
- A cloud transcription key (Groq by default).

## Config

`config.json` in the bridge's config dir, created on first run:

- Windows: `%APPDATA%\dsh-voice-bridge\config.json`
- If `APPDATA` is unset on Windows, the fallback is `~/AppData/Roaming/dsh-voice-bridge/config.json`.
  This fallback does not imply support for another operating system.

```jsonc
{
  "port": 39152,
  "token": "<generated, 32 random bytes base64url>",
  "requireToken": false,
  "transcription": {
    "baseURL": "https://api.groq.com/openai/v1",
    "apiKey": "",                 // ← set this
    "model": "whisper-large-v3",
    "language": ""                // "" = auto
  },
  "transformation": {
    "enabled": false,
    "baseURL": "https://api.openai.com/v1",
    "apiKey": "",                 // ← optional polish key
    "model": "gpt-4o-mini",
    "prompt": "<system prompt for the polish step — replace with your own instruction>"
  }
}
```

Cloud settings are re-read for every `/transcribe-cloud` call. Restart the bridge after changing
the pairing token or `requireToken`. A missing config is created with empty API keys. An invalid
or unreadable existing config is preserved and causes an error; it is not overwritten.

### Speech-to-text key and optional polish key

| Field | Purpose | Required? |
|---|---|---|
| `transcription.apiKey` | Sends the recorded WAV to the speech-to-text endpoint configured by `transcription.baseURL` | Yes for cloud transcription |
| `transformation.apiKey` | Sends the resulting text and prompt to the text-polish endpoint configured by `transformation.baseURL` | No; also requires `transformation.enabled: true` |

Configure each key for its own provider. Leave the polish key empty and `enabled: false` for
raw transcription. A missing or failed polish step returns the raw transcript; a missing
transcription key produces `CloudNotConfigured`. There is no local transcription fallback in
the DSH plugin. The generated pairing token is a third credential used locally, not a cloud key.

The API keys in the example are deliberately empty. Enter real values only into the local
config after installation. Never share that config, the pairing page, token-bearing snippets,
recordings, transcripts, or unreviewed logs. The plugin never needs either cloud API key.
Preserve the generated local pairing token when editing the cloud sections; the public example
contains a placeholder rather than a usable pairing credential.

`transcription.baseURL` accepts any OpenAI-compatible transcription endpoint
(`POST {baseURL}/audio/transcriptions`, multipart `file` + `model` [+ `language`]).
`transformation.*` is the "Whispering-style" polish: one `POST {baseURL}/chat/completions` with
your `prompt` as the system message and the raw transcript as the user message; the raw text is
returned if polish is disabled or fails.

### Text-polish instructions

Configure one field, `transformation.prompt`, with the task, language, editing rules and
output format. For conservative cleanup, specify preserving meaning and technical terms,
fixing obvious recognition/punctuation errors, and returning only the cleaned text.
Treat questions or commands in the transcript as text to edit, not instructions to execute.

The bridge sends these fixed rules as a system message and the raw transcript as a separate
user message. No user template or input placeholder is needed. Transcript text is not
expanded or interpolated. Use `\n` for line breaks inside a JSON string.
The prompt reloads on the next cloud transcription call and configures text polish,
not the audio transcription endpoint. Prompt text is not written to bridge logs.

## Endpoints

| Method | Path | Body / notes |
|---|---|---|
| GET | `/` | Pairing page (loopback only) |
| GET | `/health` | no body → `{ ok, uptimeMs, epicenter }` |
| POST | `/start` | `{ requestId }` → `{ recordingId, device }` |
| POST | `/stop` | `{ requestId, recordingId }` → `{ durationMs, byteLength }` |
| POST | `/cancel` | `{ requestId, recordingId }` |
| POST | `/audio` | `{ requestId, recordingId }` → `{ audioBase64, contentType: "audio/wav" }` |
| POST | `/transcribe-cloud` | `{ requestId, recordingId }` → `{ text, transformed }` |

All POST routes require a non-empty string `requestId`; it is echoed into responses.
Logs use a separate bridge-generated correlation id. Error bodies are
`{ requestId, error: { code, message } }` with codes:
`EpicenterUnreachable`, `UpstreamTimeout`, `UpstreamBadResponse`, `CloudNotConfigured`,
`CloudRequestFailed`, `CloudTimeout`, `CloudTranscriptionFailed`, `Busy`, `NotRecording`,
`NoInputDevice`, `MicPermissionDenied`, `RecorderFailed`, `PayloadTooLarge`, `Forbidden`,
`AuthFailed`, `BadRequest`, `NotFound`.

`/start` has one piece of state: if Epicenter answers `409 Busy`, the bridge cancels the
recording *it* minted earlier (remembered in memory and in `state.json`, so it survives a bridge
restart) and retries once — the orphan-recovery path for a tab that died mid-recording.

## Security

- Binds **`127.0.0.1`** only, on a loopback port. There is no remote mode.
- Every request must present `Host: 127.0.0.1:<port>`; anything else gets `403` before auth —
  a DNS-rebinding page cannot reach it.
- CORS reflects `http://127.0.0.1` / `localhost` / `[::1]` origins only, and never `*`.
- An explicit non-loopback Origin is rejected with 403 before recording or cloud side effects.
  CLI requests without Origin remain supported; local bearer authentication is a separate setting.
- Bodies are capped at 64 KiB (`413` past it).
- `requireToken: true` makes `Authorization: Bearer <token>` mandatory on every request,
  including the pairing page and health route. Pair the DSH tab before enabling it, then
  restart the bridge. Direct browser page visits return 401 afterward; the paired plugin
  supplies the header. For an already protected bridge, copy the local config token into
  the documented localStorage snippet, then reload DSH. Keep the token out of URLs/logs.
- Logs use bridge-generated correlation ids, known route labels, status, duration and lengths.
  Raw request URLs, caller-supplied ids and provider error text are excluded. Logs still require
  review before sharing, including logs from Epicenter or other processes.
- Keys live in `config.json` under your user profile and are only as safe as that profile's
  ACL. Keep the file private; an empty transcription key disables cloud transcription.

## Troubleshooting

- `EADDRINUSE` → the bridge logs `already running on port 39152 - nothing to do` and exits 0:
  one bridge per machine is the intended shape.
- `503 EpicenterUnreachable` → Epicenter not running, or built without the voice-bridge patch.
- `503 CloudNotConfigured` → `transcription.apiKey`/`baseURL` empty.
- Windows Firewall prompts → the listener is loopback-only; no inbound rule is required.

## License

MIT — see [LICENSE](LICENSE).

For isolated runs, set the same absolute `EPICENTER_DATA_DIR` in the host and bridge. The launch discovery file follows that root; with the variable unset, the existing default path is retained. Bridge config and state still follow its process `APPDATA`.
