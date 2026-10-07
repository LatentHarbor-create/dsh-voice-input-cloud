# dsh-voice-input-cloud

**English** | [中文安裝說明](README.zh-TW.md)

**This release supports Windows only. macOS/Linux are not supported.** Both npm packages
declare `os: ["win32"]`. The Windows launcher with path/key setup is included in the full
source distribution, not this plugin-only package; read its `launcher/README.md`.

Voice input for the **DeepSeek Harness** (DSH) web UI. One microphone control in the composer;
click to record, click again to stop, and the transcript is inserted at the caret you were at
when you clicked. **It never submits** — the draft is only ever filled.

```
click → captureInsertion()          (revision-guarded caret span)
      → POST bridge /start          (Epicenter host records)
click → POST /stop → POST /transcribe-cloud
      → insertText(text, span)       ← official InputActions API
```

Everything else — recording, audio, cloud transcription — happens in the local
`dsh-voice-bridge` process on `127.0.0.1`. This plugin is UI plus the HTTP calls;
it holds no cloud API keys and touches no audio. Its localStorage may contain the local pairing
token, which should also stay private.

## The two cloud API keys

Configure these in `%APPDATA%\dsh-voice-bridge\config.json`, never in this plugin:

- `transcription.apiKey`: required for speech-to-text; the bridge sends the WAV to the provider
  selected by `transcription.baseURL`.
- `transformation.apiKey`: optional for wording and punctuation polish; enable with
  `transformation.enabled: true`. Only the transcript and prompt go to this second endpoint.

Each key must belong to its configured provider. With polish disabled, an empty polish key,
or a failed polish request, the bridge returns the raw transcript. A missing transcription key
is an error; this plugin does not fall back to a local model. The public examples contain no
real key and do not reveal how any maintainer has configured their installation.

## npm / plugin name

- **npm package:** `dsh-voice-input-cloud`. The `-cloud` suffix identifies the cloud-only
  transcription path.
- **DSH entry and control ids:** `dsh-voice-input`. The Loader specifier and browser
  module registration use the npm package name `dsh-voice-input-cloud`, so installed
  packages resolve consistently. The visible control ids remain unchanged.

## Install

v0.1.0 is distributed on GitHub Releases, not npm registry. Use extracted source or an
installed Release tarball directory; package-name installation is not available yet.


The tested DSH version is `0.1.7-rc.2`; the candidate's declared minimum is
that version. Earlier versions have not been validated in this release pass.
Later versions still need compatibility checks if their input or slot APIs change.

1. **Epicenter desktop** with the voice-bridge surface, and the **bridge** running — see the
   source distribution's root README for the order.
2. DSH → plugin center → **Add plugin**:
   - paste the absolute path of this directory (`…/dsh-voice-input-cloud/dsh-plugin`) for a local
     install.
3. Enable it if the plugin center asks, then reload the DSH tab.
4. Pair the tab once — the plugin reads `{ url, token }` from `localStorage` under the key
   `dsh-voice-bridge`. Open <http://127.0.0.1:39152> and paste the snippet it prints:

```js
localStorage.setItem('dsh-voice-bridge', JSON.stringify({
  url: 'http://127.0.0.1:39152',
  token: '<token from http://127.0.0.1:39152>'
}))
```

Without that key the plugin falls back to `http://127.0.0.1:39152` with no token — fine when
the bridge runs with `requireToken: false` (its default).

## What you see

| Control | Meaning |
|---|---|
| `🎤 語音輸入` | idle — click to start recording |
| `⏳ 啟動錄音中…` | waiting for start; rapid clicks are ignored |
| `● 停止並轉寫（錄音中）` | recording — click to stop and transcribe |
| `⏳ 轉寫中…` | one bridge call chain in flight; the control is disabled |
| red text | the error message from the bridge (e.g. `EpicenterUnreachable`, `CloudNotConfigured`) |
| note next to the control | the caret moved while transcribing, so the text went to the current caret |

The control lives in the composer dock (`conversation.composer.dock`, session-scoped) and, while
a session is still blank, in the composer input dock (`conversation.input.dock`) — exactly one
button is visible at any moment.

## Behavior guarantees

- **No auto-submit.** The plugin never calls the submit path; it only inserts text.
- **Revision-guarded insert.** The caret is captured before the request, so text lands where you
  clicked. If the draft moved on, `insertText` is refused rather than overwriting; the plugin
  then re-captures the caret, inserts there, and says so on the control.
- **No `setDraft`.** A transcript never replaces a draft wholesale.
- **UI-only failures.** If the plugin throws while registering, it unregisters quietly and DSH
  keeps working.

## Troubleshooting

| Symptom | Fix |
|---|---|
| No mic control appears | Plugin not installed/enabled, or the DSH build has no `composer.dock` slot. |
| `Voice input unavailable (no input face)` | This session exposes no `inputActions`; reload the tab. |
| `Voice start failed (EpicenterUnreachable)` | Epicenter desktop not running, or unpatched. |
| `Voice transcription failed (CloudNotConfigured)` | Set `transcription.apiKey` in the bridge config. |
| Transcript appears in the wrong place | The caret moved; see the note on the control — nothing was overwritten. |
| `403 Forbidden` | The tab reached the bridge under a non-loopback host; use `http://127.0.0.1:39152`. |

## Implementation notes

- The client half is shipped as a **hand-written `__ModuleLoader__` bundle**
  (`lib/client.js`) rather than produced by a bundler: the module is a few hundred lines of
  plain `react` / `react/jsx-runtime` calls, and a hand-written bundle keeps the package
  dependency-free and reviewable. No build step, no `dist/`.
- `lib/index.js` is the host half. It is deliberately a no-op: a bundle must contribute at
  least one host row for the Loader to carry it, and therefore for the client scan to see its
  `dsh.client` declaration. All state lives in the bridge process.
- `cordis.patch.yml` contributes that single host row.

## License

MIT — see [LICENSE](LICENSE). (The `epicenter-patch/` directory in this repository is a
separate, AGPL-3.0-licensed patch for a different project; this package does not include it.)
