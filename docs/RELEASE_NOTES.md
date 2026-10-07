# v0.1.0 - Windows early release

Cloud voice input for DeepSeek Harness, with no local transcription-model setup.
Text is inserted into the current draft with revision checks and never automatically sent.

- Optional OpenAI-compatible polish with one prompt and a separate local key field.
- Windows BAT setup/launcher: hidden key input, service reuse, health and conflict checks.
- English/Chinese installation instructions; no real keys, recordings or transcripts included.

**GitHub source and Release assets only. Not published to npm registry.**
Use [English installation](https://github.com/LatentHarbor-create/dsh-voice-input-cloud/blob/main/docs/INSTALL_RELEASE.md)
or [中文安裝](https://github.com/LatentHarbor-create/dsh-voice-input-cloud/blob/main/docs/INSTALL_RELEASE.zh-TW.md).
npm can install the attached tgz URL; no npm account is needed for installation.

Windows only; Node >= 18, DSH >= 0.1.7-rc.2 and a locally built patched Epicenter host are required.
No prebuilt host or complete installer is included. Build prerequisites are documented in source.
Bridge/plugin/launcher are MIT; Epicenter patch is AGPL-3.0 with included notices.

This is marked prerelease: the latest client click guard has four synthetic tests, not new real
browser acceptance, and full clean-user launcher installation has not been accepted. Prior core
voice/polish acceptance is retained. macOS/Linux and other DSH versions are not validated.
Free speech quotas depend on the chosen provider; optional polish has separate billing.

Verify downloads using the attached SHA256SUMS. Report only redacted errors/synthetic examples.
