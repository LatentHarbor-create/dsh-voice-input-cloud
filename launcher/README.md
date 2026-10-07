# Windows voice launcher

**English** | [中文](README.zh-TW.md)

**Windows only. macOS/Linux are not supported by this release or launcher.**
Windows PowerShell 5.1+ and Node 18+ are required. Extract the full source archive before
using the launcher; keep this directory's three program files together. The npm packages
alone do not include it. Build the patched Epicenter host and install DSH >= 0.1.7-rc.2 and
the voice plugin first. This is a launcher/setup wizard, not a host builder or installer.

## First launch

Double-click `start-voice.bat`. The console wizard asks for:

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

Double-click the BAT again. It reuses matching services, starts missing Epicenter/bridge,
waits for bridge `epicenter: ok`, then reuses or starts DSH. Unrelated port owners cause an
error; another or unidentified Epicenter installation also blocks launching the selected host.
The launcher never stops processes or restarts an existing draft session.
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
```

`-Check` creates no first-run settings and starts no service. `-NoBrowser` does not save or
display a fresh authenticated DSH URL. The BAT uses ExecutionPolicy Bypass for that process
only; it does not change the system execution policy. Organization policy may still block it.

## Private data and limits

| File | Location | Content |
|---|---|---|
| `paths.json` | `%LOCALAPPDATA%\dsh-voice-launcher\` | Local program paths and DSH port |
| `config.json` | `%APPDATA%\dsh-voice-bridge\` | Speech/polish keys, prompt, pairing token |
| `.backup-*` | Beside the original file | Previous private settings |

Keys are stored as ordinary local JSON, not encrypted; programs running as your Windows
user can read them. Hidden entry avoids displaying them. Do not share filled settings,
backups, console captures, authenticated URLs or logs. No key is embedded in the public
launcher or passed to its process arguments. Only local health requests are made at startup;
recording and paid cloud requests require your normal voice-button action.

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
