# Service-control validation for v0.1.1

Date: 2026-10-08. This summary excludes private runtime evidence, process IDs, local account
paths, audio, real transcripts, keys, tokens and the maintainer's private prompt.

## Source and synthetic checks

- Recovery-state tests: all eight host/bridge/DSH presence combinations; healthy component
  reuse; individual unresponsive host/bridge repair; transient versus persistent conflicts;
  failed health prevents downstream startup; active recording prevents destructive repair.
- Process-control tests: exact program/argument ownership, descendant selection, process
  creation order and PID reuse, unknown owners and acquisition of all handles before stop.
- Retention tests: only owned WAV/staging/history removal, unknown WAV/config preservation,
  active-recording protection, root/header/size/layout validation, link/junction refusal.
- Bridge route tests: marker saved before successful Start, retained on Stop, removed on
  Cancel; failed marker registration cancels/refuses the recording.
- Setup/helper/menu tests: local key/config preservation, spawn acknowledgement and failure
  cleanup, browser failure handling, all menu actions, invalid input and return after failure.
- Release verifier checks current files, reachable history and metadata, local links, syntax,
  archive file sets, byte equality and checksums. Synthetic tests prove removed historical
  credentials are still detected. Exact local secret/private-prompt comparison is separate.

## Existing-installation Windows checks

The actual single BAT Start was exercised with Bridge missing, host missing, both missing
and both healthy. Controlled unresponsive host and Bridge cases exercised individual repair.
Healthy peers kept their identity. Restart stopped the selected backend, removed an owned
synthetic WAV/marker and brought the backend back to stable health. Unmarked audio remained.
DSH, its drafts and the local cloud/pairing configuration were preserved in these checks.
The checks did not record speech or call cloud providers.

Earlier user-operated transcription and optional polish passed with preserved drafts and
no automatic send. The browser client remains unchanged by v0.1.1 service-control work.
See [the historical acceptance record](VALIDATION.md) for that evidence and its limits.

## Limits

Windows only. DSH 0.1.7-rc.2 and Node 24.16.0 were tested; Node 18 is the declared minimum,
not a tested version matrix. A fresh machine/profile first-install launcher acceptance is
still pending. Real DSH hangs, real cloud failure and required-pairing browser acceptance
are not established by these component tests. No patched host binary is distributed.
Automatic privacy scans need manual review for unknown formats and private prose.
