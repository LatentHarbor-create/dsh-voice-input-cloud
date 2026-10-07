> Historical pre-publication review dated 2026-10-07. Subsequent release authorization
> uses GitHub source/assets only. npm publication is deferred. Public author name is the
> approved handle, with an empty commit email field. See the release installation guide.

# Candidate validation

Date: 2026-10-07. This candidate is local and unpublished. Public package author and the three
MIT notices use the approved GitHub handle `LatentHarbor-create`; no private email is included.
The two original git commits retain their project-placeholder metadata. The approved planned
repository is `LatentHarbor-create/dsh-voice-input-cloud`, with GitHub Issues for support.
The exact noreply commit email from GitHub account settings remains to be confirmed.
Repository and issue metadata describe the planned destination; no remote has been created.

## Completed

- Four JavaScript and two Windows PowerShell syntax checks pass.
- The release gate scans the current tree, two reachable handoff commits, archive file sets
  and contents, credential patterns, selected personal paths and relative Markdown links.
  Its output contains categories and locations, not matched secret values.
- Five synthetic verifier tests pass, including a deleted fake key that remains detectable
  in git history and findings that do not expose the matched value.
- Offline synthetic bridge checks cover Host fence; external-Origin POST rejection before
  upstream calls; loopback preflight; missing speech key; raw text with
  no polish; distinct speech and polish keys; polish-error fallback; provider-error redaction;
  malformed-config preservation; pairing authentication after restart; valid pairing auth;
  an explicit discovery root after restart; mock payload contract; and logs excluding
  all synthetic sensitive canaries. Sixteen checks pass against the installed bridge.
  Enabling polish while leaving its key empty also returns raw text without a polish call.
  A custom single prompt is sent as the system rules while the raw user transcript remains
  unchanged, including literal placeholder and dollar-sign text. A legacy user-template
  field is ignored. Prompt canaries are excluded from logs.
- The full candidate patch and both upstream draft patches apply cleanly to the pinned
  upstream commit. The full candidate patch was applied only in an isolated checkout.
- Isolated Bun frontend and sidecar builds pass with a frozen lockfile and installation scripts
  disabled. The candidate's Windows MSVC debug compile and link pass using a short target path
  and `/utf-8` C/C++ source flags. A rebuild including the configured discovery-root fix
  also passes. The debug executable has been launched for isolated acceptance, with
  separate data/folder/WebView2 storage. No executable has been distributed.
- English and Chinese installation pages have a language selector at the top of the root
  and both package READMEs. Each npm tarball includes its Chinese instructions.
- Private runtime settings, credentials, audio, transcripts, logs and browser storage were
  excluded from the candidate and archives. The authorized real test used a private temporary
  speech-setting copy; its keys and local pairing token were cleared after services stopped.
  The original bridge config fingerprint remained unchanged. Built backend files and isolated
  profiles were retained for the later polish test; no rebuild is needed to restart them.

The synthetic bridge checks use temporary configuration, invented text and an in-memory WAV
fixture against a loopback mock. They perform zero real cloud calls and do not use a microphone.
They prove the tested control/data/logging paths, not provider compatibility or DSH insertion.

Run the source checks with `python -B tools/test_verify_release.py` and
`python -B tools/smoke_privacy.py`. The smoke test needs port 39152 to be free; it refuses to
interact with an existing process there. For an installed tarball, pass its `bridge.mjs` path
with `--bridge`. Run `python -B tools/verify_release.py --artifacts <directory>` for package
content/history checks. Use `-B` to keep Python bytecode out of the source release tree.

## User-operated Windows acceptance

The isolated Windows debug host and the bridge/plugin installed from local tarballs were tested
with DSH `0.1.7-rc.2` and Node `24.16.0`. The declared DSH minimum is `0.1.7-rc.2`; other versions
have not been validated here. Node 18 is the declared minimum, rather than a tested version matrix.

| Test | User-confirmed result |
|---|---|
| New conversation recording and real cloud transcription | Text appeared in the draft; no automatic send |
| Manual edit during recording | Both the manual edit and new transcript remained; no automatic send |
| Host and bridge restart, without refreshing the DSH page | Reconnected and transcribed; existing draft retained; no automatic send |
| Existing synthetic conversation composer | Exactly one microphone control; transcript entered that draft; no automatic send |

These visual and editing outcomes were reported by the user, not inferred from package installation
or automated UI inspection. Local bridge request logs also showed successful start, stop and cloud
transcription responses. A private check of five runtime logs did not find the speech key.
No real transcript, audio, screenshot, provider payload or private configuration appears in this
public summary. Public demonstration material is restricted to synthetic text and diagrams.

The four baseline tests used raw transcription with polish disabled and `requireToken: false`.
Configuration uses one text-polish prompt; raw transcript input is supplied automatically.
Final package installation and sixteen synthetic checks are separate evidence from real tests.

## Real optional text-polish acceptance

The user subsequently tested the retained isolated frontend with polish enabled and reported
that it worked well. They explicitly confirmed the cleaned text entered the draft, the existing
draft remained, and nothing was automatically sent. Local bridge logs correlate two successful
cloud-transcription responses with `polished=true`; this distinguishes successful polish from
the best-effort raw-text fallback. The configured service was OpenAI Chat Completions with
`gpt-5.4-mini` and one private polish prompt.

A private check of eight runtime logs found neither cloud key nor the current pairing token.
The original installation config fingerprint remained unchanged. Only counts, status and
user-confirmed outcomes appear here; no real transcript, WAV, prompt, credential or provider
payload is included. This is basic functional acceptance, not a quality benchmark across all
languages or a real controlled-failure/required-pairing test. After acceptance, the user
authorized syncing polish into the daily local configuration. Only transformation settings
changed; speech settings and pairing token were retained. The daily host/bridge were activated;
the isolated host/bridge stopped. The unchanged fingerprint above describes the pre-sync
acceptance stage, not the later authorized settings update.

## Still required

- Controlled real polish failure and required pairing have synthetic coverage but have not
  been tested in the real browser. They are documented limitations and optional follow-up
  validation; do not claim real end-to-end acceptance for those modes.
- At the user's request, the successful polish round completes this local test pass.
  Packaging and privacy verification proceed without further recordings or cloud calls.
- Confirm the exact GitHub noreply email and publication account permissions. The public
  npm registry returned 404 for both names on 2026-10-07; no name is reserved, so recheck at release. Review public prose and re-run verification after any further changes.
- A release installer/binary distribution is outside this source-and-npm first-release scope.
- Explicit authorization for remote creation, push, npm publish or PR. None has occurred.

Package/source archive hashes are recorded outside the source archive to avoid a self-referential
hash. A passing scanner does not certify unknown private text or every possible secret format.

## Review evidence

The cumulative privacy change was read across these files:

```text
dsh-voice-input-cloud/
|-- .gitignore
|-- .gitattributes
|-- LICENSE
|-- README.md
|-- README.zh-TW.md
|-- bridge/
|   |-- bridge.mjs
|   |-- package.json
|   |-- README.md
|   |-- README.zh-TW.md
|   `-- LICENSE
|-- dsh-plugin/
|   |-- lib/client.js
|   |-- lib/index.js
|   |-- cordis.patch.yml
|   |-- package.json
|   |-- README.md
|   |-- README.zh-TW.md
|   `-- LICENSE
|-- epicenter-patch/
|   |-- voice-bridge.patch
|   `-- README.md
|-- docs/
|   |-- PRIVACY.md
|   |-- RELEASE_CHECKLIST.md
|   `-- VALIDATION.md
`-- tools/
    |-- verify_release.py
    |-- test_verify_release.py
    `-- smoke_privacy.py
```

The bridge owns runtime log/error boundaries and cloud credentials. The config loader preserves
existing files on parse/read failure. The release gate owns a shared inspection rule used for
current, historical and packed contents. The plugin insertion API and cloud-only behavior are
unchanged. Loader and browser module specifiers now match the published package name;
control ids stay stable. The full Epicenter patch narrows request logging and makes
discovery respect an explicit data root; it does not alter recorder or
Whispering behavior. The user subsequently authorized the Windows launcher described below.

## Windows launcher

This release supports Windows only. Both npm manifests declare `os: ["win32"]`.
The source distribution now includes BAT, PowerShell setup/startup and a hidden Node helper;
see the [English](../launcher/README.md) or [Chinese](../launcher/README.zh-TW.md) guide.
The first-run wizard reads keys with hidden input and keeps paths/config/backups local.

Sixteen PowerShell synthetic tests, nine Node helper tests and three loopback-health tests
cover fresh setup with distinct keys and one prompt; preservation/backup/concurrent edits;
malformed config; provider changes; Chinese/space paths; exact process matching and conflicts;
service reuse/check-only mode; failed health; deep JSON preservation/refusal; malformed
setting types and unsafe tokens; other Epicenter installation conflicts; browser failure; authenticated DSH URL fencing and private
browser handling; discarded process output; a real detached synthetic subprocess; and
synthetic pairing/redirect health behavior. No real service, cloud provider or microphone is
used. Windows loopback checks may need execution outside a network-restricted sandbox.

Run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/test_launcher.ps1`,
`node tools/test_launcher.mjs`, and `python -B tools/test_launcher_health.py` on Windows.
Fixtures contain synthetic values and remain outside release source. These checks do not
replace a complete new-user install/launcher acceptance test, which has not been recorded.
The bridge, plugin server entry and registration patch remain unchanged. The browser client
now adds a synchronous phase guard so rapid clicks cannot start/stop twice before React
renders. Four synthetic browser-module checks cover duplicate calls, stale draft preservation,
no submit, failed-start retry and capture failure. They detect the old rapid-click defect.
Run `node tools/test_client.mjs`. This latest client change has not been retested with real
recording/DSH insertion; include it in future first-install acceptance.
