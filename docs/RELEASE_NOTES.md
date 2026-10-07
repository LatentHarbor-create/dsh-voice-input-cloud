# v0.1.1 - Windows service recovery and recording ownership

**English** | [中文安裝與升級](INSTALL_RELEASE.zh-TW.md)

One English BAT menu now provides Start, Stop, Restart, Status and Settings.
Start checks Epicenter, Voice Bridge and DSH in dependency order, starts missing components
and keeps healthy components running. Verified unresponsive voice components are repaired
individually. Restart rebuilds the voice backend while preserving DSH and its drafts.

- Bounded retries resolve transient listener/process snapshots; persistent unknown owners
  block action. Exact paths, arguments, creation times and held process handles protect
  unrelated processes from termination.
- Worker creation is acknowledged before health checks. Failure messages identify the step;
  a browser-opening failure leaves healthy services running.
- Bridge recording starts persist plugin ownership markers. Fully stopped Start and Restart
  clear only marked plugin WAVs/history. Partial/repeated Start defer cleanup; unmarked WAVs,
  config, keys, pairing and DSH drafts are preserved. There is no age/count retention window.
- English/Chinese install, upgrade and privacy documentation explains the two separate
  speech/polish key fields and one configurable polish prompt. No local model is required.

**GitHub source and Release assets only; not published to npm registry.**
Download the full source for the launcher and Epicenter patch. The two tgz packages alone
do not include the launcher or host. When upgrading, update all launcher files and keep
`bridge.mjs` with its new `recording-history.mjs` module. See
[English installation/upgrade](INSTALL_RELEASE.md) and [中文](INSTALL_RELEASE.zh-TW.md).
The previous v0.1.0 release remains available unchanged.

Windows PowerShell 5.1+, Node >= 18, DSH >= 0.1.7-rc.2 and a locally built patched Epicenter
host are required. No prebuilt host is included. MIT covers bridge/plugin/launcher;
the Epicenter patch is AGPL-3.0 with its notices retained.

Synthetic tests cover all eight component-presence combinations, service-health failures,
ownership conflicts, menu navigation, spawn acknowledgements and marker-only cleanup.
Existing-installation Windows checks cover missing host/bridge/both, healthy reuse,
controlled unresponsive voice components and Restart cleanup of synthetic owned audio.
DSH/config and unrelated audio were preserved. No new microphone/cloud call was needed.
Prior user-operated voice/polish acceptance remains applicable to the unchanged client.
A complete clean-user launcher installation remains unaccepted; this release is a prerelease.
See [validation](VALIDATION_SERVICE_CONTROL.md) for scope and limits.

Verify downloads with SHA256SUMS. Share only redacted errors and synthetic examples in Issues.
Free speech quotas depend on the provider; optional OpenAI polish has separate billing.
