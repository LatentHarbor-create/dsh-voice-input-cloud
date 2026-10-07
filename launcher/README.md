# Windows voice launcher

**English** | [中文](README.zh-TW.md)

**Windows only. macOS/Linux are not supported by this release or launcher.**
The BAT menu and console prompts use English ASCII text. Close any already-open
menu window and reopen the BAT after updating. The launcher confirms host/bridge
process creation before waiting for health; errors identify the startup step.
Browser-opening failures leave ready services running and show a local URL to open manually.

Windows PowerShell 5.1+ and Node 18+ are required. Extract the full source archive before
using the launcher; keep all BAT, PowerShell and Node files in this directory together. The npm packages
alone do not include it. Build the patched Epicenter host and install DSH >= 0.1.7-rc.2 and
the voice plugin first. This is a launcher/setup wizard, not a host builder or installer.

## First launch

Double-click `start-voice.bat` to open the English menu. Choose **1 Start** (or **5 Settings**
to configure without starting). The first-run console wizard asks for:

1. The patched Epicenter `.exe` and bridge `.mjs` paths. The extracted bridge is the default.
2. Node and the DSH JavaScript CLI entry (`lib/bin.js`). Global npm installations are
   detected when possible; custom layouts can supply absolute paths. Paths with spaces,
   Chinese characters and environment variables are supported. Node must be version 18+.
3. DSH web port (default 3080; bridge port remains 39152).
4. Speech provider: Groq, OpenAI, or a compatible service; matching baseURL, model and key.
5. Optional text polish: enable it and configure OpenAI or a compatible service, its model,
   a separate key field, and one prompt. Skip polish to keep raw transcripts.

Key input is hidden. Enter keeps existing values; selecting a different endpoint requires
its matching key. Entering a key does not prove account/model access: setup makes no cloud
calls. Free transcription tiers depend on the provider; OpenAI polish has its own billing.
Endpoint suffixes `/audio/transcriptions` and `/chat/completions` are removed from baseURL.
Use `\n` to enter prompt line breaks. The wizard displays existing path/prompt defaults,
so keep the setup console private too.

Settings are saved only after the input is validated. Existing bridge fields, pairing token
and disabled polish settings are retained. Invalid/unreadable settings are not overwritten.
Each file is written atomically; an existing file has a local `.backup-<random id>` copy.
Path and bridge config are two separate writes; if the second write fails, inspect the
local backups and rerun setup. Concurrent edits detected before writing stop setup. Deep settings are preserved up to
the supported nesting limit; excessive nesting is refused before either file is saved.

## Later launches

Double-click the same BAT again and choose **1 Start**. It checks Epicenter, then Voice Bridge,
then DSH. Missing components are started in that order, and healthy existing components
are kept. A verified but unresponsive voice component is restarted individually;
its healthy peer and DSH are preserved. Host health is checked before starting Bridge,
and backend health is checked before starting DSH. Unrelated port owners cause an
error; another or unidentified Epicenter installation also blocks launching the selected host.
DSH processes and draft sessions are preserved. Repeated Start with all services healthy
leaves their PIDs unchanged. Transient process/listener snapshot conflicts are rechecked;
true unknown owners block action with a specific host/port message.
Closing the launcher window after startup leaves the services running. DSH started by the
launcher has a hidden Node helper that drains its output; keep that helper running too.
It does not register boot startup, scheduled tasks or Windows services.

For newly launched DSH, the helper opens its authenticated loopback launch URL internally;
the login token is not printed or written to launcher logs/status. If DSH was already running,
it opens the ordinary URL; use the existing authenticated tab/launch link if login is required.
Browser launch failure/timeout is reported separately from a running DSH service, without
printing the authenticated URL. Enable/install the voice plugin and [pair the DSH tab once](../README.md#3-the-dsh-plugin).
The launcher does not insert pairing credentials into your browser. Pair before setting
`requireToken: true`; with it enabled, direct browser visits to bridge pages return 401.
For an already protected bridge, use the token from local config in the documented snippet,
then reload the DSH tab. Never place that token in a public URL or issue.

From a terminal in this directory:

```powershell
.\start-voice.bat -Configure   # revisit paths, providers, keys and prompt; then launch
.\start-voice.bat -SetupOnly   # configure without starting services
.\start-voice.bat -Check       # check existing paths, port ownership and bridge health
.\start-voice.bat -NoBrowser   # start services without opening a browser
.\start-voice.bat -Action Stop     # stop Voice Bridge + the selected Epicenter host
.\start-voice.bat -Action Restart  # restart the voice backend; preserve DSH
.\start-voice.bat -Action Status   # read-only per-service status and backend health
```

With no command arguments, the single BAT shows **1 Start, 2 Stop, 3 Restart, 4 Status,
5 Settings, 0 Exit**. Each result stays visible until Enter returns to the same menu;
command failures and unavailable status also return to it. Settings configures without starting.
Exit closes the menu and leaves running services alone. Command arguments bypass the menu;
`-Stop`, `-Restart`, `-Status` are aliases and `-Check` is a Status alias.
Status lists host, bridge and DSH
separately, with PIDs and local backend health. Exit codes: 0 success/healthy, 1 command failure,
2 status not ready or conflicted. A running process can still have failing health.

**Finish recording/transcription before Stop, Restart or recovery of an unresponsive component.** Stop/Restart terminate the selected
Epicenter host and its verified descendants, including its Bun host and WebView processes;
any other windows/features in this same Epicenter instance also stop. They preserve DSH,
browser tabs, drafts, pairing and cloud settings. Restart starts only the two voice backend
services, even if DSH is stopped, opens no browser, and checks stable health before reporting ready.
It does not finish pending recordings or cloud requests. No process is killed by image name or
port alone: exact program paths/script arguments and process creation times are checked, and
OS handles are held before termination. Unrelated/unknown voice service owners block the action.
Already-stopped services make Stop succeed without starting anything. Stop does not require
valid API keys or a readable bridge config; saved launcher paths are still required. Restart
validates its config and executable paths before stopping anything.

## History removal on Start/Restart

Cold Start (both voice components stopped) and every Restart clear only this plugin's marked WAV recordings from
`<Epicenter data root>/blobs/`, its marked stale native captures, Voice Bridge history logs
and `state.json` tracking IDs. The bridge saves an ownership marker on each successful
recording start in `%APPDATA%/dsh-voice-bridge/recording-owners/`. It contains only the
recording ID, owner and exact audio-store path; no audio, transcript or key is stored there.
Restart stops the selected backend before deleting and starts it again afterwards.
Partial Start recovery and repeated Start preserve running components and defer history
cleanup until Restart or the next fully stopped Start. This avoids deleting audio in use.
Unmarked WAVs, including older recordings and other applications' recordings, are retained.
Keep bridge.mjs and recording-history.mjs together and update the bridge with the launcher.
If a marker cannot be saved, recording start is cancelled/rejected to avoid untracked audio.
There is no retained count or age window, and no audio backup is created. Config, API keys,
prompt, pairing, DSH drafts/conversations and non-WAV blobs are retained. The plugin has no
separate transcript history store. Status, Stop, SetupOnly and menu Exit never clear history;
starting Node/Epicenter manually bypasses this launcher policy.

An active recording blocks Restart or recovery that must stop a component. Invalid layouts, symlinks/junctions or conflicting
process owners also block cleanup. The default root is `%APPDATA%/so.epicenter`; an absolute
`EPICENTER_DATA_DIR` override is honored. Default log cleanup covers `bridge.log` beside the
bridge entry. Optional `voiceHistoryLogs` in private paths.json can list additional absolute
`bridge.log` or `local-bridge-private.log` files; no arbitrary config/text paths are accepted.
No raw audio/transcript is printed; the launcher reports counts only.
Epicenter itself already removes unfinished native staging on startup; this is separate
from the launcher's ownership-based cleanup of completed recordings.

`-Check` creates no first-run settings and starts no service. `-NoBrowser` does not save or
display a fresh authenticated DSH URL. The BAT uses ExecutionPolicy Bypass for that process
only; it does not change the system execution policy. Organization policy may still block it.

## Private data and limits

| File | Location | Content |
|---|---|---|
| `paths.json` | Beside the launcher when present; otherwise `%LOCALAPPDATA%\dsh-voice-launcher\` | Local program paths and DSH port |
| `config.json` | `%APPDATA%\dsh-voice-bridge\` | Speech/polish keys, prompt, pairing token |
| `.backup-*` | Beside the original file | Previous private settings |

Keys are stored as ordinary local JSON, not encrypted; programs running as your Windows
user can read them. Hidden entry avoids displaying them. Do not share filled settings,
backups, console captures, authenticated URLs or logs. No key is embedded in the public
launcher or passed to its process arguments. Only local health requests are made at startup;
recording and paid cloud requests require your normal voice-button action.

An existing `paths.json` beside the launcher is preferred; the BAT menu explicitly selects
it so all menu actions use the same saved paths. `-SettingsPath` can select a different file.
This local paths file contains no API keys and must not be included in public source archives.

One bridge/profile can own port 39152 at a time. A different bridge installation already
using that port is reported as a conflict; explicitly choose its entry path to reuse it.
The launcher checks file paths, Node version, process ownership and local service health,
not DSH version compatibility or cloud account access. Bun must be available for host
components that require it; its conventional user-local bin directory is added if present.
Existing-process checks cannot prove a process uses the same environment/data profile.
Keep isolated test profiles separate and resolve them locally before using this daily launcher.
The helper does not save raw process output. Diagnose deeper host/DSH problems locally
using their normal manual commands, and redact output before sharing it.

Synthetic setup/startup tests cover the launcher independently. Existing voice acceptance
remains valid; a complete user-operated first install with the launcher is not yet recorded.
