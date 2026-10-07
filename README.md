# dsh-voice-input-cloud

**English** | [中文安裝說明](README.zh-TW.md)

**Windows only. macOS/Linux are not supported in this release.**

**No local model setup. Efficient voice input with a free-tier cloud API.**

Voice input for the **DeepSeek Harness** (DSH) web UI: a microphone control in the composer
that records through the local **Epicenter** desktop host, transcribes on the cloud with your
own API key, and writes the text into the *same* draft you were typing — it never submits.

- **Skip local model setup:** no transcription model downloads, local inference server or
  GPU configuration. Epicenter still handles recording on your computer.
- **Start with a free-tier API:** Groq offers a free plan for the supported Whisper
  transcription models, subject to its [current limits](https://console.groq.com/docs/rate-limits).
  Free availability depends on the provider and account plan; optional text polish has its
  own provider and plan. See [Groq's plan information](https://console.groq.com/docs/billing-faqs).
- **Keep control of your draft:** transcription is inserted without sending, and manual
  edits made during recording are preserved.

This repository is the release-prep tree for three artifacts:

```
DSH web plugin (mic button, composer slot)
  → HTTP :39152 Voice Bridge (Node, zero dependencies)
    → Epicenter desktop host's loopback bridge surface (record / fetch WAV)
    → Groq / OpenAI-compatible /audio/transcriptions (cloud transcription, your key)
    → optional OpenAI chat-completions polish (your key, your prompt)
  → text written back into the DSH draft via the official InputActions API
    (revision-guarded; never auto-sent)
```

## Components

| # | Path | npm package | License | What it is |
|---|------|-------------|---------|------------|
| 1 | [`bridge/`](bridge/) | `dsh-voice-bridge` | MIT | Single-file, zero-dependency Node ≥ 18 HTTP bridge on `127.0.0.1:39152` |
| 2 | [`dsh-plugin/`](dsh-plugin/) | `dsh-voice-input-cloud` | MIT | DSH client plugin (mic control in the composer) |
| 3 | [`epicenter-patch/`](epicenter-patch/) | — | **AGPL-3.0** | Patch for the Epicenter desktop host: adds the loopback voice-bridge surface and fixes two upstream bugs |
| 4 | [`launcher/`](launcher/) | — | MIT | Windows BAT/PowerShell/Node setup wizard and one-click service launcher, included in source |

Three processes, in this order:

```
DSH tab ──▶ voice-bridge (this repo's bridge/) ──▶ Epicenter desktop host (record / WAV)
                         └──────────────────▶ configured cloud providers (speech / text polish)
```

The bridge holds the two cloud API keys in its local config. Epicenter's per-launch token and
the browser pairing token are separate local credentials. The bridge binds loopback only
(`127.0.0.1`), fences requests on Host and Origin, and excludes transcript text from its logs.

## Distribution

**v0.1.0 is an early Windows release on GitHub, not on npm registry.**
Download the reviewed source and two `.tgz` packages from the
[GitHub Release](https://github.com/LatentHarbor-create/dsh-voice-input-cloud/releases/tag/v0.1.0). No npm account is needed to download or install them.
Package-name commands such as `npm install dsh-voice-bridge` are unavailable for this release.
Use the [English release installation guide](docs/INSTALL_RELEASE.md), or its
[Chinese version](docs/INSTALL_RELEASE.zh-TW.md). Source-only host build prerequisites remain.

## Requirements

- **Node ≥ 18** (the bridge uses global `fetch` and `AbortSignal.timeout`).
- **DSH ≥ 0.1.7-rc.2**. This release was tested on `0.1.7-rc.2`; earlier versions are
  outside the validated minimum, and later API changes may require compatibility checks.
- **Epicenter desktop**, built with the patch in [`epicenter-patch/`](epicenter-patch/) —
  without it there is no loopback surface and the bridge answers `503 EpicenterUnreachable`.
- **A cloud transcription key**: Groq (`whisper-large-v3` by default) or any
  OpenAI-compatible `/audio/transcriptions` endpoint. A separate OpenAI-compatible
  chat-completions key is optional, for the polish step.
- This release supports Windows only. macOS/Linux are not supported; do not use this installation workflow on those systems.

## Install, in order

### 1. Epicenter desktop, with the voice-bridge surface

Follow [`epicenter-patch/README.md`](epicenter-patch/README.md). It lists the upstream commit
the patch is cut against, the Windows build prerequisites, and the `git apply` invocation.

On startup, Epicenter writes its per-launch credential to
`%APPDATA%\so.epicenter\voice-bridge.json` (`{"port": …, "token": …}`). The bridge re-reads
that file on every upstream call, so restarting Epicenter never needs a bridge restart.

### 2. The bridge

```bash
npm install -g "https://github.com/LatentHarbor-create/dsh-voice-input-cloud/releases/download/v0.1.0/dsh-voice-bridge-0.1.0.tgz"
# Or from extracted source: npm install -g ./bridge
dsh-voice-bridge                     # listens on http://127.0.0.1:39152
```

First run writes its config to `%APPDATA%\dsh-voice-bridge\config.json` (both cloud API keys empty) and
prints the pairing URL. Open <http://127.0.0.1:39152> for the pairing snippet and a live
`epicenter: ok|unreachable` indicator. `GET /health` is the machine-readable version.

### Startup mode

Startup is manual by default. Start the patched Epicenter host, then the bridge, and run
`dsh web` if your DSH frontend is not already running. Installing the plugin does not
register a Windows startup task or service; the mic button sends requests to services
that must already be running. Closing the bridge's terminal stops the bridge.

You can also double-click [`launcher/start-voice.bat`](launcher/start-voice.bat) from the
full source distribution. Its Windows setup wizard guides program paths, the speech key,
optional polish key/model and one prompt; later launches reuse working services and drafts.
See the [Windows launcher guide](launcher/README.md) for first-run setup, reconfiguration,
private backups, pairing and diagnostics. Boot startup remains a separate optional choice.

### 3. The DSH plugin

DSH → plugin center → **Add plugin** → paste the absolute path of
[`dsh-plugin/`](dsh-plugin/) in extracted source. An installed Release tarball can also
be added by its installed directory; see the release installation guide. See [`dsh-plugin/README.md`](dsh-plugin/README.md).

Then pair the tab once (the plugin reads its bridge URL and token from `localStorage`):

```js
// DSH tab → F12 → console → paste the snippet printed on http://127.0.0.1:39152
localStorage.setItem('dsh-voice-bridge', JSON.stringify({
  url: 'http://127.0.0.1:39152',
  token: '<the token from the bridge page or config.json>'
}))
```

Click the mic → speak → click again → the transcript appears at the caret you were at. The
draft is never submitted, and if the draft moved while transcribing, the text is placed at the
current caret instead (with a short note on the control) — never overwriting your edits.

## Configuration

Everything lives in `%APPDATA%\dsh-voice-bridge\config.json`, created with empty API keys on first
run. The cloud settings are re-read for every `/transcribe-cloud` call. Restart the bridge
after changing its pairing token or `requireToken` setting.

### The two API keys

| Setting | Purpose | Required? | What is sent |
|---|---|---|---|
| `transcription.apiKey` | Speech-to-text: authenticate to the provider at `transcription.baseURL` | Required for this cloud-only plugin | The recorded WAV and selected transcription settings |
| `transformation.apiKey` | Text polish: authenticate to the provider at `transformation.baseURL` | Optional; also set `transformation.enabled: true` | The raw transcript and your polish prompt, without the WAV |

The first key turns speech into text. The second can correct wording and punctuation after
transcription. Each belongs to the provider configured in the same section; a Groq key is not
an OpenAI key. If both endpoints use the same provider, that provider may allow one credential
to serve both purposes, but the two configuration fields remain separate.
When changing providers, set a matching `baseURL` and supported `model` in that section as well
as its key. Use HTTPS for real cloud endpoints and keep credentials out of URLs.

Leaving the polish key empty or `enabled: false` returns the raw transcript. A failed polish
request also returns the raw transcript. A missing transcription key stops cloud transcription
with `CloudNotConfigured`; the plugin does not fall back to a local model.

Both keys stay in the local bridge config. Enter them locally after installation. Do not put
them into the plugin, browser localStorage, screenshots, git, npm packages, logs, or support
attachments. The pairing token in localStorage is a separate local credential, not either
cloud API key. Keep that token private too.

The configuration below is a public example with empty API keys. It does not describe the
maintainer's private setup. See [publication privacy rules](docs/PRIVACY.md) and the
[release checklist](docs/RELEASE_CHECKLIST.md).

Edit the two cloud sections in the generated local config. Preserve its generated pairing
token; do not replace that token with the public example's placeholder.

```jsonc
{
  "port": 39152,
  "token": "<generated: 32 random bytes, base64url>",
  "requireToken": false,            // true → every request needs Authorization: Bearer <token>
  "transcription": {
    "baseURL": "https://api.groq.com/openai/v1",
    "apiKey": "",                   // REQUIRED: your speech-to-text provider key
    "model": "whisper-large-v3",
    "language": ""                  // "" = auto-detect, or e.g. "zh", "en"
  },
  "transformation": {
    "enabled": false,               // ← true to polish the raw transcript
    "baseURL": "https://api.openai.com/v1",
    "apiKey": "",                   // OPTIONAL: your text-polish provider key
    "model": "gpt-4o-mini",
    "prompt": "你是語音轉寫潤飾器。修正錯字、標點與語順，保留原意、語言與專業詞彙，不要添加內容，只輸出潤飾後的文字。"
  }
}
```

- `transcription.*` — the OpenAI-compatible transcription wire (Groq, OpenAI, or a
  self-hosted gateway). `POST {baseURL}/audio/transcriptions`, multipart, one WAV.
- `transformation.prompt` is the **system prompt** of the polish call — replace it with your
  own instruction (fix punctuation, translate, structure into Markdown, …). `enabled: false`
  keeps the raw transcript. If the polish call fails for any reason, the bridge silently
  returns the raw transcript; polish is best-effort by design.
- Configure only `transformation.prompt`: combine the task, language, editing rules and
  output format in this one instruction. The bridge sends the raw transcript separately
  as the user message; no second prompt or input placeholder is needed. Use `\n` for
  line breaks inside JSON strings. The prompt reloads on the next transcription call
  and configures text polish, not the audio transcription endpoint.

- The manual first-run bridge example uses `gpt-4o-mini`. The Windows wizard suggests
  `gpt-5.4-mini` when choosing OpenAI polish; either is a configurable model choice,
  subject to the provider/account. Existing values are preserved when keeping the provider.

- Keys are read from the file, never from a URL, and never written to a log. The raw transcript
  and the polish result are also absent from logs — only lengths and state transitions appear.
- The file is only as private as your user profile's ACL. Anything running as your user can
  read it; that is the same trust level as your browser profile.

## Endpoints (bridge, all on `127.0.0.1:39152`)

| Method | Path | Purpose |
|---|---|---|
| GET | `/` | Pairing page (loopback only) with the localStorage snippet |
| GET | `/health` | `{ ok, uptimeMs, epicenter: "ok"\|"unreachable" }` |
| POST | `/start` | Start a recording (Epicenter owns the microphone) → `{ recordingId }` |
| POST | `/stop` | Stop it → `{ durationMs, byteLength }` |
| POST | `/cancel` | Discard an in-flight recording |
| POST | `/audio` | The recorded WAV, base64-wrapped |
| POST | `/transcribe-cloud` | `/audio` → cloud transcription (+ optional polish) → `{ text, transformed }` |

Every POST requires a `requestId` (string, non-empty) and answers JSON. Errors are typed:
`EpicenterUnreachable`, `UpstreamTimeout`, `CloudNotConfigured`, `CloudTranscriptionFailed`,
`Busy`, `NotRecording`, `PayloadTooLarge`, `Forbidden`, `AuthFailed`.

## Security posture

Load-bearing, and unchanged by configuration:

- binds `127.0.0.1` only, on a loopback port; no remote listener, no port forwarding story;
- every request must carry `Host: 127.0.0.1:39152` — a DNS-rebinding page cannot pass;
- CORS reflects loopback origins only, never `*`;
- requests with an explicit non-loopback Origin are rejected before any recording or cloud call;
- request bodies are capped (64 KiB, 413 past it);
- logs carry request ids, state transitions, durations and error classes — **never** transcript
  text, audio bytes, or keys;
- the DSH-side token is optional (`requireToken`). Pair before enabling it and restart the
  bridge; afterward, ordinary browser visits to the pairing/health pages return 401 because
  every route requires the bearer header. An already protected installation can pair using
  the token from local config in the snippet above; reload DSH afterward. Keep it private;
- the plugin inserts text; it never calls the submit path.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Voice start failed (EpicenterUnreachable)` | Epicenter desktop is not running, or was built without the patch (`%APPDATA%\so.epicenter\voice-bridge.json` missing). Start it, then retry. |
| `Voice start failed (Busy)` | Another recording is holding the single recorder slot. The bridge cancels a recording *it* started and retries once; a Whispering-window recording must be stopped there. |
| `Voice start failed (MicPermissionDenied)` | Windows microphone privacy setting, or another app holding the device. |
| `Voice transcription failed (CloudNotConfigured)` | `transcription.apiKey`/`baseURL` are empty in `config.json`. |
| `Voice transcription failed (CloudTranscriptionFailed)` + HTTP 401 | Check the transcription provider and key locally. The UI receives a generic status message rather than the provider's raw error body. |
| The mic button never appears | The plugin is not installed/enabled in DSH, or the DSH build predates the composer `dock` slot. |
| Button shows `Voice input unavailable (no input face)` | The session has no `inputActions` face — reload the tab. |
| Button is disabled in `transcribing` | Deliberate: one bridge call chain in flight per control. |
| `403 Forbidden (Host header must be …)` | Something is reaching the bridge under another hostname (a proxy, or a rebinding page). Use `http://127.0.0.1:39152` directly. |
| Port 39152 already in use | Another bridge instance. The second instance logs `already running … nothing to do` and exits 0. |
| Text lands at the wrong spot | The caret moved while transcribing; the fallback places text at the *current* caret and says so on the control. |

## Licensing (dual)

- `bridge/` and `dsh-plugin/` are **MIT** (root [`LICENSE`](LICENSE) and the per-package
  copies).
- `epicenter-patch/` is a derivative work of [Epicenter](https://github.com/EpicenterHQ/epicenter)
  and is therefore **AGPL-3.0** — see [`epicenter-patch/LICENSE`](epicenter-patch/LICENSE).
  The license attaches to the patch content and to any build that includes it, not to the two
  MIT packages on their own.

Because a patched Epicenter build contains AGPL-3.0 code, **do not distribute a patched
Epicenter binary** without satisfying AGPL-3.0 (source offer, notices) — the patch directory
is provided as source for local builds. The MIT packages are unaffected.

## Validation and remaining work

- This candidate's isolated Windows debug build and packaged plugin passed user-operated
  recording/cloud acceptance on DSH `0.1.7-rc.2`: new and existing composers, preservation
  of edits during recording, reconnection after host/bridge restart without a page reload,
  one visible microphone control, and no auto-submit. See [validation](docs/VALIDATION.md).
- Real optional text polish passed user-operated acceptance: two successful polish responses,
  text inserted into the draft, existing draft preserved, and no automatic send. Disabled/empty-key
  behavior and failure fallback also have synthetic coverage. Controlled real polish failure
  and required pairing have not been tested in the browser; real tests used `requireToken: false`.
  No additional real test is scheduled for this local packaging pass.
- No Windows binary is distributed here. Install the patched Epicenter host separately.
- This distribution uses GitHub source/Release assets. No npm-registry publication or market PR is included.

Repository: `LatentHarbor-create/dsh-voice-input-cloud`. Use GitHub Issues for support,
with redacted reproduction steps. Public demonstrations use synthetic text only. Public
commit author name is the approved GitHub handle; this initial commit has no email address.

For isolated runs, set the same absolute `EPICENTER_DATA_DIR` in the host and bridge. The launch discovery file follows that root; with the variable unset, the existing default path is retained. Bridge config and state still follow its process `APPDATA`.

The final local review adds a rapid-click guard to the browser client. Its four synthetic
regression checks pass; that latest change has not been retested in the real browser.
See [final review and remaining gates](docs/FINAL_REVIEW.md).
